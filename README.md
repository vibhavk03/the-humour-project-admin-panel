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

## Two-tier administrator roles

Apply `supabase/008-admin-hierarchy.sql` after migrations 001–007, **before deploying this app revision**. Applied with approval on October 23, 2026. Live checks confirmed one superadmin (Vibhav), zero Admins, blocked member self-promotion/direct role writes, disabled legacy superadmin changes, and working owner reads. Local PostgreSQL tests cover the Admin permission paths without granting a real account access. Older security descriptions below describe the original migrations; 008 replaces their superadmin-only read/media guards with checks for either role.

Vibhav's account (`c679baab-8190-4376-9f76-a0fb9bb25cb0`) is the sole Superadmin. A database constraint fixes this role to that account. No app endpoint can grant, remove, or transfer superadmin status; recovery requires trusted database-owner access. A trigger protects the owner profile from authenticated deletion or changes by other accounts. The owner can still edit their own ordinary profile fields in the main app.

Only the superadmin sees the Admin access switch on other profiles. The same-origin `PUT /api/admin/users/[id]/admin` calls `admin_set_admin`, which checks the caller again, requires Google identity for grants, serializes changes, rejects stale status, protects the owner target, and audits role changes. The old `/superadmin` endpoint and RPC reject all app role changes. Direct writes to either role column remain forbidden.

Admins can view Pulse, profiles, ratings and media, and edit/delete ordinary users' posts. They cannot manage roles or edit/delete the superadmin's posts. Protected posts show a read-only view; database checks also reject forged mutation requests. Profiles remain read-only throughout the control room; no account-deletion feature is added.

Any existing superadmins besides Vibhav are converted to Admins, preserving their operational access. Migration 008 is now live. Apply the migration before deploying code that queries `is_admin`; missing schema fails closed.

`npm run test:roles` starts a disposable local PostgreSQL instance and tests migration reruns, sole-owner constraints, conversion of existing roles, Google-only grants, stale changes, direct/legacy escalation denial, protected owner profile/posts, admin reads/media mutations, revocation and audit records. It never connects to the shared database.

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

## Admin-owned AI remixes

On `/media/[id]`, open **Create a remix**. The prompt starts with the post's saved
AI prompt (or a fallback when none was recorded), and context is editable for the
new post. **Generate 3 captions** produces three distinct choices. Select one, review/edit it, then use
**Publish as [your profile name]** to create a separate post in the shared feed.
The feed uses the new post's `user_id` to display the admin's profile name. No
source post fields, votes, authorship or generation metadata are updated.
Admins may remix any image they can read, including protected superadmin posts;
this does not grant permission to edit/delete the protected source.

Apply `supabase/009-admin-remixes.sql` as database owner after migration 008 to
activate the feature. It creates a private request-history table and narrowly
scoped RPCs. Every operation rechecks Google identity and current admin access.
Drafts are private to the requesting admin, including when another superadmin
asks for them. No service-role key or broad table/storage grants are added.
Use the existing server-only `OPENAI_API_KEY`; optional `OPENAI_CAPTION_MODEL`
defaults to the main app's `gpt-4.1-mini`. Set these independently on deployment.

