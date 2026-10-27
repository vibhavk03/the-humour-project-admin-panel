import Link from 'next/link';

const navigation = [
  { key: 'pulse', href: '/', label: 'Overview', path: 'M3 12h4l3-8 4 16 3-8h4' },
  { key: 'users', href: '/users', label: 'Users', path: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m20 0v-2a4 4 0 0 0-3-3.87M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8m8-7.87a4 4 0 0 1 0 7.75' },
  { key: 'media', href: '/media', label: 'Media', path: 'M4 3h16a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1m-1 14 6-6 4 4 3-3 5 5M8 7h.01' },
  { key: 'ratings', href: '/ratings', label: 'Ratings', path: 'M8 3v18M4 7l4-4 4 4m4 14V3m-4 14 4 4 4-4' },
] as const;

export function AdminShell({ email, active, children }: { email?: string; active: 'pulse' | 'users' | 'media' | 'ratings'; children: React.ReactNode }) {
  return <div className="control-room">
    <aside className="workspace-sidebar">
      <Link className="brand" href="/" aria-label="The Humour Project home"><span className="brand-symbol" aria-hidden="true">✳</span><span className="brand-wordmark">humour<span className="brand-subtitle">ADMIN PANEL</span></span></Link>
      <span className="navigation-label">WORKSPACE</span>
      <nav className="workspace-nav" aria-label="Admin navigation">{navigation.map(item => <Link key={item.key} href={item.href} aria-label={item.label} title={item.label} aria-current={active === item.key ? 'page' : undefined}>
        <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={item.path} /></svg><span>{item.label}</span>{active === item.key && <i />}
      </Link>)}</nav>
      <div className="sidebar-workspace"><span className="workspace-status"><i /> ADMIN WORKSPACE</span><p>A little order.<br />A lot of humour.</p><span>THE HUMOUR PROJECT</span></div>
    </aside>
    <div className="room-body"><header className="workspace-header"><div className="workspace-breadcrumb">Workspace <span>/</span> <b>{navigation.find(item => item.key === active)?.label}</b></div><div className="room-account"><span className="account-avatar" title={email} aria-label={email || 'Administrator'}>{email?.slice(0, 1).toUpperCase() || 'A'}</span><span className="account-email" title={email}>{email}</span><form action="/auth/signout" method="post"><button type="submit">Sign out ↗</button></form></div></header>{children}<footer className="workspace-footer"><span>THE HUMOUR PROJECT</span><span><i /> ADMIN WORKSPACE</span></footer></div>
  </div>;
}
