import { NextRequest, NextResponse } from 'next/server';
import { extractBearerToken, verifyUserToken } from '@/lib/auth';
import { callSp } from '@/lib/db';
export const runtime = 'nodejs';
export async function GET(req: NextRequest) {
  const token = extractBearerToken(req.headers.get('authorization'));
  if (!token || !(await verifyUserToken(token))) return NextResponse.json({ error: 'Unauthorized.' }, { status: 401 });
  const statuses = new URL(req.url).searchParams.get('status') || 'OPEN,ACKNOWLEDGED';
  if (!/^[A-Z_,]{1,100}$/.test(statuses)) return NextResponse.json({ error: 'Invalid status filter.' }, { status: 400 });
  try { return NextResponse.json(await callSp('dbo.usp_list_alerts', { statuses })); }
  catch { return NextResponse.json({ error: 'Failed to list alerts.' }, { status: 503 }); }
}
