-- Media reads and guarded caption/context edits/deletion. No arbitrary table writes.
begin;
create table if not exists public.admin_media_changes (
  id bigint generated always as identity primary key, actor_id uuid not null,
  post_id uuid not null, action text not null check(action in ('update','delete')),
  previous_data jsonb not null, new_data jsonb, created_at timestamptz not null default now()
);
create table if not exists public.admin_media_cleanup (
  post_id uuid primary key, image_path text not null, created_at timestamptz not null default now(), completed_at timestamptz
);
alter table public.admin_media_changes enable row level security;
alter table public.admin_media_cleanup enable row level security;
revoke all on public.admin_media_changes,public.admin_media_cleanup from public,anon,authenticated;
revoke all on sequence public.admin_media_changes_id_seq from public,anon,authenticated;

create or replace function public.admin_media_list(search_query text default '', status_filter text default 'all', page_number integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare term text:=btrim(coalesce(search_query,'')); total bigint; selected_page integer; items jsonb;
begin
  if not exists(select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true) then raise exception 'Superadmin access required' using errcode='42501'; end if;
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
  if not exists(select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true) then raise exception 'Superadmin access required' using errcode='42501'; end if;
  return (select (to_jsonb(p)-'image_path')||jsonb_build_object('version',md5(to_jsonb(p)::text),
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
  if not exists(select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true) then raise exception 'Superadmin access required' using errcode='42501'; end if;
  select * into old_row from public.posts where id=target_id for update;
  if not found then raise exception 'Post not found' using errcode='P0002'; end if;
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
  if not exists(select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true) then raise exception 'Superadmin access required' using errcode='42501'; end if;
  select * into old_row from public.posts where id=target_id for update;
  if not found then
    select * into cleanup_row from public.admin_media_cleanup where post_id=target_id;
    if not found then raise exception 'Post not found' using errcode='P0002'; end if;
    return jsonb_build_object('path',cleanup_row.image_path,'cleanupPending',cleanup_row.completed_at is null);
  end if;
  if expected_version is null or md5(to_jsonb(old_row)::text)<>expected_version then raise exception 'This post changed. Reload before deleting.' using errcode='40001'; end if;
  if split_part(old_row.image_path,'/',1)<>old_row.user_id::text then raise exception 'Unexpected image ownership' using errcode='22023'; end if;
  insert into public.admin_media_cleanup(post_id,image_path) values(target_id,old_row.image_path);
  insert into public.admin_media_changes(actor_id,post_id,action,previous_data) values(auth.uid(),target_id,'delete',to_jsonb(old_row));
  delete from public.posts where id=target_id;
  return jsonb_build_object('path',old_row.image_path,'cleanupPending',true);
end; $$;

create or replace function public.admin_media_can_cleanup(object_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true)
    and exists(select 1 from public.admin_media_cleanup c where c.image_path=object_path and c.completed_at is null
      and not exists(select 1 from public.posts p where p.image_path=object_path));
$$;
create or replace function public.admin_media_finish_cleanup(target_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true) then raise exception 'Superadmin access required' using errcode='42501'; end if;
  update public.admin_media_cleanup c set completed_at=now() where c.post_id=target_id
    and not exists(select 1 from storage.objects o where o.bucket_id='post-images' and o.name=c.image_path);
  return found;
end; $$;
revoke all on function public.admin_media_list(text,text,integer),public.admin_media_detail(uuid),public.admin_media_update(uuid,text,text,text),public.admin_media_delete(uuid,text),public.admin_media_can_cleanup(text),public.admin_media_finish_cleanup(uuid) from public,anon,authenticated;
grant execute on function public.admin_media_list(text,text,integer),public.admin_media_detail(uuid),public.admin_media_update(uuid,text,text,text),public.admin_media_delete(uuid,text),public.admin_media_can_cleanup(text),public.admin_media_finish_cleanup(uuid) to authenticated;
drop policy if exists "Superadmins can remove queued deleted post images" on storage.objects;
create policy "Superadmins can remove queued deleted post images" on storage.objects for delete to authenticated
using(bucket_id='post-images' and public.admin_media_can_cleanup(name));
commit;
notify pgrst, 'reload schema';
