\ir test-users.sql
create table auth.identities(user_id uuid,provider text);
insert into auth.identities values ('00000000-0000-0000-0000-000000000001','google'),('00000000-0000-0000-0000-000000000002','google');
update public.profiles set is_superadmin=true where id='00000000-0000-0000-0000-000000000001';
\ir ../supabase/005-admin-role-toggle.sql
\ir ../supabase/005-admin-role-toggle.sql
set role anon;
do $$ begin
  begin perform public.admin_set_superadmin('00000000-0000-0000-0000-000000000002',true,false); raise exception 'Guest granted access'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
  begin perform public.admin_set_superadmin(auth.uid(),true,false); raise exception 'Self-promotion succeeded'; exception when insufficient_privilege then null; end;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
do $$ begin
  begin perform public.admin_set_superadmin(auth.uid(),false,true); raise exception 'Last admin demoted'; exception when check_violation then null; end;
  begin perform public.admin_set_superadmin('00000000-0000-0000-0000-000000000002',true,true); raise exception 'Stale write accepted'; exception when serialization_failure then null; end;
  begin perform public.admin_set_superadmin('00000000-0000-0000-0000-000000000003',true,false); raise exception 'NonGoogle grant accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_set_superadmin('ffffffff-ffff-ffff-ffff-ffffffffffff',true,false); raise exception 'Missing target accepted'; exception when no_data_found then null; end;
  begin perform public.admin_set_superadmin(auth.uid(),null,true); raise exception 'Null role accepted'; exception when invalid_parameter_value then null; end;
  if not public.admin_set_superadmin('00000000-0000-0000-0000-000000000002',true,false) then raise exception 'Grant failed'; end if;
  if public.admin_set_superadmin('00000000-0000-0000-0000-000000000002',false,true) then raise exception 'Revoke failed'; end if;
  perform public.admin_set_superadmin('00000000-0000-0000-0000-000000000002',true,false);
  perform public.admin_set_superadmin(auth.uid(),false,true);
  begin perform public.admin_set_superadmin(auth.uid(),true,false); raise exception 'Revoked caller can grant'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.admin_role_changes; raise exception 'Audit log exposed'; exception when insufficient_privilege then null; end;
  begin update public.profiles set is_superadmin=true where id=auth.uid(); raise exception 'Direct write allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.admin_role_changes)<>4 then raise exception 'Incorrect audit count'; end if;
  if exists(select 1 from public.admin_role_changes where actor_id<>'00000000-0000-0000-0000-000000000001') then raise exception 'Wrong audit actor'; end if;
end $$;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
  begin perform public.admin_set_superadmin(auth.uid(),false,true); raise exception 'Remaining last admin demoted'; exception when check_violation then null; end;
end $$;
reset role;
