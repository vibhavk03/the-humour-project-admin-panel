-- Aggregate-only access. Apply as database owner; existing table RLS is unchanged.
begin;
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
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_superadmin = true) then
    raise exception 'Superadmin access required' using errcode = '42501';
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
commit;
notify pgrst, 'reload schema';
