import Link from 'next/link';
export default function MissingProfile() {
  return <main className="status-shell"><section className="status-card"><span className="eyebrow">USERS / PROFILE UNAVAILABLE</span><h1>This profile isn’t here.</h1><p>It may have been removed, or the account ID is incorrect.</p><Link href="/users">← Back to users</Link></section></main>;
}
