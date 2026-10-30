export type PulseDay = { date: string; users: number; memes: number; upvotes: number; downvotes: number };
export type Pulse = {
  generatedAt: string; timezone: string; periodDays: number;
  totals: { users: number; memes: number; upvotes: number; downvotes: number };
  days: PulseDay[];
};
export function pulsePeriod(value: string | string[] | undefined): 7 | 30 | 90 {
  return value === '7' ? 7 : value === '90' ? 90 : 30;
}
export function summarizeDays(days: PulseDay[]) {
  return days.reduce((sum, day) => ({
    users: sum.users + day.users, memes: sum.memes + day.memes,
    upvotes: sum.upvotes + day.upvotes, downvotes: sum.downvotes + day.downvotes,
  }), { users: 0, memes: 0, upvotes: 0, downvotes: 0 });
}

export type PulseSearch = { days?: string | string[]; start?: string | string[]; end?: string | string[] };
export function pulseRange(params: PulseSearch, today: string) {
  const period = pulsePeriod(params.days);
  const dateValue = (value: unknown): value is string => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
  if (params.start === undefined && params.end === undefined) return { period, custom: false, start: '', end: '', error: '' };
  if (!dateValue(params.start) || !dateValue(params.end)) return { period, custom: false, start: '', end: '', error: 'Choose a valid start and end date.' };
  const length = (Date.parse(params.end) - Date.parse(params.start)) / 86400000 + 1;
  const error = params.end > today ? 'Choose dates on or before today.' : length < 1 ? 'End date must be on or after start date.' : length > 366 ? 'Choose a range of up to 366 days.' : '';
  return { period, custom: !error, start: params.start, end: params.end, error };
}
