-- Read-only users/profiles section. Apply as database owner.
begin;
create or replace function public.admin_profiles(search_query text default '', page_number integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  term text := btrim(coalesce(search_query, ''));
  total bigint;
  selected_page integer;
  rows_json jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_superadmin = true) then
    raise exception 'Superadmin access required' using errcode = '42501';
  end if;
  if char_length(term) > 100 or page_number is null or page_number < 1 then
    raise exception 'Invalid search or page' using errcode = '22023';
  end if;
  select count(*) into total from public.profiles p
  where term = '' or strpos(lower(concat_ws(' ', p.first_name, p.last_name)), lower(term)) > 0 or strpos(p.id::text, lower(term)) > 0;
  selected_page := least(page_number, greatest(1, ceil(total / 10.0)::integer));
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc), '[]'::jsonb) into rows_json from (
    select p.id, p.first_name, p.last_name, p.created_at, p.is_superadmin, (p.photo_url is not null) as has_avatar,
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
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_superadmin = true) then
    raise exception 'Superadmin access required' using errcode = '42501';
  end if;
  if post_page is null or post_page < 1 then raise exception 'Invalid page' using errcode = '22023'; end if;
  select jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,
    'created_at',p.created_at,'is_superadmin',p.is_superadmin,'has_avatar',p.photo_url is not null,
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
  if not exists (select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true) then
    raise exception 'Superadmin access required' using errcode='42501';
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
using (bucket_id in ('photos','post-images') and exists (
  select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true
));
commit;
notify pgrst, 'reload schema';
