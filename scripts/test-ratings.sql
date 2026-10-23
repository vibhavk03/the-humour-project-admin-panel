\ir test-users.sql
alter table public.post_hearts add column created_at timestamptz not null default now();
update public.profiles set is_superadmin=true where id='00000000-0000-0000-0000-000000000001';
insert into public.post_hearts(post_id,user_id,vote)
select '10000000-0000-0000-0000-000000000008',('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,1 from generate_series(3,23)n;
\ir ../supabase/007-admin-ratings.sql
\ir ../supabase/007-admin-ratings.sql
set role anon;
do $$ begin begin perform public.admin_ratings();raise exception 'Guest ratings leaked';exception when insufficient_privilege then null;end;end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
do $$ begin begin perform public.admin_ratings();raise exception 'Member ratings leaked';exception when insufficient_privilege then null;end;end $$;
set request.jwt.claim.sub='';
do $$ begin begin perform public.admin_ratings();raise exception 'Missing identity ratings leaked';exception when insufficient_privilege then null;end;end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
do $$ declare r jsonb;combined integer;begin
 r:=public.admin_ratings();
 if r->>'total'<>'24' or r->>'upvotes'<>'23' or r->>'downvotes'<>'1' or r->>'net'<>'22' then raise exception 'Summary incorrect: %',r;end if;
 if jsonb_array_length(r->'ratings')<>20 or jsonb_array_length(public.admin_ratings('','all',null,null,2)->'ratings')<>4 then raise exception 'Pagination incorrect';end if;
 select count(distinct(row->>'post_id',row->>'voter_id'))into combined from(select jsonb_array_elements(r->'ratings')as row union all select jsonb_array_elements(public.admin_ratings('','all',null,null,2)->'ratings')) t;
 if combined<>24 then raise exception 'Pagination duplicated or skipped records';end if;
 r:=public.admin_ratings('','down');if r->>'total'<>'1' or r->>'net'<>'-1' then raise exception 'Downvote filter/score failed';end if;
 if public.admin_ratings('','all','10000000-0000-0000-0000-000000000008')->>'total'<>'23' then raise exception 'Post filter failed';end if;
 if public.admin_ratings('','all',null,'00000000-0000-0000-0000-000000000002')->>'total'<>'2' then raise exception 'Voter filter failed';end if;
 if public.admin_ratings('','down',null,'00000000-0000-0000-0000-000000000002')->>'total'<>'0' then raise exception 'Combined filters failed';end if;
 if public.admin_ratings('ADMIN ONE')->>'total'<>'1' then raise exception 'Name search failed';end if;
 if public.admin_ratings('%')->>'total'<>'0' then raise exception 'Wildcard not literal';end if;
 if public.admin_ratings('','all',null,null,999)->>'page'<>'2' then raise exception 'Page clamp failed';end if;
 r:=public.admin_ratings('does not exist');if r->>'total'<>'0' or r->>'net'<>'0' or jsonb_array_length(r->'ratings')<>0 then raise exception 'Empty state failed';end if;
 begin perform public.admin_ratings('','invalid');raise exception 'Invalid filter accepted';exception when invalid_parameter_value then null;end;
 begin perform public.admin_ratings('','all',null,null,0);raise exception 'Invalid page accepted';exception when invalid_parameter_value then null;end;
 begin perform 1 from public.post_hearts;raise exception 'Base voter table exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set is_superadmin=false where id='00000000-0000-0000-0000-000000000001';
set role authenticated;
do $$ begin begin perform public.admin_ratings();raise exception 'Revoked admin retained access';exception when insufficient_privilege then null;end;end $$;
reset role;
