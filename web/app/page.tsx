'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';

type NodeRow = {
  id: number; name: string; rack_name: string | null; room_name: string | null; site_name: string | null;
  status: string; last_ping_at: string | null; collected_at: string | null;
  cpu_usage_percent: number | null; memory_usage_percent: number | null; disk_usage_percent: number | null;
};
type AlertRow = { id: number; node_id: number; node_name: string; alert_type: string; severity: string; status: string; message: string; metric_value: number; triggered_at: string };
type TicketRow = {
  id: number; alert_id: number | null; node_id: number; node_name: string; title: string; description: string;
  priority: string; status: string; assigned_to_username: string | null; created_by_username: string | null;
  created_at: string; updated_at: string;
};
type SessionUser = { id: number; username: string; full_name: string | null; role: string };

const ROLE_LABEL: Record<string, string> = {
  ADMINISTRATOR: 'Quản trị viên',
  SYSTEM_OPERATOR: 'Vận hành hệ thống',
  FIELD_TECHNICIAN: 'Kỹ thuật viên hiện trường',
};

/** Backend chỉ cho ADMINISTRATOR/SYSTEM_OPERATOR ghi; technician chỉ đọc. */
const WRITE_ROLES = new Set(['ADMINISTRATOR', 'SYSTEM_OPERATOR']);
const PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'URGENT', 'CRITICAL'] as const;
const PRIORITY_LABEL: Record<string, string> = {
  LOW: 'Thấp', MEDIUM: 'Trung bình', HIGH: 'Cao', URGENT: 'Khẩn', CRITICAL: 'Nghiêm trọng',
};
/** Chỉ bước kế tiếp hợp lệ của state machine trong usp_update_ticket_status. */
const TICKET_FLOW: Record<string, string | null> = {
  OPEN: 'IN_PROGRESS', IN_PROGRESS: 'PENDING_CLOSURE', PENDING_CLOSURE: 'CLOSED', CLOSED: null,
};
const TICKET_ACTION_LABEL: Record<string, string> = {
  IN_PROGRESS: 'Bắt đầu xử lý', PENDING_CLOSURE: 'Chờ nghiệm thu', CLOSED: 'Đóng ticket',
};

function IconServer() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <rect x="3" y="4" width="18" height="7" rx="2" /><rect x="3" y="13" width="18" height="7" rx="2" />
    <path d="M7 7.5h.01M7 16.5h.01" />
  </svg>;
}

function IconPulse() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M3 12h4l2.5-6 4 12 2.5-6h5" />
  </svg>;
}

function IconWarning() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M12 4.5 21 20H3L12 4.5Z" /><path d="M12 10v4.5M12 17.2h.01" />
  </svg>;
}

function IconBell() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M6 9a6 6 0 1 1 12 0c0 4 1.5 5.5 1.5 5.5h-15S6 13 6 9Z" /><path d="M10 18a2 2 0 0 0 4 0" />
  </svg>;
}

function Meter({ value }: { value: number | null }) {
  if (value == null) return <span className="value-empty">—</span>;
  const pct = Math.max(0, Math.min(100, Math.round(value)));
  const tone = pct >= 85 ? 'meter-danger' : pct >= 65 ? 'meter-warn' : 'meter-ok';
  return (
    <span className="meter-cell">
      <span className="meter-value">{pct}%</span>
      <span className={`meter ${tone}`} role="presentation"><span style={{ width: `${pct}%` }} /></span>
    </span>
  );
}

function formatWhen(value: string | null) {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString('vi-VN');
}

