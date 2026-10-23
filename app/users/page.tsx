import Link from 'next/link';
import { requireAdmin } from '@/lib/auth/server';
import { AdminShell } from '@/app/components/admin-shell';
import { ProfileAvatar } from '@/app/components/profile-avatar';
import { Pagination } from '@/app/components/pagination';
import { displayDate, pageNumber, profileName, type ProfileList } from '@/lib/users/types';
export default async function Users({ searchParams }: { searchParams: Promise<{ q?: string | string[]; page?: string | string[] }> }) {
  const { client, user } = await requireAdmin();
  const query = await searchParams;
  const q = typeof query.q === 'string' ? query.q.trim().slice(0, 100) : '';
  const page = pageNumber(query.page);
  const { data, error } = await client.rpc('admin_profiles', { search_query: q, page_number: page });
  const result = !error && data ? data as ProfileList : null;
  const href = (next: number) => `/users?${new URLSearchParams({ q, page: String(next) })}`;
  return <AdminShell email={user.email} active="users"><main className="pulse-main users-main">
    <div className="pulse-heading"><div><span className="eyebrow">THE PEOPLE BEHIND THE PUNCHLINES</span><h1>Users<span>.</span></h1><p>Meet your community, one profile at a time.</p></div><span className="pill">READ ONLY</span></div>
    <section className="users-panel" aria-labelledby="directory-title"><div className="directory-header"><div><h2 id="directory-title">The cast.</h2><p>{result ? `${result.total} ${q ? 'matching' : 'community'} profiles` : 'Community profiles'}</p></div>
      <form action="/users" method="get" className="user-search"><label htmlFor="profile-search">Search profiles</label><div><input id="profile-search" name="q" defaultValue={q} maxLength={100} placeholder="Name or account ID" type="search" /><button type="submit">Search ↗</button></div>{q && <Link href="/users">Clear search</Link>}</form>
    </div>
    {!result ? <div className="users-empty" role="alert"><h3>Profiles are temporarily unavailable.</h3><p>Try again in a moment.</p><form action="/users" method="get"><input type="hidden" name="q" value={q} /><input type="hidden" name="page" value={page} /><button className="refresh-link">Retry ↗</button></form></div> : <>
      {result.profiles.length === 0 ? <div className="users-empty"><h3>{q ? 'No profiles found.' : 'The cast is still assembling.'}</h3><p>{q ? 'Try another name or part of an account ID.' : 'Profiles will appear here after people join the app.'}</p></div> : <div className="table-scroll"><table className="users-table"><thead><tr><th scope="col">Profile</th><th scope="col">Joined</th><th scope="col">Posts</th><th scope="col">Votes cast</th><th scope="col">Access</th><th scope="col"><span className="sr-only">Profile details</span></th></tr></thead><tbody>
        {result.profiles.map(profile => { const name = profileName(profile); const details = `/users/${profile.id}?${new URLSearchParams({ q, page: String(result.page) })}`; return <tr key={profile.id}>
          <th scope="row"><Link className="profile-cell" href={details}><ProfileAvatar id={profile.id} name={name} hasAvatar={profile.has_avatar} /><span><strong>{name}</strong><code>{profile.id}</code></span></Link></th>
          <td>{displayDate(profile.created_at)}</td><td>{profile.post_count}</td><td>{profile.vote_count}</td><td><span className={`role-badge${profile.is_superadmin || profile.is_admin ? ' admin' : ''}`}>{profile.is_superadmin ? 'Superadmin' : profile.is_admin ? 'Admin' : 'Member'}</span></td><td><Link className="profile-open" href={details} aria-label={`View ${name}'s profile`}>View ↗</Link></td>
        </tr>; })}
      </tbody></table></div>}
      <Pagination page={result.page} total={result.total} pageSize={result.pageSize} href={href} />
    </>}
    </section><p className="users-note">Profiles and activity are read-only. Post counts include unpublished uploads. Dates use America/New_York.</p>
  </main></AdminShell>;
}
