import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from '@/lib/auth/check';
export async function GET() {
  const access = await checkAdmin(await createClient());
  if (access.status !== 'allowed') return NextResponse.json({ error: 'Admin access could not be verified' }, {
    status: access.status === 'signed-out' ? 401 : access.status === 'denied' ? 403 : 503,
    headers: { 'Cache-Control': 'private, no-store' },
  });
  return NextResponse.json({ userId: access.user.id, role: access.role, isSuperadmin: access.role === 'superadmin' }, { headers: { 'Cache-Control': 'private, no-store' } });
}
