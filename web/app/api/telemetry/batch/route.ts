import { NextRequest } from 'next/server';
import { proxyToBackend } from '@/lib/backend';

export const runtime = 'nodejs';

/** Agent-facing batch ingest endpoint; Flask validates X-API-Key and calls usp_record_telemetry_batch. */
export async function POST(req: NextRequest) {
  return proxyToBackend(req, '/telemetry/batch', { method: 'POST', forward: ['x-api-key', 'content-type'], body: true });
}
