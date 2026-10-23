# The Humour Project Admin Panel

Separate admin app for the existing Humour Project's shared Supabase database.
This repository contains the initial database permission setup and admin login app.

## Read-only users / profiles

Open `/users` from the sidebar. The directory searches names (case-insensitive
literal substrings) or account UUIDs, with ten profiles per page, newest first
and an ID tie-breaker. Search terms and page numbers are stored in the URL.
Each `/users/[id]` detail page shows name/avatar, account ID, join date, admin
status, post and vote counts, plus six posts per page with current upvotes,
downvotes and net scores. Back to users preserves the directory search/page.
User email and authentication details are not fetched for this section.

`supabase/004-admin-users.sql` was applied to the shared project with approval
on October 23, 2026. It adds `admin_profiles`, `admin_profile_detail`, and
`admin_profile_image`. Every function rechecks the caller's current superadmin
flag, has an empty search path, rejects guests/nonadmins, and performs reads
only. Existing profile/post/vote table RLS and all write permissions are unchanged.
The new storage SELECT policy allows existing superadmins to read `photos` and
`post-images`; it does not allow uploads, updates or deletes.

`/api/admin/users/[id]/image` verifies Google/admin access again, resolves only
the current target's avatar or owned post path, and downloads with the caller's
session. It accepts PNG/JPEG/WebP/GIF up to 5 MB and returns private, no-store,
nosniff responses. No storage paths or reusable signed URLs are put in the page.
Avatars fall back to initials and missing post images show an unavailable state.
All users pages remain protected by the default-deny proxy and page-level guard.

Posts include unpublished uploads; published means a non-null saved caption.
Votes cast counts current vote rows, while post ratings count votes received.
Dates use America/New_York. Profile fields, media and ratings remain read-only; superadmin access is managed separately using the toggle described below.

Validation: `sh scripts/test-users.sh` uses a disposable local PostgreSQL cluster
to test search, list/post pagination, counts, ratings, missing data, image ownership,
guest/member denial, revoked admin access, and unchanged base-table RLS. Build,
lint, TypeScript, auth tests and signed-out HTTP checks passed. Live browser checks
confirmed search/empty results, avatars/post images, detail counts/ratings and
post pagination. The live directory had ten profiles at verification time.

## The Pulse dashboard

The protected home page shows live all-time counts for profiles, published memes
(posts with a non-null caption, matching `home_feed`), and current votes split
into up/down. The 7/30/90-day selector changes the daily chart and recent counts;
all-time totals remain all-time. Today is included. Days use America/New_York,
and inactive dates are filled with zeroes.

Apply `supabase/003-admin-pulse.sql` as database owner to enable the dashboard.
The function returns aggregates only, checks the current caller's superadmin
flag inside the database, rejects guests/ordinary users, and restricts ranges to
7/30/90 days. No table-level RLS policies or write permissions change.
The app uses the existing user's token, with no service-role key. Requests still
pass the existing Google login and admin checks. Statistics are fetched on each
page request; Refresh data performs a fresh request.

Chart series can be toggled, each day can be inspected with a mouse, keyboard or
touch, and an expandable daily table provides the same numbers. A failed query
shows an unavailable state, never fabricated zeroes or sample data.

These are current-record statistics, not an event log: deleted records disappear,
vote switches retain the original vote creation time, and edited captions use
the original post creation time. User counts are profile counts, not a separate
count of Auth accounts. Vote totals cover current `post_hearts` rows.

`sh scripts/test-pulse.sh` validates the actual SQL in an isolated local PostgreSQL
cluster: authorization, permission revocation, draft exclusion, day boundaries,
empty data, allowed ranges and zero-filled dates. It never connects to Supabase.

