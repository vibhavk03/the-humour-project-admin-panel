-- Preserve all caption choices, retaining existing one-caption previews and RPC grants.
begin;
alter table public.admin_remix_requests add column if not exists generated_captions jsonb not null default '[]'::jsonb;
update public.admin_remix_requests set generated_captions=jsonb_build_array(generated_caption)
where generated_caption is not null and generated_captions='[]'::jsonb;

-- Keep the existing signature/permissions for rolling deployment compatibility.
-- caption_value accepts a JSON array of three strings, or a legacy plain caption.
create or replace function public.admin_remix_finish(request_id uuid, caption_value text, model_value text, response_id text, image_hash text, failure_message text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job public.admin_remix_requests%rowtype; choices jsonb; choice jsonb;
begin
 if not public.admin_remix_authorized() then raise exception 'Admin access required' using errcode='42501'; end if;
 select * into job from public.admin_remix_requests where id=request_id and actor_id=auth.uid() for update;
 if not found then raise exception 'Remix not found' using errcode='P0002'; end if;
 if job.status<>'generating' then return to_jsonb(job); end if;
 if failure_message is null then
   if caption_value is null or model_value is null or char_length(model_value) not between 1 and 200
     or image_hash is null or image_hash !~ '^[a-f0-9]{64}$' then
     raise exception 'Invalid generated result' using errcode='22023'; end if;
   if left(ltrim(caption_value),1)='[' then
     begin choices:=caption_value::jsonb;
     exception when invalid_text_representation then raise exception 'Invalid caption choices' using errcode='22023'; end;
     if jsonb_typeof(choices)<>'array' or jsonb_array_length(choices)<>3 then
       raise exception 'Expected three caption choices' using errcode='22023'; end if;
   else
     choices:=jsonb_build_array(btrim(caption_value));
   end if;
   for choice in select value from jsonb_array_elements(choices) loop
     if jsonb_typeof(choice)<>'string' or char_length(btrim(choice#>>'{}')) not between 1 and 200 or (choice#>>'{}') ~ E'[\\r\\n]' then
       raise exception 'Each caption must be a nonempty line up to 200 characters.' using errcode='22023'; end if;
   end loop;
   select jsonb_agg(btrim(value#>>'{}') order by ordinality) into choices from jsonb_array_elements(choices) with ordinality;
   if (select count(distinct lower(value#>>'{}')) from jsonb_array_elements(choices))<>jsonb_array_length(choices) then
     raise exception 'Caption choices must be distinct' using errcode='22023'; end if;
 end if;
 update public.admin_remix_requests set status=case when failure_message is null then 'ready' else 'failed' end,
   generated_caption=case when failure_message is null then choices->>0 end,
   generated_captions=coalesce(choices,'[]'::jsonb),
   model=model_value,provider_response_id=response_id,image_sha256=image_hash,
   error_message=left(failure_message,300),completed_at=now()
 where id=request_id returning * into job;
 return to_jsonb(job);
end $$;
commit;
notify pgrst, 'reload schema';
