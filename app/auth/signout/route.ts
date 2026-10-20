import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { appOrigin } from '@/lib/supabase/config';

export async function POST(request: Request) {
  const origin = appOrigin();
  if (request.headers.get('origin') !== origin) return new Response('Invalid origin', { status: 403 });
  const client = await createClient();
  const { error } = await client.auth.signOut({ scope: 'local' });
  if (error) return NextResponse.redirect(`${origin}/login?error=signout`, 303);
  return NextResponse.redirect(`${origin}/login`, 303);
}
