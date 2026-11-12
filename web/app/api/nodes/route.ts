import { NextRequest, NextResponse } from 'next/server';
import { extractBearerToken, verifyUserToken } from '@/lib/auth';
import { callSp } from '@/lib/db';

export const runtime = 'nodejs';

export async function GET(req: NextRequest) {
  const token = extractBearerToken(req.headers.get('authorization'));
  if (!token) return NextResponse.json({ error: 'Missing token.' }, { status: 401 });

  const payload = await verifyUserToken(token);
  if (!payload) return NextResponse.json({ error: 'Invalid or expired token.' }, { status: 401 });

  try {
    const nodes = await callSp('dbo.usp_list_nodes_latest');
    return NextResponse.json(nodes);
  } catch {
    return NextResponse.json({ error: 'Failed to list nodes.' }, { status: 503 });
  }
}
