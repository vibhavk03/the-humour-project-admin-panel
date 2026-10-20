-- Read-only inspection. Run in the SAME project used by the main app.
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name in ('profiles', 'posts', 'post_hearts')
order by table_name, ordinal_position;

select tablename, rowsecurity from pg_tables
where schemaname = 'public' and tablename in ('profiles', 'posts', 'post_hearts');

select tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename in ('profiles', 'posts', 'post_hearts');

select grantee, privilege_type from information_schema.table_privileges
where table_schema = 'public' and table_name = 'profiles'
order by grantee, privilege_type;

select grantee, column_name, privilege_type from information_schema.column_privileges
where table_schema = 'public' and table_name = 'profiles'
order by grantee, column_name, privilege_type;

select id, public, file_size_limit, allowed_mime_types
from storage.buckets where id in ('photos', 'post-images');

select 'profiles' as entity, count(*) from public.profiles
union all select 'posts', count(*) from public.posts
union all select 'post_hearts', count(*) from public.post_hearts;
