-- Accumulate batches of three, up to fifteen choices in one remix session.
begin;
alter table public.admin_remix_requests add column if not exists session_id uuid;
create index if not exists admin_remix_session_idx on public.admin_remix_requests(session_id,created_at);

-- Return all alternatives with their originating generation request/model.
create or replace function public.admin_remix_get(request_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare job public.admin_remix_requests%rowtype; sid uuid; alternatives jsonb; published public.admin_remix_requests%rowtype;
begin
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 select * into job from public.admin_remix_requests where id=request_id and actor_id=auth.uid();
 if not found then return null; end if;
 sid:=coalesce(job.session_id,job.id);
 select coalesce(jsonb_agg(jsonb_build_object('requestId',r.id,'caption',c.value,'model',r.model)
   order by r.created_at,r.id,c.ordinality),'[]'::jsonb) into alternatives
 from public.admin_remix_requests r cross join lateral jsonb_array_elements_text(r.generated_captions) with ordinality c
 where coalesce(r.session_id,r.id)=sid and r.actor_id=auth.uid() and r.status in ('ready','published');
 select * into published from public.admin_remix_requests where coalesce(session_id,id)=sid and actor_id=auth.uid() and status='published' order by published_at limit 1;
 return to_jsonb(job)||jsonb_build_object('session_id',sid,'session_captions',alternatives,
   'session_post_id',published.id,'session_caption',published.published_caption);
end $$;

create or replace function public.admin_remix_begin_batch(target_id uuid, request_id uuid, edited_prompt text, image_context text, previous_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare parent public.admin_remix_requests%rowtype; existing public.admin_remix_requests%rowtype; sid uuid; reserved jsonb; total integer;
begin
 perform 1 from public.profiles where id=auth.uid() for update;
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 if previous_request_id is not null then
   select * into parent from public.admin_remix_requests where id=previous_request_id and actor_id=auth.uid();
   if not found then raise exception 'Remix session not found' using errcode='P0002'; end if;
   sid:=coalesce(parent.session_id,parent.id);
   if parent.source_post_id<>target_id or parent.prompt is distinct from btrim(edited_prompt) or parent.context is distinct from btrim(image_context) then
     raise exception 'Use the same image, prompt and context to request more captions.' using errcode='22023'; end if;
 end if;
 -- Retrying a completed/in-flight batch never reserves another paid call.
 select * into existing from public.admin_remix_requests where id=request_id;
 if found then
   if existing.actor_id<>auth.uid() then raise exception 'Remix not found' using errcode='42501'; end if;
   if coalesce(existing.session_id,existing.id) is distinct from coalesce(sid,request_id) then
     raise exception 'This request belongs to a different session.' using errcode='22023'; end if;
   reserved:=public.admin_remix_begin(target_id,request_id,edited_prompt,image_context);
   return public.admin_remix_get(request_id)||jsonb_build_object('claimed',false);
 end if;
 if sid is not null then
   if exists(select 1 from public.admin_remix_requests where coalesce(session_id,id)=sid and status='published') then
     raise exception 'This remix is already published. Start a new remix.' using errcode='22023'; end if;
   select coalesce(sum(jsonb_array_length(generated_captions)),0) into total from public.admin_remix_requests
     where coalesce(session_id,id)=sid and status='ready';
   if total=0 or total%3<>0 then raise exception 'Start a new three-caption preview for this older session.' using errcode='22023'; end if;
   if total+3>15 then raise exception 'This remix has reached its limit of 15 captions.' using errcode='22023'; end if;
 end if;
 reserved:=public.admin_remix_begin(target_id,request_id,edited_prompt,image_context);
 update public.admin_remix_requests set session_id=coalesce(sid,request_id) where id=request_id;
 return public.admin_remix_get(request_id)||jsonb_build_object('claimed',true);
end $$;
revoke all on function public.admin_remix_begin_batch(uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.admin_remix_begin_batch(uuid,uuid,text,text,uuid) to authenticated;

-- Keep validation from migration 010; extend completion to enforce the session cap,
-- exclude repeated captions and preserve the image used by the first batch.
create or replace function public.admin_remix_finish(request_id uuid, caption_value text, model_value text, response_id text, image_hash text, failure_message text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job public.admin_remix_requests%rowtype; choices jsonb; choice jsonb; sid uuid; prior_count integer;
begin
 perform 1 from public.profiles where id=auth.uid() for update;
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 select * into job from public.admin_remix_requests where id=request_id and actor_id=auth.uid() for update;
 if not found then raise exception 'Remix not found' using errcode='P0002'; end if;
 if job.status<>'generating' then return public.admin_remix_get(job.id); end if;
 sid:=coalesce(job.session_id,job.id);
 if failure_message is null then
   if caption_value is null or model_value is null or char_length(model_value) not between 1 and 200
     or image_hash is null or image_hash !~ '^[a-f0-9]{64}$' then
     raise exception 'Invalid generated result' using errcode='22023'; end if;
   if left(ltrim(caption_value),1)='[' then
     begin choices:=caption_value::jsonb;
     exception when invalid_text_representation then raise exception 'Invalid caption choices' using errcode='22023'; end;
     if jsonb_typeof(choices)<>'array' or jsonb_array_length(choices)<>3 then
       raise exception 'Expected three caption choices' using errcode='22023'; end if;
   else choices:=jsonb_build_array(btrim(caption_value)); end if;
   for choice in select value from jsonb_array_elements(choices) loop
     if jsonb_typeof(choice)<>'string' or char_length(btrim(choice#>>'{}')) not between 1 and 200 or (choice#>>'{}') ~ E'[\\r\\n]' then
       raise exception 'Each caption must be a nonempty line up to 200 characters.' using errcode='22023'; end if;
   end loop;
   select jsonb_agg(btrim(value#>>'{}') order by ordinality) into choices from jsonb_array_elements(choices) with ordinality;
   if (select count(distinct lower(value#>>'{}')) from jsonb_array_elements(choices))<>jsonb_array_length(choices) then
     raise exception 'Caption choices must be distinct' using errcode='22023'; end if;
   select coalesce(sum(jsonb_array_length(generated_captions)),0) into prior_count from public.admin_remix_requests
     where coalesce(session_id,id)=sid and id<>job.id and status in ('ready','published');
   if prior_count+jsonb_array_length(choices)>15 then raise exception 'This remix has reached its limit of 15 captions.' using errcode='22023'; end if;
   if exists(select 1 from public.admin_remix_requests r cross join lateral jsonb_array_elements_text(r.generated_captions) old_choice
     cross join jsonb_array_elements_text(choices) new_choice
     where coalesce(r.session_id,r.id)=sid and r.id<>job.id and r.status in ('ready','published') and lower(btrim(old_choice))=lower(btrim(new_choice))) then
     raise exception 'The AI repeated a previous caption. Request a fresh batch.' using errcode='22023'; end if;
   if exists(select 1 from public.admin_remix_requests where coalesce(session_id,id)=sid and id<>job.id
     and status in ('ready','published') and image_sha256 is distinct from image_hash) then
     raise exception 'The source image changed. Start a new remix.' using errcode='22023'; end if;
 end if;
 update public.admin_remix_requests set status=case when failure_message is null then 'ready' else 'failed' end,
   generated_caption=case when failure_message is null then choices->>0 end,generated_captions=coalesce(choices,'[]'::jsonb),
   model=model_value,provider_response_id=response_id,image_sha256=image_hash,
   error_message=left(failure_message,300),completed_at=now() where id=request_id;
 return public.admin_remix_get(job.id);
end $$;

create or replace function public.admin_remix_history(target_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(public.admin_remix_get(r.id) order by r.created_at desc),'[]'::jsonb) from (
   select id,created_at from public.admin_remix_requests where source_post_id=target_id and actor_id=auth.uid() and coalesce(session_id,id)=id
   order by created_at desc limit 10
 ) r);
end $$;

create or replace function public.admin_remix_publish(request_id uuid, new_caption text)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.admin_remix_requests%rowtype; actor uuid:=auth.uid(); published_id uuid;
begin
 -- All batches share the actor lock: publishing two different batches is idempotent.
 perform 1 from public.profiles where id=actor for update;
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 select * into job from public.admin_remix_requests where id=request_id and actor_id=actor for update;
 if not found then raise exception 'Remix not found' using errcode='P0002'; end if;
 select id into published_id from public.admin_remix_requests where coalesce(session_id,id)=coalesce(job.session_id,job.id) and status='published' limit 1;
 if found then return published_id; end if;
 if job.status<>'ready' then raise exception 'Generate a caption before publishing.' using errcode='22023'; end if;
 if new_caption is null or char_length(btrim(new_caption)) not between 1 and 200 then
   raise exception 'Use a caption between 1 and 200 characters.' using errcode='22023'; end if;
 if not exists(select 1 from storage.objects where bucket_id='post-images' and name=job.image_path) then
   raise exception 'The independent image copy is missing. Please retry publishing.' using errcode='22023'; end if;
 insert into public.posts(id,user_id,image_path,caption,context,generation_prompt,prompt_version,model)
 values(job.id,actor,job.image_path,btrim(new_caption),nullif(job.context,''),job.prompt,'admin-remix-v1',job.model);
 update public.admin_remix_requests set status='published',published_caption=btrim(new_caption),published_at=now() where id=job.id;
 return job.id;
end $$;
commit;
notify pgrst, 'reload schema';
