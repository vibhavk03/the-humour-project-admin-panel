-- Reproduce current main-app profile grants, ownership policies and write payloads.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon;
create table public.profiles (
  id uuid primary key,
  first_name text,
  last_name text,
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.profiles to authenticated;
alter table public.profiles enable row level security;
create policy own_read on public.profiles for select to authenticated using (auth.uid() = id);
create policy own_insert on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy own_update on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

\ir ../supabase/001-superadmin.sql
\ir ../supabase/001-superadmin.sql

insert into public.profiles (id, first_name) values ('00000000-0000-0000-0000-000000000001', 'Owner');
do $$ begin
  if (select is_superadmin from public.profiles limit 1) is distinct from false then
    raise exception 'Default must be false';
  end if;
end $$;
-- Database owner can bootstrap the first admin.
update public.profiles set is_superadmin = true where id = '00000000-0000-0000-0000-000000000001';

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
-- Existing default-profile creation and profile-editor upsert payloads.
insert into public.profiles (id, first_name, last_name)
values (auth.uid(), 'New user', null) on conflict (id) do nothing;
insert into public.profiles (id, first_name, last_name, photo_url, updated_at)
values (auth.uid(), 'Edited', 'Name', null, now())
on conflict (id) do update set id = excluded.id, first_name = excluded.first_name,
  last_name = excluded.last_name, photo_url = excluded.photo_url, updated_at = excluded.updated_at;
update public.profiles set photo_url = null, updated_at = now() where id = auth.uid();
do $$ begin
  if (select first_name from public.profiles where id = auth.uid()) <> 'Edited' then
    raise exception 'Existing profile edit broke';
  end if;
  if (select count(*) from public.profiles) <> 1 then raise exception 'Cross-user read leaked'; end if;
  begin
    update public.profiles set is_superadmin = true where id = auth.uid();
    raise exception 'Self-promotion succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.profiles (id, is_superadmin) values (auth.uid(), true)
    on conflict (id) do update set is_superadmin = excluded.is_superadmin;
    raise exception 'Upsert self-promotion succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.profiles (id, first_name) values ('00000000-0000-0000-0000-000000000003', 'Other');
    raise exception 'Cross-user insert succeeded';
  exception when insufficient_privilege then null; end;
  update public.profiles set first_name = 'Attacked' where id = '00000000-0000-0000-0000-000000000001';
  if found then raise exception 'Cross-user update succeeded'; end if;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$ begin
  if not (select is_superadmin from public.profiles where id = auth.uid()) then
    raise exception 'Owner bootstrap failed';
  end if;
  begin
    update public.profiles set is_superadmin = false where id = auth.uid();
    raise exception 'Admin flag editable with user token';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set role anon;
do $$ begin
  begin
    select * from public.profiles;
    raise exception 'Anonymous profile read succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.profiles (id, is_superadmin) values ('00000000-0000-0000-0000-000000000004', true);
    raise exception 'Anonymous admin insert succeeded';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