Applied and verified in the shared project on October 20, 2026. The live function
returned 10 profiles, 34 published memes, 87 upvotes and 3 downvotes, plus 30
daily buckets. A nonadmin call was rejected and the anonymous role has no EXECUTE
privilege. Browser QA confirmed the seven-day filter, series toggle, daily
inspection and daily table. Build, lint, TypeScript, auth tests, SQL tests and
signed-out HTTP access checks passed. Deployment remains a separate step.

## Run the login app

The Next.js app now includes Google sign-in, an access-denied screen, a protected
welcome page, and a protected `/api/admin/session` endpoint.

1. `npm install`
2. Copy `.env.example` to `.env.local` and use the main app's Supabase URL and
   publishable key. No service-role key or Google client secret is needed here.
3. Set `APP_URL=http://localhost:3001` locally. On Vercel, the exact unique
   deployment origin is automatically trusted through the system `VERCEL_URL`.
   Set `APP_URL` to the stable production origin if you also want to use that
   domain (or to one exact branch/custom-domain origin).
4. In Supabase Authentication → URL Configuration, add
   `http://localhost:3001/auth/callback` to Additional Redirect URLs. Keep the
   main app's existing Site URL and callback entries. Add the admin deployment's
   exact callback URL when deploying it.
5. `npm run dev`, then open `http://localhost:3001`.

The server starts Google OAuth using PKCE. Login callbacks and subsequent redirects
stay on the incoming origin, only if it exactly matches the configured `APP_URL`
or `https://${VERCEL_URL}`. Arbitrary domains and return URLs are not accepted.
Login/sign-out and admin mutations require the Origin header to match that same
request origin. Untrusted origins fail with 403 rather than redirecting. Localhost
HTTP is accepted only when explicitly configured in a non-production environment.
Admin cookies are separate from the main app's cookies,
HTTP-only, SameSite=Lax, and Secure in production.

For commit-specific submissions, push this code and use the newly created unique
deployment URL. Keep Vercel's automatic system variables exposed so `VERCEL_URL`
is available; do not manually set it. Add that deployment's exact
`https://<deployment>/auth/callback` to Supabase's Additional Redirect URLs after
the deployment is ready. The Supabase allowlist change does not require another
redeploy. Keep the shared project's main-app Site URL and existing callback entries.
Older immutable deployments keep their original code/configuration.

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
cannot directly write `is_superadmin` through the profile table API. Existing
superadmins can use the guarded role-management RPC added by migration 005.
The initial administrator still needs trusted owner/service access to bootstrap.
No service credential belongs in browser code.

Do not rerun the main app's original `profiles.sql` blindly after this migration:
future migrations must preserve these column restrictions. Test the effective
grants again after any schema or permission change.

## Local security test

`sh scripts/test-superadmin.sh` runs against a disposable local PostgreSQL cluster;
it never connects to Supabase. Override `ADMIN_PG_BIN` if PostgreSQL is elsewhere.

## Superadmin toggle

Each profile detail page has a Superadmin access switch with an explicit
confirmation showing the target name and account ID. Only an existing
server-verified Google superadmin can call the same-origin PUT endpoint
`/api/admin/users/[id]/superadmin`. The database RPC independently checks the
current caller's role, requires a Google identity for a new admin, compares the
expected current status to reject stale writes, and serializes changes with a
table lock so simultaneous demotions cannot remove all admins. Direct profile
column writes remain blocked. A self-demotion redirects out of the admin area.

Migration `005-admin-role-toggle.sql` adds this capability and a protected
`admin_role_changes` audit table recording actor, target, before/after values
and time. The UI has no access to edit or read the audit log. Installing the
migration does not promote or demote any account.

Applied with approval on October 23, 2026. Live verification rejected a nonadmin
call and confirmed one existing superadmin, zero role-change audit records, and
no anonymous execute privilege. No actual user was promoted or demoted for testing.
The browser confirmation was checked without submitting a role change.

`sh scripts/test-admin-role.sh` verifies grants/revokes in a disposable local
database, including guest/member denial, last-admin protection, stale writes,
missing Google identities, audit records, and denied direct profile writes.

