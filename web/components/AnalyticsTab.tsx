'use client';

import { useEffect, useState } from 'react';
import { SparkChart } from '@/components/SparkChart';
import { downloadCsv } from '@/lib/csv';
import { getCopy } from '@/lib/i18n';
import type {
  AnalyticsSummary,
  HierarchicalReportRow,
  Lang,
  NodeRow,
  RackCapacityRow,
  TelemetryPoint,
} from '@/lib/types';

type Props = {
  token: string;
  lang: Lang;
  summary: AnalyticsSummary | null;
  rackCapacity: RackCapacityRow[];
  nodes: NodeRow[];
};

const METRICS = [
  { code: 'cpu_usage_percent', label: 'CPU (%)' },
  { code: 'memory_usage_percent', label: 'RAM (%)' },
  { code: 'disk_usage_percent', label: 'Disk (%)' },
  { code: 'temperature_celsius', label: 'Temperature (°C)' },
];

export function AnalyticsTab({ token, lang, summary, rackCapacity, nodes }: Props) {
  const t = getCopy(lang);
  const [selectedNodeId, setSelectedNodeId] = useState<number>(nodes[0]?.id ?? 1);
  const [metricCode, setMetricCode] = useState('cpu_usage_percent');
  const [limit, setLimit] = useState('40');
  const [points, setPoints] = useState<TelemetryPoint[]>([]);

  const [groupBy, setGroupBy] = useState<'SITE' | 'ROOM' | 'RACK' | 'NODE'>('RACK');
  const [hours, setHours] = useState('24');
  const [hierarchyReport, setHierarchyReport] = useState<HierarchicalReportRow[]>([]);

  useEffect(() => {
    if (nodes.length && !nodes.some(n => n.id === selectedNodeId)) {
      setSelectedNodeId(nodes[0].id);
    }
  }, [nodes, selectedNodeId]);

  useEffect(() => {
    if (!token || !selectedNodeId) return;
    let active = true;
    fetch(`/api/telemetry/history?node_id=${selectedNodeId}&metric_type=${encodeURIComponent(metricCode)}&limit=${limit}`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: 'no-store',
    })
      .then(r => (r.ok ? r.json() : []))
      .then(data => { if (active && Array.isArray(data)) setPoints(data); })
      .catch(() => undefined);
    return () => { active = false; };
  }, [token, selectedNodeId, metricCode, limit]);

  useEffect(() => {
    if (!token) return;
    let active = true;
    fetch(`/api/reports/hierarchy?group_by=${groupBy}&hours=${hours}`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: 'no-store',
    })
      .then(r => (r.ok ? r.json() : []))
      .then(data => { if (active && Array.isArray(data)) setHierarchyReport(data); })
      .catch(() => undefined);
    return () => { active = false; };
  }, [token, groupBy, hours]);

  return (
    <div className="tab-stack">
      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">{t.analytics.eyebrow}</div>
            <h2>{t.analytics.title}</h2>
          </div>
          {summary && <span className="marker-pill">PUE {summary.current_pue.toFixed(2)}</span>}
        </div>

        {summary && (
          <div className="analytics-grid">
            <div className="ar-gauge"><span>{t.kpi.itWatts}</span><strong>{summary.it_power_watts.toFixed(0)} W</strong></div>
            <div className="ar-gauge"><span>{t.analytics.facilityPower}</span><strong>{summary.total_facility_watts.toFixed(0)} W</strong></div>
            <div className="ar-gauge"><span>{t.analytics.itEnergyDay}</span><strong>{summary.it_energy_kwh_per_day.toFixed(2)} kWh</strong></div>
            <div className="ar-gauge"><span>{t.analytics.facilityEnergyDay}</span><strong>{summary.total_energy_kwh_per_day.toFixed(2)} kWh</strong></div>
            <div className="ar-gauge"><span>{t.analytics.activeCollectors}</span><strong>{summary.active_collectors}</strong></div>
            <div className="ar-gauge"><span>{t.analytics.runningContainers}</span><strong>{summary.running_containers}/{summary.total_containers}</strong></div>
            <div className="ar-gauge"><span>{t.analytics.warrantyAttention}</span><strong>{summary.warranty_attention_count}</strong></div>
            <div className="ar-gauge"><span>{t.kpi.mttr}</span><strong>{summary.avg_mttr_minutes.toFixed(1)} {t.kpi.minutes}</strong></div>
          </div>
        )}
      </section>

      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">4-Level Aggregation</div>
            <h2>{t.analytics.hierarchyReportTitle}</h2>
          </div>
          <div className="trend-controls">
            <select value={groupBy} onChange={e => setGroupBy(e.target.value as 'SITE' | 'ROOM' | 'RACK' | 'NODE')} aria-label={t.analytics.groupBy}>
              <option value="SITE">SITE</option>
              <option value="ROOM">ROOM</option>
              <option value="RACK">RACK</option>
              <option value="NODE">NODE</option>
            </select>
            <select value={hours} onChange={e => setHours(e.target.value)} aria-label={t.analytics.windowHours}>
              <option value="1">1h</option>
              <option value="6">6h</option>
              <option value="24">24h</option>
              <option value="168">7d</option>
              <option value="720">30d</option>
            </select>
            <button
              type="button"
              className="compact-action secondary"
              disabled={!hierarchyReport.length}
              onClick={() => downloadCsv(
                `ar-imms-hierarchy-${groupBy.toLowerCase()}-${hours}h.csv`,
                ['group_by', 'group_label', 'node_count', 'total_power_watts', 'running_containers', 'open_alerts', 'open_tickets', 'avg_cpu_percent', 'max_cpu_percent', 'avg_ram_percent', 'max_temp_celsius', 'sample_count'],
                hierarchyReport.map(r => [
                  r.group_by,
                  r.group_label,
                  r.node_count,
                  r.total_power_watts,
                  r.running_containers,
                  r.open_alerts,
                  r.open_tickets,
                  r.avg_cpu_percent,
                  r.max_cpu_percent,
                  r.avg_ram_percent,
                  r.max_temp_celsius,
                  r.sample_count,
                ]),
              )}
            >
              {t.exportCsv}
            </button>
          </div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>{groupBy}</th>
                <th>Nodes</th>
                <th>{t.twin.powerWatts}</th>
                <th>{t.analytics.containersRunning}</th>
                <th>Alerts / Tickets</th>
                <th>{t.analytics.avgCpu}</th>
                <th>{t.analytics.maxCpu}</th>
                <th>{t.analytics.avgRam}</th>
                <th>{t.analytics.maxTemp}</th>
                <th>{t.analytics.samples}</th>
              </tr>
            </thead>
            <tbody>
              {hierarchyReport.map(row => (
                <tr key={`${row.group_by}-${row.group_id}`}>
                  <td><strong>{row.group_label}</strong></td>
                  <td>{row.node_count}</td>
                  <td>{row.total_power_watts.toFixed(0)} W</td>
                  <td>{row.running_containers}</td>
                  <td>{row.open_alerts} / {row.open_tickets}</td>
                  <td>{row.avg_cpu_percent != null ? `${row.avg_cpu_percent.toFixed(1)}%` : '—'}</td>
                  <td>{row.max_cpu_percent != null ? `${row.max_cpu_percent.toFixed(1)}%` : '—'}</td>
                  <td>{row.avg_ram_percent != null ? `${row.avg_ram_percent.toFixed(1)}%` : '—'}</td>
                  <td>{row.max_temp_celsius != null ? `${row.max_temp_celsius.toFixed(1)}°C` : '—'}</td>
                  <td className="cell-muted">{row.sample_count}</td>
                </tr>
              ))}
              {!hierarchyReport.length && (
                <tr><td colSpan={10} className="empty">{t.kpi.noData}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">Capacity Planning</div>
            <h2>{t.analytics.rackCapacityTitle}</h2>
          </div>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Site / Room / Rack</th>
                <th>{t.analytics.uSlots}</th>
                <th>{t.analytics.powerLoad}</th>
                <th>{t.analytics.avgCpu}</th>
                <th>{t.analytics.avgRam}</th>
                <th>{t.analytics.avgDisk}</th>
                <th>{t.analytics.maxTemp}</th>
              </tr>
            </thead>
            <tbody>
              {rackCapacity.map(rc => {
                const powerPct = rc.total_power_capacity_watts > 0
                  ? Math.round((rc.used_power_watts / rc.total_power_capacity_watts) * 100)
                  : 0;
                return (
                  <tr key={rc.rack_id}>
                    <td>
                      <span className="node-cell">
                        <span className="node-name">{rc.rack_name} ({rc.rack_code})</span>
                        <span className="node-id">{rc.site_name} / {rc.room_name}</span>
                      </span>
                    </td>
                    <td>{rc.used_u} / {rc.unit_capacity} U ({rc.node_count} nodes)</td>
                    <td>
                      <span className="meter-cell">
                        <span className="meter-value">{rc.used_power_watts.toFixed(0)}/{rc.total_power_capacity_watts.toFixed(0)}W ({powerPct}%)</span>
                      </span>
                    </td>
                    <td>{rc.avg_cpu_percent != null ? `${rc.avg_cpu_percent.toFixed(1)}%` : '—'}</td>
                    <td>{rc.avg_ram_percent != null ? `${rc.avg_ram_percent.toFixed(1)}%` : '—'}</td>
                    <td>{rc.avg_disk_percent != null ? `${rc.avg_disk_percent.toFixed(1)}%` : '—'}</td>
                    <td>{rc.max_temp_celsius != null ? `${rc.max_temp_celsius.toFixed(1)}°C` : '—'}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">Time-Series SQL Query</div>
            <h2>{t.analytics.trendTitle}</h2>
          </div>
          <div className="trend-controls">
            <select value={selectedNodeId} onChange={e => setSelectedNodeId(Number(e.target.value))}>
              {nodes.map(n => <option key={n.id} value={n.id}>{n.name} (#{n.id})</option>)}
            </select>
            <select value={metricCode} onChange={e => setMetricCode(e.target.value)}>
              {METRICS.map(m => <option key={m.code} value={m.code}>{m.label}</option>)}
            </select>
            <select value={limit} onChange={e => setLimit(e.target.value)}>
              <option value="20">20 {t.analytics.sampleLimit}</option>
              <option value="40">40 {t.analytics.sampleLimit}</option>
              <option value="100">100 {t.analytics.sampleLimit}</option>
            </select>
          </div>
        </div>
        <SparkChart points={points} emptyLabel={t.kpi.noData} />
      </section>
    </div>
  );
}
