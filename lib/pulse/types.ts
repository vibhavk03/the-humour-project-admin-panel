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
