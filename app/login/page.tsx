import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from '@/lib/auth/check';

const messages: Record<string, string> = {
  oauth: 'Google sign-in did not complete. Please try again.',
  verification: 'We couldn’t verify your access. Please try again in a moment.',
  signout: 'Sign-out did not complete. Please try again.',
};
export default async function Login({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const client = await createClient();
  const access = await checkAdmin(client);
  if (access.status === 'allowed') redirect('/');
  if (access.status === 'denied') redirect('/access-denied');
  const { error } = await searchParams;
  const message = messages[error ?? ''] ?? (access.status === 'unavailable' ? messages.verification : null);
  return <main className="login-shell">
    <section className="intro">
      <a className="brand" href="/login">the humour project<span className="brand-dot">.</span></a>
      <div className="intro-copy"><span className="eyebrow">BEHIND THE PUNCHLINES</span>
        <h1>Serious tools.<br /><span>Funny business.</span></h1>
        <p>A little order behind all the chaos. Welcome to the home of the people who keep the humour running.</p>
        <div className="stamp" aria-hidden="true">THP<br /><span>CONTROL ROOM</span></div>
      </div>
      <span className="footer-note">THE HUMOUR PROJECT / ADMIN AREA</span>
    </section>
    <section className="login-panel" aria-labelledby="login-title">
      <div className="login-card"><span className="pill"><span /> RESTRICTED ACCESS</span>
        <h2 id="login-title">You’re backstage.</h2>
        <p className="subtext">Sign in with your approved Google account to enter the control room.</p>
        <form action="/auth/google" method="post"><button className="google-button" type="submit"><span className="google-mark" aria-hidden="true">G</span>Continue with Google<span aria-hidden="true">↗</span></button></form>
        {message && <p className="alert" role="alert">{message}</p>}
        <div className="access-note"><span aria-hidden="true">⌁</span><p>For authorised administrators only. Signing in doesn’t automatically grant access.</p></div>
      </div>
      <span className="panel-footer">GOOD HUMOUR. GOOD HANDS.</span>
    </section>
  </main>;
}
