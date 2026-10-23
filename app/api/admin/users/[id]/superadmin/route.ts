import { NextResponse } from 'next/server';
export async function PUT() {
  return NextResponse.json({error:'Superadmin access cannot be changed in the app.'}, {status:403,headers:{'Cache-Control':'no-store'}});
}
