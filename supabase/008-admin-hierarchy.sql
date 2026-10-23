-- Two-tier control room access. Apply after 001–007 as database owner.
-- The sole superadmin is fixed; the app can grant/revoke only the Admin role.
begin;
alter table public.profiles add column if not exists is_admin boolean not null default false;
lock table public.profiles in share row exclusive mode;
do $$ begin
  if not exists(select 1 from public.profiles where id='c679baab-8190-4376-9f76-a0fb9bb25cb0') then
    raise exception 'Owner profile missing; no roles changed';
  end if;
  if not exists(select 1 from auth.identities where user_id='c679baab-8190-4376-9f76-a0fb9bb25cb0' and provider='google') then
    raise exception 'Owner must have a Google identity';
  end if;
end $$;
alter table public.admin_role_changes add column if not exists role_kind text not null default 'superadmin';
-- Preserve other existing administrators' access, but remove their owner powers.
insert into public.admin_role_changes(actor_id,target_id,previous_status,new_status,role_kind)
select 'c679baab-8190-4376-9f76-a0fb9bb25cb0',id,true,false,'superadmin' from public.profiles
where is_superadmin and id<>'c679baab-8190-4376-9f76-a0fb9bb25cb0';
update public.profiles set is_admin=true where is_superadmin and id<>'c679baab-8190-4376-9f76-a0fb9bb25cb0';
update public.profiles set is_superadmin=(id='c679baab-8190-4376-9f76-a0fb9bb25cb0') where is_superadmin or id='c679baab-8190-4376-9f76-a0fb9bb25cb0';
alter table public.profiles drop constraint if exists profiles_sole_superadmin;
alter table public.profiles add constraint profiles_sole_superadmin
check (is_superadmin = (id='c679baab-8190-4376-9f76-a0fb9bb25cb0'::uuid));
-- Reset column grants, including any accidentally broad grants, then allow only profile fields.
revoke insert,update on public.profiles from public,anon,authenticated;
do $$ declare cols text; begin
 select string_agg(quote_ident(attname),',') into cols from pg_attribute
 where attrelid='public.profiles'::regclass and attnum>0 and not attisdropped;
 execute format('revoke insert (%s), update (%s) on public.profiles from public,anon,authenticated',cols,cols);
end $$;
grant insert(id,first_name,last_name,photo_url,updated_at),update(id,first_name,last_name,photo_url,updated_at) on public.profiles to authenticated;

-- No authenticated app operation may remove or change ownership of the owner profile.
create or replace function public.protect_superadmin_profile()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.is_superadmin and auth.uid() is not null then
  if tg_op='DELETE' then raise exception 'Superadmin profile is protected' using errcode='42501'; end if;
  if new.id is distinct from old.id or new.is_superadmin is distinct from old.is_superadmin
    or new.is_admin is distinct from old.is_admin or auth.uid()<>old.id then
   raise exception 'Superadmin profile is protected' using errcode='42501';
  end if;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function public.protect_superadmin_profile() from public,anon,authenticated;
drop trigger if exists protect_superadmin_profile on public.profiles;
create trigger protect_superadmin_profile before update or delete on public.profiles
for each row execute function public.protect_superadmin_profile();

create or replace function public.has_admin_access()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and (is_superadmin or is_admin));
$$;
revoke all on function public.has_admin_access() from public,anon,authenticated;
grant execute on function public.has_admin_access() to authenticated;

