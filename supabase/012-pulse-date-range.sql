-- Inclusive calendar dates in America/New_York; existing preset RPC is unchanged.
begin;
create or replace function public.admin_pulse_range(start_date date, end_date date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  zone_name constant text := 'America/New_York';
  today date := (now() at time zone zone_name)::date;
  first_day date := start_date;
  period_days integer := end_date - start_date + 1;
  range_end timestamptz;
  result jsonb;
begin
  if not public.has_admin_access() then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if start_date is null or end_date is null or start_date > end_date or end_date > today or period_days > 366 then
    raise exception 'Choose a valid range of up to 366 days ending on or before today' using errcode = '22023';
  end if;
  range_end := least(((end_date + 1)::timestamp at time zone zone_name), now());
  with calendar as (
    select first_day + n as day from generate_series(0, period_days - 1) n
  ), users_daily as (
    select (created_at at time zone zone_name)::date as day, count(*) as total
    from public.profiles where created_at >= (first_day::timestamp at time zone zone_name) and created_at < range_end group by 1
  ), memes_daily as (
    select (created_at at time zone zone_name)::date as day, count(*) as total
    from public.posts where caption is not null and created_at >= (first_day::timestamp at time zone zone_name) and created_at < range_end group by 1
  ), votes_daily as (
    select (created_at at time zone zone_name)::date as day,
      count(*) filter (where vote = 1) as upvotes, count(*) filter (where vote = -1) as downvotes
    from public.post_hearts where created_at >= (first_day::timestamp at time zone zone_name) and created_at < range_end group by 1
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
revoke all on function public.admin_pulse_range(date,date) from public, anon, authenticated;
grant execute on function public.admin_pulse_range(date,date) to authenticated;
commit;
notify pgrst, 'reload schema';
