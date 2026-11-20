import { NextRequest, NextResponse } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';
const actions = new Set(['request-access', 'reset-password', 'change-password', 'logout', 'sessions', 'sessions/revoke-others', 'mfa/setup', 'mfa/enable', 'mfa/disable']);

async function forward(req: NextRequest, context: { params: Promise<{ action: string[] }> }) {
  const { action } = await context.params;
  const path = action.join('/');
  if (!actions.has(path)) return NextResponse.json({ error: 'Not found.' }, { status: 404 });
  return proxyToBackend(req, `/auth/${path}`, { method: req.method, forward: ['authorization', 'content-type'], body: req.method === 'POST' });
}

export const GET = forward;
export const POST = forward;
