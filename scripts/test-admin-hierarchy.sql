-- Baseline user tests also supply realistic RLS fixtures.
\ir test-users.sql
alter table public.profiles add column updated_at timestamptz;
alter table public.posts add column context text,add column generation_prompt text,add column prompt_version text,add column model text;
alter table public.post_hearts add column created_at timestamptz default now();
alter table public.post_hearts add constraint hierarchy_votes_fk foreign key(post_id) references public.posts(id) on delete cascade;
grant delete on storage.objects to authenticated;
create table auth.identities(user_id uuid,provider text);
insert into public.profiles(id,first_name,is_superadmin) values('c679baab-8190-4376-9f76-a0fb9bb25cb0','Owner',true);
insert into auth.identities values ('c679baab-8190-4376-9f76-a0fb9bb25cb0','google'),('00000000-0000-0000-0000-000000000002','google');
-- Another existing superadmin becomes a regular admin without losing access.
update public.profiles set is_superadmin=true where id='00000000-0000-0000-0000-000000000001';
\ir ../supabase/003-admin-pulse.sql
\ir ../supabase/005-admin-role-toggle.sql
\ir ../supabase/006-admin-media.sql
\ir ../supabase/007-admin-ratings.sql
set request.jwt.claim.sub='';
\ir ../supabase/008-admin-hierarchy.sql
\ir ../supabase/008-admin-hierarchy.sql
insert into public.posts(id,user_id,image_path,caption) values('20000000-0000-0000-0000-000000000001','c679baab-8190-4376-9f76-a0fb9bb25cb0','c679baab-8190-4376-9f76-a0fb9bb25cb0/owner.png','Owner post');
insert into storage.objects values('post-images','c679baab-8190-4376-9f76-a0fb9bb25cb0/owner.png');
do $$ begin
 if (select count(*) from public.profiles where is_superadmin)<>1 then raise exception 'Not sole owner';end if;
 if not (select is_admin and not is_superadmin from public.profiles where id='00000000-0000-0000-0000-000000000001') then raise exception 'Existing admin access not preserved';end if;
 begin update public.profiles set is_superadmin=true where id='00000000-0000-0000-0000-000000000002';raise exception 'Second superadmin accepted';exception when check_violation then null;end;
end $$;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
 if public.has_admin_access() then raise exception 'Member access';end if;
 begin perform public.admin_pulse();raise exception 'Member dashboard';exception when insufficient_privilege then null;end;
 begin perform public.admin_set_admin(auth.uid(),true,false);raise exception 'Self-promotion';exception when insufficient_privilege then null;end;
 begin update public.profiles set is_admin=true where id=auth.uid();raise exception 'Direct role write';exception when insufficient_privilege then null;end;
 begin perform public.admin_set_superadmin(auth.uid(),true,false);raise exception 'Legacy escalation';exception when insufficient_privilege then null;end;
end $$;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
do $$ begin
 if not public.admin_set_admin('00000000-0000-0000-0000-000000000002',true,false) then raise exception 'Grant failed';end if;
 begin perform public.admin_set_admin(auth.uid(),false,false);raise exception 'Owner role writable';exception when insufficient_privilege then null;end;
 begin perform public.admin_set_admin('00000000-0000-0000-0000-000000000002',false,false);raise exception 'Stale role accepted';exception when serialization_failure then null;end;
 begin perform public.admin_set_admin('00000000-0000-0000-0000-000000000003',true,false);raise exception 'Non-Google grant accepted';exception when invalid_parameter_value then null;end;
 begin perform public.admin_set_superadmin('00000000-0000-0000-0000-000000000003',true,false);raise exception 'Owner can grant superadmin';exception when insufficient_privilege then null;end;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ declare d jsonb;begin
 if not public.has_admin_access() then raise exception 'Admin denied';end if;
 perform public.admin_pulse();perform public.admin_profiles();perform public.admin_ratings();perform public.admin_media_list();
 if public.admin_profile_detail(auth.uid())->'profile'->>'is_admin'<>'true' then raise exception 'Admin flag absent';end if;
 if (select count(*) from storage.objects)<2 then raise exception 'Admin image reads denied';end if;
 begin perform public.admin_set_admin('00000000-0000-0000-0000-000000000003',true,false);raise exception 'Admin grants roles';exception when insufficient_privilege then null;end;
 begin perform public.admin_set_admin('00000000-0000-0000-0000-000000000001',false,true);raise exception 'Admin revokes roles';exception when insufficient_privilege then null;end;
 d:=public.admin_media_detail('20000000-0000-0000-0000-000000000001');
 if d->>'can_manage'<>'false' then raise exception 'Owner editor shown';end if;
 begin perform public.admin_media_update('20000000-0000-0000-0000-000000000001',d->>'version','Changed',null);raise exception 'Owner post edited';exception when insufficient_privilege then null;end;
 begin perform public.admin_media_delete('20000000-0000-0000-0000-000000000001',d->>'version');raise exception 'Owner post deleted';exception when insufficient_privilege then null;end;
 d:=public.admin_media_detail('10000000-0000-0000-0000-000000000007');
 perform public.admin_media_update('10000000-0000-0000-0000-000000000007',d->>'version','Admin edit',null);
 d:=public.admin_media_detail('10000000-0000-0000-0000-000000000007');
 perform public.admin_media_delete('10000000-0000-0000-0000-000000000007',d->>'version');
 if public.admin_media_detail('10000000-0000-0000-0000-000000000007') is not null then raise exception 'Admin delete failed';end if;
end $$;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
do $$ declare d jsonb;begin
 d:=public.admin_media_detail('20000000-0000-0000-0000-000000000001');
 perform public.admin_media_update('20000000-0000-0000-0000-000000000001',d->>'version','Owner edit',null);
 if public.admin_set_admin('00000000-0000-0000-0000-000000000002',false,true) then raise exception 'Revoke failed';end if;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
 begin perform public.admin_media_list();raise exception 'Revoked access retained';exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Exercise trigger defense even with a hypothetical future broad profile grant/policy.
grant update,delete on public.profiles to authenticated;
create policy test_broad_profile on public.profiles for all to authenticated using(true) with check(true);
set role authenticated;
do $$ begin
 begin update public.profiles set first_name='Compromised' where is_superadmin;raise exception 'Owner profile modified';exception when insufficient_privilege then null;end;
 begin delete from public.profiles where is_superadmin;raise exception 'Owner deleted';exception when insufficient_privilege then null;end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.admin_profiles();raise exception 'Guest read';exception when insufficient_privilege then null;end;
 begin perform public.admin_set_admin('00000000-0000-0000-0000-000000000002',true,false);raise exception 'Guest role write';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.admin_role_changes where role_kind='admin')<>2 then raise exception 'Role audit missing';end if;
 if not exists(select 1 from public.profiles where is_superadmin and first_name='Owner') then raise exception 'Owner damaged';end if;
end $$;
