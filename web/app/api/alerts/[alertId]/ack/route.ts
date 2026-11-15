import { NextRequest } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';

export async function POST(req: NextRequest, { params }: { params: Promise<{ alertId: string }> }) {
  const { alertId } = await params;
  if (!/^\d{1,10}$/.test(alertId)) return new Response('Invalid alert id.', { status: 400 });
  return proxyToBackend(req, `/api/alerts/${alertId}/ack`, { method: 'POST' });
}
