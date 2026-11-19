import { NextRequest, NextResponse } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';

async function forward(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  const { path } = await params;
  if (!path.length || path.some(segment => segment === '..' || segment.includes('\0'))) {
    return NextResponse.json({ error: 'Invalid API path.' }, { status: 400 });
  }
  const hasBody = req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH';
  return proxyToBackend(req, `/api/${path.map(encodeURIComponent).join('/')}`, {
    method: req.method,
    body: hasBody,
  });
}

export const GET = forward;
export const POST = forward;
export const PUT = forward;
export const PATCH = forward;
export const DELETE = forward;
