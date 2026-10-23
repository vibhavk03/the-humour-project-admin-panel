-- Read-only individual vote inspection; existing voter RLS is unchanged.
begin;
create or replace function public.admin_ratings(search_query text default '', direction_filter text default 'all', target_post uuid default null, target_voter uuid default null, page_number integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare term text:=btrim(coalesce(search_query,'')); result jsonb;
begin
  if not exists(select 1 from public.profiles where id=(select auth.uid()) and is_superadmin=true) then raise exception 'Superadmin access required' using errcode='42501';end if;
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
