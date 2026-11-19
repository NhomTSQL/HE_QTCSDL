import { NextRequest, NextResponse } from 'next/server';
import { backendBaseUrl } from '@/lib/backend';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** Long-lived SSE proxy to Flask /api/stream without the 10s REST proxy timeout. */
export async function GET(req: NextRequest) {
  try {
    const url = new URL('/api/stream', backendBaseUrl());
    url.search = new URL(req.url).search;
    const headers: Record<string, string> = {};
    const auth = req.headers.get('authorization');
    if (auth) headers.authorization = auth;

    const upstream = await fetch(url, {
      method: 'GET',
      headers,
      cache: 'no-store',
      signal: req.signal,
    });

    if (!upstream.ok || !upstream.body) {
      return NextResponse.json(
        { error: 'Stream unavailable.' },
        { status: upstream.status || 503 },
      );
    }

    return new NextResponse(upstream.body, {
      status: 200,
      headers: {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        connection: 'keep-alive',
      },
    });
  } catch {
    return NextResponse.json({ error: 'Stream disconnected.' }, { status: 503 });
  }
}
