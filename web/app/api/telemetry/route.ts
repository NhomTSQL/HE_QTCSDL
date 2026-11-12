import { createHash } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import sql from 'mssql';
import { callSp, SpParams } from '@/lib/db';

export const runtime = 'nodejs';

const numberFields = [
  'cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent', 'temperature_celsius',
  'network_in_bytes', 'network_out_bytes', 'uptime_seconds', 'process_count',
] as const;

type Telemetry = {
  node_id: number;
  collected_at: string;
  cpu_usage_percent?: number | null;
  memory_usage_percent?: number | null;
  disk_usage_percent?: number | null;
  temperature_celsius?: number | null;
  network_in_bytes?: number | null;
  network_out_bytes?: number | null;
  uptime_seconds?: number | null;
  process_count?: number | null;
};

export async function POST(req: NextRequest) {
  const agentKey = req.headers.get('x-agent-key');
  if (!agentKey || agentKey.length > 512) {
    return NextResponse.json({ error: 'Invalid agent credentials.' }, { status: 401 });
  }

  let body: Telemetry;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body.' }, { status: 400 });
  }

  if (!Number.isInteger(body.node_id) || body.node_id <= 0 || typeof body.collected_at !== 'string') {
    return NextResponse.json({ error: 'node_id and collected_at are required.' }, { status: 400 });
  }
  const collected = new Date(body.collected_at);
  if (!Number.isFinite(collected.getTime()) || !/(Z|[+-]\d{2}:?\d{2})$/i.test(body.collected_at)) {
    return NextResponse.json({ error: 'collected_at must be ISO-8601 with timezone.' }, { status: 400 });
  }
  for (const field of numberFields) {
    const value = body[field];
    if (value !== undefined && value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
      return NextResponse.json({ error: `Invalid ${field}.` }, { status: 400 });
    }
  }
  for (const field of ['cpu_usage_percent', 'memory_usage_percent', 'disk_usage_percent'] as const) {
    const value = body[field];
    if (value !== undefined && value !== null && value > 100) {
      return NextResponse.json({ error: `Invalid ${field}.` }, { status: 400 });
    }
  }

  try {
    const keyHash = createHash('sha256').update(agentKey, 'utf8').digest('hex');
    const agents = await callSp<{ agent_id: number; node_id: number; is_active: boolean }>(
      'dbo.usp_authenticate_agent', { key_hash: { value: keyHash, type: sql.Char(64) } }
    );
    const agent = agents[0];
    if (!agent || !agent.is_active || agent.node_id !== body.node_id) {
      return NextResponse.json({ error: 'Invalid agent credentials.' }, { status: 401 });
    }

    const params: SpParams = {
      node_id: body.node_id,
      collected_at: { value: collected, type: sql.DateTime2(0) },
      cpu_usage_percent: body.cpu_usage_percent == null ? null : { value: body.cpu_usage_percent, type: sql.Decimal(5, 2) },
      memory_usage_percent: body.memory_usage_percent == null ? null : { value: body.memory_usage_percent, type: sql.Decimal(5, 2) },
      disk_usage_percent: body.disk_usage_percent == null ? null : { value: body.disk_usage_percent, type: sql.Decimal(5, 2) },
      temperature_celsius: body.temperature_celsius == null ? null : { value: body.temperature_celsius, type: sql.Decimal(6, 2) },
      network_in_bytes: body.network_in_bytes == null ? null : { value: body.network_in_bytes, type: sql.BigInt },
      network_out_bytes: body.network_out_bytes == null ? null : { value: body.network_out_bytes, type: sql.BigInt },
      uptime_seconds: body.uptime_seconds == null ? null : { value: body.uptime_seconds, type: sql.BigInt },
      process_count: body.process_count == null ? null : { value: body.process_count, type: sql.Int },
    };
    await callSp('dbo.usp_record_telemetry_wide', params);
    return NextResponse.json({ ok: true }, { status: 201 });
  } catch (err: any) {
    if (err?.number === 51050) return NextResponse.json({ error: 'Node not found.' }, { status: 404 });
    return NextResponse.json({ error: 'Telemetry service unavailable.' }, { status: 503 });
  }
}
