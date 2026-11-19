'use client';

import type { TelemetryPoint } from '@/lib/types';

type Props = {
  points: TelemetryPoint[];
  unit?: string | null;
  emptyLabel: string;
};

export function SparkChart({ points, unit, emptyLabel }: Props) {
  if (!points.length) {
    return <div className="empty chart-empty">{emptyLabel}</div>;
  }

  const values = points.map(p => p.value);
  const rawMin = Math.min(...values);
  const rawMax = Math.max(...values);
  const pad = rawMax === rawMin ? Math.max(1, Math.abs(rawMax) * 0.1) : (rawMax - rawMin) * 0.12;
  const minVal = Math.max(0, rawMin - pad);
  const maxVal = rawMax + pad;
  const range = Math.max(1e-6, maxVal - minVal);

  const width = 640;
  const height = 180;
  const left = 42;
  const right = 14;
  const top = 16;
  const bottom = 28;
  const plotW = width - left - right;
  const plotH = height - top - bottom;

  const coords = points.map((p, idx) => {
    const x = points.length === 1 ? left + plotW / 2 : left + (idx / (points.length - 1)) * plotW;
    const y = top + (1 - (p.value - minVal) / range) * plotH;
    return { x, y, point: p };
  });

  const linePath = coords.map((c, i) => `${i === 0 ? 'M' : 'L'}${c.x.toFixed(1)},${c.y.toFixed(1)}`).join(' ');
  const areaPath = `${linePath} L${coords[coords.length - 1].x.toFixed(1)},${(top + plotH).toFixed(1)} L${coords[0].x.toFixed(1)},${(top + plotH).toFixed(1)} Z`;

  const latest = points[points.length - 1];
  const avg = values.reduce((acc, v) => acc + v, 0) / values.length;
  const displayUnit = unit || latest.unit || '';

  return (
    <div className="spark-chart-wrap">
      <div className="spark-stats">
        <span>Min: <strong>{rawMin.toFixed(1)}{displayUnit}</strong></span>
        <span>Avg: <strong>{avg.toFixed(1)}{displayUnit}</strong></span>
        <span>Max: <strong>{rawMax.toFixed(1)}{displayUnit}</strong></span>
        <span>Latest: <strong className="tone-teal">{latest.value.toFixed(1)}{displayUnit}</strong></span>
      </div>
      <svg viewBox={`0 0 ${width} ${height}`} className="spark-svg" role="img" aria-label="Telemetry time-series chart">
        <defs>
          <linearGradient id="arimmsSparkFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="rgba(100, 210, 255, 0.36)" />
            <stop offset="100%" stopColor="rgba(100, 210, 255, 0.02)" />
          </linearGradient>
        </defs>
        {[0, 0.5, 1].map(frac => {
          const y = top + frac * plotH;
          const label = (maxVal - frac * range).toFixed(0);
          return (
            <g key={frac}>
              <line x1={left} y1={y} x2={width - right} y2={y} className="spark-grid" />
              <text x={left - 8} y={y + 4} textAnchor="end" className="spark-axis">{label}</text>
            </g>
          );
        })}
        {coords.length > 1 && <path d={areaPath} fill="url(#arimmsSparkFill)" />}
        {coords.length > 1 && <path d={linePath} fill="none" className="spark-line" />}
        {coords.map((c, idx) => (
          <circle key={c.point.id ?? idx} cx={c.x} cy={c.y} r={idx === coords.length - 1 ? 4.2 : 2.3} className="spark-dot">
            <title>{`${c.point.value}${displayUnit} @ ${new Date(c.point.timestamp).toLocaleString()}`}</title>
          </circle>
        ))}
        <text x={left} y={height - 6} className="spark-axis">
          {new Date(points[0].timestamp).toLocaleTimeString()}
        </text>
        <text x={width - right} y={height - 6} textAnchor="end" className="spark-axis">
          {new Date(latest.timestamp).toLocaleTimeString()}
        </text>
      </svg>
    </div>
  );
}
