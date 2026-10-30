'use client';

import Link from 'next/link';
import { useState } from 'react';

export function PulseRangePicker({ period, custom, start, end, today }: { period: number; custom: boolean; start: string; end: string; today: string }) {
  const [open, setOpen] = useState(custom || Boolean(start));
  const [from, setFrom] = useState(start || today);
  const [to, setTo] = useState(end || today);
  const [error, setError] = useState('');
  return <div className="activity-range-controls">
    <nav className="period-picker" aria-label="Activity date range">
      {[7, 30, 90].map(days => <Link key={days} href={`/?days=${days}`} aria-current={!custom && period === days ? 'page' : undefined} scroll={false} onClick={() => setOpen(false)}>{days} days</Link>)}
      <button type="button" aria-expanded={open} aria-controls="custom-activity-range" aria-pressed={custom} onClick={() => setOpen(!open)}>Custom</button>
    </nav>
    {open && <form id="custom-activity-range" className="custom-activity-range" action="/" method="get" onSubmit={event => {
      const length = (Date.parse(to) - Date.parse(from)) / 86400000 + 1;
      const message = !from || !to || !Number.isFinite(length) ? 'Choose both dates.' : length < 1 ? 'End date must be on or after start date.' : to > today ? 'Choose dates on or before today.' : length > 366 ? 'Choose a range of up to 366 days.' : '';
      setError(message);
      if (message) event.preventDefault();
    }}>
      <label>From<input aria-label="Start date" type="date" name="start" value={from} max={today} required onChange={event => setFrom(event.target.value)} /></label>
      <label>To<input aria-label="End date" type="date" name="end" value={to} min={from || undefined} max={today} required onChange={event => setTo(event.target.value)} /></label>
      <button className="range-apply" type="submit">Apply</button>
      <small>Up to 366 days · America/New_York</small>
      {error && <p className="range-error" role="alert">{error}</p>}
    </form>}
  </div>;
}
