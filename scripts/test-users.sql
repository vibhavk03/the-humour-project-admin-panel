create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated,anon;
create schema storage;
create table storage.objects (bucket_id text, name text);
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated;
grant select on storage.objects to authenticated;
create table public.profiles (id uuid primary key, first_name text, last_name text, photo_url text, created_at timestamptz default now(), is_superadmin boolean default false);
create table public.posts (id uuid primary key, user_id uuid, image_path text, caption text, created_at timestamptz default now());
create table public.post_hearts (post_id uuid, user_id uuid, vote smallint);
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_hearts enable row level security;
grant select on public.profiles to authenticated;
create policy own_profile on public.profiles for select to authenticated using (id=auth.uid());
\ir ../supabase/004-admin-users.sql
\ir ../supabase/004-admin-users.sql
insert into public.profiles (id,first_name,last_name,is_superadmin,photo_url) values
('00000000-0000-0000-0000-000000000001','Admin','One',true,'00000000-0000-0000-0000-000000000001/avatar.png'),
('00000000-0000-0000-0000-000000000002','Alice','Jones',false,null);
insert into public.profiles (id,first_name,created_at)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'Person '||n,now()-n*interval '1 day' from generate_series(3,23)n;
insert into public.posts (id,user_id,image_path,caption)
select ('10000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002/'||n||'.gif',case when n=1 then null else 'Caption '||n end from generate_series(1,8)n;
insert into public.post_hearts values
('10000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000002',1),
('10000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000001',-1),
('10000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000002',1);
insert into storage.objects values ('photos','00000000-0000-0000-0000-000000000001/avatar.png'),('post-images','00000000-0000-0000-0000-000000000002/8.gif'),('other','secret');
set role anon;
do $$ begin
  begin perform public.admin_profiles(); raise exception 'Guest list leaked'; exception when insufficient_privilege then null; end;
  begin perform public.admin_profile_detail('00000000-0000-0000-0000-000000000002'); raise exception 'Guest detail leaked'; exception when insufficient_privilege then null; end;
  begin perform public.admin_profile_image('00000000-0000-0000-0000-000000000001'); raise exception 'Guest image leaked'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
  begin perform public.admin_profiles(); raise exception 'Member list leaked'; exception when insufficient_privilege then null; end;
  begin perform public.admin_profile_detail('00000000-0000-0000-0000-000000000001'); raise exception 'Member detail leaked'; exception when insufficient_privilege then null; end;
  begin perform public.admin_profile_image('00000000-0000-0000-0000-000000000001'); raise exception 'Member image leaked'; exception when insufficient_privilege then null; end;
  if (select count(*) from storage.objects)<>0 then raise exception 'Member storage leaked'; end if;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
do $$ declare r jsonb; d jsonb; begin
  r:=public.admin_profiles('',1);
  if (r->>'total')::int<>23 or jsonb_array_length(r->'profiles')<>10 then raise exception 'List count/pagination failed'; end if;
  if (select count(*) from public.profiles)<>1 then raise exception 'Base profile RLS expanded'; end if;
  r:=public.admin_profiles('',3);
  if jsonb_array_length(r->'profiles')<>3 then raise exception 'Last page failed'; end if;
  if public.admin_profiles('',999)->>'page'<>'3' then raise exception 'Out of bounds page failed'; end if;
  if public.admin_profiles('ALICE JONES')->>'total'<>'1' then raise exception 'Case-insensitive full name search failed'; end if;
  if public.admin_profiles('%')->>'total'<>'0' then raise exception 'Search wildcard was not literal'; end if;
  if public.admin_profiles('000000000002')->>'total'<>'1' then raise exception 'UUID search failed'; end if;
  d:=public.admin_profile_detail('00000000-0000-0000-0000-000000000002');
  if d->'profile'->>'post_count'<>'8' or d->'profile'->>'published_count'<>'7' or d->'profile'->>'vote_count'<>'2' then raise exception 'Detail counts wrong: %',d; end if;
  if jsonb_array_length(d->'posts')<>6 or d->'posts'->0->>'upvotes'<>'1' or d->'posts'->0->>'downvotes'<>'1' then raise exception 'Ratings/page incorrect'; end if;
  if jsonb_array_length(public.admin_profile_detail('00000000-0000-0000-0000-000000000002',2)->'posts')<>2 then raise exception 'Post page 2 failed'; end if;
  if public.admin_profile_detail('ffffffff-ffff-ffff-ffff-ffffffffffff') is not null then raise exception 'Missing profile not null'; end if;
  if public.admin_profile_image('00000000-0000-0000-0000-000000000002') is not null then raise exception 'Missing avatar not null'; end if;
  if public.admin_profile_image('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000008') is not null then raise exception 'Cross-user post image leaked'; end if;
  if public.admin_profile_image('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000008')->>'bucket'<>'post-images' then raise exception 'Post image failed'; end if;
  if (select count(*) from storage.objects)<>2 then raise exception 'Admin storage read scope wrong'; end if;
  begin perform public.admin_profiles('',0); raise exception 'Invalid page accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_profiles(repeat('a',101)); raise exception 'Long search accepted'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
update public.profiles set is_superadmin=false where id='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$ begin
  begin perform public.admin_profiles(); raise exception 'Revoked access retained'; exception when insufficient_privilege then null; end;
  if (select count(*) from storage.objects)<>0 then raise exception 'Revoked storage retained'; end if;
end $$;
reset role;
