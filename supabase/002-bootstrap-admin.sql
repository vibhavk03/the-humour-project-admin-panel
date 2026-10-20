-- Target verified in the shared project: Vibhav Kashyap, with a Google identity.
-- Run as database owner AFTER 001-superadmin.sql. Never run from a browser client.
begin;
do $$
declare
  target_id uuid := 'c679baab-8190-4376-9f76-a0fb9bb25cb0';
begin
  if target_id = '00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Replace target_id with the verified Google account UUID first';
  end if;
  if not exists (
    select 1 from auth.identities where user_id = target_id and provider = 'google'
  ) then
    raise exception 'Target account has no Google identity';
  end if;
  update public.profiles set is_superadmin = true where id = target_id;
  if not found then
    raise exception 'Target has no profile; sign into the main app first';
  end if;
end;
$$;
commit;
