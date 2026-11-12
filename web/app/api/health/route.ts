import { NextResponse } from 'next/server';
import { pingDb } from '@/lib/db';

export async function GET() {
  const connected = await pingDb();
  return NextResponse.json(
    connected
      ? { status: 'healthy', database: 'connected' }
      : { status: 'unhealthy', database: 'disconnected' },
    { status: connected ? 200 : 503 }
  );
}