Generation uses the Responses API with a base64 image input, `store: false` and a
strict JSON schema with three captions ([vision documentation](https://developers.openai.com/api/docs/guides/images-vision),
[structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)).
Supported originals are PNG/JPEG/WebP/GIF up to 5 MB. Vision sees a resized still
(first frame for GIFs); publishing copies the exact original bytes, retaining GIF
animation. One generation has a 40-second provider deadline, at most 10 reserved
requests per admin per 15 minutes, and one active request at a time. Interrupted
requests expire after two minutes when the admin next reserves/checks a request.
Failed requests count toward the limit. Provider keys, raw failures, image paths
and image data are never returned to the composer.

A generation UUID prevents duplicate paid calls on recovery; **Check last request**
recovers the same result. Your last ten requests are available in the composer,
including after a page reload. A publish UUID is also the new post ID, and a
locked database transaction commits the new post and published history together.
Repeat or concurrent publish calls return the same ID. The author is taken from
`auth.uid()`, never a client-supplied author field. Captions must be 1–200
characters. Changing prompt/context after preview requires regenerating or
restoring the saved inputs; caption refinement is allowed.

The copied image has its own admin-owned storage path; its SHA-256 must match the
image used for generation. Deleting either published post does not break the
other's image. Source IDs/names and original captions remain snapshotted in
history after source deletion. The admin detail page shows remix attribution and
a source link while it exists. The main app's existing feed shows the admin as
author; a public “remixed from” badge would require a separate main-app UI change.
If the source disappears before an independent copy is made, publishing fails
without changing it. If storage upload succeeds but the database commit fails,
the request retains the deterministic copy path for a safe retry. Such copies are
not deleted by a background worker; abandoned failed-publish copies require
owner cleanup. Ordinary caption-only previews do not upload an image.

Validation: `npm run test:remix-ai` covers the real provider adapter with mocked
HTTP, edited prompts, strict output, refusals, output limits, GIF conversion and
quota failures. `npm run test:remixes` runs the actual migration and hierarchy
suite against disposable local PostgreSQL: source preservation, admin ownership,
Google-only access, draft isolation, revocation, copied-image requirement,
idempotency, metadata/history, rate limits and survival after source deletion.
It never connects to the live Supabase project. The HTTP smoke script also checks
signed-out protection for the new endpoints. Publishing live content remains an
explicit action in the composer; development checks do not publish live posts.

Migration 009 was applied to the shared project with approval on October 27, 2026.
Live checks confirmed RLS on remix history, no anonymous RPC execution, no direct
history-table SELECT for authenticated users, and rejection of ordinary-member
history access. A real edited-prompt request produced a preview with
`gpt-4.1-mini-2025-04-14`; the draft was retained for review, without publishing.
The source post's full-row digest stayed identical, and live totals stayed at
36 posts and 91 votes. Local publishing tests cover the creation path without
publishing test content to the shared feed.


### Three-caption remix choices

Apply `supabase/010-remix-caption-choices.sql` after 009. It preserves each set of
three captions in `generated_captions`, so history and recovered previews retain
all alternatives. Existing single-caption previews remain available with one
option; generate again to receive three. The migration replaces the existing
completion function without changing its signature, grants or authorization.
The existing `caption_value` wire argument accepts a serialized JSON array for
new clients and a plain caption for older clients during a rolling deployment.

The composer offers a radio selection for each caption, then an editable selected
caption field. Only the selected/edited caption is published; all AI alternatives
remain in private generation history. Captions are validated server-side and in
SQL for count, uniqueness, length and line breaks. The database suite verifies
legacy preservation, history recovery and publication of the third option.

Migration 010 was applied on October 27, 2026. A live generation returned three
captions; selecting option 3 populated the selected-caption editor correctly.
Live history retained the two older one-caption results and the new three-caption
result. The source post's row digest remained unchanged and no post was published
during this check. Build, lint, TypeScript, AI adapter tests, auth tests and the
expanded local database regression suite passed.

### Request more captions, up to fifteen

Apply `supabase/011-remix-caption-sessions.sql` after 010. New batches join the
same private remix session, preserving earlier captions and their originating
request IDs/models. The composer appends three choices at a time, shows an
`N / 15` counter, and stops at fifteen. Changing prompt/context starts a new set.
Existing one-caption previews remain readable and start a new three-caption set
when generating again. Existing three-caption previews can be continued.

The database serializes reservations/completions per admin, checks the session's
saved prompt/context and image hash, and rejects requests beyond fifteen. Failed
requests keep the previous choices, consume no caption slots, and still count
against the existing ten-attempts-per-fifteen-minutes rate limit. Retries recover
the same batch without another AI call. Previously offered captions are sent to
the model as source material to avoid; repeats are rejected by both the provider
adapter and database. All options are restored from saved session history.

The chosen option's originating request supplies the post ID, copied image path,
model and prompt metadata. Publishing any batch closes the whole session; retries
from a different batch return that same published post instead of creating a
second one. The selected caption and any manual edits stay in the editor while
more captions are generated. The expanded local database suite verifies 3→6→9→12→15,
the blocked sixth batch, repeated-caption/image-change rejection, recovery,
history, and publishing option 15 with its original model and a single post.

Migration 011 was applied on October 27, 2026. Live browser checks continued an
existing three-caption preview to six choices, preserving option 3's selection
and a manual caption edit. Saved history retained all six choices. The source
post's full-row digest remained identical, history RLS stayed enabled, and the
anonymous role cannot execute batch reservations. No live post was published by
these checks. Build, lint, TypeScript, six AI adapter tests, fourteen auth tests,
HTTP protection checks and the expanded isolated PostgreSQL suite passed.


## Custom activity dates

Activity overview supports 7, 30, and 90-day presets plus Custom start/end dates.
Ranges include both dates in America/New_York and are limited to 366 days ending
on or before today. The chart and recent metric counts use the selected range;
all-time totals and sentiment remain all-time. Selections survive refresh in the URL.
Apply `supabase/012-pulse-date-range.sql` after migration 008 to install the
admin-only aggregate RPC. The migration is installed in the shared project.
`npm run test:roles` covers inclusive boundaries across daylight-saving time,
historical zero-filled days, range limits, invalid inputs, and access checks.
