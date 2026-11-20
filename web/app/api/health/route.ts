import { callBackend } from '@/lib/backend';

export const runtime = 'nodejs';

/** BFF health check: reports whether Flask can reach SQL Server. */
export async function GET() {
  return callBackend('/health');
}
