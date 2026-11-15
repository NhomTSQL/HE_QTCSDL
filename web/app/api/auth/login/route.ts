import { NextRequest } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';

export async function POST(req: NextRequest) {
  return proxyToBackend(req, '/auth/login', { method: 'POST', forward: ['content-type'], body: true });
}