-- Remove the legacy privilege-escalation path even for older app deployments.
create or replace function public.admin_set_superadmin(target_id uuid, enabled boolean, expected_status boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin raise exception 'Superadmin is fixed. Use Admin role management.' using errcode='42501'; end $$;
revoke all on function public.admin_set_superadmin(uuid,boolean,boolean) from public,anon,authenticated;
create or replace function public.admin_set_admin(target_id uuid, enabled boolean, expected_status boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare previous boolean; actor uuid:=auth.uid();
begin
 lock table public.profiles in share row exclusive mode;
 if not exists(select 1 from public.profiles where id=actor and is_superadmin) then
  raise exception 'Only the superadmin can manage admins' using errcode='42501'; end if;
 if enabled is null or expected_status is null then raise exception 'Invalid role value' using errcode='22023'; end if;
 select is_admin into previous from public.profiles where id=target_id;
 if not found then raise exception 'Profile not found' using errcode='P0002'; end if;
 if exists(select 1 from public.profiles where id=target_id and is_superadmin) then
  raise exception 'Superadmin profile is protected' using errcode='42501'; end if;
 if previous<>expected_status then raise exception 'Role changed. Refresh and try again.' using errcode='40001'; end if;
 if enabled and not exists(select 1 from auth.identities where user_id=target_id and provider='google') then
  raise exception 'This account needs a Google identity before becoming an admin.' using errcode='22023'; end if;
 if previous=enabled then return previous; end if;
 update public.profiles set is_admin=enabled where id=target_id;
 insert into public.admin_role_changes(actor_id,target_id,previous_status,new_status,role_kind)
 values(actor,target_id,previous,enabled,'admin');
 return enabled;
end $$;
revoke all on function public.admin_set_admin(uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.admin_set_admin(uuid,boolean,boolean) to authenticated;

create or replace function public.admin_pulse(period_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  zone_name constant text := 'America/New_York';
  today date := (now() at time zone zone_name)::date;
  first_day date;
  result jsonb;
begin
  if not public.has_admin_access() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if period_days is null or period_days not in (7, 30, 90) then
    raise exception 'Choose 7, 30 or 90 days' using errcode = '22023';
  end if;
  first_day := today - (period_days - 1);
  with calendar as (
    select first_day + n as day from generate_series(0, period_days - 1) n
  ), users_daily as (
    select (created_at at time zone zone_name)::date as day, count(*) as total
    from public.profiles where created_at >= (first_day::timestamp at time zone zone_name) and created_at <= now() group by 1
  ), memes_daily as (
    select (created_at at time zone zone_name)::date as day, count(*) as total
    from public.posts where caption is not null and created_at >= (first_day::timestamp at time zone zone_name) and created_at <= now() group by 1
  ), votes_daily as (
    select (created_at at time zone zone_name)::date as day,
      count(*) filter (where vote = 1) as upvotes, count(*) filter (where vote = -1) as downvotes
    from public.post_hearts where created_at >= (first_day::timestamp at time zone zone_name) and created_at <= now() group by 1
  )
  select jsonb_build_object(
    'generatedAt', now(), 'timezone', zone_name, 'periodDays', period_days,
    'totals', jsonb_build_object(
      'users', (select count(*) from public.profiles),
      'memes', (select count(*) from public.posts where caption is not null),
      'upvotes', (select count(*) from public.post_hearts where vote = 1),
      'downvotes', (select count(*) from public.post_hearts where vote = -1)
    ),
    'days', jsonb_agg(jsonb_build_object(
      'date', c.day, 'users', coalesce(u.total, 0), 'memes', coalesce(m.total, 0),
      'upvotes', coalesce(v.upvotes, 0), 'downvotes', coalesce(v.downvotes, 0)
    ) order by c.day)
  ) into result from calendar c
  left join users_daily u using (day) left join memes_daily m using (day) left join votes_daily v using (day);
  return result;
end;
$$;
revoke all on function public.admin_pulse(integer) from public, anon, authenticated;
grant execute on function public.admin_pulse(integer) to authenticated;
comment on function public.admin_pulse(integer) is
  'Superadmin-only aggregate statistics. No private profile/media/voter rows returned. Days use America/New_York.';



create or replace function public.admin_profiles(search_query text default '', page_number integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  term text := btrim(coalesce(search_query, ''));
  total bigint;
  selected_page integer;
  rows_json jsonb;
begin
  if not public.has_admin_access() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if char_length(term) > 100 or page_number is null or page_number < 1 then
    raise exception 'Invalid search or page' using errcode = '22023';
  end if;
  select count(*) into total from public.profiles p
  where term = '' or strpos(lower(concat_ws(' ', p.first_name, p.last_name)), lower(term)) > 0 or strpos(p.id::text, lower(term)) > 0;
  selected_page := least(page_number, greatest(1, ceil(total / 10.0)::integer));
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc), '[]'::jsonb) into rows_json from (
    select p.id, p.first_name, p.last_name, p.created_at, p.is_superadmin, p.is_admin, (p.photo_url is not null) as has_avatar,
      (select count(*) from public.posts where user_id = p.id) as post_count,
      (select count(*) from public.post_hearts where user_id = p.id) as vote_count
    from public.profiles p
    where term = '' or strpos(lower(concat_ws(' ', p.first_name, p.last_name)), lower(term)) > 0 or strpos(p.id::text, lower(term)) > 0
    order by p.created_at desc, p.id desc limit 10 offset ((selected_page - 1)::bigint * 10)
  ) r;
  return jsonb_build_object('profiles', rows_json, 'total', total, 'page', selected_page, 'pageSize', 10);
end; $$;

create or replace function public.admin_profile_detail(target_id uuid, post_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  profile_json jsonb;
  posts_json jsonb;
  total bigint;
  selected_page integer;
begin
  if not public.has_admin_access() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if post_page is null or post_page < 1 then raise exception 'Invalid page' using errcode = '22023'; end if;
  select jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,
    'created_at',p.created_at,'is_superadmin',p.is_superadmin,'is_admin',p.is_admin,'has_avatar',p.photo_url is not null,
    'post_count',(select count(*) from public.posts where user_id=p.id),
    'published_count',(select count(*) from public.posts where user_id=p.id and caption is not null),
    'vote_count',(select count(*) from public.post_hearts where user_id=p.id),
    'upvotes_cast',(select count(*) from public.post_hearts where user_id=p.id and vote=1),
    'downvotes_cast',(select count(*) from public.post_hearts where user_id=p.id and vote=-1)
  ) into profile_json from public.profiles p where p.id=target_id;
  if profile_json is null then return null; end if;
  total := (profile_json->>'post_count')::bigint;
  selected_page := least(post_page, greatest(1, ceil(total / 6.0)::integer));
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc),'[]'::jsonb) into posts_json from (
    select p.id,p.caption,p.created_at,
      (select count(*) from public.post_hearts where post_id=p.id and vote=1) as upvotes,
      (select count(*) from public.post_hearts where post_id=p.id and vote=-1) as downvotes
    from public.posts p where p.user_id=target_id order by p.created_at desc,p.id desc
    limit 6 offset ((selected_page-1)::bigint*6)
  ) r;
  return jsonb_build_object('profile',profile_json,'posts',posts_json,'page',selected_page,'pageSize',6);
end; $$;

-- Returns only the current target's image path, never an arbitrary supplied path.
create or replace function public.admin_profile_image(target_id uuid, target_post_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare path text;
begin
  if not public.has_admin_access() then
    raise exception 'Admin access required' using errcode='42501';
  end if;
  if target_post_id is null then
    select photo_url into path from public.profiles where id=target_id;
  else
    select image_path into path from public.posts where id=target_post_id and user_id=target_id;
  end if;
  if path is null or split_part(path,'/',1) <> target_id::text then return null; end if;
  return jsonb_build_object('bucket',case when target_post_id is null then 'photos' else 'post-images' end,'path',path);
end; $$;

revoke all on function public.admin_profiles(text,integer) from public,anon,authenticated;
revoke all on function public.admin_profile_detail(uuid,integer) from public,anon,authenticated;
revoke all on function public.admin_profile_image(uuid,uuid) from public,anon,authenticated;
grant execute on function public.admin_profiles(text,integer) to authenticated;
grant execute on function public.admin_profile_detail(uuid,integer) to authenticated;
grant execute on function public.admin_profile_image(uuid,uuid) to authenticated;
-- Existing owner and public-feed policies remain in place. This is SELECT only.
drop policy if exists "Superadmins can read profile and post images" on storage.objects;
create policy "Superadmins can read profile and post images" on storage.objects for select to authenticated
using (bucket_id in ('photos','post-images') and public.has_admin_access());



create or replace function public.admin_media_list(search_query text default '', status_filter text default 'all', page_number integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare term text:=btrim(coalesce(search_query,'')); total bigint; selected_page integer; items jsonb;
begin
  if not public.has_admin_access() then raise exception 'Admin access required' using errcode='42501'; end if;
  if char_length(term)>100 or status_filter is null or status_filter not in ('all','published','unpublished') or page_number is null or page_number<1 then raise exception 'Invalid filter or page' using errcode='22023'; end if;
  select count(*) into total from public.posts p left join public.profiles a on a.id=p.user_id
  where (status_filter='all' or (status_filter='published' and p.caption is not null) or (status_filter='unpublished' and p.caption is null))
    and (term='' or strpos(lower(concat_ws(' ',p.caption,a.first_name,a.last_name,p.id::text,p.user_id::text)),lower(term))>0);
  selected_page:=least(page_number,greatest(1,ceil(total/12.0)::integer));
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]'::jsonb) into items from (
    select p.id,p.user_id,p.caption,p.created_at,nullif(btrim(concat_ws(' ',a.first_name,a.last_name)),'') as author_name,
      (select count(*) from public.post_hearts where post_id=p.id and vote=1) as upvotes,
      (select count(*) from public.post_hearts where post_id=p.id and vote=-1) as downvotes
    from public.posts p left join public.profiles a on a.id=p.user_id
    where (status_filter='all' or (status_filter='published' and p.caption is not null) or (status_filter='unpublished' and p.caption is null))
      and (term='' or strpos(lower(concat_ws(' ',p.caption,a.first_name,a.last_name,p.id::text,p.user_id::text)),lower(term))>0)
    order by p.created_at desc,p.id desc limit 12 offset((selected_page-1)::bigint*12)
  )r;
  return jsonb_build_object('posts',items,'total',total,'page',selected_page,'pageSize',12);
end; $$;

create or replace function public.admin_media_detail(target_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not public.has_admin_access() then raise exception 'Admin access required' using errcode='42501'; end if;
  return (select (to_jsonb(p)-'image_path')||jsonb_build_object('version',md5(to_jsonb(p)::text),
    'can_manage',not coalesce(a.is_superadmin,false) or exists(select 1 from public.profiles where id=auth.uid() and is_superadmin),
    'author_name',nullif(btrim(concat_ws(' ',a.first_name,a.last_name)),''),
    'upvotes',(select count(*) from public.post_hearts where post_id=p.id and vote=1),
    'downvotes',(select count(*) from public.post_hearts where post_id=p.id and vote=-1))
    from public.posts p left join public.profiles a on a.id=p.user_id where p.id=target_id);
end; $$;

create or replace function public.admin_media_update(target_id uuid, expected_version text, new_caption text, new_context text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old_row public.posts%rowtype; updated_row public.posts%rowtype;
  caption_value text:=nullif(btrim(new_caption),''); context_value text:=nullif(btrim(new_context),'');
begin
  lock table public.profiles in share mode;
  if not public.has_admin_access() then raise exception 'Admin access required' using errcode='42501'; end if;
  select * into old_row from public.posts where id=target_id for update;
  if not found then raise exception 'Post not found' using errcode='P0002'; end if;
  if exists(select 1 from public.profiles where id=old_row.user_id and is_superadmin)
    and not exists(select 1 from public.profiles where id=auth.uid() and is_superadmin) then
    raise exception 'Superadmin posts are protected' using errcode='42501'; end if;
  if expected_version is null or md5(to_jsonb(old_row)::text)<>expected_version then raise exception 'This post changed. Reload before saving.' using errcode='40001'; end if;
  if char_length(caption_value)>200 or char_length(context_value)>1000 or (old_row.caption is not null and caption_value is null) then
    raise exception 'Use a nonempty caption up to 200 characters and context up to 1000 characters.' using errcode='22023'; end if;
  if old_row.caption is not distinct from caption_value and old_row.context is not distinct from context_value then return public.admin_media_detail(target_id); end if;
  update public.posts set caption=caption_value,context=context_value where id=target_id returning * into updated_row;
  insert into public.admin_media_changes(actor_id,post_id,action,previous_data,new_data) values(auth.uid(),target_id,'update',to_jsonb(old_row),to_jsonb(updated_row));
  return public.admin_media_detail(target_id);
end; $$;

create or replace function public.admin_media_delete(target_id uuid, expected_version text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old_row public.posts%rowtype; cleanup_row public.admin_media_cleanup%rowtype;
begin
  lock table public.profiles in share mode;
  if not public.has_admin_access() then raise exception 'Admin access required' using errcode='42501'; end if;
  select * into old_row from public.posts where id=target_id for update;
  if not found then
    select * into cleanup_row from public.admin_media_cleanup where post_id=target_id;
    if not found then raise exception 'Post not found' using errcode='P0002'; end if;
    return jsonb_build_object('path',cleanup_row.image_path,'cleanupPending',cleanup_row.completed_at is null);
  end if;
  if exists(select 1 from public.profiles where id=old_row.user_id and is_superadmin)
    and not exists(select 1 from public.profiles where id=auth.uid() and is_superadmin) then
    raise exception 'Superadmin posts are protected' using errcode='42501'; end if;
  if expected_version is null or md5(to_jsonb(old_row)::text)<>expected_version then raise exception 'This post changed. Reload before deleting.' using errcode='40001'; end if;
  if split_part(old_row.image_path,'/',1)<>old_row.user_id::text then raise exception 'Unexpected image ownership' using errcode='22023'; end if;
  insert into public.admin_media_cleanup(post_id,image_path) values(target_id,old_row.image_path);
  insert into public.admin_media_changes(actor_id,post_id,action,previous_data) values(auth.uid(),target_id,'delete',to_jsonb(old_row));
  delete from public.posts where id=target_id;
  return jsonb_build_object('path',old_row.image_path,'cleanupPending',true);
end; $$;

create or replace function public.admin_media_can_cleanup(object_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select public.has_admin_access()
    and exists(select 1 from public.admin_media_cleanup c where c.image_path=object_path and c.completed_at is null
      and not exists(select 1 from public.posts p where p.image_path=object_path));
$$;
create or replace function public.admin_media_finish_cleanup(target_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not public.has_admin_access() then raise exception 'Admin access required' using errcode='42501'; end if;
  update public.admin_media_cleanup c set completed_at=now() where c.post_id=target_id
    and not exists(select 1 from storage.objects o where o.bucket_id='post-images' and o.name=c.image_path);
  return found;
end; $$;
revoke all on function public.admin_media_list(text,text,integer),public.admin_media_detail(uuid),public.admin_media_update(uuid,text,text,text),public.admin_media_delete(uuid,text),public.admin_media_can_cleanup(text),public.admin_media_finish_cleanup(uuid) from public,anon,authenticated;
grant execute on function public.admin_media_list(text,text,integer),public.admin_media_detail(uuid),public.admin_media_update(uuid,text,text,text),public.admin_media_delete(uuid,text),public.admin_media_can_cleanup(text),public.admin_media_finish_cleanup(uuid) to authenticated;
drop policy if exists "Superadmins can remove queued deleted post images" on storage.objects;
create policy "Superadmins can remove queued deleted post images" on storage.objects for delete to authenticated
using(bucket_id='post-images' and public.admin_media_can_cleanup(name));



create or replace function public.admin_ratings(search_query text default '', direction_filter text default 'all', target_post uuid default null, target_voter uuid default null, page_number integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare term text:=btrim(coalesce(search_query,'')); result jsonb;
begin
  if not public.has_admin_access() then raise exception 'Admin access required' using errcode='42501';end if;
  if char_length(term)>100 or direction_filter is null or direction_filter not in ('all','up','down') or page_number is null or page_number<1 then raise exception 'Invalid ratings filter or page' using errcode='22023';end if;
  with filtered as materialized (
    select v.post_id,v.user_id as voter_id,v.vote,v.created_at,p.user_id as author_id,p.caption,
      nullif(btrim(concat_ws(' ',voter.first_name,voter.last_name)),'') as voter_name,
      nullif(btrim(concat_ws(' ',author.first_name,author.last_name)),'') as author_name
    from public.post_hearts v join public.posts p on p.id=v.post_id
    left join public.profiles voter on voter.id=v.user_id left join public.profiles author on author.id=p.user_id
    where (direction_filter='all' or(direction_filter='up' and v.vote=1)or(direction_filter='down' and v.vote=-1))
      and(target_post is null or v.post_id=target_post)and(target_voter is null or v.user_id=target_voter)
      and(term='' or strpos(lower(concat_ws(' ',p.caption,voter.first_name,voter.last_name,author.first_name,author.last_name,v.post_id::text,v.user_id::text)),lower(term))>0)
  ), stats as (
    select count(*) as total,count(*)filter(where vote=1)as upvotes,count(*)filter(where vote=-1)as downvotes from filtered
  ), paging as (
    select *,least(page_number,greatest(1,ceil(total/20.0)::integer))as selected_page from stats
  ), items as (
    select * from filtered order by created_at desc,post_id desc,voter_id desc limit 20 offset((select selected_page-1 from paging)::bigint*20)
  )
  select jsonb_build_object('total',total,'upvotes',upvotes,'downvotes',downvotes,'net',upvotes-downvotes,'page',selected_page,'pageSize',20,
    'ratings',(select coalesce(jsonb_agg(to_jsonb(i)order by i.created_at desc,i.post_id desc,i.voter_id desc),'[]'::jsonb)from items i))into result from paging;
  return result;
end; $$;
revoke all on function public.admin_ratings(text,text,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.admin_ratings(text,text,uuid,uuid,integer) to authenticated;
comment on function public.admin_ratings(text,text,uuid,uuid,integer) is 'Read-only superadmin vote list. Creation timestamps reflect current rows, not vote-change events.';



commit;
notify pgrst, 'reload schema';
