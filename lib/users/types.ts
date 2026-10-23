export type Profile = {
  id: string; first_name: string | null; last_name: string | null;
  created_at: string; is_superadmin: boolean; has_avatar: boolean;
  post_count: number; vote_count: number;
};
export type ProfileList = { profiles: Profile[]; total: number; page: number; pageSize: number };
export type ProfileDetail = {
  profile: Profile & { published_count: number; upvotes_cast: number; downvotes_cast: number };
  posts: { id: string; caption: string | null; created_at: string; upvotes: number; downvotes: number }[];
  page: number; pageSize: number;
};
export function profileName(profile: Pick<Profile, 'first_name' | 'last_name'>) {
  return [profile.first_name?.trim(), profile.last_name?.trim()].filter(Boolean).join(' ') || 'Unnamed contributor';
}
export function pageNumber(value: string | string[] | undefined) {
  if (typeof value !== 'string' || !/^\d{1,9}$/.test(value)) return 1;
  return Math.max(1, Number(value));
}
export function validUserId(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
export function displayDate(value: string) {
  return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'America/New_York' }).format(new Date(value));
}
