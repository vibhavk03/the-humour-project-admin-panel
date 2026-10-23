import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { appOrigin } from '@/lib/supabase/config';
import { checkAdmin } from '@/lib/auth/check';
import { validUserId } from '@/lib/users/types';
const headers = { 'Cache-Control': 'private, no-store' };
export async function PUT(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const origin = appOrigin(request);
  if (!origin || request.headers.get('origin') !== origin) return NextResponse.json({error:'Invalid origin'}, {status:403,headers});
  const client = await createClient();
  const access = await checkAdmin(client);
  if (access.status !== 'allowed') return NextResponse.json({error:'Superadmin access required'}, {status:access.status==='signed-out'?401:access.status==='denied'?403:503,headers});
  const { id } = await params;
  if (!validUserId(id)) return NextResponse.json({error:'Invalid account ID'}, {status:400,headers});
  let body;
  try { body = await request.json(); } catch { return NextResponse.json({error:'Invalid request'}, {status:400,headers}); }
  if (typeof body?.enabled !== 'boolean' || typeof body?.expectedStatus !== 'boolean') return NextResponse.json({error:'Invalid role value'}, {status:400,headers});
  const { data, error } = await client.rpc('admin_set_superadmin', {target_id:id,enabled:body.enabled,expected_status:body.expectedStatus});
  if (error) {
    const status = error.code==='42501'?403:error.code==='P0002'?404:['40001','23514'].includes(error.code)?409:error.code==='22023'?400:503;
    const message = ['40001','23514','22023'].includes(error.code)?error.message:status===404?'Profile not found':status===403?'Superadmin access required':'Could not update access. Please try again.';
    return NextResponse.json({error:message}, {status,headers});
  }
  return NextResponse.json({isSuperadmin:data}, {headers});
}
