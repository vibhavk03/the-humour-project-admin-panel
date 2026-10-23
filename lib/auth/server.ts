import 'server-only';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from './check';

export async function requireAdmin() {
  const client = await createClient();
  const access = await checkAdmin(client);
  if (access.status === 'signed-out') redirect('/login');
  if (access.status === 'denied') redirect('/access-denied');
  if (access.status !== 'allowed') redirect('/login?error=verification');
  return { client, user: access.user, role: access.role };
}
