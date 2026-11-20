import { NextRequest } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';
export async function POST(req: NextRequest) {
  return proxyToBackend(req, '/auth/sessions/revoke-others', { method: 'POST', forward: ['authorization', 'content-type'], body: true });
}
