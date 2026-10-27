import { AdminShell } from '@/app/components/admin-shell';
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
  return <AdminShell email={user.email} active="pulse">
      <main className="pulse-main"><div className="pulse-heading"><div><span className="eyebrow">YOUR COMMUNITY, AT A GLANCE</span><h1>The Pulse<span>.</span></h1><p>Community activity, content and engagement.</p></div><form action="/" method="get"><input type="hidden" name="days" value={period} /><button className="refresh-link">↻ Refresh data</button></form></div>
        {!pulse || !recent ? <section className="pulse-error" role="alert"><h2>We couldn’t load the numbers.</h2><p>Statistics are temporarily unavailable. Try refreshing in a moment.</p><form action="/" method="get"><input type="hidden" name="days" value={period} /><button className="refresh-link">Try again ↗</button></form></section> : <>
          <div className="pulse-cards" aria-label="All-time community totals">
            <section className="metric-card"><div className="metric-label">TOTAL USERS<span aria-hidden="true">◎</span></div><strong>{number(pulse.totals.users)}</strong><p><b>+{number(recent.users)}</b> in the last {period} days</p><span className="metric-note">Profiles in the community</span></section>
            <section className="metric-card featured"><div className="metric-label">PUBLISHED MEMES<span aria-hidden="true">▧</span></div><strong>{number(pulse.totals.memes)}</strong><p><b>+{number(recent.memes)}</b> in the last {period} days</p><span className="metric-note">Punchlines out in the world</span></section>
            <section className="metric-card"><div className="metric-label">TOTAL VOTES<span aria-hidden="true">⇅</span></div><strong>{number(votes)}</strong><p><b>+{number(recentVotes)}</b> in the last {period} days</p><span className="metric-note">{number(pulse.totals.upvotes)} up · {number(pulse.totals.downvotes)} down</span></section>
          </div>
          <div className="dashboard-grid"><section className="activity-panel" aria-labelledby="activity-title"><div className="activity-header"><div><span className="eyebrow">THE DAILY DOSE</span><h2 id="activity-title">Activity overview</h2><p>New users, published memes, and votes over time.</p></div><nav className="period-picker" aria-label="Activity date range">{[7, 30, 90].map(days => <Link key={days} href={`/?days=${days}`} aria-current={period === days ? 'page' : undefined} scroll={false}>{days} days</Link>)}</nav></div>
            <div className="period-summary"><strong>{number(recent.users + recent.memes + recentVotes)}</strong><span>records created in the last {period} days<br /><small>Including today · America/New_York</small></span></div>
            <PulseChart key={period} days={pulse.days} />
          </section>
          <aside className="engagement-panel" aria-labelledby="engagement-title">
            <div className="insight-heading"><h2 id="engagement-title">Community sentiment</h2><span className="pill">ALL TIME</span></div>
            <p className="insight-description">How the community responds.</p>
            <div className="sentiment-ring" role="img" aria-label={approval === null ? 'No votes yet' : `${approval}% upvotes from ${number(votes)} current votes`} style={{ background: votes ? `conic-gradient(#74866c 0 ${pulse.totals.upvotes / votes * 100}%, #ddd5c9 ${pulse.totals.upvotes / votes * 100}% 100%)` : '#ddd5c9' }}><div><strong>{approval === null ? '—' : `${approval}%`}</strong><span>{approval === null ? 'No votes yet' : 'positive votes'}</span></div></div>
            <div className="sentiment-legend"><span><i /> Upvotes <b>{number(pulse.totals.upvotes)}</b></span><span><i /> Downvotes <b>{number(pulse.totals.downvotes)}</b></span></div>
            <Link className="insight-link" href="/ratings">Explore ratings <span>↗</span></Link>
          </aside>
          <section className="workspace-links" aria-label="Workspace shortcuts"><div><span className="eyebrow">YOUR WORKSPACE</span><h2>Keep the community moving.</h2></div><Link href="/users"><span>◎</span><div>Users<small>Explore profiles and activity</small></div><b>↗</b></Link><Link href="/media"><span>▧</span><div>Media<small>Review and manage content</small></div><b>↗</b></Link></section>
          </div>
          <section className="pulse-footnotes"><div className="vote-mood"><span aria-hidden="true">↗</span><div><strong>{approval === null ? 'The crowd hasn’t voted yet.' : `${approval}% of current votes are upvotes.`}</strong><p>{approval === null ? 'The first vote starts the conversation.' : 'A little snapshot of the room’s sense of humour.'}</p></div></div><p className="data-definition">Totals reflect records currently in the database. Published memes have a saved caption. Daily activity uses record creation dates; deleted records disappear and vote changes aren’t tracked as new events.</p></section>
          <footer className="pulse-footer"><span>SMALL NUMBERS. BIG PUNCHLINES.</span><span>Updated {new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: pulse.timezone, timeZoneName: 'short' }).format(new Date(pulse.generatedAt))}</span></footer>
        </>}
      </main>
  </AdminShell>;
}
