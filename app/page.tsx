import { requireAdmin } from '@/lib/auth/server';
export default async function Home() {
  const { user } = await requireAdmin();
  return <main className="status-shell"><section className="status-card">
    <span className="pill"><span /> SUPERADMIN VERIFIED</span>
    <h1>Welcome to the control room.</h1>
    <p>You’re signed in as <strong>{user.email}</strong>. Your administrator access is verified.</p>
    <p>The dashboard and management tools will be built here next.</p>
    <form action="/auth/signout" method="post"><button className="primary-button">Sign out</button></form>
  </section></main>;
}
