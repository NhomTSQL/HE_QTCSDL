'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';

type NodeRow = {
  id: number; name: string; rack_name: string | null; room_name: string | null; site_name: string | null;
  status: string; last_ping_at: string | null; collected_at: string | null;
  cpu_usage_percent: number | null; memory_usage_percent: number | null; disk_usage_percent: number | null;
};
type AlertRow = { id: number; node_id: number; node_name: string; alert_type: string; severity: string; status: string; message: string; metric_value: number; triggered_at: string };

export default function Dashboard() {
  const [token, setToken] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [nodes, setNodes] = useState<NodeRow[]>([]);
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async (jwt: string) => {
    const headers = { Authorization: `Bearer ${jwt}` };
    const [nodeRes, alertRes] = await Promise.all([
      fetch('/api/nodes', { headers, cache: 'no-store' }),
      fetch('/api/alerts?status=OPEN,ACKNOWLEDGED', { headers, cache: 'no-store' }),
    ]);
    if (!nodeRes.ok || !alertRes.ok) throw new Error('Không tải được dữ liệu. Đăng nhập lại hoặc kiểm tra API/DB.');
    setNodes(await nodeRes.json());
    setAlerts(await alertRes.json());
  }, []);

  useEffect(() => {
    if (!token) return;
    let active = true;
    const tick = async () => {
      try { await refresh(token); if (active) setError(''); }
      catch (e) { if (active) setError(e instanceof Error ? e.message : 'Lỗi tải dữ liệu.'); }
    };
    void tick();
    const timer = window.setInterval(() => void tick(), 5000);
    return () => { active = false; window.clearInterval(timer); };
  }, [token, refresh]);

  async function login(event: FormEvent) {
    event.preventDefault(); setLoading(true); setError('');
    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Đăng nhập thất bại.');
      setToken(data.token);
    } catch (e) { setError(e instanceof Error ? e.message : 'Đăng nhập thất bại.'); }
    finally { setLoading(false); }
  }

  if (!token) return <main className="login-wrap"><form className="login-card" onSubmit={login}>
    <div className="eyebrow">AR-IMMS · COMMAND CENTER</div><h1>Đăng nhập</h1><p>Giám sát hạ tầng Data Center</p>
    <label>Tên đăng nhập<input autoComplete="username" value={username} onChange={e => setUsername(e.target.value)} required /></label>
    <label>Mật khẩu<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
    {error && <div className="error">{error}</div>}<button disabled={loading}>{loading ? 'Đang xác thực…' : 'Tiếp tục'}</button>
  </form></main>;

  const online = nodes.filter(n => n.status === 'ONLINE').length;
  const attention = nodes.filter(n => ['WARNING', 'CRITICAL', 'UNAVAILABLE'].includes(n.status)).length;
  return <main className="shell">
    <header className="topbar"><div><div className="eyebrow">AR-IMMS · DIGITAL TWIN</div><h1>Command Center</h1></div><button className="secondary" onClick={() => { setToken(''); setNodes([]); setAlerts([]); }}>Đăng xuất</button></header>
    {error && <div className="error banner">{error}</div>}
    <section className="metrics">
      <article><span>Tổng node</span><strong>{nodes.length}</strong></article>
      <article><span>Đang hoạt động</span><strong className="green">{online}</strong></article>
      <article><span>Cần chú ý</span><strong className="red">{attention}</strong></article>
      <article><span>Cảnh báo mở</span><strong>{alerts.length}</strong></article>
    </section>
    <section className="panel"><div className="section-head"><div><div className="eyebrow">INFRASTRUCTURE</div><h2>Node mới nhất</h2></div><span className="refresh-label">Tự làm mới · 5 giây</span></div>
      <div className="table-wrap"><table><thead><tr><th>Node</th><th>Vị trí</th><th>Trạng thái</th><th>CPU</th><th>RAM</th><th>Disk</th><th>Telemetry UTC</th></tr></thead>
        <tbody>{nodes.map(node => <tr key={node.id}><td><strong>{node.name}</strong><small>#{node.id}</small></td><td>{[node.site_name,node.room_name,node.rack_name].filter(Boolean).join(' / ') || '—'}</td>
          <td><span className={`status status-${node.status.toLowerCase()}`}>{node.status}</span></td><td>{node.cpu_usage_percent == null ? '—' : `${node.cpu_usage_percent}%`}</td><td>{node.memory_usage_percent == null ? '—' : `${node.memory_usage_percent}%`}</td><td>{node.disk_usage_percent == null ? '—' : `${node.disk_usage_percent}%`}</td><td>{node.collected_at ? new Date(node.collected_at).toLocaleString() : '—'}</td></tr>)}
          {!nodes.length && <tr><td colSpan={7} className="empty">Chưa có node hoặc dữ liệu telemetry.</td></tr>}</tbody></table></div>
    </section>
    <section className="panel"><div className="section-head"><div><div className="eyebrow">ACTIVE EVENTS</div><h2>Cảnh báo đang mở</h2></div></div>
      <div className="alert-list">{alerts.map(alert => <article key={alert.id} className="alert-row"><span className={`severity severity-${alert.severity.toLowerCase()}`}>{alert.severity}</span><div><strong>{alert.node_name} · {alert.alert_type}</strong><p>{alert.message}</p></div><time>{new Date(alert.triggered_at).toLocaleString()}</time></article>)}
        {!alerts.length && <div className="empty">Không có cảnh báo đang mở.</div>}</div>
    </section>
  </main>;
}
