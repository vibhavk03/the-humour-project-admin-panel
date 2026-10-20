# The Humour Project Admin Panel

Separate admin app for the existing Humour Project's shared Supabase database.
This repository contains the initial database permission setup and admin login app.

## Run the login app

The Next.js app now includes Google sign-in, an access-denied screen, a protected
welcome page, and a protected `/api/admin/session` endpoint.

1. `npm install`
2. Copy `.env.example` to `.env.local` and use the main app's Supabase URL and
   publishable key. No service-role key or Google client secret is needed here.
3. Set `APP_URL=http://localhost:3001` locally. In a deployment, set it to that
   deployment's exact HTTPS origin.
4. In Supabase Authentication → URL Configuration, add
   `http://localhost:3001/auth/callback` to Additional Redirect URLs. Keep the
   main app's existing Site URL and callback entries. Add the admin deployment's
   exact callback URL when deploying it.
5. `npm run dev`, then open `http://localhost:3001`.

The server starts Google OAuth using PKCE. Callback redirects have a fixed target
on `APP_URL`; arbitrary return URLs are not accepted. Login/sign-out accept only
same-origin POST requests. Admin cookies are separate from the main app's cookies,
HTTP-only, SameSite=Lax, and Secure in production.

`proxy.ts` denies all application routes by default except the login, denial and
authentication endpoints. Static Next.js assets are excluded. Both the welcome
page and session API independently check server-verified Google identity and the
current database flag. Future data pages/actions must call `requireAdmin()`;
future APIs must also call `checkAdmin()` before any database operation. There is
no privileged database client or cross-user database access in this login step.

Run `npm run test:auth`, `npm run lint`, `npm run typecheck`, and `npm run build`.
With the dev server running, `node scripts/test-login-http.mjs` checks signed-out
page/API protection, file-extension paths, and cross-origin POST rejection.

Verified locally on October 20, 2026: production build, lint, TypeScript, six auth
tests, and nine HTTP checks passed. The localhost callback was added in Supabase
with approval, and real Google sign-in reached the protected welcome page for
the confirmed superadmin. The authenticated session API returned the expected
account and admin status, and sign-out returned to the login page.
Production dependency audit reported zero advisories.
The full audit still reports five high-severity findings in the development-only
ESLint → fast-glob → micromatch → braces dependency chain; no forced downgrade was applied.

## Database map (confirmed against the live project)

| Entity | Relevant fields / purpose |
| --- | --- |
| `auth.users` / `auth.identities` | Account ID and verified Google identity; managed by Supabase Auth |
| `public.profiles` | ID references account; first/last name, private photo path, creation/update timestamps |
| `public.posts` | Author ID, owner-prefixed private image path, optional context/caption, generation prompt/version/model, creation timestamp |
| `public.post_hearts` | One row per post/user; vote is +1 or -1; creation timestamp; cascading post deletion |
| `storage.buckets` | Private `photos` and `post-images` buckets |

The existing public-feed views expose published content. Admin access will need
separate authorization; the new flag alone does not grant cross-user reads.

Live inspection on October 20, 2026 confirmed 10 profiles, 34 posts, 90 votes,
RLS on all three tables, owner-only profile policies, and both buckets private.
The target UUID `c679baab-8190-4376-9f76-a0fb9bb25cb0` belongs to Vibhav Kashyap
and has a Google identity. Counts will change as the main app is used.

Initial setup applied and verified on October 20, 2026: `001-superadmin.sql`
is live, and the confirmed target account has `is_superadmin = true`.
Exactly one profile is a superadmin. Effective authenticated-role privileges
deny both INSERT and UPDATE of the admin field. Local database tests passed
for profile upserts, ownership isolation, default false, and blocked self-promotion.
An interactive main-app Google sign-in/profile-edit smoke test remains pending.

## Apply the initial setup

1. In the main app's Supabase project, run `supabase/000-inspect.sql` and verify
   the live tables, ownership policies, grants, and private buckets match.
2. Apply `supabase/001-superadmin.sql` as the database owner. It is transactional
   and rerunnable. New profiles default to `is_superadmin = false`.
3. `002-bootstrap-admin.sql` targets the verified account above. Run that script
   as database owner only when granting that account access is authorized, then
   verify the target profile's flag. Reconfirm identity before adapting it for others.
4. Check an ordinary user's profile edit and Google sign-in still work.

Profile INSERT/UPDATE privileges explicitly allow only existing app payload fields.
Ownership RLS stays in place. Ordinary users, including a signed-in superadmin,
cannot write `is_superadmin` using their user token. Only trusted owner/service
access can grant/revoke it. No service credential belongs in browser code.

Do not rerun the main app's original `profiles.sql` blindly after this migration:
future migrations must preserve these column restrictions. Test the effective
grants again after any schema or permission change.

## Local security test

`sh scripts/test-superadmin.sh` runs against a disposable local PostgreSQL cluster;
it never connects to Supabase. Override `ADMIN_PG_BIN` if PostgreSQL is elsewhere.
