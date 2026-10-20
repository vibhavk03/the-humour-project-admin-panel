import Link from 'next/link';
import { requireAdmin } from '@/lib/auth/server';
import { PulseChart } from '@/app/components/pulse-chart';
import { pulsePeriod, summarizeDays, type Pulse } from '@/lib/pulse/types';

const number = (value: number) => new Intl.NumberFormat('en-US').format(value);

export default async function Home({ searchParams }: { searchParams: Promise<{ days?: string | string[] }> }) {
  const { client, user } = await requireAdmin();
  const period = pulsePeriod((await searchParams).days);
  const { data, error } = await client.rpc('admin_pulse', { period_days: period });
  const pulse = !error && data ? data as Pulse : null;
  const recent = pulse ? summarizeDays(pulse.days) : null;
  const votes = pulse ? pulse.totals.upvotes + pulse.totals.downvotes : 0;
  const recentVotes = recent ? recent.upvotes + recent.downvotes : 0;
  const approval = votes && pulse ? Math.round(pulse.totals.upvotes / votes * 100) : null;
  return <div className="control-room">
    <aside className="room-sidebar"><Link className="brand" href="/">the humour<br />project<span className="brand-dot">.</span></Link>
      <span className="sidebar-label">CONTROL ROOM</span><nav aria-label="Admin navigation"><Link href="/" aria-current="page"><span aria-hidden="true">↗</span> The Pulse <span className="nav-dot" /></Link></nav>
      <div className="sidebar-bottom"><span className="pill"><span /> ADMIN ACCESS</span><p>A little order.<br />A lot of humour.</p><span className="sidebar-foot">THP / EST. 2026</span></div>
    </aside>
    <div className="room-body"><header className="room-topbar"><span>THE HUMOUR PROJECT <span className="topbar-slash">/</span> OVERVIEW</span><div className="room-account"><span title={user.email}>{user.email}</span><form action="/auth/signout" method="post"><button type="submit">Sign out ↗</button></form></div></header>
      <main className="pulse-main"><div className="pulse-heading"><div><span className="eyebrow">YOUR COMMUNITY, AT A GLANCE</span><h1>The Pulse<span>.</span></h1><p>How’s the funny business doing?</p></div><form action="/" method="get"><input type="hidden" name="days" value={period} /><button className="refresh-link">↻ Refresh data</button></form></div>
        {!pulse || !recent ? <section className="pulse-error" role="alert"><h2>We couldn’t load the numbers.</h2><p>Statistics are temporarily unavailable. Try refreshing in a moment.</p><form action="/" method="get"><input type="hidden" name="days" value={period} /><button className="refresh-link">Try again ↗</button></form></section> : <>
          <div className="pulse-cards" aria-label="All-time community totals">
            <section className="metric-card"><div className="metric-label">TOTAL USERS<span aria-hidden="true">◎</span></div><strong>{number(pulse.totals.users)}</strong><p><b>+{number(recent.users)}</b> in the last {period} days</p><span className="metric-note">Profiles in the community</span></section>
            <section className="metric-card featured"><div className="metric-label">PUBLISHED MEMES<span aria-hidden="true">▧</span></div><strong>{number(pulse.totals.memes)}</strong><p><b>+{number(recent.memes)}</b> in the last {period} days</p><span className="metric-note">Punchlines out in the world</span></section>
            <section className="metric-card"><div className="metric-label">TOTAL VOTES<span aria-hidden="true">⇅</span></div><strong>{number(votes)}</strong><p><b>+{number(recentVotes)}</b> in the last {period} days</p><span className="metric-note">{number(pulse.totals.upvotes)} up · {number(pulse.totals.downvotes)} down</span></section>
          </div>
          <section className="activity-panel" aria-labelledby="activity-title"><div className="activity-header"><div><span className="eyebrow">THE DAILY DOSE</span><h2 id="activity-title">A community in motion.</h2><p>New users, published memes, and votes over time.</p></div><nav className="period-picker" aria-label="Activity date range">{[7, 30, 90].map(days => <Link key={days} href={`/?days=${days}`} aria-current={period === days ? 'page' : undefined} scroll={false}>{days} days</Link>)}</nav></div>
            <div className="period-summary"><strong>{number(recent.users + recent.memes + recentVotes)}</strong><span>records created in the last {period} days<br /><small>Including today · America/New_York</small></span></div>
            <PulseChart key={period} days={pulse.days} />
          </section>
          <section className="pulse-footnotes"><div className="vote-mood"><span aria-hidden="true">↗</span><div><strong>{approval === null ? 'The crowd hasn’t voted yet.' : `${approval}% of current votes are upvotes.`}</strong><p>{approval === null ? 'The first vote starts the conversation.' : 'A little snapshot of the room’s sense of humour.'}</p></div></div><p className="data-definition">Totals reflect records currently in the database. Published memes have a saved caption. Daily activity uses record creation dates; deleted records disappear and vote changes aren’t tracked as new events.</p></section>
          <footer className="pulse-footer"><span>SMALL NUMBERS. BIG PUNCHLINES.</span><span>Updated {new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: pulse.timezone, timeZoneName: 'short' }).format(new Date(pulse.generatedAt))}</span></footer>
        </>}
      </main>
    </div>
  </div>;
}