export default function Dashboard() {
  const [token, setToken] = useState('');
  const [user, setUser] = useState<SessionUser | null>(null);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [nodes, setNodes] = useState<NodeRow[]>([]);
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [tickets, setTickets] = useState<TicketRow[]>([]);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [loading, setLoading] = useState(false);
  const [syncedAt, setSyncedAt] = useState<string>('');
  const [pending, setPending] = useState<string>('');
  const [showTicketForm, setShowTicketForm] = useState(false);
  const [formNodeId, setFormNodeId] = useState('');
  const [formTitle, setFormTitle] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formPriority, setFormPriority] = useState<string>('MEDIUM');
  const [formAlertId, setFormAlertId] = useState('');

  const refresh = useCallback(async (jwt: string) => {
    const headers = { Authorization: `Bearer ${jwt}` };
    const [nodeRes, alertRes, ticketRes] = await Promise.all([
      fetch('/api/nodes', { headers, cache: 'no-store' }),
      fetch('/api/alerts?status=OPEN,ACKNOWLEDGED', { headers, cache: 'no-store' }),
      fetch('/api/tickets', { headers, cache: 'no-store' }),
    ]);
    if (!nodeRes.ok || !alertRes.ok || !ticketRes.ok) throw new Error('Không tải được dữ liệu. Đăng nhập lại hoặc kiểm tra API/DB.');
    setNodes(await nodeRes.json());
    setAlerts(await alertRes.json());
    setTickets(await ticketRes.json());
    setSyncedAt(new Date().toLocaleTimeString('vi-VN'));
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
      setToken(data.access_token);
      setUser(data.user ?? null);
      setPassword('');
    } catch (e) { setError(e instanceof Error ? e.message : 'Đăng nhập thất bại.'); }
    finally { setLoading(false); }
  }

  async function submitAction(key: string, url: string, method: 'POST' | 'PATCH', body?: Record<string, unknown>) {
    setPending(key); setError(''); setNotice('');
    try {
      const response = await fetch(url, {
        method,
        headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error || `Yêu cầu thất bại (HTTP ${response.status}).`);
      await refresh(token);
      return result as Record<string, unknown>;
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Thao tác thất bại.';
      setError(message);
      throw e;
    } finally {
      setPending('');
    }
  }

  async function acknowledgeAlert(alert: AlertRow) {
    try {
      await submitAction(`alert-${alert.id}`, `/api/alerts/${alert.id}/ack`, 'POST');
      setNotice(`Đã xác nhận cảnh báo #${alert.id}.`);
    } catch { /* submitAction shows API error in the banner. */ }
  }

  async function createTicket(event: FormEvent) {
    event.preventDefault();
    const nodeId = Number(formNodeId);
    if (!Number.isInteger(nodeId) || nodeId <= 0 || !formTitle.trim() || formTitle.trim().length > 200) {
      setError('Chọn node và nhập tiêu đề dài 1–200 ký tự.');
      return;
    }
    try {
      const result = await submitAction('create-ticket', '/api/tickets', 'POST', {
        node_id: nodeId,
        title: formTitle.trim(),
        description: formDescription,
        priority: formPriority,
        ...(formAlertId ? { alert_id: Number(formAlertId) } : {}),
      });
      setNotice(`Đã tạo ticket #${String(result.id)}.`);
      setFormTitle(''); setFormDescription(''); setFormAlertId(''); setShowTicketForm(false);
    } catch { /* submitAction shows API error in the banner. */ }
  }

  async function advanceTicket(ticket: TicketRow) {
    const nextStatus = TICKET_FLOW[ticket.status];
    if (!nextStatus) return;
    if (nextStatus === 'CLOSED' && !window.confirm(`Đóng ticket #${ticket.id}? Thao tác này kết thúc quy trình xử lý.`)) return;
    try {
      await submitAction(`ticket-${ticket.id}`, `/api/tickets/${ticket.id}/status`, 'PATCH', { status: nextStatus });
      setNotice(`Ticket #${ticket.id}: ${ticket.status} → ${nextStatus}.`);
    } catch { /* submitAction shows API error in the banner. */ }
  }

  function startTicketFromAlert(alert: AlertRow) {
    setFormNodeId(String(alert.node_id));
    setFormTitle(`${alert.alert_type} · ${alert.node_name}`.slice(0, 200));
    setFormDescription(alert.message);
    setFormPriority(alert.severity === 'CRITICAL' ? 'CRITICAL' : alert.severity === 'WARNING' ? 'HIGH' : 'MEDIUM');
    setFormAlertId(String(alert.id));
    setShowTicketForm(true);
    setError(''); setNotice('');
  }

  function logout() {
    setToken(''); setUser(null); setNodes([]); setAlerts([]); setTickets([]); setError(''); setNotice(''); setSyncedAt('');
  }

  if (!token) return <main className="login-wrap"><form className="login-card" onSubmit={login}>
    <div className="brand-mark"><IconServer /></div>
    <div className="eyebrow">AR-IMMS · Command Center</div>
    <h1>Đăng nhập</h1>
    <p>Giám sát hạ tầng Data Center</p>
    <label>Tên đăng nhập<input autoComplete="username" value={username} onChange={e => setUsername(e.target.value)} required /></label>
    <label>Mật khẩu<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
    {error && <div className="error" role="alert">{error}</div>}
    <button disabled={loading}>{loading ? 'Đang xác thực…' : 'Tiếp tục'}</button>
  </form></main>;

  const online = nodes.filter(n => n.status === 'ONLINE').length;
  const attention = nodes.filter(n => ['WARNING', 'CRITICAL', 'UNAVAILABLE'].includes(n.status)).length;
  const displayName = user?.full_name || user?.username || 'Phiên làm việc';
  const canWrite = WRITE_ROLES.has(user?.role ?? '');
  const initials = displayName.trim().split(/\s+/).slice(-2).map(part => part[0]).join('').toUpperCase();
  const openAlerts = alerts.filter(alert => alert.status === 'OPEN').length;

  return <main className="shell">
    <header className="topbar">
      <div className="brand">
        <div className="brand-mark"><IconServer /></div>
        <div>
          <div className="eyebrow">AR-IMMS · Digital Twin</div>
          <h1>Command Center</h1>
        </div>
      </div>
      <div className="topbar-actions">
        <span className="live"><span className="live-dot" />{syncedAt ? `Live · ${syncedAt}` : 'Đang kết nối…'}</span>
        <div className="user">
          <span className="avatar">{initials || 'AR'}</span>
          <span className="user-meta">
            <span className="user-name">{displayName}</span>
            <span className="user-role">{user ? (ROLE_LABEL[user.role] ?? user.role) : '—'}</span>
          </span>
        </div>
        <button className="secondary" onClick={logout}>Đăng xuất</button>
      </div>
    </header>

    {error && <div className="error banner" role="alert">{error}</div>}
    {notice && <div className="notice banner" role="status">{notice}</div>}

    <section className="metrics" aria-label="Tổng quan hạ tầng">
      <article className="metric">
        <div className="metric-head"><span className="metric-icon"><IconServer /></span><span className="metric-label">Tổng node</span></div>
        <strong className="metric-value">{nodes.length}</strong>
        <span className="metric-foot">Thiết bị trong Digital Twin</span>
      </article>
      <article className="metric">
        <div className="metric-head"><span className="metric-icon tone-green"><IconPulse /></span><span className="metric-label">Đang hoạt động</span></div>
        <strong className="metric-value tone-green">{online}</strong>
        <span className="metric-foot">{nodes.length ? `${Math.round((online / nodes.length) * 100)}% tổng số node` : 'Chưa có dữ liệu'}</span>
      </article>
      <article className="metric">
        <div className="metric-head"><span className="metric-icon tone-orange"><IconWarning /></span><span className="metric-label">Cần chú ý</span></div>
        <strong className={`metric-value ${attention ? 'tone-red' : ''}`}>{attention}</strong>
        <span className="metric-foot">Warning · Critical · Unavailable</span>
      </article>
      <article className="metric">
        <div className="metric-head"><span className="metric-icon tone-red"><IconBell /></span><span className="metric-label">Cảnh báo mở</span></div>
        <strong className="metric-value">{alerts.length}</strong>
        <span className="metric-foot">Chưa xử lý hoặc đã xác nhận</span>
      </article>
    </section>

    <section className="panel">
      <div className="section-head">
        <div><div className="eyebrow">Infrastructure</div><h2>Node mới nhất</h2></div>
        <span className="refresh-label">Tự làm mới · 5 giây</span>
      </div>
      <div className="table-wrap">
        <table>
          <thead><tr><th>Node</th><th>Vị trí</th><th>Trạng thái</th><th>CPU</th><th>RAM</th><th>Disk</th><th>Telemetry UTC</th></tr></thead>
          <tbody>
            {nodes.map(node => <tr key={node.id}>
              <td><span className="node-cell"><span className="node-name">{node.name}</span><span className="node-id">#{node.id}</span></span></td>
              <td className="cell-muted">{[node.site_name, node.room_name, node.rack_name].filter(Boolean).join(' / ') || '—'}</td>
              <td><span className={`status status-${node.status.toLowerCase()}`}>{node.status}</span></td>
              <td><Meter value={node.cpu_usage_percent} /></td>
              <td><Meter value={node.memory_usage_percent} /></td>
              <td><Meter value={node.disk_usage_percent} /></td>
              <td className="cell-time">{formatWhen(node.collected_at)}</td>
            </tr>)}
            {!nodes.length && <tr><td colSpan={7} className="empty">Chưa có node hoặc dữ liệu telemetry.</td></tr>}
          </tbody>
        </table>
      </div>
    </section>

    <section className="panel">
      <div className="section-head">
        <div><div className="eyebrow">Active Events</div><h2>Cảnh báo đang mở</h2></div>
        <span className="refresh-label">{alerts.length ? `${alerts.length} sự kiện` : 'Không có sự kiện'}</span>
      </div>
      <div className="alert-list">
        {alerts.map(alert => <article key={alert.id} className="alert-row">
          <span className={`severity severity-${alert.severity.toLowerCase()}`}>{alert.severity}</span>
          <div><strong>{alert.node_name} · {alert.alert_type}</strong><p>{alert.message}</p></div>
          <div className="alert-actions">
            <time>{formatWhen(alert.triggered_at)}</time>
            {canWrite && alert.status === 'OPEN' && <button className="compact-action" disabled={pending === `alert-${alert.id}`} onClick={() => void acknowledgeAlert(alert)}>
              {pending === `alert-${alert.id}` ? 'Đang lưu…' : 'Xác nhận'}
            </button>}
            {canWrite && <button className="compact-action secondary" disabled={pending !== ''} onClick={() => startTicketFromAlert(alert)}>Tạo ticket</button>}
          </div>
        </article>)}
        {!alerts.length && <div className="empty">Không có cảnh báo đang mở.</div>}
      </div>
    </section>

    <section className="panel ticket-panel">
      <div className="section-head">
        <div><div className="eyebrow">Incident workflow</div><h2>Ticket bảo trì</h2></div>
        <div className="ticket-heading-actions">
          <span className="refresh-label">{tickets.length} ticket</span>
          {canWrite && <button className="compact-action" onClick={() => { setShowTicketForm(value => !value); setError(''); setNotice(''); }}>
            {showTicketForm ? 'Đóng biểu mẫu' : 'Tạo ticket'}
          </button>}
        </div>
      </div>

      {showTicketForm && canWrite && <form className="ticket-form" onSubmit={createTicket}>
        <label>Node
          <select value={formNodeId} onChange={event => setFormNodeId(event.target.value)} required>
            <option value="">Chọn node</option>
            {nodes.map(node => <option key={node.id} value={node.id}>{node.name} · #{node.id}</option>)}
          </select>
        </label>
        <label>Tiêu đề
          <input value={formTitle} maxLength={200} onChange={event => setFormTitle(event.target.value)} required />
        </label>
        <label>Độ ưu tiên
          <select value={formPriority} onChange={event => setFormPriority(event.target.value)}>
            {PRIORITIES.map(priority => <option key={priority} value={priority}>{PRIORITY_LABEL[priority]}</option>)}
          </select>
        </label>
        <label className="ticket-description">Mô tả
          <textarea rows={3} value={formDescription} onChange={event => setFormDescription(event.target.value)} />
        </label>
        <div className="ticket-form-footer">
          {formAlertId && <span className="linked-alert">Liên kết cảnh báo #{formAlertId}</span>}
          <button disabled={pending === 'create-ticket' || nodes.length === 0}>
            {pending === 'create-ticket' ? 'Đang tạo…' : 'Lưu ticket'}
          </button>
        </div>
      </form>}

      <div className="ticket-list">
        {tickets.map(ticket => {
          const nextStatus = TICKET_FLOW[ticket.status];
          return <article className="ticket-row" key={ticket.id}>
            <div className="ticket-main">
              <div className="ticket-title-line"><strong>{ticket.title}</strong><span className={`priority priority-${ticket.priority.toLowerCase()}`}>{PRIORITY_LABEL[ticket.priority] ?? ticket.priority}</span></div>
              <p>{ticket.node_name} · #{ticket.node_id}{ticket.alert_id ? ` · Cảnh báo #${ticket.alert_id}` : ''}</p>
              {ticket.description && <p className="ticket-description-text">{ticket.description}</p>}
              <span className="ticket-meta">Tạo bởi {ticket.created_by_username ?? '—'} · {formatWhen(ticket.updated_at)}</span>
            </div>
            <div className="ticket-side">
              <span className={`ticket-status ticket-status-${ticket.status.toLowerCase()}`}>{ticket.status.replaceAll('_', ' ')}</span>
              {canWrite && nextStatus && <button className="compact-action" disabled={pending === `ticket-${ticket.id}`} onClick={() => void advanceTicket(ticket)}>
                {pending === `ticket-${ticket.id}` ? 'Đang lưu…' : TICKET_ACTION_LABEL[nextStatus]}
              </button>}
            </div>
          </article>;
        })}
        {!tickets.length && <div className="empty">Chưa có ticket bảo trì.</div>}
      </div>
    </section>
  </main>;
}
