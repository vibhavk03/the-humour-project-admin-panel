import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from '@/lib/auth/check';
import { appOrigin } from '@/lib/supabase/config';
import { validUserId } from '@/lib/users/types';
const headers={'Cache-Control':'private, no-store'};
async function mutate(request:Request, params:Promise<{id:string}>, deleting:boolean) {
  if(request.headers.get('origin')!==appOrigin()) return NextResponse.json({error:'Invalid origin'},{status:403,headers});
  const client=await createClient(); const access=await checkAdmin(client);
  if(access.status!=='allowed') return NextResponse.json({error:'Superadmin access required'},{status:access.status==='signed-out'?401:access.status==='denied'?403:503,headers});
  const {id}=await params;
  if(!validUserId(id)) return NextResponse.json({error:'Invalid post ID'},{status:400,headers});
  let body;
  try{body=await request.json();}catch{return NextResponse.json({error:'Invalid request'},{status:400,headers});}
  if(typeof body?.expectedVersion!=='string'||!/^[a-f0-9]{32}$/.test(body.expectedVersion)||(!deleting&&(typeof body.caption!=='string'||typeof body.context!=='string'||body.caption.length>200||body.context.length>1000))) return NextResponse.json({error:'Invalid caption, context or post version'},{status:400,headers});
  const {data,error}=deleting
    ?await client.rpc('admin_media_delete',{target_id:id,expected_version:body.expectedVersion})
    :await client.rpc('admin_media_update',{target_id:id,expected_version:body.expectedVersion,new_caption:body.caption,new_context:body.context});
  if(error){const status=error.code==='42501'?403:error.code==='P0002'?404:error.code==='40001'?409:error.code==='22023'?400:503;
    return NextResponse.json({error:['40001','22023'].includes(error.code)?error.message:status===404?'Post not found':status===403?'Superadmin access required':'Could not save this change. Please try again.'},{status,headers});}
  if(!deleting) return NextResponse.json({post:data},{headers});
  const cleanup=data as {path:string;cleanupPending:boolean};
  if(cleanup.cleanupPending){
    try{
      const {error:removeError}=await client.storage.from('post-images').remove([cleanup.path]);
      if(!removeError){const {data:finished,error:finishError}=await client.rpc('admin_media_finish_cleanup',{target_id:id}); cleanup.cleanupPending=!!finishError||finished!==true;}
    }catch{cleanup.cleanupPending=true;}
  }
  return NextResponse.json({deleted:true,cleanupPending:cleanup.cleanupPending},{headers});
}
export async function PATCH(request:Request,{params}:{params:Promise<{id:string}>}) {return mutate(request,params,false);}
export async function DELETE(request:Request,{params}:{params:Promise<{id:string}>}) {return mutate(request,params,true);}
