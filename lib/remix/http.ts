import 'server-only';
import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from '@/lib/auth/check';
import { appOrigin } from '@/lib/supabase/config';

export const privateHeaders = { 'Cache-Control': 'private, no-store' };
export function failure(error: string, status: number) { return NextResponse.json({ error }, { status, headers: privateHeaders }); }

export async function remixAccess(request: Request) {
  const origin = appOrigin(request);
  if (!origin || request.headers.get('origin') !== origin) return { response: failure('Invalid origin', 403) };
  const client = await createClient();
  const access = await checkAdmin(client);
  if (access.status !== 'allowed') return { response: failure('Admin access required', access.status === 'signed-out' ? 401 : access.status === 'denied' ? 403 : 503) };
  return { client, user: access.user };
}

export function databaseFailure(error: { code?: string; message?: string }) {
  const status = error.code === '42501' ? 403 : error.code === 'P0002' ? 404 : error.code === '22023' ? 400 : error.code === 'P0001' ? 429 : 503;
  return failure(status === 503 ? 'Remixing is unavailable. Check that database migration 009 has been applied, then retry.'
    : status === 403 ? 'You do not have access to this remix.' : error.message || 'The remix could not be saved.', status);
}
