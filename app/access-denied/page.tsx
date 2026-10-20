import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from '@/lib/auth/check';
export default async function AccessDenied() {
  const client = await createClient();
  const access = await checkAdmin(client);
  if (access.status === 'signed-out') redirect('/login');
  if (access.status === 'allowed') redirect('/');
  return <main className="status-shell"><section className="status-card">
    <span className="eyebrow">THE HUMOUR PROJECT / CONTROL ROOM</span>
    <h1>{access.status === 'unavailable' ? 'We couldn’t check your access.' : 'Backstage pass required.'}</h1>
    <p>{access.status === 'unavailable' ? 'Access is temporarily unavailable. Please try again shortly.' : 'You’re signed in, but this account does not have administrator access. Contact the project owner or switch to your approved Google account.'}</p>
    <form action="/auth/signout" method="post"><button className="primary-button">Sign out & switch account</button></form>
  </section></main>;
}
