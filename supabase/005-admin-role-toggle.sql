-- Explicit role management; ordinary profile writes remain column-restricted.
begin;
create table if not exists public.admin_role_changes (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  target_id uuid not null,
  previous_status boolean not null,
  new_status boolean not null,
  created_at timestamptz not null default now()
);
alter table public.admin_role_changes enable row level security;
revoke all on public.admin_role_changes from public,anon,authenticated;
revoke all on sequence public.admin_role_changes_id_seq from public,anon,authenticated;
create or replace function public.admin_set_superadmin(target_id uuid, enabled boolean, expected_status boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare previous boolean; actor uuid := (select auth.uid());
begin
  if not exists (select 1 from public.profiles where id=actor and is_superadmin=true) then
    raise exception 'Superadmin access required' using errcode='42501';
  end if;
  if enabled is null or expected_status is null then raise exception 'Invalid role value' using errcode='22023'; end if;
  -- Serialize role changes, including simultaneous demotions of different admins.
  lock table public.profiles in share row exclusive mode;
  if not exists (select 1 from public.profiles where id=actor and is_superadmin=true) then
    raise exception 'Superadmin access required' using errcode='42501';
  end if;
  select is_superadmin into previous from public.profiles where id=target_id;
  if not found then raise exception 'Profile not found' using errcode='P0002'; end if;
  if previous <> expected_status then raise exception 'Role changed. Refresh and try again.' using errcode='40001'; end if;
  if previous = enabled then return previous; end if;
  if enabled and not exists (select 1 from auth.identities where user_id=target_id and provider='google') then
    raise exception 'This account needs a Google identity before becoming an admin.' using errcode='22023';
  end if;
  if not enabled and (select count(*) from public.profiles where is_superadmin=true) <= 1 then
    raise exception 'The last superadmin cannot be removed.' using errcode='23514';
  end if;
  update public.profiles set is_superadmin=enabled where id=target_id;
  insert into public.admin_role_changes(actor_id,target_id,previous_status,new_status) values(actor,target_id,previous,enabled);
  return enabled;
end; $$;
revoke all on function public.admin_set_superadmin(uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.admin_set_superadmin(uuid,boolean,boolean) to authenticated;
commit;
notify pgrst, 'reload schema';
