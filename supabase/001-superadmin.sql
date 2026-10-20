-- Apply as database owner in the shared Humour Project Supabase SQL Editor.
-- This adds the permission field only; it grants no cross-user admin access yet.
begin;

alter table public.profiles
  add column if not exists is_superadmin boolean not null default false;

-- Fail closed if a pre-existing field has an incompatible definition.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'is_superadmin' and data_type = 'boolean'
      and is_nullable = 'NO' and column_default = 'false'
  ) then
    raise exception 'profiles.is_superadmin must be boolean NOT NULL DEFAULT false';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass) then
    raise exception 'profiles RLS must be enabled before applying this migration';
  end if;
end;
$$;

-- Table-level grants override column restrictions: remove both forms first.
revoke insert, update on public.profiles from public, anon, authenticated;
do $$
declare column_list text;
begin
  select string_agg(quote_ident(attname), ', ') into column_list
  from pg_attribute
  where attrelid = 'public.profiles'::regclass and attnum > 0 and not attisdropped;
  execute format('revoke insert (%s), update (%s) on public.profiles from public, anon, authenticated', column_list, column_list);
end;
$$;

-- Match the existing app's profile upsert payload, including its conflict key.
-- Existing ownership RLS still restricts whose row can be inserted/updated.
grant insert (id, first_name, last_name, photo_url, updated_at),
      update (id, first_name, last_name, photo_url, updated_at)
  on public.profiles to authenticated;

comment on column public.profiles.is_superadmin is
  'Admin permission. Default false; writable only through trusted database-owner/service access, never user profile requests.';

commit;
notify pgrst, 'reload schema';
