import Link from 'next/link';
export function AdminShell({ email, active, children }: { email?: string; active: 'pulse' | 'users' | 'media' | 'ratings'; children: React.ReactNode }) {
  return <div className="control-room">
    <aside className="room-sidebar"><Link className="brand" href="/">the humour<br />project<span className="brand-dot">.</span></Link>
      <span className="sidebar-label">CONTROL ROOM</span><nav aria-label="Admin navigation">
        <Link href="/" aria-current={active === 'pulse' ? 'page' : undefined}><span aria-hidden="true">↗</span> The Pulse {active === 'pulse' && <span className="nav-dot" />}</Link>
        <Link href="/users" aria-current={active === 'users' ? 'page' : undefined}><span aria-hidden="true">◎</span> Users {active === 'users' && <span className="nav-dot" />}</Link>
        <Link href="/media" aria-current={active === 'media' ? 'page' : undefined}><span aria-hidden="true">▧</span> Media {active === 'media' && <span className="nav-dot" />}</Link>
        <Link href="/ratings" aria-current={active === 'ratings' ? 'page' : undefined}><span aria-hidden="true">⇅</span> Ratings {active === 'ratings' && <span className="nav-dot" />}</Link>
      </nav><div className="sidebar-bottom"><span className="pill"><span /> ADMIN ACCESS</span><p>A little order.<br />A lot of humour.</p><span className="sidebar-foot">THP / EST. 2026</span></div>
    </aside><div className="room-body"><header className="room-topbar"><span>THE HUMOUR PROJECT <span className="topbar-slash">/</span> {active === 'users' ? 'USERS' : active === 'media' ? 'MEDIA' : active === 'ratings' ? 'RATINGS' : 'OVERVIEW'}</span><div className="room-account"><span title={email}>{email}</span><form action="/auth/signout" method="post"><button type="submit">Sign out ↗</button></form></div></header>{children}</div>
  </div>;
}
