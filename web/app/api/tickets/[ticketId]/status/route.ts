import { NextRequest } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ ticketId: string }> }) {
  const { ticketId } = await params;
  if (!/^\d{1,10}$/.test(ticketId)) return new Response('Invalid ticket id.', { status: 400 });
  return proxyToBackend(req, `/api/tickets/${ticketId}/status`, { method: 'PATCH', body: true });
}
