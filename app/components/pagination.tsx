import Link from 'next/link';
export function Pagination({ page, total, pageSize, href, label = 'Users' }: { page: number; total: number; pageSize: number; href: (page: number) => string; label?: string }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  return <nav className="users-pagination" aria-label={`${label} pagination`}>
    <span>{total ? `${(page - 1) * pageSize + 1}–${Math.min(page * pageSize, total)} of ${total}` : '0 results'}</span>
    <div>{page > 1 ? <Link href={href(page - 1)}>← Previous</Link> : <span aria-disabled="true">← Previous</span>}<span>Page {page} of {pages}</span>{page < pages ? <Link href={href(page + 1)}>Next →</Link> : <span aria-disabled="true">Next →</span>}</div>
  </nav>;
}
