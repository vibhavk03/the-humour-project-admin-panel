import { AdminToggle } from '@/app/components/admin-toggle';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/lib/auth/server';
import { AdminShell } from '@/app/components/admin-shell';
import { ProfileAvatar } from '@/app/components/profile-avatar';
import { ProfilePostImage } from '@/app/components/profile-post-image';
import { Pagination } from '@/app/components/pagination';
import { displayDate, pageNumber, profileName, validUserId, type ProfileDetail } from '@/lib/users/types';
export default async function UserDetail({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ postsPage?: string | string[]; q?: string | string[]; page?: string | string[] }> }) {
  const { client, user, role } = await requireAdmin();
  const { id } = await params;
  if (!validUserId(id)) notFound();
  const query = await searchParams;
  const q = typeof query.q === 'string' ? query.q.trim().slice(0, 100) : '';
  const backPage = pageNumber(query.page);
  const postPage = pageNumber(query.postsPage);
  const { data, error } = await client.rpc('admin_profile_detail', { target_id: id, post_page: postPage });
  if (!error && !data) notFound();
  const details = !error && data ? data as ProfileDetail : null;
  const back = `/users?${new URLSearchParams({ q, page: String(backPage) })}`;
  const href = (next: number) => `/users/${id}?${new URLSearchParams({ q, page: String(backPage), postsPage: String(next) })}`;
  const profile = details?.profile;
  const name = profile ? profileName(profile) : '';
  return <AdminShell email={user.email} active="users"><main className="pulse-main users-main">
    <Link className="back-link" href={back}>← Back to users</Link>
    {!details || !profile ? <section className="pulse-error" role="alert"><h2>We couldn’t load this profile.</h2><p>Please try again shortly.</p><form action={`/users/${id}`} method="get"><input type="hidden" name="q" value={q} /><input type="hidden" name="page" value={backPage} /><input type="hidden" name="postsPage" value={postPage} /><button className="refresh-link">Retry ↗</button></form></section> : <>
      <section className="profile-heading"><ProfileAvatar id={id} name={name} hasAvatar={profile.has_avatar} large /><div><span className="eyebrow">COMMUNITY PROFILE</span><h1>{name}</h1><div className="profile-meta"><span className={`role-badge${profile.is_superadmin || profile.is_admin ? ' admin' : ''}`}>{profile.is_superadmin ? 'Superadmin' : profile.is_admin ? 'Admin' : 'Member'}</span><span>Joined {displayDate(profile.created_at)}</span><span className="pill">PROFILE DETAILS</span></div><p className="account-id">Account ID <code>{profile.id}</code></p></div></section>
      <div className="profile-stats"><section><span>Total posts</span><strong>{profile.post_count}</strong><p>{profile.published_count} published · {profile.post_count - profile.published_count} unpublished</p></section><section><span>Votes cast</span><strong>{profile.vote_count}</strong><p>{profile.upvotes_cast} upvotes · {profile.downvotes_cast} downvotes</p><Link className="media-manage" href={`/ratings?voter=${profile.id}`}>View votes cast ↗</Link></section><section><span>Admin status</span><strong className="status-value">{profile.is_superadmin ? 'Superadmin' : profile.is_admin ? 'Admin' : 'Member'}</strong><p>{profile.is_superadmin ? 'Owner access. This role cannot be changed in the app.' : profile.is_admin ? 'Has control room access' : 'No control room access'}</p>{role === 'superadmin' && !profile.is_superadmin && <AdminToggle key={profile.id} id={profile.id} name={name} enabled={profile.is_admin} />}</section></div>
      <section className="users-panel profile-posts" aria-labelledby="posts-title"><div className="directory-header"><div><span className="eyebrow">THEIR CONTRIBUTIONS</span><h2 id="posts-title">Posts & crowd reaction.</h2><p>Current ratings received on each post.</p></div><span className="pill">{profile.post_count} POSTS</span></div>
        {details.posts.length === 0 ? <div className="users-empty"><h3>No posts yet.</h3><p>This contributor hasn’t uploaded any media.</p></div> : <div className="profile-post-grid">{details.posts.map(post => <article className="profile-post" key={post.id}>
          <ProfilePostImage userId={id} postId={post.id} /><div className="profile-post-body"><div className="post-date"><span>{displayDate(post.created_at)}</span><span className="role-badge">{post.caption !== null ? 'Published' : 'Unpublished'}</span></div><p className="post-caption">{post.caption ?? 'No caption saved.'}</p><div className="post-ratings"><span>↑ {post.upvotes} <span className="sr-only">upvotes</span></span><span>↓ {post.downvotes} <span className="sr-only">downvotes</span></span><strong>Net {post.upvotes - post.downvotes > 0 ? '+' : ''}{post.upvotes - post.downvotes}</strong></div><Link className="media-manage" href={`/media/${post.id}`}>View & manage ↗</Link><code className="post-id">{post.id}</code></div>
        </article>)}</div>}
        <Pagination label="Posts" page={details.page} total={profile.post_count} pageSize={details.pageSize} href={href} />
      </section><p className="users-note">Counts reflect current records. Deleted posts and votes are excluded. Profile details and ratings are read-only here. Use View & manage for post edits or deletion; only the superadmin can change Admin access above.</p>
    </>}
  </main></AdminShell>;
}
