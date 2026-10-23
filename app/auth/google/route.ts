import { NextResponse } from 'next/server';
import { appOrigin } from '@/lib/supabase/config';
import { createClient } from '@/lib/supabase/server';

export async function POST(request: Request) {
  const origin = appOrigin(request);
  if (!origin || request.headers.get('origin') !== origin) return new Response('Invalid origin', { status: 403 });
  const client = await createClient();
  const { data, error } = await client.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: `${origin}/auth/callback`, skipBrowserRedirect: true, queryParams: { prompt: 'select_account' } },
  });
  return NextResponse.redirect(error || !data.url ? `${origin}/login?error=oauth` : data.url, 303);
}
