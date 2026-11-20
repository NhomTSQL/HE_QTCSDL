import { NextRequest } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';
export async function POST(req: NextRequest, context: { params: Promise<{ userId: string }> }) {
  const { userId } = await context.params;
  if (!/^\d+$/.test(userId)) return Response.json({ error: 'Invalid user.' }, { status: 400 });
  return proxyToBackend(req, `/auth/users/${userId}/recovery-code`, { method: 'POST', forward: ['authorization', 'content-type'], body: true });
}
