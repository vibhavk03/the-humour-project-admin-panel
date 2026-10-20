import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { appOrigin } from '@/lib/supabase/config';
import { checkAdmin } from '@/lib/auth/check';

export async function GET(request: Request) {
  const origin = appOrigin();
  const code = new URL(request.url).searchParams.get('code');
  if (!code) return NextResponse.redirect(`${origin}/login?error=oauth`);
  const client = await createClient();
  const { error } = await client.auth.exchangeCodeForSession(code);
  if (error) return NextResponse.redirect(`${origin}/login?error=oauth`);
  const access = await checkAdmin(client);
  const path = access.status === 'allowed' ? '/' : access.status === 'denied' ? '/access-denied' : '/login?error=verification';
  return NextResponse.redirect(`${origin}${path}`);
}
