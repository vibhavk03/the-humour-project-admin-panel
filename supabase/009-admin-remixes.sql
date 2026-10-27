-- Admin remixes create independent posts. Apply after 008 as database owner.
begin;
create table if not exists public.admin_remix_requests (
  id uuid primary key,
  actor_id uuid not null,
  source_post_id uuid not null,
  source_author_id uuid not null,
  source_author_name text,
  source_caption text,
  source_image_path text not null,
  image_path text not null unique,
  prompt text not null check(char_length(prompt) between 1 and 12000),
  context text not null default '' check(char_length(context)<=1000),
  status text not null default 'generating' check(status in ('generating','ready','failed','published')),
  generated_caption text,
  published_caption text,
  model text,
  provider_response_id text,
  image_sha256 text,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  published_at timestamptz
);
create index if not exists admin_remix_actor_time on public.admin_remix_requests(actor_id,created_at desc);
create index if not exists admin_remix_source on public.admin_remix_requests(source_post_id,created_at desc);
alter table public.admin_remix_requests enable row level security;
revoke all on public.admin_remix_requests from public,anon,authenticated;

create or replace function public.admin_remix_authorized()
returns boolean language sql stable security definer set search_path='' as $$
 select public.has_admin_access() and exists(
   select 1 from auth.identities where user_id=auth.uid() and provider='google'
 );
$$;
revoke all on function public.admin_remix_authorized() from public,anon,authenticated;
grant execute on function public.admin_remix_authorized() to authenticated;