## Media: read, update and delete

`/media` lists all community posts (12 per page), with literal substring search
by caption, author name, post ID or author ID, plus published/unpublished filters.
`/media/[id]` shows the image/GIF, author, dates, current vote counts, private
context and original generation metadata. Profile post cards also link here.

Existing Google superadmins can edit captions (up to 200 characters) and private
context (up to 1,000). Authorship, image path, creation time and generation metadata
are preserved. Changing context does not call the AI service. Published captions
cannot be cleared; adding a caption to an unpublished upload publishes it, matching
the main app's existing non-null-caption rule. No creation, image replacement or
caption-regeneration workflow is included in this step.

Delete requires typing DELETE in the confirmation. The database deletes the post,
cascades its votes, and records the original row in a protected audit table in one
transaction. The server then removes the private image. Storage DELETE permission
is restricted to paths queued for cleanup after their post has been deleted;
admins cannot use the new policy to remove images of surviving posts. Cleanup
failures keep a durable pending record and show a retry button before leaving the
page. The same DELETE endpoint can safely retry cleanup after a network failure.
No background cleanup worker is installed; unresolved queue entries remain until
an administrator retries cleanup. The queue and audit tables are not exposed to
normal user tokens.

PATCH and DELETE use the existing authenticated session and a same-origin check.
Database functions independently check current superadmin access. Row locks and
an expected post version reject stale edits/deletions. Every actual edit/deletion
records the actor, time, and before/after data. Empty/no-op saves do not add audit
records. There is no privileged service key and no expansion of base post-table
write permissions. The public main app reads the same rows, so saved edits/deleted
posts appear there on refresh.

`supabase/006-admin-media.sql` was applied with approval on October 23, 2026.
`sh scripts/test-media.sh` tests real SQL in a disposable local PostgreSQL cluster,
including role denial, literal search/status filters, provenance preservation,
stale changes, caption limits, vote cascades, deletion replay, cleanup permissions,
and audit records. Build, lint, TypeScript and signed-out HTTP checks passed.
Browser QA checked the live gallery/detail, unsaved edit/reset behavior and delete
confirmation without saving or deleting any live post.

Live verification returned 37 posts, zero media-change audit records and zero
cleanup records after testing. A nonadmin media read was rejected. Browser checks
also covered page 2 of the gallery and the unpublished filter's empty state.

## Read-only Ratings

`/ratings` shows individual current upvote/downvote rows, voter profile links,
post thumbnails/captions and author links, and original vote creation timestamps.
It has 20 rows per page, newest first with post/voter IDs as deterministic tie
breakers. Literal text search matches names, captions and IDs; direction, exact
post UUID and exact voter UUID filters combine. Invalid IDs show validation
feedback. The three summary cards count matching upvotes, downvotes and net score,
so they change with the filters. Profile and media pages link to scoped ratings.
No voting controls or mutation endpoint are added.

`supabase/007-admin-ratings.sql` was applied with approval on October 23, 2026.
It adds one read-only RPC that checks the caller's current superadmin flag and
rejects guests and ordinary users. Base vote-table RLS and all existing write
permissions are unchanged. The page separately enforces Google/superadmin access
and remains covered by the default-deny proxy and private/no-store responses.
No auth account emails, private context, or generation prompts enter vote rows.

The timestamp is labelled Vote created because switching a vote retains its
original creation time. Removed votes and votes on deleted posts disappear; this
is a current-state view, not historical event tracking. Dates use America/New_York.

`sh scripts/test-ratings.sh` validates role denial, revoked access, summary math,
combined filters, literal search, two-page deterministic pagination, empty data
and unchanged base-table privacy in a disposable local PostgreSQL cluster. Build,
lint, TypeScript and signed-out HTTP checks passed. Browser QA verified live totals
of 88 upvotes / 3 downvotes / +85 net across 91 votes, pagination, direction/voter
filters and empty results. No votes were changed during implementation or testing.
