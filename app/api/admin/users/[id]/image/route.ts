import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from '@/lib/auth/check';
import { validUserId } from '@/lib/users/types';
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const client = await createClient();
  const access = await checkAdmin(client);
  if (access.status !== 'allowed') return NextResponse.json({ error: 'Admin access required' }, { status: access.status === 'signed-out' ? 401 : access.status === 'denied' ? 403 : 503, headers });
  const { id } = await params;
  const post = new URL(request.url).searchParams.get('post');
  if (!validUserId(id) || (post !== null && !validUserId(post))) return new Response(null, { status: 400, headers });
  const { data, error } = await client.rpc('admin_profile_image', { target_id: id, target_post_id: post });
  if (error) return new Response(null, { status: 503, headers });
  if (!data) return new Response(null, { status: 404, headers });
  const image = data as { bucket: string; path: string };
  const { data: file, error: downloadError } = await client.storage.from(image.bucket).download(image.path);
  if (downloadError || !file) return new Response(null, { status: 404, headers });
  if (!['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(file.type) || file.size > 5 * 1024 * 1024) return new Response(null, { status: 415, headers });
  return new Response(file, { headers: { ...headers, 'Content-Type': file.type } });
}