create or replace function public.admin_remix_begin(target_id uuid, request_id uuid, edited_prompt text, image_context text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare source public.posts%rowtype; job public.admin_remix_requests%rowtype; actor uuid:=auth.uid();
begin
 -- Serialize reservations per actor so concurrent requests cannot bypass limits.
 perform 1 from public.profiles where id=actor for update;
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 if request_id is null or edited_prompt is null or char_length(btrim(edited_prompt)) not between 1 and 12000
   or image_context is null or char_length(image_context)>1000 then
   raise exception 'Use a prompt up to 12,000 characters and context up to 1,000 characters.' using errcode='22023'; end if;
 update public.admin_remix_requests set status='failed',error_message='This generation did not finish. Generate a new preview.',completed_at=now()
 where actor_id=actor and status='generating' and created_at<now()-interval '2 minutes';
 select * into job from public.admin_remix_requests where id=request_id;
 if found then
   if job.actor_id<>actor then raise exception 'Remix not found' using errcode='42501'; end if;
   if job.source_post_id<>target_id or job.prompt<>btrim(edited_prompt) or job.context<>btrim(image_context) then
     raise exception 'This request ID belongs to a different preview.' using errcode='22023'; end if;
   return to_jsonb(job)||jsonb_build_object('claimed',false);
 end if;
 if (select count(*) from public.admin_remix_requests where actor_id=actor and created_at>now()-interval '15 minutes')>=10 then
   raise exception 'Remix limit reached. Try again in 15 minutes.' using errcode='P0001'; end if;
 if exists(select 1 from public.admin_remix_requests where actor_id=actor and status='generating' and created_at>now()-interval '2 minutes') then
   raise exception 'A caption is already generating. Wait a moment before trying again.' using errcode='P0001'; end if;
 select * into source from public.posts where id=target_id for share;
 if not found then raise exception 'Source post not found' using errcode='P0002'; end if;
 if split_part(source.image_path,'/',1)<>source.user_id::text then raise exception 'Unexpected image ownership' using errcode='22023'; end if;
 insert into public.admin_remix_requests(id,actor_id,source_post_id,source_author_id,source_author_name,source_caption,
   source_image_path,image_path,prompt,context)
 values(request_id,actor,target_id,source.user_id,
   (select nullif(btrim(concat_ws(' ',first_name,last_name)),'') from public.profiles where id=source.user_id),
   source.caption,source.image_path,actor::text||'/'||request_id::text,btrim(edited_prompt),btrim(image_context))
 returning * into job;
 return to_jsonb(job)||jsonb_build_object('claimed',true);
end $$;

create or replace function public.admin_remix_get(request_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select to_jsonb(r) from public.admin_remix_requests r where id=request_id and actor_id=auth.uid());
end $$;

create or replace function public.admin_remix_finish(request_id uuid, caption_value text, model_value text, response_id text, image_hash text, failure_message text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job public.admin_remix_requests%rowtype;
begin
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 select * into job from public.admin_remix_requests where id=request_id and actor_id=auth.uid() for update;
 if not found then raise exception 'Remix not found' using errcode='P0002'; end if;
 if job.status<>'generating' then return to_jsonb(job); end if;
 if failure_message is null and (caption_value is null or char_length(btrim(caption_value)) not between 1 and 200
   or model_value is null or char_length(model_value) not between 1 and 200 or image_hash is null or image_hash !~ '^[a-f0-9]{64}$') then
   raise exception 'Invalid generated result' using errcode='22023'; end if;
 update public.admin_remix_requests set status=case when failure_message is null then 'ready' else 'failed' end,
   generated_caption=case when failure_message is null then btrim(caption_value) end,
   model=model_value,provider_response_id=response_id,image_sha256=image_hash,
   error_message=left(failure_message,300),completed_at=now()
 where id=request_id returning * into job;
 return to_jsonb(job);
end $$;

create or replace function public.admin_remix_publish(request_id uuid, new_caption text)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.admin_remix_requests%rowtype; actor uuid:=auth.uid();
begin
 perform 1 from public.profiles where id=actor for share;
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 select * into job from public.admin_remix_requests where id=request_id and actor_id=actor for update;
 if not found then raise exception 'Remix not found' using errcode='P0002'; end if;
 -- One request can create exactly one post, including after a lost HTTP response.
 if job.status='published' then return job.id; end if;
 if job.status<>'ready' then raise exception 'Generate a caption before publishing.' using errcode='22023'; end if;
 if new_caption is null or char_length(btrim(new_caption)) not between 1 and 200 then
   raise exception 'Use a caption between 1 and 200 characters.' using errcode='22023'; end if;
 if not exists(select 1 from storage.objects where bucket_id='post-images' and name=job.image_path) then
   raise exception 'The independent image copy is missing. Please retry publishing.' using errcode='22023'; end if;
 -- Ownership always comes from the session, never an author supplied by the browser.
 insert into public.posts(id,user_id,image_path,caption,context,generation_prompt,prompt_version,model)
 values(job.id,actor,job.image_path,btrim(new_caption),nullif(job.context,''),job.prompt,'admin-remix-v1',job.model);
 update public.admin_remix_requests set status='published',published_caption=btrim(new_caption),published_at=now() where id=job.id;
 return job.id;
end $$;

create or replace function public.admin_remix_history(target_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc),'[]'::jsonb) from (
   select * from public.admin_remix_requests where source_post_id=target_id and actor_id=auth.uid()
   order by created_at desc limit 10
 ) r);
end $$;

-- Read-only lineage in the control room. Snapshot IDs/names survive source deletion.
create or replace function public.admin_remix_provenance(target_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select jsonb_build_object('source_post_id',r.source_post_id,'source_author_name',r.source_author_name,
   'source_exists',exists(select 1 from public.posts p where p.id=r.source_post_id),'generated_caption',r.generated_caption,
   'published_at',r.published_at) from public.admin_remix_requests r where r.id=target_id and r.status='published');
end $$;

revoke all on function public.admin_remix_begin(uuid,uuid,text,text),public.admin_remix_get(uuid),
 public.admin_remix_finish(uuid,text,text,text,text,text),public.admin_remix_publish(uuid,text),public.admin_remix_provenance(uuid),public.admin_remix_history(uuid)
 from public,anon,authenticated;
grant execute on function public.admin_remix_begin(uuid,uuid,text,text),public.admin_remix_get(uuid),
 public.admin_remix_finish(uuid,text,text,text,text,text),public.admin_remix_publish(uuid,text),public.admin_remix_provenance(uuid),public.admin_remix_history(uuid)
 to authenticated;
-- Existing owner-prefixed storage INSERT/SELECT policies handle the independent copy.
-- No source-post UPDATE/DELETE, new broad storage policies, or service-role key.
commit;
notify pgrst, 'reload schema';
