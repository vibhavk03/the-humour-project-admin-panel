\ir ../supabase/012-pulse-date-range.sql
\ir ../supabase/012-pulse-date-range.sql
insert into public.posts(id,user_id,caption,created_at) values
 ('30000000-0000-0000-0000-000000000001','c679baab-8190-4376-9f76-a0fb9bb25cb0','Start boundary','2024-03-10 05:00:00+00'),
 ('30000000-0000-0000-0000-000000000002','c679baab-8190-4376-9f76-a0fb9bb25cb0','Last second','2024-03-11 03:59:59+00'),
 ('30000000-0000-0000-0000-000000000003','c679baab-8190-4376-9f76-a0fb9bb25cb0','Next day','2024-03-11 04:00:00+00');
set role authenticated;
set request.jwt.claim.sub='c679baab-8190-4376-9f76-a0fb9bb25cb0';
do $$ declare r jsonb; today date := (now() at time zone 'America/New_York')::date; begin
 r := public.admin_pulse_range('2024-03-10','2024-03-10');
 if jsonb_array_length(r->'days')<>1 or (r->'days'->0->>'memes')::int<>2 then raise exception 'Inclusive DST day boundaries failed: %',r;end if;
 r := public.admin_pulse_range('2024-03-09','2024-03-11');
 if jsonb_array_length(r->'days')<>3 or (r->'days'->0->>'memes')::int<>0 or (r->'days'->2->>'memes')::int<>1 then raise exception 'Historical calendar failed';end if;
 r := public.admin_pulse_range(today-365,today);
 if jsonb_array_length(r->'days')<>366 then raise exception 'Maximum range failed';end if;
 begin perform public.admin_pulse_range(today-366,today);raise exception 'Unbounded range allowed';exception when invalid_parameter_value then null;end;
 begin perform public.admin_pulse_range(today,today-1);raise exception 'Reversed range allowed';exception when invalid_parameter_value then null;end;
 begin perform public.admin_pulse_range(today,today+1);raise exception 'Future range allowed';exception when invalid_parameter_value then null;end;
 begin perform public.admin_pulse_range(null,today);raise exception 'Null range allowed';exception when invalid_parameter_value then null;end;
 r := public.admin_pulse(7);
 if jsonb_array_length(r->'days')<>7 then raise exception 'Preset regression';end if;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin
 begin perform public.admin_pulse_range('2024-03-10','2024-03-10');raise exception 'Member access allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
set role anon;
do $$ begin
 begin perform public.admin_pulse_range('2024-03-10','2024-03-10');raise exception 'Guest access allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
