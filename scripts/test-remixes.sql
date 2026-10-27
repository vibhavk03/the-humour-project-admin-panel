-- Existing hierarchy suite supplies the realistic tables and role guards.
\ir test-admin-hierarchy.sql
reset role;
-- Restore the real column grants after the hierarchy suite's defensive trigger probe.
drop policy test_broad_profile on public.profiles;
set request.jwt.claim.sub='';
\ir ../supabase/008-admin-hierarchy.sql
\ir ../supabase/009-admin-remixes.sql
\ir ../supabase/009-admin-remixes.sql
alter table public.posts add constraint remix_owner_path check(split_part(image_path,'/',1)=user_id::text);
create unique index remix_unique_image on public.posts(image_path);
create temp table source_snapshot as select to_jsonb(p) as data from public.posts p where id='20000000-0000-0000-0000-000000000001';
insert into public.post_hearts values('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,now());
set role anon;
do $$ begin
 begin perform public.admin_remix_history('20000000-0000-0000-0000-000000000001'); raise exception 'Guest history leaked'; exception when insufficient_privilege then null; end;
end $$;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
 begin perform public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Prompt','');raise exception 'Member remix accepted';exception when insufficient_privilege then null;end;
end $$;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
select public.admin_set_admin('00000000-0000-0000-0000-000000000002',true,false);
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
do $$ begin
 begin perform public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Prompt','');raise exception 'Non-Google admin accepted';exception when insufficient_privilege then null;end;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ declare j jsonb;begin
 begin perform public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','','');raise exception 'Empty prompt';exception when invalid_parameter_value then null;end;
 begin perform public.admin_remix_begin('ffffffff-ffff-ffff-ffff-ffffffffffff','30000000-0000-0000-0000-000000000001','Prompt','');raise exception 'Missing source';exception when no_data_found then null;end;
 j:=public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Edited prompt','New context');
 if j->>'claimed'<>'true' or j->>'actor_id'<>auth.uid()::text or j->>'source_author_name'<>'Owner' then raise exception 'Wrong source snapshot/actor';end if;
 if j->>'image_path'<>auth.uid()::text||'/30000000-0000-0000-0000-000000000001' then raise exception 'Wrong independent path';end if;
 if public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Edited prompt','New context')->>'claimed'<>'false' then raise exception 'Duplicate AI request';end if;
 begin perform public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Different','');raise exception 'ID reused with different input';exception when invalid_parameter_value then null;end;
 begin perform public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','Other request','');raise exception 'Concurrent generation allowed';exception when raise_exception then if sqlerrm='Concurrent generation allowed' then raise;end if;end;
 begin perform public.admin_remix_publish('30000000-0000-0000-0000-000000000001','New caption');raise exception 'Published before generation';exception when invalid_parameter_value then null;end;
 j:=public.admin_remix_finish('30000000-0000-0000-0000-000000000001','Generated caption','test-model','response-1',repeat('a',64),null);
 if j->>'status'<>'ready' then raise exception 'Generation not saved';end if;
 begin perform public.admin_remix_publish('30000000-0000-0000-0000-000000000001','New caption');raise exception 'Published without copy';exception when invalid_parameter_value then null;end;
 begin perform public.admin_remix_publish('30000000-0000-0000-0000-000000000001',repeat('a',201));raise exception 'Long caption accepted';exception when invalid_parameter_value then null;end;
 begin perform * from public.admin_remix_requests;raise exception 'History table directly accessible';exception when insufficient_privilege then null;end;
end $$;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
do $$ begin
 if public.admin_remix_get('30000000-0000-0000-0000-000000000001') is not null then raise exception 'Another admin preview leaked';end if;
 if jsonb_array_length(public.admin_remix_history('20000000-0000-0000-0000-000000000001'))<>0 then raise exception 'Another admin history leaked';end if;
 begin perform public.admin_remix_publish('30000000-0000-0000-0000-000000000001','Forged');raise exception 'Another admin published';exception when no_data_found then null;end;
 begin perform public.admin_remix_finish('30000000-0000-0000-0000-000000000001','Forged','test','test',repeat('a',64),null);raise exception 'Another admin completed job';exception when no_data_found then null;end;
end $$;
reset role;
-- Simulate the Storage API's independent upload, not a shared source path.
insert into storage.objects values('post-images','00000000-0000-0000-0000-000000000002/30000000-0000-0000-0000-000000000001');
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
select public.admin_remix_publish('30000000-0000-0000-0000-000000000001','Admin-selected caption');
select public.admin_remix_publish('30000000-0000-0000-0000-000000000001','Retry with different text');
reset role;
do $$ declare p public.posts%rowtype;begin
 select * into p from public.posts where id='30000000-0000-0000-0000-000000000001';
 if p.user_id<>'00000000-0000-0000-0000-000000000002' or p.caption<>'Admin-selected caption' or p.context<>'New context' or p.generation_prompt<>'Edited prompt' or p.model<>'test-model' then raise exception 'Wrong new post metadata';end if;
 if p.prompt_version<>'admin-remix-v1' or p.image_path='c679baab-8190-4376-9f76-a0fb9bb25cb0/owner.png' then raise exception 'Original metadata/image reused';end if;
 if (select to_jsonb(original) from public.posts original where id='20000000-0000-0000-0000-000000000001') is distinct from (select data from source_snapshot) then raise exception 'Source post changed';end if;
 if (select count(*) from public.post_hearts where post_id='20000000-0000-0000-0000-000000000001')<>1 or exists(select 1 from public.post_hearts where post_id=p.id) then raise exception 'Votes changed/copied';end if;
 if (select count(*) from public.posts where id='30000000-0000-0000-0000-000000000001')<>1 then raise exception 'Duplicate publish';end if;
end $$;
-- Failures are retained, release the in-flight slot, and count towards the paid-call limit.
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ declare n int; rid uuid;begin
 for n in 2..10 loop
   rid:=('30000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
   perform public.admin_remix_begin('20000000-0000-0000-0000-000000000001',rid,'Prompt','');
   perform public.admin_remix_finish(rid,null,null,null,null,'Simulated provider failure');
 end loop;
 begin perform public.admin_remix_begin('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000011','Prompt','');raise exception 'Rate limit bypass';exception when raise_exception then if sqlerrm='Rate limit bypass' then raise;end if;end;
 if jsonb_array_length(public.admin_remix_history('20000000-0000-0000-0000-000000000001'))<>10 then raise exception 'History missing';end if;
end $$;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
select public.admin_set_admin('00000000-0000-0000-0000-000000000002',false,true);
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
 begin perform public.admin_remix_get('30000000-0000-0000-0000-000000000001');raise exception 'Revoked access retained';exception when insufficient_privilege then null;end;
 begin perform public.admin_remix_publish('30000000-0000-0000-0000-000000000001','Retry');raise exception 'Revoked publish allowed';exception when insufficient_privilege then null;end;
end $$;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
do $$ declare d jsonb;begin
 d:=public.admin_media_detail('20000000-0000-0000-0000-000000000001');
 perform public.admin_media_delete('20000000-0000-0000-0000-000000000001',d->>'version');
 if public.admin_remix_provenance('30000000-0000-0000-0000-000000000001')->>'source_author_name'<>'Owner'
 or public.admin_remix_provenance('30000000-0000-0000-0000-000000000001')->>'source_exists'<>'false' then raise exception 'Source deletion lost provenance';end if;
end $$;
reset role;
delete from storage.objects where name='c679baab-8190-4376-9f76-a0fb9bb25cb0/owner.png';
do $$ begin
 if not exists(select 1 from storage.objects where name='00000000-0000-0000-0000-000000000002/30000000-0000-0000-0000-000000000001') then raise exception 'Source deletion removed remix image';end if;
end $$;
-- Choices migration preserves old previews and persists all three new alternatives.
\ir ../supabase/010-remix-caption-choices.sql
\ir ../supabase/010-remix-caption-choices.sql
do $$ begin
 if (select generated_captions from public.admin_remix_requests where id='30000000-0000-0000-0000-000000000001')<>'["Generated caption"]'::jsonb then raise exception 'Legacy caption lost';end if;
end $$;
set role authenticated;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
select public.admin_remix_begin('10000000-0000-0000-0000-000000000008','40000000-0000-0000-0000-000000000001','Three caption prompt','');
do $$ declare invalid_choices text; result jsonb;begin
 foreach invalid_choices in array array['["one"]','["one","two"]','["one","two","three","four"]','["one","two",null]','["one","two",""]','["Same"," same ","Other"]','["one","two",4]','["one","two","line\nbreak"]','["one","two","'||repeat('x',201)||'"]'] loop
   begin perform public.admin_remix_finish('40000000-0000-0000-0000-000000000001',invalid_choices,'test-model','response',repeat('b',64),null);
   raise exception 'Invalid choices accepted: %',invalid_choices;
   exception when invalid_parameter_value then null;end;
 end loop;
 result:=public.admin_remix_finish('40000000-0000-0000-0000-000000000001','["First joke","Second joke","Third joke"]','test-model','response',repeat('b',64),null);
 if result->'generated_captions'<>'["First joke","Second joke","Third joke"]'::jsonb or result->>'generated_caption'<>'First joke' then raise exception 'Choices not persisted';end if;
 if public.admin_remix_history('10000000-0000-0000-0000-000000000008')->0->'generated_captions'<>result->'generated_captions' then raise exception 'History lost alternatives';end if;
end $$;
reset role;
insert into storage.objects values('post-images','c679baab-8190-4376-9f76-a0fb9bb25cb0/40000000-0000-0000-0000-000000000001');
set role authenticated;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
select public.admin_remix_publish('40000000-0000-0000-0000-000000000001','Third joke');
reset role;
do $$ begin
 if (select caption from public.posts where id='40000000-0000-0000-0000-000000000001')<>'Third joke' then raise exception 'Selected caption not published';end if;
 if (select generated_captions from public.admin_remix_requests where id='40000000-0000-0000-0000-000000000001')<>'["First joke","Second joke","Third joke"]'::jsonb then raise exception 'Publishing lost original choices';end if;
end $$;
-- A session accumulates five batches and enforces its limit in the database.
\ir ../supabase/011-remix-caption-sessions.sql
\ir ../supabase/011-remix-caption-sessions.sql
set role authenticated;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
do $$ declare job jsonb; result jsonb; rid uuid; batch int; target constant uuid:='10000000-0000-0000-0000-000000000008'; root constant uuid:='50000000-0000-0000-0000-000000000001';begin
 job:=public.admin_remix_begin_batch(target,root,'Batch prompt','Batch context',null);
 result:=public.admin_remix_finish(root,'["Caption 1","Caption 2","Caption 3"]','batch-model-1','response',repeat('c',64),null);
 if jsonb_array_length(result->'session_captions')<>3 then raise exception 'First batch missing';end if;
 begin perform public.admin_remix_begin_batch(target,'50000000-0000-0000-0000-000000000002','Changed prompt','Batch context',root);raise exception 'Changed prompt appended';exception when invalid_parameter_value then null;end;
 perform public.admin_remix_begin_batch(target,'50000000-0000-0000-0000-000000000002','Batch prompt','Batch context',root);
 begin perform public.admin_remix_finish('50000000-0000-0000-0000-000000000002','["Caption 1","Other caption","Different caption"]','batch-model-2','response',repeat('c',64),null);raise exception 'Duplicate old caption accepted';exception when invalid_parameter_value then null;end;
 perform public.admin_remix_finish('50000000-0000-0000-0000-000000000002',null,null,null,null,'Repeated caption rejected');
 if jsonb_array_length(public.admin_remix_get(root)->'session_captions')<>3 then raise exception 'Failed request erased previous choices';end if;
 for batch in 2..5 loop
   rid:=('50000000-0000-0000-0000-'||lpad((batch+1)::text,12,'0'))::uuid;
   job:=public.admin_remix_begin_batch(target,rid,'Batch prompt','Batch context',root);
   if job->>'claimed'<>'true' then raise exception 'Batch not claimed';end if;
   if public.admin_remix_begin_batch(target,rid,'Batch prompt','Batch context',root)->>'claimed'<>'false' then raise exception 'Retry reserved another batch';end if;
   if batch=2 then
     begin perform public.admin_remix_finish(rid,'["Caption 4","Caption 5","Caption 6"]','batch-model-2','response',repeat('d',64),null);raise exception 'Changed image accepted';exception when invalid_parameter_value then null;end;
   end if;
   result:=public.admin_remix_finish(rid,jsonb_build_array('Caption '||(batch*3-2),'Caption '||(batch*3-1),'Caption '||(batch*3))::text,'batch-model-'||batch,'response',repeat('c',64),null);
   if jsonb_array_length(result->'session_captions')<>batch*3 then raise exception 'Batch accumulation failed';end if;
 end loop;
 begin perform public.admin_remix_begin_batch(target,'50000000-0000-0000-0000-000000000007','Batch prompt','Batch context',root);raise exception 'Sixth batch allowed';exception when invalid_parameter_value then null;end;
 if jsonb_array_length(public.admin_remix_get(root)->'session_captions')<>15 then raise exception 'Cap recovery lost captions';end if;
 if public.admin_remix_get(root)->'session_captions'->14->>'requestId'<>'50000000-0000-0000-0000-000000000006' then raise exception 'Originating generation lost';end if;
 if public.admin_remix_get(root)->'session_captions'->14->>'model'<>'batch-model-5' then raise exception 'Originating model lost';end if;
 if public.admin_remix_history(target)->0->'session_captions'<>public.admin_remix_get(root)->'session_captions' then raise exception 'History failed to recover full session';end if;
end $$;
reset role;
insert into storage.objects values('post-images','c679baab-8190-4376-9f76-a0fb9bb25cb0/50000000-0000-0000-0000-000000000006');
set role authenticated;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
select public.admin_remix_publish('50000000-0000-0000-0000-000000000006','Caption 15');
do $$ begin
 if public.admin_remix_publish('50000000-0000-0000-0000-000000000001','Caption 1')<>'50000000-0000-0000-0000-000000000006'::uuid then raise exception 'Cross-batch publish created a duplicate';end if;
 if public.admin_remix_get('50000000-0000-0000-0000-000000000001')->>'session_post_id'<>'50000000-0000-0000-0000-000000000006' then raise exception 'Session publication not recovered';end if;
 begin perform public.admin_remix_begin_batch('10000000-0000-0000-0000-000000000008','50000000-0000-0000-0000-000000000007','Batch prompt','Batch context','50000000-0000-0000-0000-000000000001');raise exception 'Appended after publication';exception when invalid_parameter_value then null;end;
end $$;
reset role;
do $$ begin
 if (select caption from public.posts where id='50000000-0000-0000-0000-000000000006')<>'Caption 15' then raise exception 'Wrong selection published';end if;
 if (select model from public.posts where id='50000000-0000-0000-0000-000000000006')<>'batch-model-5' then raise exception 'Wrong generation model published';end if;
 if (select count(*) from public.posts where id::text like '50000000-%')<>1 then raise exception 'Multiple posts for one session';end if;
end $$;
