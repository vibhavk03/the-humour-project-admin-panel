import Link from 'next/link';
export default function MissingPost(){return <main className="status-shell"><section className="status-card"><h1>This post isn’t here.</h1><p>It may have been deleted, or the post ID is incorrect.</p><Link href="/media">← Back to media</Link></section></main>;}
