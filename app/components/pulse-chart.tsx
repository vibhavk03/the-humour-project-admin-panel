'use client';
import { useState } from 'react';
import type { PulseDay } from '@/lib/pulse/types';
const series = [
  { key: 'users', label: 'New users', color: '#a7b2ba' },
  { key: 'memes', label: 'Published memes', color: '#74866c' },
  { key: 'votes', label: 'Votes', color: '#c9a777' },
] as const;
type Series = typeof series[number]['key'];
const dayLabel = (date: string) => new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(new Date(`${date}T12:00:00Z`));
const value = (day: PulseDay, key: Series) => key === 'votes' ? day.upvotes + day.downvotes : day[key];
export function PulseChart({ days }: { days: PulseDay[] }) {
  const [visible, setVisible] = useState<Record<Series, boolean>>({ users: true, memes: true, votes: true });
  const [selected, setSelected] = useState<string | null>(null);
  const active = series.filter(item => visible[item.key]);
  const max = Math.max(1, ...days.map(day => active.reduce((sum, item) => sum + value(day, item.key), 0)));
  const selectedDay = days.find(day => day.date === selected);
  const activity = days.some(day => day.users + day.memes + day.upvotes + day.downvotes > 0);
  return <>
    <div className="chart-legend" aria-label="Chart series">{series.map(item => <button key={item.key} type="button" aria-pressed={visible[item.key]} onClick={() => setVisible(current => ({ ...current, [item.key]: !current[item.key] }))}><span style={{ background: item.color }} />{item.label}</button>)}</div>
    {!activity && <p className="chart-notice">A quiet spell. No activity in this date range yet.</p>}
    {active.length === 0 && <p className="chart-notice">Select a series above to show activity.</p>}
    <div className="chart-scroll"><div className="pulse-chart" style={{ minWidth: days.length > 30 ? Math.max(900, days.length * 12) : 570 }}>
      <div className="chart-scale" aria-hidden="true"><span>{max}</span><span>{max / 2}</span><span>0</span></div>
      <div className="chart-plot" role="group" aria-label="Daily activity. Select a bar for details.">
        <div className="chart-grid" aria-hidden="true"><i /><i /><i /></div>
        <div className="chart-bars">{days.map(day => <button className={`chart-day${selected === day.date ? ' selected' : ''}`} type="button" key={day.date}
          onMouseEnter={() => setSelected(day.date)} onFocus={() => setSelected(day.date)} onClick={() => setSelected(day.date)}
          aria-label={`${dayLabel(day.date)}: ${day.users} new users, ${day.memes} published memes, ${day.upvotes} upvotes and ${day.downvotes} downvotes`} aria-pressed={selected === day.date}
        >{active.map(item => <span key={item.key} style={{ height: `${value(day, item.key) / max * 100}%`, background: item.color }} />)}</button>)}</div>
      </div>
      <div className="chart-dates" aria-hidden="true"><span>{dayLabel(days[0].date)}</span><span>{dayLabel(days[Math.floor(days.length / 2)].date)}</span><span>{dayLabel(days[days.length - 1].date)}</span></div>
    </div></div>
    <div className="chart-selection" aria-live="polite">{selectedDay ? <><strong>{dayLabel(selectedDay.date)}</strong><span>{selectedDay.users} new users</span><span>{selectedDay.memes} memes</span><span>{selectedDay.upvotes} upvotes · {selectedDay.downvotes} downvotes</span></> : <span>Hover, tap, or focus a bar to inspect the day.</span>}</div>
    <details className="activity-table"><summary>View daily numbers</summary><div className="table-scroll"><table><caption>Daily activity · America/New_York</caption><thead><tr><th scope="col">Date</th><th scope="col">New users</th><th scope="col">Published memes</th><th scope="col">Upvotes</th><th scope="col">Downvotes</th></tr></thead><tbody>{days.map(day => <tr key={day.date}><th scope="row">{dayLabel(day.date)}</th><td>{day.users}</td><td>{day.memes}</td><td>{day.upvotes}</td><td>{day.downvotes}</td></tr>)}</tbody></table></div></details>
  </>;
}
