\ir test-users.sql
alter table public.posts add column context text,add column generation_prompt text,add column prompt_version text,add column model text;
alter table public.post_hearts add constraint media_votes_post_fk foreign key(post_id) references public.posts(id) on delete cascade;
grant delete on storage.objects to authenticated;
update public.profiles set is_superadmin=true where id='00000000-0000-0000-0000-000000000001';
update public.posts set context='Private',generation_prompt='Original prompt',prompt_version='v1',model='model-original';
\ir ../supabase/006-admin-media.sql
\ir ../supabase/006-admin-media.sql
set role anon;
do $$ begin
  begin perform public.admin_media_list();raise exception 'Guest read';exception when insufficient_privilege then null;end;
  begin perform public.admin_media_update('10000000-0000-0000-0000-000000000008','','bad','bad');raise exception 'Guest update';exception when insufficient_privilege then null;end;
  begin perform public.admin_media_delete('10000000-0000-0000-0000-000000000008','');raise exception 'Guest delete';exception when insufficient_privilege then null;end;
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
  begin perform public.admin_media_detail('10000000-0000-0000-0000-000000000008');raise exception 'Member read';exception when insufficient_privilege then null;end;
  begin perform public.admin_media_update('10000000-0000-0000-0000-000000000008','','bad','bad');raise exception 'Member update';exception when insufficient_privilege then null;end;
  begin perform public.admin_media_delete('10000000-0000-0000-0000-000000000008','');raise exception 'Member delete';exception when insufficient_privilege then null;end;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
do $$ declare r jsonb;original jsonb;edited jsonb;deleted jsonb;begin
  if public.admin_media_list()->>'total'<>'8' or public.admin_media_list('','published')->>'total'<>'7' or public.admin_media_list('','unpublished')->>'total'<>'1' then raise exception 'Status filters wrong';end if;
  if public.admin_media_list('ALICE')->>'total'<>'8' or public.admin_media_list('%')->>'total'<>'0' then raise exception 'Search wrong';end if;
  if public.admin_media_list('', 'all',999)->>'page'<>'1' then raise exception 'Page clamp wrong';end if;
  original:=public.admin_media_detail('10000000-0000-0000-0000-000000000008');
  if original->>'upvotes'<>'1' or original->>'downvotes'<>'1' or original?'image_path' then raise exception 'Read ratings/path wrong';end if;
  begin perform public.admin_media_update('10000000-0000-0000-0000-000000000008','stale','changed','context');raise exception 'Stale update accepted';exception when serialization_failure then null;end;
  begin perform public.admin_media_update('10000000-0000-0000-0000-000000000008',original->>'version','',null);raise exception 'Blank published caption accepted';exception when invalid_parameter_value then null;end;
  begin perform public.admin_media_update('10000000-0000-0000-0000-000000000008',original->>'version',repeat('a',201),null);raise exception 'Long caption accepted';exception when invalid_parameter_value then null;end;
  edited:=public.admin_media_update('10000000-0000-0000-0000-000000000008',original->>'version','Edited caption','New context');
  if edited->>'caption'<>'Edited caption' or edited->>'context'<>'New context' or edited->>'user_id'<>original->>'user_id' or edited->>'generation_prompt'<>'Original prompt' or edited->>'model'<>'model-original' or edited->>'created_at'<>original->>'created_at' then raise exception 'Edit changed provenance or did not save';end if;
  if public.admin_media_can_cleanup('00000000-0000-0000-0000-000000000002/8.gif') then raise exception 'Cleanup allowed before deletion';end if;
  delete from storage.objects where bucket_id='post-images'; if found then raise exception 'Live image deletion allowed';end if;
  begin perform public.admin_media_delete('10000000-0000-0000-0000-000000000008',original->>'version');raise exception 'Stale deletion accepted';exception when serialization_failure then null;end;
  deleted:=public.admin_media_delete('10000000-0000-0000-0000-000000000008',edited->>'version');
  if public.admin_media_detail('10000000-0000-0000-0000-000000000008') is not null then raise exception 'Post not deleted';end if;
  if not public.admin_media_can_cleanup(deleted->>'path') then raise exception 'Queued cleanup denied';end if;
  if public.admin_media_finish_cleanup('10000000-0000-0000-0000-000000000008') then raise exception 'Cleanup completed while object exists';end if;
  if public.admin_media_delete('10000000-0000-0000-0000-000000000008','retry')->>'cleanupPending'<>'true' then raise exception 'Retry failed';end if;
  delete from storage.objects where bucket_id='post-images' and name=deleted->>'path';
  if not found then raise exception 'Image cleanup failed';end if;
  if not public.admin_media_finish_cleanup('10000000-0000-0000-0000-000000000008') then raise exception 'Cleanup not finished';end if;
  if public.admin_media_can_cleanup(deleted->>'path') then raise exception 'Completed cleanup permission retained';end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from public.post_hearts where post_id='10000000-0000-0000-0000-000000000008') then raise exception 'Vote cascade failed';end if;
  if(select count(*) from public.admin_media_changes)<>2 then raise exception 'Audit count incorrect';end if;
  if exists(select 1 from public.admin_media_changes where actor_id<>'00000000-0000-0000-0000-000000000001') then raise exception 'Wrong actor';end if;
end $$;
