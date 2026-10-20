create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon;
create table public.profiles (id uuid primary key, is_superadmin boolean not null default false, created_at timestamptz not null default now());
create table public.posts (id integer primary key, caption text, created_at timestamptz not null default now());
create table public.post_hearts (vote smallint, created_at timestamptz not null default now());
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_hearts enable row level security;
-- No caller table grants: the function must check identity before using its owner.
\ir ../supabase/003-admin-pulse.sql
\ir ../supabase/003-admin-pulse.sql
insert into public.profiles (id,is_superadmin) values ('00000000-0000-0000-0000-000000000001',true), ('00000000-0000-0000-0000-000000000002',false);
insert into public.posts (id,caption,created_at) values
  (1,'Published',now()), (2,null,now()),
  (3,'Old',now()-interval '100 days'),
  (4,'Boundary', (((now() at time zone 'America/New_York')::date - 6)::timestamp at time zone 'America/New_York')),
  (5,'Before boundary', (((now() at time zone 'America/New_York')::date - 6)::timestamp at time zone 'America/New_York') - interval '1 millisecond');
insert into public.post_hearts (vote) values (1),(1),(-1);
set role anon;
do $$ begin
  begin perform public.admin_pulse(30); raise exception 'Anonymous access succeeded'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
do $$ begin
  begin perform public.admin_pulse(30); raise exception 'Nonadmin access succeeded'; exception when insufficient_privilege then null; end;
end $$;
set request.jwt.claim.sub = '';
do $$ begin
  begin perform public.admin_pulse(30); raise exception 'Missing identity succeeded'; exception when insufficient_privilege then null; end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
do $$ declare result jsonb; size integer; begin
  foreach size in array array[7,30,90] loop
    result := public.admin_pulse(size);
    if jsonb_array_length(result->'days') <> size then raise exception 'Missing calendar days'; end if;
    if (result->'days'->0->>'date')::date <> (now() at time zone 'America/New_York')::date-(size-1) then raise exception 'Wrong start day'; end if;
  end loop;
  result := public.admin_pulse(7);
  if result->'totals' <> '{"users":2,"memes":4,"upvotes":2,"downvotes":1}'::jsonb then raise exception 'Incorrect totals: %',result; end if;
  if (select sum((d->>'memes')::int) from jsonb_array_elements(result->'days') d) <> 2 then raise exception 'Draft or out-of-range record counted'; end if;
  if (result->'days'->0->>'memes')::int <> 1 then raise exception 'New York boundary wrong'; end if;
  if (result->'days'->1->>'users')::int <> 0 then raise exception 'Zero filling failed'; end if;
  if result->'days'->6->>'date' <> ((now() at time zone 'America/New_York')::date)::text then raise exception 'Today missing'; end if;
  begin perform public.admin_pulse(10000); raise exception 'Unbounded period allowed'; exception when invalid_parameter_value then null; end;
  begin perform public.admin_pulse(null); raise exception 'Null period allowed'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
update public.profiles set is_superadmin=false where id='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$ begin
  begin perform public.admin_pulse(30); raise exception 'Revoked admin retained access'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.profiles set is_superadmin=true where id='00000000-0000-0000-0000-000000000001';
truncate public.posts, public.post_hearts;
set role authenticated;
do $$ declare result jsonb; begin
  result := public.admin_pulse(7);
  if (result->'totals'->>'memes')::int <> 0 or (select sum((d->>'upvotes')::int+(d->>'downvotes')::int) from jsonb_array_elements(result->'days') d) <> 0 then raise exception 'Empty data failed'; end if;
end $$;
reset role;
