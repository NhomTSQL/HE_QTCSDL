import { NextRequest } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';

export async function GET(req: NextRequest) {
  return proxyToBackend(req, '/api/nodes');
}

export async function POST(req: NextRequest) {
  return proxyToBackend(req, '/api/nodes', { method: 'POST', body: true });
}
