'use client';

import { FormEvent, useCallback, useEffect, useRef, useState } from 'react';
import { ArrowLeftRight, Bell, Boxes, ChartNoAxesColumn, ClipboardList, LayoutDashboard, LogOut, Menu, QrCode, Shield, X } from 'lucide-react';
import { AdminTab } from '@/components/AdminTab';
import { AnalyticsTab } from '@/components/AnalyticsTab';
import { ArScannerTab } from '@/components/ArScannerTab';
import { AssetsTab } from '@/components/AssetsTab';
import { HandoverTab, type HandoverNoteRow } from '@/components/HandoverTab';
import { apiUrl } from '@/lib/api';
import { SparkChart } from '@/components/SparkChart';
import { getCopy } from '@/lib/i18n';
import type {
  AlertRow,
  AnalyticsSummary,
  AssetRow,
  AuditLogRow,
  AccountAccessRequest,
  CollectorAgentRow,
  ContainerRow,
  Lang,
  MaintenanceRow,
  NodeRow,
  NotificationRow,
  RackCapacityRow,
  RackRow,
  SessionUser,
  SiteRoomRow,
  TechnicianOption,
  TelemetryPoint,
  ThresholdRow,
  TicketNoteRow,
  TicketRow,
  UserRow,
} from '@/lib/types';

type TabKey = 'overview' | 'my-work' | 'handover' | 'ar' | 'assets' | 'analytics' | 'admin';

const MODULES = [
  { key: 'overview', icon: LayoutDashboard },
  { key: 'my-work', icon: ClipboardList },
  { key: 'handover', icon: ArrowLeftRight },
  { key: 'ar', icon: QrCode },
  { key: 'assets', icon: Boxes },
  { key: 'analytics', icon: ChartNoAxesColumn },
  { key: 'admin', icon: Shield },
] as const;
const ALERT_FILTERS = [
  ['OPEN,ACKNOWLEDGED', 'filterActive'],
  ['OPEN,ACKNOWLEDGED,RESOLVED,CLOSED', 'filterAll'],
] as const;

const WRITE_ROLES = new Set(['ADMINISTRATOR', 'SYSTEM_OPERATOR']);
const PRIORITIES = ['LOW', 'MEDIUM', 'HIGH', 'URGENT', 'CRITICAL'] as const;
const PAGE_SIZE = 25;
const SESSION_STORAGE_KEY = 'ar_imms_session';

type RefreshOpts = {
  activeTab: TabKey;
  entityFilter: string;
  activeAlertFilter: string;
  activeAlertPage: number;
  activeTicketPage: number;
  activeAuditPage: number;
  thresholdsOpen: boolean;
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
function IconBolt() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z" />
  </svg>;
}
function IconClock() {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" />
  </svg>;
}

function Meter({ value }: { value: number | null | undefined }) {
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

function formatWhen(value: string | null | undefined, lang: Lang) {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString(lang === 'vi' ? 'vi-VN' : 'en-US');
}

function LanguageSwitch({ lang, onSwitch }: { lang: Lang; onSwitch: (next: Lang) => void }) {
  return (
    <div className="lang-switch" role="group" aria-label={getCopy(lang).language}>
      <button type="button" aria-pressed={lang === 'en'} className={lang === 'en' ? 'active' : ''} onClick={() => onSwitch('en')}>EN</button>
      <button type="button" aria-pressed={lang === 'vi'} className={lang === 'vi' ? 'active' : ''} onClick={() => onSwitch('vi')}>VI</button>
    </div>
  );
}

export default function Dashboard() {
  const [lang, setLang] = useState<Lang>('en');
  const [token, setToken] = useState('');
  const [user, setUser] = useState<SessionUser | null>(null);
  const [tab, setTab] = useState<TabKey>('overview');

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [authView, setAuthView] = useState<'login' | 'forgot' | 'request'>('login');
  const [recoveryCode, setRecoveryCode] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [mfaRequired, setMfaRequired] = useState(false);
  const [requestForm, setRequestForm] = useState({ username: '', email: '', full_name: '', requested_role: 'FIELD_TECHNICIAN', note: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [syncedAt, setSyncedAt] = useState('');
  const [checks, setChecks] = useState<Partial<Record<TabKey, { time?: number; failed: boolean }>>>({});
  const ticketTitleRef = useRef<HTMLInputElement>(null);
  const focusTicketTitle = useRef(false);
  const notificationButton = useRef<HTMLButtonElement>(null);
  const mobileMenu = useRef<HTMLDialogElement>(null);
  const [pending, setPending] = useState('');

  // Core data
  const [nodes, setNodes] = useState<NodeRow[]>([]);
  const [racks, setRacks] = useState<RackRow[]>([]);
  const [containers, setContainers] = useState<ContainerRow[]>([]);
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [thresholds, setThresholds] = useState<ThresholdRow[]>([]);
  const [tickets, setTickets] = useState<TicketRow[]>([]);
  const [technicians, setTechnicians] = useState<TechnicianOption[]>([]);
  const [assets, setAssets] = useState<AssetRow[]>([]);
  const [maintenance, setMaintenance] = useState<MaintenanceRow[]>([]);
  const [summary, setSummary] = useState<AnalyticsSummary | null>(null);
  const [rackCapacity, setRackCapacity] = useState<RackCapacityRow[]>([]);
  const [usersList, setUsersList] = useState<UserRow[]>([]);
  const [accountRequests, setAccountRequests] = useState<AccountAccessRequest[]>([]);
  const [accountRequestsAvailable, setAccountRequestsAvailable] = useState(true);
  const [handoverNotes, setHandoverNotes] = useState<HandoverNoteRow[]>([]);
  const [handoverAvailable, setHandoverAvailable] = useState(true);
  const [auditLogs, setAuditLogs] = useState<AuditLogRow[]>([]);
  const [auditFilter, setAuditFilter] = useState('');
  const [collectors, setCollectors] = useState<CollectorAgentRow[]>([]);
  const [notifications, setNotifications] = useState<NotificationRow[]>([]);
  const [showNotifs, setShowNotifs] = useState(false);
  const [sitesRooms, setSitesRooms] = useState<SiteRoomRow[]>([]);
  const [sseConnected, setSseConnected] = useState(false);
  const [alertFilter, setAlertFilter] = useState<'OPEN,ACKNOWLEDGED' | 'OPEN,ACKNOWLEDGED,RESOLVED,CLOSED'>('OPEN,ACKNOWLEDGED');
  const [alertPage, setAlertPage] = useState(0);
  const [alertHasNext, setAlertHasNext] = useState(false);
  const [ticketPage, setTicketPage] = useState(0);
  const [ticketHasNext, setTicketHasNext] = useState(false);
  const [auditPage, setAuditPage] = useState(0);
  const [auditHasNext, setAuditHasNext] = useState(false);

  // Overview Drill-down & Onboarding & Hierarchy
  const [selectedRoomId, setSelectedRoomId] = useState<number | null>(null);
  const [selectedRackId, setSelectedRackId] = useState<number | null>(null);
  const [inspectedNodeId, setInspectedNodeId] = useState<number | null>(null);
  const [inspectMetric, setInspectMetric] = useState('cpu_usage_percent');
  const [inspectHistory, setInspectHistory] = useState<TelemetryPoint[]>([]);
  const [showOnboardForm, setShowOnboardForm] = useState(false);
  const [showInfraForm, setShowInfraForm] = useState(false);
  const [issuedApiKey, setIssuedApiKey] = useState('');
  const [copiedKey, setCopiedKey] = useState(false);

  useEffect(() => {
    if (!issuedApiKey) return;
    const timer = setTimeout(() => {
      setIssuedApiKey('');
      setCopiedKey(false);
    }, 10000);
    return () => clearTimeout(timer);
  }, [issuedApiKey]);
  const [accountOpen, setAccountOpen] = useState(false);
  const [currentPassword, setCurrentPassword] = useState('');
  const [mfaSecret, setMfaSecret] = useState('');
  const [mfaCode, setMfaCode] = useState('');
  const [mfaBackupCodes, setMfaBackupCodes] = useState<string[]>([]);

  // Hierarchy manager state
  const [infraType, setInfraType] = useState<'SITE' | 'ROOM' | 'RACK'>('RACK');
  const [infraParentId, setInfraParentId] = useState('1');
  const [infraName, setInfraName] = useState('');
  const [infraCode, setInfraCode] = useState('');
  const [infraExtra, setInfraExtra] = useState('');
  const [infraUnits, setInfraUnits] = useState('42');
  const [infraPowerCap, setInfraPowerCap] = useState('10000');

  // Node update / relocate state
  const [editNodeRackId, setEditNodeRackId] = useState('1');
  const [editNodeName, setEditNodeName] = useState('');
  const [editNodeHost, setEditNodeHost] = useState('');
  const [editNodeIp, setEditNodeIp] = useState('');
  const [editNodeMac, setEditNodeMac] = useState('');
  const [editNodeU, setEditNodeU] = useState('1');
  const [editNodePower, setEditNodePower] = useState('150');
  const [editNodeStatus, setEditNodeStatus] = useState('ONLINE');

  const [obRackId, setObRackId] = useState('1');
  const [obName, setObName] = useState('');
  const [obHostname, setObHostname] = useState('');
  const [obIp, setObIp] = useState('');
  const [obMac, setObMac] = useState('');
  const [obU, setObU] = useState('4');
  const [obPower, setObPower] = useState('220');
  const [obMarker, setObMarker] = useState('');

  // Marker assignment on inspected node
  const [markerTypeInput, setMarkerTypeInput] = useState('QR');
  const [markerCodeInput, setMarkerCodeInput] = useState('');

  // Thresholds editor
  const [showThresholds, setShowThresholds] = useState(false);
  const [thresholdDrafts, setThresholdDrafts] = useState<Record<number, { warning: string; critical: string; duration: string; active: boolean }>>({});

  // Ticket creation, notes, assignment, closure
  const [showTicketForm, setShowTicketForm] = useState(false);
  const [formNodeId, setFormNodeId] = useState('');
  const [formTitle, setFormTitle] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formPriority, setFormPriority] = useState<string>('MEDIUM');
  const [formAlertId, setFormAlertId] = useState('');

  const [assignDrafts, setAssignDrafts] = useState<Record<number, string>>({});
  const [openNotesTicketId, setOpenNotesTicketId] = useState<number | null>(null);
  const [ticketNotes, setTicketNotes] = useState<TicketNoteRow[]>([]);
  const [newNoteText, setNewNoteText] = useState('');
  const [closureTicketId, setClosureTicketId] = useState<number | null>(null);
  const [closureSummary, setClosureSummary] = useState('');
  const [closureDetails, setClosureDetails] = useState('');
  const [closureType, setClosureType] = useState('CORRECTIVE');

  const t = getCopy(lang);

  useEffect(() => {
    const desktop = window.matchMedia('(min-width: 56rem)');
    const closeOnDesktop = () => { if (desktop.matches) mobileMenu.current?.close(); };
    desktop.addEventListener('change', closeOnDesktop);
    return () => desktop.removeEventListener('change', closeOnDesktop);
  }, []);

  useEffect(() => { document.documentElement.lang = lang; }, [lang]);

  useEffect(() => {
    if (showTicketForm && focusTicketTitle.current) {
      ticketTitleRef.current?.focus();
      focusTicketTitle.current = false;
    }
  }, [showTicketForm]);

  useEffect(() => {
    try {
      const savedLang = window.localStorage.getItem('ar_imms_lang');
      if (savedLang === 'en' || savedLang === 'vi') setLang(savedLang);
      const savedSession = window.sessionStorage.getItem(SESSION_STORAGE_KEY);
      if (savedSession) {
        const parsed = JSON.parse(savedSession) as { token?: unknown; user?: SessionUser | null };
        if (typeof parsed?.token === 'string' && parsed.token) {
          setToken(parsed.token);
          setUser(parsed.user ?? null);
        }
      }
    } catch { /* ignore storage restrictions */ }
  }, []);

  function switchLanguage(next: Lang) {
    setLang(next);
    try { window.localStorage.setItem('ar_imms_lang', next); } catch { /* ignore */ }
  }

  const refreshOpts: RefreshOpts = {
    activeTab: tab,
    entityFilter: auditFilter,
    activeAlertFilter: alertFilter,
    activeAlertPage: alertPage,
    activeTicketPage: ticketPage,
    activeAuditPage: auditPage,
    thresholdsOpen: showThresholds,
  };
  const refreshOptsRef = useRef<RefreshOpts>(refreshOpts);
  refreshOptsRef.current = refreshOpts;

  const refresh = useCallback(async (jwt: string, currentUser: SessionUser | null, opts: RefreshOpts) => {
    const headers = { Authorization: `Bearer ${jwt}` };
    const fetchJson = async (url: string) => {
      const res = await fetch(apiUrl(url), { headers, cache: 'no-store' });
      if (res.status === 401) throw new Error('UNAUTHORIZED');
      if (!res.ok) {
        const detail = await res.clone().json().catch(() => ({}));
        throw new Error(`LOAD_ERR ${url} (${res.status})${detail.error ? `: ${detail.error}` : ''}`);
      }
      return res.json();
    };

    const tasks: Promise<void>[] = [
      fetchJson('/api/notifications?limit=30').then(setNotifications),
    ];

    if (opts.activeTab === 'overview' || opts.activeTab === 'analytics' || opts.activeTab === 'my-work' || opts.activeTab === 'handover') {
      tasks.push(
        fetchJson('/api/nodes?limit=200').then(setNodes),
        fetchJson('/api/summary').then(summaryData => {
          setSummary(summaryData.summary ?? null);
          setRackCapacity(summaryData.racks ?? []);
        }),
      );
    }

    if (opts.activeTab === 'overview' || opts.activeTab === 'my-work') {
      const mine = opts.activeTab === 'my-work';
      const alertUrl = mine ? '/api/alerts?status=OPEN,ACKNOWLEDGED&limit=500&offset=0' : `/api/alerts?status=${encodeURIComponent(opts.activeAlertFilter)}&limit=${PAGE_SIZE + 1}&offset=${opts.activeAlertPage * PAGE_SIZE}`;
      const ticketUrl = mine ? '/api/tickets?limit=500&offset=0' : `/api/tickets?limit=${PAGE_SIZE + 1}&offset=${opts.activeTicketPage * PAGE_SIZE}`;
      tasks.push(
        fetchJson(alertUrl).then((data: AlertRow[]) => {
          setAlertHasNext(!mine && data.length > PAGE_SIZE);
          setAlerts(data.slice(0, mine ? 500 : PAGE_SIZE));
        }),
        fetchJson(ticketUrl).then((data: TicketRow[]) => {
          setTicketHasNext(!mine && data.length > PAGE_SIZE);
          setTickets(data.slice(0, mine ? 500 : PAGE_SIZE));
        }),
        ...(mine ? [] : [fetchJson('/api/hierarchy').then(hierarchyData => {
          setSitesRooms(hierarchyData.sites_rooms ?? []);
          setRacks(hierarchyData.racks ?? []);
        }), fetchJson('/api/containers').then(setContainers)]),
      );
      if (opts.thresholdsOpen && !mine) {
        tasks.push(fetchJson('/api/thresholds').then(setThresholds));
      }
      if (WRITE_ROLES.has(currentUser?.role ?? '')) {
        tasks.push(fetchJson('/api/technicians').then(setTechnicians));
      }
    } else if (opts.activeTab === 'assets') {
      tasks.push(
        fetchJson('/api/assets').then(setAssets),
        fetchJson('/api/maintenance').then(setMaintenance),
      );
    } else if (opts.activeTab === 'admin' && currentUser?.role === 'ADMINISTRATOR') {
      const entityParam = opts.entityFilter ? `&target_entity=${encodeURIComponent(opts.entityFilter)}` : '';
      const auditUrl = `/api/audit-logs?limit=${PAGE_SIZE + 1}&offset=${opts.activeAuditPage * PAGE_SIZE}${entityParam}`;
      tasks.push(
        fetchJson('/api/users').then(setUsersList),
        fetchJson('/api/collectors').then(setCollectors),
        fetchJson(auditUrl).then((data: AuditLogRow[]) => {
          setAuditHasNext(data.length > PAGE_SIZE);
          setAuditLogs(data.slice(0, PAGE_SIZE));
        }),
      );
      if (accountRequestsAvailable) {
        tasks.push(fetchJson('/api/account-requests').then(data => {
          setAccountRequests(data);
          setAccountRequestsAvailable(true);
        }).catch(err => {
          if (err instanceof Error && err.message === 'UNAUTHORIZED') throw err;
          setAccountRequests([]);
          setAccountRequestsAvailable(false);
        }));
      }
    } else if (opts.activeTab === 'handover') {
      if (handoverAvailable) tasks.push(fetchJson('/api/handover').then(data => {
        setHandoverNotes(data);
        setHandoverAvailable(true);
      }).catch(err => {
        if (err instanceof Error && err.message === 'UNAUTHORIZED') throw err;
        setHandoverNotes([]);
        setHandoverAvailable(false);
      }));
    }

    await Promise.all(tasks);
    setSyncedAt(new Date().toLocaleTimeString(lang === 'vi' ? 'vi-VN' : 'en-US'));
  }, [accountRequestsAvailable, handoverAvailable, lang]);

  useEffect(() => {
    if (!token) return;
    let active = true;
    const tick = async () => {
      try {
        await refresh(token, user, {
          activeTab: tab,
          entityFilter: auditFilter,
          activeAlertFilter: alertFilter,
          activeAlertPage: alertPage,
          activeTicketPage: ticketPage,
          activeAuditPage: auditPage,
          thresholdsOpen: showThresholds,
        });
        if (active) setChecks(previous => ({ ...previous, [tab]: { time: Date.now(), failed: false } }));
      } catch (err) {
        if (!active) return;
        if (err instanceof Error && err.message === 'UNAUTHORIZED') {
          try { window.sessionStorage.removeItem(SESSION_STORAGE_KEY); } catch { /* ignore */ }
          setToken('');
          setUser(null);
          setChecks({});
          setError(t.sessionExpired);
          return;
        }
        setChecks(previous => ({ ...previous, [tab]: { time: previous[tab]?.time, failed: true } }));
      }
    };
    void tick();
    const timer = window.setInterval(() => void tick(), 5000);
    return () => { active = false; window.clearInterval(timer); };
  }, [token, user, tab, showThresholds, auditFilter, alertFilter, alertPage, ticketPage, auditPage, refresh, t.sessionExpired]);

  useEffect(() => {
    if (!token) {
      setSseConnected(false);
      return;
    }
    const es = new EventSource(`/api/stream?token=${encodeURIComponent(token)}`);
    let firstMessage = true;
    let debounceTimer: number | undefined;
    es.onopen = () => setSseConnected(true);
    es.onmessage = () => {
      setSseConnected(true);
      if (firstMessage) {
        firstMessage = false;
        return;
      }
      if (debounceTimer !== undefined) window.clearTimeout(debounceTimer);
      debounceTimer = window.setTimeout(() => {
        debounceTimer = undefined;
        void refresh(token, user, refreshOptsRef.current).catch(() => undefined);
      }, 1500);
    };
    es.onerror = () => setSseConnected(false);
    return () => {
      if (debounceTimer !== undefined) window.clearTimeout(debounceTimer);
      es.close();
      setSseConnected(false);
    };
  }, [token, user, refresh]);

  useEffect(() => {
    if (!token || inspectedNodeId == null) return;
    let active = true;
    fetch(apiUrl(`/api/telemetry/history?node_id=${inspectedNodeId}&metric_type=${encodeURIComponent(inspectMetric)}&limit=30`), {
      headers: { Authorization: `Bearer ${token}` },
      cache: 'no-store',
    })
      .then(r => (r.ok ? r.json() : []))
      .then(data => { if (active && Array.isArray(data)) setInspectHistory(data); })
      .catch(() => undefined);
    return () => { active = false; };
  }, [token, inspectedNodeId, inspectMetric, syncedAt]);

  async function login(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError('');
    try {
      const response = await fetch(apiUrl('/api/auth/login'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password, ...(otp ? { otp } : {}) }),
      });
      const data = await response.json();
      if (!response.ok) {
        if (data.error === 'mfa_required') { setMfaRequired(true); throw new Error(t.mfaRequired); }
        throw new Error(data.error || t.loginFailed);
      }
      const nextUser = (data.user ?? null) as SessionUser | null;
      setToken(data.access_token);
      setUser(nextUser);
      setPassword('');
      setOtp(''); setMfaRequired(false);
      try {
        window.sessionStorage.setItem(
          SESSION_STORAGE_KEY,
          JSON.stringify({ token: data.access_token, user: nextUser }),
        );
      } catch { /* ignore storage restrictions */ }
    } catch (e) {
      setError(e instanceof Error ? e.message : t.loginFailed);
    } finally {
      setLoading(false);
    }
  }

  async function resetPassword(event: FormEvent) {
    event.preventDefault(); setLoading(true); setError('');
    try {
      const response = await fetch(apiUrl('/api/auth/reset-password'), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: recoveryCode.trim(), password: newPassword }) });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || t.passwordResetFailed);
      setNotice(t.passwordResetDone); setAuthView('login'); setRecoveryCode(''); setNewPassword('');
    } catch (e) { setError(e instanceof Error ? e.message : t.passwordResetFailed); }
    finally { setLoading(false); }
  }

  async function requestAccess(event: FormEvent) {
    event.preventDefault(); setLoading(true); setError('');
    try {
      const response = await fetch(apiUrl('/api/auth/request-access'), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(requestForm) });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || t.accountRequestFailed);
      setNotice(t.accountRequestDone); setAuthView('login'); setRequestForm({ username: '', email: '', full_name: '', requested_role: 'FIELD_TECHNICIAN', note: '' });
    } catch (e) { setError(e instanceof Error ? e.message : t.accountRequestFailed); }
    finally { setLoading(false); }
  }

  async function changePassword(event: FormEvent) {
    event.preventDefault(); setLoading(true); setError(''); setNotice('');
    try {
      const response = await fetch(apiUrl('/api/auth/change-password'), { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }) });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || t.passwordChangeFailed);
      setNotice(t.passwordChangeDone); setAccountOpen(false); setCurrentPassword(''); setNewPassword('');
    } catch (e) { setError(e instanceof Error ? e.message : t.passwordChangeFailed); }
    finally { setLoading(false); }
  }

  async function revokeOtherSessions() {
    const response = await fetch(apiUrl('/api/auth/sessions/revoke-others'), { method: 'POST', headers: { Authorization: `Bearer ${token}` } });
    if (!response.ok) { setError(t.sessionActionFailed); return; }
    setNotice(t.sessionsRevoked);
  }

  async function beginMfaSetup() {
    const response = await fetch(apiUrl('/api/auth/mfa/setup'), { method: 'POST', headers: { Authorization: `Bearer ${token}` } });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) { setError(data.error || t.mfaSetupFailed); return; }
    setMfaSecret(data.secret || ''); setMfaCode('');
  }

  async function enableMfa() {
    const response = await fetch(apiUrl('/api/auth/mfa/enable'), { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ code: mfaCode }) });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) { setError(data.error || t.mfaSetupFailed); return; }
    setMfaBackupCodes(data.backup_codes || []); setMfaSecret(''); setMfaCode(''); setNotice(t.mfaEnabled);
  }

  async function submitAction(key: string, url: string, method: 'POST' | 'PATCH' | 'PUT', body?: Record<string, unknown>) {
    setPending(key);
    setError('');
    setNotice('');
    try {
      const response = await fetch(apiUrl(url), {
        method,
        headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
      try {
        await refresh(token, user, refreshOptsRef.current);
      } catch (refreshError) {
        if (refreshError instanceof Error && refreshError.message === 'UNAUTHORIZED') {
          setChecks(previous => ({ ...previous, [tab]: { time: previous[tab]?.time, failed: true } }));
          setError(t.sessionExpired);
        } else {
          setChecks(previous => ({ ...previous, [tab]: { time: previous[tab]?.time, failed: true } }));
          setError(t.loadError);
        }
      }
      return result as Record<string, unknown>;
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Request failed.';
      setError(message);
      throw e;
    } finally {
      setPending('');
    }
  }

  function selectInspectNode(node: NodeRow) {
    if (inspectedNodeId === node.id) {
      setInspectedNodeId(null);
      return;
    }
    setInspectedNodeId(node.id);
    setEditNodeRackId(String(node.rack_id ?? racks[0]?.id ?? 1));
    setEditNodeName(node.name);
    setEditNodeHost(node.hostname ?? '');
    setEditNodeIp(node.ip_address ?? '');
    setEditNodeMac(node.mac_address ?? '');
    setEditNodeU(String(node.rack_position_u ?? 1));
    setEditNodePower(String(node.power_consumption_watts ?? 150));
    setEditNodeStatus(node.status);
  }

  async function saveInfrastructure(event: FormEvent) {
    event.preventDefault();
    try {
      await submitAction('save-infra', '/api/hierarchy', 'POST', {
        entity_type: infraType,
        ...(infraType !== 'SITE' ? { parent_id: Number(infraParentId) } : {}),
        name: infraName.trim(),
        code: infraCode.trim(),
        ...(infraExtra.trim() ? { extra_text: infraExtra.trim() } : {}),
        ...(infraType === 'RACK' ? { unit_capacity: Number(infraUnits), power_capacity_watts: Number(infraPowerCap) } : {}),
      });
      setInfraName('');
      setInfraCode('');
      setInfraExtra('');
      setShowInfraForm(false);
      setNotice(`${infraType} saved.`);
    } catch { /* shown */ }
  }

  async function updateInspectedNode(event: FormEvent) {
    event.preventDefault();
    if (inspectedNodeId == null) return;
    try {
      await submitAction(`update-node-${inspectedNodeId}`, `/api/nodes/${inspectedNodeId}`, 'PUT', {
        rack_id: Number(editNodeRackId),
        name: editNodeName.trim(),
        hostname: editNodeHost.trim(),
        ip_address: editNodeIp.trim(),
        ...(editNodeMac.trim() ? { mac_address: editNodeMac.trim() } : {}),
        rack_position_u: Number(editNodeU),
        power_consumption_watts: Number(editNodePower),
        status: editNodeStatus,
      });
      setNotice(`Node #${inspectedNodeId} updated.`);
    } catch { /* shown */ }
  }

  async function updateAlertStatus(alertId: number, status: 'ACKNOWLEDGED' | 'RESOLVED' | 'CLOSED') {
    try {
      await submitAction(`alert-${alertId}`, `/api/alerts/${alertId}/status`, 'PATCH', { status });
      setNotice(`Alert #${alertId} → ${status}.`);
    } catch { /* shown */ }
  }

  async function markNotificationRead(notificationId?: number) {
    try {
      await submitAction('notif-read', '/api/notifications/read', 'POST', notificationId ? { notification_id: notificationId } : {});
      setNotifications(current => current.map(item => notificationId == null || item.id === notificationId ? { ...item, is_read: true } : item));
    } catch { /* Mutation error is shown in the dashboard. */ }
  }

  async function acknowledgeAlert(alert: AlertRow) {
    try {
      await submitAction(`alert-${alert.id}`, `/api/alerts/${alert.id}/ack`, 'POST');
      setNotice(`Alert #${alert.id} acknowledged.`);
    } catch { /* shown in error banner */ }
  }

  async function createTicket(event: FormEvent) {
    event.preventDefault();
    const nodeId = Number(formNodeId);
    if (!Number.isInteger(nodeId) || nodeId <= 0 || !formTitle.trim() || formTitle.trim().length > 200) {
      setError('Invalid node or title.');
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
      setNotice(`Ticket #${String(result.id)} created.`);
      setFormTitle('');
      setFormDescription('');
      setFormAlertId('');
      setShowTicketForm(false);
    } catch { /* shown */ }
  }

  async function registerNode(event: FormEvent) {
    event.preventDefault();
    try {
      const result = await submitAction('register-node', '/api/nodes', 'POST', {
        rack_id: Number(obRackId),
        name: obName.trim(),
        hostname: obHostname.trim(),
        ip_address: obIp.trim(),
        ...(obMac.trim() ? { mac_address: obMac.trim() } : {}),
        rack_position_u: Number(obU),
        power_consumption_watts: Number(obPower),
        ...(obMarker.trim() ? { marker_code: obMarker.trim() } : {}),
      });
      setIssuedApiKey(String(result.api_key ?? ''));
      setCopiedKey(false);
      setObName('');
      setObHostname('');
      setObIp('');
      setObMac('');
      setObMarker('');
      setShowOnboardForm(false);
      setNotice(`Node #${String(result.id)} registered.`);
    } catch { /* shown */ }
  }

  async function restartContainer(containerDbId: number, skipConfirm = false) {
    if (!skipConfirm && !window.confirm(t.twin.confirmRestart)) return;
    await submitAction(`container-${containerDbId}`, `/api/containers/${containerDbId}/restart`, 'POST');
    setNotice(`Container #${containerDbId} restarted.`);
  }

  async function saveMarker(event: FormEvent) {
    event.preventDefault();
    if (inspectedNodeId == null || !markerCodeInput.trim()) return;
    await submitAction('save-marker', '/api/markers', 'POST', {
      node_id: inspectedNodeId,
      marker_type: markerTypeInput,
      marker_code: markerCodeInput.trim(),
    });
    setMarkerCodeInput('');
    setNotice('Marker updated.');
  }

  async function saveThreshold(th: ThresholdRow) {
    const draft = thresholdDrafts[th.metric_type_id] ?? {
      warning: String(th.warning_threshold),
      critical: String(th.critical_threshold),
      duration: String(th.duration_seconds),
      active: Boolean(th.is_active),
    };
    await submitAction(`threshold-${th.metric_type_id}`, `/api/thresholds/${th.metric_type_id}`, 'PUT', {
      warning_threshold: Number(draft.warning),
      critical_threshold: Number(draft.critical),
      duration_seconds: Number(draft.duration),
      is_active: draft.active,
    });
    setNotice(`Threshold ${th.metric_code} updated.`);
  }

  async function loadNotes(ticketId: number) {
    if (openNotesTicketId === ticketId) {
      setOpenNotesTicketId(null);
      return;
    }
    setOpenNotesTicketId(ticketId);
    const res = await fetch(apiUrl(`/api/tickets/${ticketId}/notes`), {
      headers: { Authorization: `Bearer ${token}` },
      cache: 'no-store',
    });
    if (res.ok) setTicketNotes(await res.json());
  }

  async function addTicketNote(ticketId: number, noteText: string) {
    await submitAction(`note-${ticketId}`, `/api/tickets/${ticketId}/notes`, 'POST', { note_text: noteText });
    const res = await fetch(apiUrl(`/api/tickets/${ticketId}/notes`), {
      headers: { Authorization: `Bearer ${token}` },
      cache: 'no-store',
    });
    if (res.ok) setTicketNotes(await res.json());
    setNewNoteText('');
    setNotice(`Note added to ticket #${ticketId}.`);
  }

  async function assignTicket(ticketId: number) {
    const chosen = Number(assignDrafts[ticketId] || technicians[0]?.id);
    if (!chosen) return;
    await submitAction(`assign-${ticketId}`, `/api/tickets/${ticketId}/assign`, 'PATCH', {
      assigned_to_user_id: chosen,
    });
    setNotice(`Ticket #${ticketId} assigned.`);
  }

  async function startWork(ticketId: number) {
    await submitAction(`ticket-${ticketId}`, `/api/tickets/${ticketId}/status`, 'PATCH', { status: 'IN_PROGRESS' });
    setNotice(`Ticket #${ticketId} → IN_PROGRESS.`);
  }

  async function submitClosure(ticketId: number, summaryText: string, detailsText: string, mtype: string) {
    await submitAction(`closure-${ticketId}`, `/api/tickets/${ticketId}/closure-request`, 'POST', {
      summary: summaryText,
      resolution_details: detailsText,
      maintenance_type: mtype,
    });
    setClosureTicketId(null);
    setClosureSummary('');
    setClosureDetails('');
    setNotice(`Closure request submitted for ticket #${ticketId}.`);
  }

  async function reviewClosure(ticketId: number, decision: 'APPROVED' | 'REJECTED') {
    if (decision === 'APPROVED' && !window.confirm(t.tickets.confirmClose)) return;
    await submitAction(`review-${ticketId}`, `/api/tickets/${ticketId}/closure-review`, 'POST', { decision });
    setNotice(`Ticket #${ticketId} ${decision}.`);
  }

  function startTicketFromAlert(alert: AlertRow) {
    setFormNodeId(String(alert.node_id));
    setFormTitle(`${alert.alert_type} · ${alert.node_name}`.slice(0, 200));
    setFormDescription(alert.message);
    setFormPriority(alert.severity === 'CRITICAL' ? 'CRITICAL' : alert.severity === 'WARNING' ? 'HIGH' : 'MEDIUM');
    setFormAlertId(String(alert.id));
    if (showTicketForm) ticketTitleRef.current?.focus();
    else focusTicketTitle.current = true;
    setShowTicketForm(true);
    setError('');
    setNotice('');
  }

  async function logout() {
    try { await fetch(apiUrl('/api/auth/logout'), { method: 'POST', headers: { Authorization: `Bearer ${token}` } }); } catch { /* Clear local credentials when offline too. */ }
    try { window.sessionStorage.removeItem(SESSION_STORAGE_KEY); } catch { /* ignore */ }
    setToken('');
    setUser(null);
    setNodes([]);
    setAlerts([]);
    setTickets([]);
    setAlertPage(0);
    setAlertHasNext(false);
    setTicketPage(0);
    setTicketHasNext(false);
    setAuditPage(0);
    setAuditHasNext(false);
    setNotifications([]);
    setShowNotifs(false);
    setCollectors([]);
    setAccountRequests([]);
    setAccountRequestsAvailable(true);
    setHandoverNotes([]);
    setHandoverAvailable(true);
    setSelectedRoomId(null);
    setSelectedRackId(null);
    setInspectedNodeId(null);
    setError('');
    setNotice('');
    setSyncedAt('');
    setChecks({});
    setIssuedApiKey('');
    setTab('overview');
  }

  if (!token) {
    return (
      <main className="login-wrap">
        <div className="login-language">
          <LanguageSwitch lang={lang} onSwitch={switchLanguage} />
        </div>
        <div className="login-body">
          <h1 id="login-heading">{authView === 'login' ? t.loginTitle : authView === 'forgot' ? t.forgotPassword : t.requestAccount}</h1>
          <p>{authView === 'login' ? t.loginSubtitle : authView === 'forgot' ? t.forgotPasswordHelp : t.requestAccountHelp}</p>
          {authView === 'login' && (
            <form className="login-card" aria-labelledby="login-heading" onSubmit={login}>
              <label>{t.username}<input autoComplete="username" value={username} onChange={e => setUsername(e.target.value)} required /></label>
              <label>{t.password}<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
              {mfaRequired && (
                <label>
                  {t.mfaCode}
                  <input inputMode="numeric" autoComplete="one-time-code" value={otp} onChange={e => setOtp(e.target.value)} placeholder={t.mfaCodeHelp} required />
                </label>
              )}
              {error && <div className="error" role="alert">{error}</div>}
              <button disabled={loading}>{loading ? t.signingIn : t.continueBtn}</button>
              <div className="auth-links">
                <button type="button" className="text-button" onClick={() => { setAuthView('forgot'); setError(''); }}>
                  {t.forgotPassword}
                </button>
                <button type="button" className="text-button" onClick={() => { setAuthView('request'); setError(''); }}>
                  {t.requestAccount}
                </button>
              </div>
            </form>
          )}
          {authView === 'forgot' && (
            <form className="login-card" onSubmit={resetPassword}>
              <label>{t.recoveryCode}<input value={recoveryCode} onChange={e => setRecoveryCode(e.target.value)} placeholder={t.recoveryCodePlaceholder} required /></label>
              <label>{t.newPassword}<input type="password" minLength={12} value={newPassword} onChange={e => setNewPassword(e.target.value)} required /></label>
              {error && <div className="error" role="alert">{error}</div>}
              <button disabled={loading}>{loading ? t.saving : t.resetPassword}</button>
              <button type="button" className="text-button" onClick={() => setAuthView('login')}>{t.backToLogin}</button>
            </form>
          )}
          {authView === 'request' && (
            <form className="login-card" onSubmit={requestAccess}>
              <label>{t.username}<input value={requestForm.username} onChange={e => setRequestForm({ ...requestForm, username: e.target.value })} required /></label>
              <label>{t.admin.email}<input type="email" value={requestForm.email} onChange={e => setRequestForm({ ...requestForm, email: e.target.value })} required /></label>
              <label>{t.admin.fullName}<input value={requestForm.full_name} onChange={e => setRequestForm({ ...requestForm, full_name: e.target.value })} required /></label>
              <label>
                {t.admin.role}
                <select value={requestForm.requested_role} onChange={e => setRequestForm({ ...requestForm, requested_role: e.target.value })}>
                  <option value="FIELD_TECHNICIAN">{t.roles.FIELD_TECHNICIAN}</option>
                  <option value="SYSTEM_OPERATOR">{t.roles.SYSTEM_OPERATOR}</option>
                </select>
              </label>
              <label>{t.requestNote}<textarea rows={3} value={requestForm.note} onChange={e => setRequestForm({ ...requestForm, note: e.target.value })} /></label>
              {error && <div className="error" role="alert">{error}</div>}
              <button disabled={loading}>{loading ? t.saving : t.submitRequest}</button>
              <button type="button" className="text-button" onClick={() => setAuthView('login')}>{t.backToLogin}</button>
            </form>
          )}
        </div>
      </main>
    );
  }

  const online = nodes.filter(n => n.status === 'ONLINE').length;
  const attention = nodes.filter(n => ['WARNING', 'CRITICAL', 'UNAVAILABLE'].includes(n.status)).length;
  const displayName = user?.full_name || user?.username || 'Session';
  const canWrite = WRITE_ROLES.has(user?.role ?? '');
  const isAdmin = user?.role === 'ADMINISTRATOR';
  const initials = displayName.trim().split(/\s+/).slice(-2).map(part => part[0]).join('').toUpperCase();
  const openTickets = tickets.filter(item => item.status !== 'CLOSED');
  const myWorkTickets = openTickets.filter(
    item =>
      item.assigned_to_user_id === user?.id
      || item.assigned_to_username === user?.username
      || (canWrite && !item.assigned_to_user_id)
      || (canWrite && item.closure_status === 'PENDING'),
  );

  const uniqueRooms = sitesRooms.filter(
    (sr, idx, arr) => sr.room_id != null && arr.findIndex(x => x.room_id === sr.room_id) === idx,
  );
  const uniqueSites = sitesRooms.filter(
    (sr, idx, arr) => arr.findIndex(x => x.site_id === sr.site_id) === idx,
  );
  const filteredRacks = selectedRoomId == null ? racks : racks.filter(rk => rk.room_id === selectedRoomId);
  const chassisRacks = selectedRackId != null ? racks.filter(rk => rk.id === selectedRackId) : filteredRacks;
  const visibleNodes = nodes.filter(n => {
    if (selectedRackId != null) return n.rack_id === selectedRackId;
    if (selectedRoomId != null) return n.room_id === selectedRoomId;
    return true;
  });
  const inspectedNode = nodes.find(n => n.id === inspectedNodeId) ?? null;
  const inspectedContainers = inspectedNode ? containers.filter(c => c.node_id === inspectedNode.id) : [];
  const unreadCount = notifications.filter(n => !n.is_read).length;
  const check = checks[tab];
  const showData = Boolean(check?.time);
  const syncLabel = check?.failed ? (showData ? t.stale : t.unavailable)
    : !showData ? t.connecting : sseConnected ? t.live : t.periodicSync;

  function renderModules() {
    return (
      <nav className="nav-tabs" aria-label={t.modules}>
        {MODULES.filter(({ key }) => key !== 'admin' || isAdmin).map(({ key, icon: Icon }) => (
          <button key={key} type="button" aria-current={tab === key ? 'page' : undefined} className={`nav-tab ${tab === key ? 'active' : ''}`} onClick={() => {
            setTab(key);
            mobileMenu.current?.close();
          }}>
            <Icon aria-hidden="true" />
            <span>{t.tabs[key]}</span>
          </button>
        ))}
      </nav>
    );
  }

  return (
    <main className="shell">
      <aside className="module-sidebar">
        <div className="sidebar-brand brand">
          <div className="brand-mark"><IconServer /></div>
          <strong>AR-IMMS</strong>
        </div>
        {renderModules()}
        <div className="sidebar-language"><LanguageSwitch lang={lang} onSwitch={switchLanguage} /></div>
        <button type="button" className="sidebar-logout" onClick={logout}><LogOut aria-hidden="true" />{t.signOut}</button>
      </aside>
      <header className="topbar">
        <div className="toolbar-title">
          <button type="button" className="secondary mobile-menu-button" aria-label={t.modules} title={t.modules} aria-haspopup="dialog" onClick={() => mobileMenu.current?.showModal()}><Menu aria-hidden="true" /></button>
          <strong>{t.tabs[tab]}</strong>
        </div>
        <div className="topbar-actions">
          <div className="notif-wrap" onKeyDown={e => {
            if (e.key === 'Escape' && showNotifs) {
              setShowNotifs(false);
              notificationButton.current?.focus();
            }
          }}>
            <button
              ref={notificationButton}
              type="button"
              className="secondary notif-btn"
              onClick={() => setShowNotifs(v => !v)}
              aria-label={t.notifications}
              aria-expanded={showNotifs}
            >
              <Bell aria-hidden="true" />
              {unreadCount > 0 && <span className="notif-badge">{unreadCount}</span>}
            </button>
            {showNotifs && (
              <div className="notif-popover">
                <div className="notif-head">
                  <strong>{t.notifications}</strong>
                  {unreadCount > 0 && (
                    <button type="button" className="compact-action secondary" onClick={() => void markNotificationRead()}>
                      {t.markAllRead}
                    </button>
                  )}
                </div>
                <div className="notif-list">
                  {notifications.map(n => (
                    <button
                      key={n.id}
                      type="button"
                      className={`notif-item ${n.is_read ? 'read' : 'unread'}`}
                      onClick={() => { if (!n.is_read) void markNotificationRead(n.id); }}
                    >
                      <strong>{n.title}</strong>
                      <span className="notif-message">{n.message}</span>
                      <span>{formatWhen(n.created_at, lang)}</span>
                    </button>
                  ))}
                  {!notifications.length && <div className="empty">{t.noNotifications}</div>}
                </div>
              </div>
            )}
          </div>
          <button
            type="button"
            className="user"
            onClick={() => setAccountOpen(v => !v)}
            aria-expanded={accountOpen}
            title={t.account}
          >
            <span className="avatar">{initials || 'AR'}</span>
            <span className="user-meta">
              <span className="user-name">{displayName}</span>
              <span className="user-role">{user ? (t.roles[user.role] ?? user.role) : '—'}</span>
            </span>
          </button>
        </div>
      </header>

      <dialog ref={mobileMenu} className="module-drawer" aria-label={t.modules} onClick={e => {
        if (e.target !== e.currentTarget) return;
        const bounds = e.currentTarget.getBoundingClientRect();
        if (e.clientX < bounds.left || e.clientX > bounds.right || e.clientY < bounds.top || e.clientY > bounds.bottom) e.currentTarget.close();
      }}>
        <div className="sidebar-brand brand">
          <div className="brand-mark"><IconServer /></div>
          <strong>AR-IMMS</strong>
          <button type="button" className="secondary drawer-close" aria-label={t.closeMenu} title={t.closeMenu} onClick={() => mobileMenu.current?.close()}><X aria-hidden="true" /></button>
        </div>
        {renderModules()}
        <div className="sidebar-language"><LanguageSwitch lang={lang} onSwitch={switchLanguage} /></div>
        <button type="button" className="sidebar-logout" onClick={() => { mobileMenu.current?.close(); logout(); }}><LogOut aria-hidden="true" />{t.signOut}</button>
      </dialog>

      <div className="workspace-content">
      <div className="workspace-heading">
        <h1>{t.tabs[tab]}</h1>
        <div className="sync-bar">
          <span className="live" role="status">
            <span aria-hidden="true" className={`live-dot ${check?.failed ? 'live-dot-warn' : !showData || !sseConnected ? 'live-dot-muted' : ''}`} />
            {syncLabel}
          </span>
          {check?.time != null && <span>{t.lastSync}: <time dateTime={new Date(check.time).toISOString()}>{new Date(check.time).toLocaleTimeString(lang === 'vi' ? 'vi-VN' : 'en-US')}</time></span>}
        </div>
      </div>

      {error && <div className="error banner" role="alert">{error}</div>}
      {check?.failed && <div className="notice-muted">{showData ? t.staleDetail : t.loadError}</div>}
      {notice && <div className="notice banner" role="status">{notice}</div>}
      {accountOpen && (
        <section className="account-panel panel">
          <div className="section-head">
            <div>
              <h2>{t.account}</h2>
              <p className="section-sub">{displayName} · {user ? (t.roles[user.role] ?? user.role) : ''}</p>
            </div>
            <button type="button" className="compact-action secondary" onClick={() => setAccountOpen(false)}>
              {t.close}
            </button>
          </div>
          <form className="ticket-form" onSubmit={changePassword}>
            <label>
              {t.currentPassword}
              <input type="password" minLength={12} value={currentPassword} onChange={e => setCurrentPassword(e.target.value)} required />
            </label>
            <label>
              {t.newPassword}
              <input type="password" minLength={12} value={newPassword} onChange={e => setNewPassword(e.target.value)} required />
            </label>
            <div className="ticket-form-footer">
              <button disabled={loading}>{loading ? t.saving : t.changePassword}</button>
              <button type="button" className="secondary" onClick={() => void revokeOtherSessions()}>
                {t.revokeOtherSessions}
              </button>
            </div>
          </form>
          {isAdmin && (
            <div className="account-security">
              <h3>{t.mfaTitle}</h3>
              {!mfaSecret && !mfaBackupCodes.length && (
                <button type="button" className="secondary compact-action" onClick={() => void beginMfaSetup()}>
                  {t.enableMfa}
                </button>
              )}
              {mfaSecret && (
                <div>
                  <p>{t.mfaSecret}: <code>{mfaSecret}</code></p>
                  <input inputMode="numeric" placeholder={t.mfaCodeHelp} value={mfaCode} onChange={e => setMfaCode(e.target.value)} />
                  <button type="button" className="compact-action" onClick={() => void enableMfa()}>
                    {t.confirmMfa}
                  </button>
                </div>
              )}
              {mfaBackupCodes.length > 0 && (
                <p>{t.mfaBackupCodes}: <code>{mfaBackupCodes.join(' · ')}</code></p>
              )}
            </div>
          )}
        </section>
      )}
      {issuedApiKey && (
        <div className="notice banner key-banner" role="status">
          <span>{t.twin.issuedKeyNotice} <code>{issuedApiKey}</code></span>
          <div className="ticket-actions-wrap">
            <button
              type="button"
              className="compact-action"
              onClick={() => {
                void navigator.clipboard?.writeText(issuedApiKey);
                setCopiedKey(true);
              }}
            >
              {copiedKey ? t.twin.copied : t.twin.copyKey}
            </button>
            <button
              type="button"
              className="compact-action secondary"
              onClick={() => {
                setIssuedApiKey('');
                setCopiedKey(false);
              }}
            >
              {t.close}
            </button>
          </div>
        </div>
      )}

      {tab !== 'ar' && !showData && !check?.failed && <p className="panel data-loading">{t.loadingData}</p>}

      {tab === 'overview' && showData && <section className="metrics metrics-6" aria-label={t.tabs.overview}>
        <article className="metric">
          <div className="metric-head"><span className="metric-icon"><IconServer /></span><span className="metric-label">{t.kpi.totalNodes}</span></div>
          <strong className="metric-value">{nodes.length}</strong>
          <span className="metric-foot">{t.kpi.totalNodesFoot}</span>
        </article>
        <article className="metric">
          <div className="metric-head"><span className="metric-icon tone-green"><IconPulse /></span><span className="metric-label">{t.kpi.online}</span></div>
          <strong className="metric-value tone-green">{online}</strong>
          <span className="metric-foot">{nodes.length ? `${Math.round((online / nodes.length) * 100)}% ${t.kpi.ofNodes}` : t.kpi.noData}</span>
        </article>
        <article className="metric">
          <div className="metric-head"><span className="metric-icon tone-orange"><IconWarning /></span><span className="metric-label">{t.kpi.attention}</span></div>
          <strong className={`metric-value ${attention ? 'tone-red' : ''}`}>{attention}</strong>
          <span className="metric-foot">{t.kpi.attentionFoot}</span>
        </article>
        <article className="metric">
          <div className="metric-head"><span className="metric-icon tone-red"><IconBell /></span><span className="metric-label">{t.kpi.openAlerts}</span></div>
          <strong className="metric-value">{summary?.open_alerts ?? '—'}</strong>
          <span className="metric-foot">{t.kpi.openAlertsFoot}</span>
        </article>
        <article className="metric">
          <div className="metric-head"><span className="metric-icon tone-teal"><IconBolt /></span><span className="metric-label">{t.kpi.pue}</span></div>
          <strong className="metric-value tone-teal">{summary ? summary.current_pue.toFixed(2) : '—'}</strong>
          <span className="metric-foot">{summary ? `${t.kpi.itWatts}: ${summary.it_power_watts.toFixed(0)}W` : t.kpi.noData}</span>
        </article>
        <article className="metric">
          <div className="metric-head"><span className="metric-icon"><IconClock /></span><span className="metric-label">{t.kpi.mttr}</span></div>
          <strong className="metric-value">{summary ? summary.avg_mttr_minutes.toFixed(0) : '—'}</strong>
          <span className="metric-foot">{t.kpi.minutes}</span>
        </article>
      </section>}

      {tab === 'overview' && showData && (
        <>
          <section className="panel incident-panel">
            <div className="section-head">
              <h2>{t.alerts.title}</h2>
              <div className="ticket-heading-actions">
                <button type="button" className="compact-action secondary" aria-expanded={showThresholds} onClick={() => setShowThresholds(v => !v)}>
                  {showThresholds ? t.alerts.hideThresholds : t.alerts.thresholdsBtn}
                </button>
              </div>
            </div>
            <div className="list-toolbar">
              <div className="filter-segments" role="group" aria-label={t.alerts.filterLabel}>
                {ALERT_FILTERS.map(([value, label]) => (
                  <button key={value} type="button" aria-pressed={alertFilter === value} onClick={() => {
                    if (alertFilter !== value) { setAlertFilter(value); setAlertPage(0); }
                  }}>{t.alerts[label]}</button>
                ))}
              </div>
              <span className="list-count">{alerts.length ? `${alerts.length} ${t.alerts.events}` : t.alerts.noEvents}</span>
            </div>

            {showThresholds && (
              <div className="table-wrap threshold-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>{t.alerts.metric}</th>
                      <th>{t.alerts.warning}</th>
                      <th>{t.alerts.critical}</th>
                      <th>{t.alerts.durationSec}</th>
                      <th>{t.alerts.active}</th>
                      {canWrite && <th />}
                    </tr>
                  </thead>
                  <tbody>
                    {thresholds.map(th => {
                      const draft = thresholdDrafts[th.metric_type_id] ?? {
                        warning: String(th.warning_threshold),
                        critical: String(th.critical_threshold),
                        duration: String(th.duration_seconds),
                        active: Boolean(th.is_active),
                      };
                      const updateDraft = (patch: Partial<typeof draft>) =>
                        setThresholdDrafts(prev => ({ ...prev, [th.metric_type_id]: { ...draft, ...patch } }));
                      return (
                        <tr key={th.metric_type_id}>
                          <td><strong>{th.metric_code}</strong> <span className="cell-muted">({th.unit})</span></td>
                          <td>
                            <input
                              type="number"
                              step="0.5"
                              className="mini-input"
                              disabled={!canWrite}
                              value={draft.warning}
                              onChange={e => updateDraft({ warning: e.target.value })}
                            />
                          </td>
                          <td>
                            <input
                              type="number"
                              step="0.5"
                              className="mini-input"
                              disabled={!canWrite}
                              value={draft.critical}
                              onChange={e => updateDraft({ critical: e.target.value })}
                            />
                          </td>
                          <td>
                            <input
                              type="number"
                              min={1}
                              className="mini-input"
                              disabled={!canWrite}
                              value={draft.duration}
                              onChange={e => updateDraft({ duration: e.target.value })}
                            />
                          </td>
                          <td>
                            <input
                              type="checkbox"
                              disabled={!canWrite}
                              checked={draft.active}
                              onChange={e => updateDraft({ active: e.target.checked })}
                            />
                          </td>
                          {canWrite && (
                            <td>
                              <button
                                type="button"
                                className="compact-action"
                                disabled={pending === `threshold-${th.metric_type_id}`}
                                onClick={() => void saveThreshold(th)}
                              >
                                {t.alerts.saveThreshold}
                              </button>
                            </td>
                          )}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            <div className="alert-list">
              {alerts.map(alert => (
                <article key={alert.id} className="alert-row">
                  <span className={`severity severity-${alert.severity.toLowerCase()}`}>{alert.severity}</span>
                  <div>
                    <strong>{alert.node_name} · {alert.alert_type} · <span className="cell-muted">[{alert.status}]</span></strong>
                    <p>{alert.message}</p>
                  </div>
                  <div className="alert-actions">
                    <time>{formatWhen(alert.triggered_at, lang)}</time>
                    <div className="alert-actions-buttons">
                      {canWrite && alert.status === 'OPEN' && (
                        <button className="compact-action" disabled={pending === `alert-${alert.id}`} onClick={() => void acknowledgeAlert(alert)}>
                          {pending === `alert-${alert.id}` ? t.alerts.saving : t.alerts.acknowledge}
                        </button>
                      )}
                      {canWrite && (alert.status === 'OPEN' || alert.status === 'ACKNOWLEDGED') && (
                        <button className="compact-action secondary" disabled={pending === `alert-${alert.id}`} onClick={() => void updateAlertStatus(alert.id, 'RESOLVED')}>
                          {t.alerts.resolve}
                        </button>
                      )}
                      {canWrite && alert.status !== 'CLOSED' && (
                        <button className="compact-action secondary" disabled={pending === `alert-${alert.id}`} onClick={() => void updateAlertStatus(alert.id, 'CLOSED')}>
                          {t.alerts.closeAlert}
                        </button>
                      )}
                      {canWrite && (
                        <button className="compact-action secondary" disabled={pending !== ''} onClick={() => startTicketFromAlert(alert)}>
                          {t.alerts.createTicket}
                        </button>
                      )}
                    </div>
                  </div>
                </article>
              ))}
              {!alerts.length && <div className="empty">{t.alerts.noAlerts}</div>}
            </div>
            <div className="pager-bar">
              <button type="button" className="compact-action secondary" disabled={alertPage === 0} onClick={() => setAlertPage(p => Math.max(0, p - 1))}>{t.prevPage}</button>
              <span>{t.pageLabel} {alertPage + 1}</span>
              <button type="button" className="compact-action secondary" disabled={!alertHasNext} onClick={() => setAlertPage(p => p + 1)}>{t.nextPage}</button>
            </div>
          </section>

          <section className="panel ticket-panel">
            <div className="section-head">
              <h2>{t.tickets.title}</h2>
              <div className="ticket-heading-actions">
                <span className="refresh-label">{tickets.length}</span>
                {canWrite && (
                  <button className="compact-action" onClick={() => { setShowTicketForm(v => !v); setError(''); setNotice(''); }}>
                    {showTicketForm ? t.tickets.closeForm : t.tickets.newTicket}
                  </button>
                )}
              </div>
            </div>

            {showTicketForm && canWrite && (
              <form className="ticket-form" onSubmit={createTicket}>
                <label>{t.tickets.node}
                  <select value={formNodeId} onChange={e => setFormNodeId(e.target.value)} required>
                    <option value="">{t.tickets.selectNode}</option>
                    {nodes.map(node => <option key={node.id} value={node.id}>{node.name} · #{node.id}</option>)}
                  </select>
                </label>
                <label>{t.tickets.titleField}<input ref={ticketTitleRef} value={formTitle} maxLength={200} onChange={e => setFormTitle(e.target.value)} required /></label>
                <label>{t.tickets.priority}
                  <select value={formPriority} onChange={e => setFormPriority(e.target.value)}>
                    {PRIORITIES.map(p => <option key={p} value={p}>{t.priorities[p] ?? p}</option>)}
                  </select>
                </label>
                <label className="ticket-description">{t.tickets.description}
                  <textarea rows={3} value={formDescription} onChange={e => setFormDescription(e.target.value)} />
                </label>
                <div className="ticket-form-footer">
                  {formAlertId && <span className="linked-alert">{t.tickets.linkedAlert} #{formAlertId}</span>}
                  <button disabled={pending === 'create-ticket' || nodes.length === 0}>
                    {pending === 'create-ticket' ? t.tickets.creating : t.tickets.saveTicket}
                  </button>
                </div>
              </form>
            )}

            <div className="ticket-list">
              {tickets.map(ticket => (
                <article className="ticket-row-block" key={ticket.id}>
                  <div className="ticket-row">
                    <div className="ticket-main">
                      <div className="ticket-title-line">
                        <strong>#{ticket.id} · {ticket.title}</strong>
                        <span className={`priority priority-${ticket.priority.toLowerCase()}`}>{t.priorities[ticket.priority] ?? ticket.priority}</span>
                        {ticket.closure_status === 'PENDING' && <span className="priority pending-review">{t.tickets.closurePending}</span>}
                      </div>
                      <p>{ticket.node_name} · #{ticket.node_id}{ticket.alert_id ? ` · Alert #${ticket.alert_id}` : ''}</p>
                      {ticket.description && <p className="ticket-description-text">{ticket.description}</p>}
                      {ticket.closure_summary && (
                        <p className="cell-muted">
                          {t.tickets.summary}: {ticket.closure_summary} — {ticket.closure_resolution_details}
                        </p>
                      )}
                      <span className="ticket-meta">
                        {t.tickets.createdBy}: {ticket.created_by_username ?? '—'} · {t.tickets.assignedTo}: <strong>{ticket.assigned_to_username ?? t.tickets.unassigned}</strong> · {formatWhen(ticket.updated_at, lang)}
                      </span>
                    </div>

                    <div className="ticket-side">
                      <span className={`ticket-status ticket-status-${ticket.status.toLowerCase()}`}>{ticket.status.replaceAll('_', ' ')}</span>
                      <div className="ticket-actions-wrap">
                        <button type="button" className="compact-action secondary" onClick={() => void loadNotes(ticket.id)}>
                          {t.tickets.notesBtn} ({ticket.note_count ?? 0})
                        </button>
                        {ticket.status === 'OPEN' && (
                          <button type="button" className="compact-action" disabled={pending === `ticket-${ticket.id}`} onClick={() => void startWork(ticket.id)}>
                            {t.tickets.startWork}
                          </button>
                        )}
                        {(ticket.status === 'OPEN' || ticket.status === 'IN_PROGRESS') && (
                          <button type="button" className="compact-action secondary" onClick={() => setClosureTicketId(closureTicketId === ticket.id ? null : ticket.id)}>
                            {t.tickets.requestClosure}
                          </button>
                        )}
                        {canWrite && ticket.status === 'PENDING_CLOSURE' && ticket.closure_status === 'PENDING' && (
                          <>
                            <button type="button" className="compact-action" onClick={() => void reviewClosure(ticket.id, 'APPROVED')}>
                              {t.tickets.approveClosure}
                            </button>
                            <button type="button" className="compact-action secondary" onClick={() => void reviewClosure(ticket.id, 'REJECTED')}>
                              {t.tickets.rejectClosure}
                            </button>
                          </>
                        )}
                      </div>
                      {canWrite && ticket.status !== 'CLOSED' && technicians.length > 0 && (
                        <div className="assign-inline">
                          <select
                            value={assignDrafts[ticket.id] ?? String(ticket.assigned_to_user_id ?? technicians[0]?.id ?? '')}
                            onChange={e => setAssignDrafts(prev => ({ ...prev, [ticket.id]: e.target.value }))}
                          >
                            {technicians.map(tech => <option key={tech.id} value={tech.id}>{tech.username}</option>)}
                          </select>
                          <button type="button" className="compact-action secondary" onClick={() => void assignTicket(ticket.id)}>
                            {t.tickets.assignBtn}
                          </button>
                        </div>
                      )}
                    </div>
                  </div>

                  {openNotesTicketId === ticket.id && (
                    <div className="notes-drawer">
                      <div className="ar-mini-list">
                        {ticketNotes.map(n => (
                          <div key={n.id} className="note-item">
                            <strong>{n.author_username}</strong> <span className="cell-muted">· {formatWhen(n.created_at, lang)}</span>
                            <p>{n.note_text}</p>
                          </div>
                        ))}
                        {!ticketNotes.length && <span className="cell-muted">{t.tickets.noNotes}</span>}
                      </div>
                      <form
                        className="inline-subform"
                        onSubmit={e => {
                          e.preventDefault();
                          if (newNoteText.trim()) void addTicketNote(ticket.id, newNoteText.trim());
                        }}
                      >
                        <input value={newNoteText} onChange={e => setNewNoteText(e.target.value)} placeholder={t.tickets.addNotePlaceholder} required />
                        <button type="submit" className="compact-action">{t.tickets.addNoteBtn}</button>
                      </form>
                    </div>
                  )}

                  {closureTicketId === ticket.id && (
                    <form
                      className="inline-subform vertical closure-box"
                      onSubmit={e => {
                        e.preventDefault();
                        void submitClosure(ticket.id, closureSummary.trim(), closureDetails.trim(), closureType);
                      }}
                    >
                      <div className="eyebrow">{t.tickets.closureTitle}</div>
                      <div className="inline-row">
                        <input value={closureSummary} onChange={e => setClosureSummary(e.target.value)} placeholder={t.tickets.summary} required />
                        <select value={closureType} onChange={e => setClosureType(e.target.value)}>
                          <option value="CORRECTIVE">CORRECTIVE</option>
                          <option value="PREVENTIVE">PREVENTIVE</option>
                          <option value="EMERGENCY">EMERGENCY</option>
                          <option value="INSPECTION">INSPECTION</option>
                        </select>
                      </div>
                      <textarea rows={2} value={closureDetails} onChange={e => setClosureDetails(e.target.value)} placeholder={t.tickets.resolutionDetails} required />
                      <div className="ticket-form-footer">
                        <button type="button" className="secondary compact-action" onClick={() => setClosureTicketId(null)}>{t.assets.cancelEdit}</button>
                        <button type="submit" className="compact-action">{t.tickets.submitClosure}</button>
                      </div>
                    </form>
                  )}
                </article>
              ))}
              {!tickets.length && <div className="empty">{t.tickets.noTickets}</div>}
            </div>
            <div className="pager-bar">
              <button type="button" className="compact-action secondary" disabled={ticketPage === 0} onClick={() => setTicketPage(p => Math.max(0, p - 1))}>{t.prevPage}</button>
              <span>{t.pageLabel} {ticketPage + 1}</span>
              <button type="button" className="compact-action secondary" disabled={!ticketHasNext} onClick={() => setTicketPage(p => p + 1)}>{t.nextPage}</button>
            </div>
          </section>

          <section className="panel">
            <div className="section-head">
              <div>
                <h2>{t.twin.title}</h2>
                <p className="section-sub">{t.twin.inspectHint}</p>
              </div>
              <div className="ticket-heading-actions">
                {canWrite && (
                  <>
                    <button type="button" className="compact-action secondary" onClick={() => setShowInfraForm(v => !v)}>
                      {showInfraForm ? t.twin.closeInfra : t.twin.manageInfra}
                    </button>
                    <button type="button" className="compact-action" onClick={() => setShowOnboardForm(v => !v)}>
                      {showOnboardForm ? t.twin.closeForm : t.twin.onboardNode}
                    </button>
                  </>
                )}
              </div>
            </div>

            {showInfraForm && canWrite && (
              <form className="ticket-form grid-3" onSubmit={e => void saveInfrastructure(e)}>
                <label>{t.twin.entityType}
                  <select value={infraType} onChange={e => {
                    const next = e.target.value as 'SITE' | 'ROOM' | 'RACK';
                    setInfraType(next);
                    if (next === 'ROOM' && uniqueSites[0]) setInfraParentId(String(uniqueSites[0].site_id));
                    if (next === 'RACK' && uniqueRooms[0]?.room_id) setInfraParentId(String(uniqueRooms[0].room_id));
                  }}>
                    <option value="RACK">RACK</option>
                    <option value="ROOM">ROOM</option>
                    <option value="SITE">SITE</option>
                  </select>
                </label>
                {infraType !== 'SITE' && (
                  <label>{t.twin.parentEntity}
                    <select value={infraParentId} onChange={e => setInfraParentId(e.target.value)}>
                      {infraType === 'ROOM' && uniqueSites.map(s => (
                        <option key={s.site_id} value={s.site_id}>{s.site_name} ({s.site_code})</option>
                      ))}
                      {infraType === 'RACK' && uniqueRooms.map(rm => (
                        <option key={rm.room_id!} value={rm.room_id!}>{rm.site_name} / {rm.room_name}</option>
                      ))}
                    </select>
                  </label>
                )}
                <label>{t.twin.codeLabel}<input value={infraCode} onChange={e => setInfraCode(e.target.value)} placeholder="RACK-B01" required /></label>
                <label>{t.twin.nameLabel}<input value={infraName} onChange={e => setInfraName(e.target.value)} required /></label>
                {infraType !== 'RACK' ? (
                  <label>{t.twin.extraLabel}<input value={infraExtra} onChange={e => setInfraExtra(e.target.value)} /></label>
                ) : (
                  <>
                    <label>{t.twin.unitCapLabel}<input type="number" min={1} value={infraUnits} onChange={e => setInfraUnits(e.target.value)} required /></label>
                    <label>{t.twin.powerCapLabel}<input type="number" min={100} value={infraPowerCap} onChange={e => setInfraPowerCap(e.target.value)} required /></label>
                  </>
                )}
                <div className="ticket-form-footer">
                  <button type="submit" disabled={pending === 'save-infra'}>{t.twin.saveInfra}</button>
                </div>
              </form>
            )}

            <div className="rack-pills">
              <button
                type="button"
                className={`chip-btn ${selectedRoomId == null ? 'active' : ''}`}
                onClick={() => { setSelectedRoomId(null); setSelectedRackId(null); }}
              >
                {t.twin.allSitesRooms}
              </button>
              {uniqueRooms.map(rm => (
                <button
                  key={rm.room_id!}
                  type="button"
                  className={`chip-btn ${selectedRoomId === rm.room_id ? 'active' : ''}`}
                  onClick={() => { setSelectedRoomId(rm.room_id!); setSelectedRackId(null); }}
                >
                  {rm.site_code} / {rm.room_name}
                </button>
              ))}
            </div>

            <div className="rack-pills">
              <button
                type="button"
                className={`chip-btn ${selectedRackId == null ? 'active' : ''}`}
                onClick={() => setSelectedRackId(null)}
              >
                {t.twin.allRacks} ({visibleNodes.length})
              </button>
              {filteredRacks.map(rk => (
                <button
                  key={rk.id}
                  type="button"
                  className={`chip-btn ${selectedRackId === rk.id ? 'active' : ''}`}
                  onClick={() => setSelectedRackId(rk.id)}
                >
                  {rk.site_code} · {rk.name} ({rk.node_count} nodes · {rk.used_power_watts.toFixed(0)}W)
                </button>
              ))}
            </div>

            <div className="rack-chassis-wrap">
              <h3 className="subheading">{t.twin.rackChassisTitle}</h3>
              <div className="rack-chassis-grid">
                {chassisRacks.map(rk => {
                  const rackNodes = nodes
                    .filter(n => n.rack_id === rk.id)
                    .sort((a, b) => (a.rack_position_u ?? 0) - (b.rack_position_u ?? 0));
                  return (
                    <div key={rk.id} className="rack-chassis">
                      <div className="rack-chassis-head">
                        <strong>{rk.name} ({rk.code})</strong>
                        <span className="cell-muted">{rk.used_power_watts.toFixed(0)}/{rk.total_power_capacity_watts.toFixed(0)}W</span>
                      </div>
                      <div className="rack-slots">
                        {rackNodes.map(n => (
                          <button
                            key={n.id}
                            type="button"
                            className={`rack-blade ${inspectedNodeId === n.id ? 'selected' : ''}`}
                            aria-pressed={inspectedNodeId === n.id}
                            aria-controls={inspectedNodeId === n.id ? 'node-inspector' : undefined}
                            onClick={() => selectInspectNode(n)}
                          >
                            <span className="u-badge">U{n.rack_position_u ?? 1}</span>
                            <span className="blade-name">{n.name}</span>
                            <span className={`status status-${n.status.toLowerCase()}`}>{n.status}</span>
                          </button>
                        ))}
                        {!rackNodes.length && <div className="cell-muted">{t.twin.noNodes}</div>}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {showOnboardForm && canWrite && (
              <form className="ticket-form grid-3" onSubmit={e => void registerNode(e)}>
                <label>{t.twin.rackLabel}
                  <select value={obRackId} onChange={e => setObRackId(e.target.value)}>
                    {racks.map(rk => <option key={rk.id} value={rk.id}>{rk.site_name} / {rk.room_name} / {rk.name}</option>)}
                  </select>
                </label>
                <label>{t.twin.nodeName}<input value={obName} onChange={e => setObName(e.target.value)} required /></label>
                <label>{t.twin.hostname}<input value={obHostname} onChange={e => setObHostname(e.target.value)} required /></label>
                <label>{t.twin.ipAddress}<input value={obIp} onChange={e => setObIp(e.target.value)} placeholder="192.168.10.20" required /></label>
                <label>{t.twin.macAddress}<input value={obMac} onChange={e => setObMac(e.target.value)} /></label>
                <label>{t.twin.uPosition}<input type="number" min={1} value={obU} onChange={e => setObU(e.target.value)} required /></label>
                <label>{t.twin.powerWatts}<input type="number" min={1} value={obPower} onChange={e => setObPower(e.target.value)} required /></label>
                <label>{t.twin.markerCode}<input value={obMarker} onChange={e => setObMarker(e.target.value)} placeholder="arimms://node/NODE-05" /></label>
                <div className="ticket-form-footer">
                  <button disabled={pending === 'register-node'}>{pending === 'register-node' ? t.twin.registering : t.twin.registerBtn}</button>
                </div>
              </form>
            )}

            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>{t.twin.colNode}</th>
                    <th>{t.twin.colLocation}</th>
                    <th>{t.twin.colStatus}</th>
                    <th>CPU</th>
                    <th>RAM</th>
                    <th>Disk</th>
                    <th>{t.twin.colTemp}</th>
                    <th>{t.twin.colContainers}</th>
                    <th>{t.twin.colUtc}</th>
                  </tr>
                </thead>
                <tbody>
                  {visibleNodes.map(node => (
                    <tr
                      key={node.id}
                      className={`clickable-row ${inspectedNodeId === node.id ? 'row-selected' : ''}`}
                      onClick={() => selectInspectNode(node)}
                    >
                      <td>
                        <button type="button" className="node-cell node-trigger" aria-pressed={inspectedNodeId === node.id} aria-controls={inspectedNodeId === node.id ? 'node-inspector' : undefined} onClick={e => { e.stopPropagation(); selectInspectNode(node); }}>
                          <span className="node-name">{node.name}</span>
                          <span className="node-id">#{node.id}{node.primary_marker_code ? ` · ${node.primary_marker_code}` : ''}</span>
                        </button>
                      </td>
                      <td className="cell-muted">
                        {[node.site_name, node.room_name, node.rack_name].filter(Boolean).join(' / ') || '—'}
                        {node.rack_position_u ? ` · U${node.rack_position_u}` : ''}
                      </td>
                      <td><span className={`status status-${node.status.toLowerCase()}`}>{node.status}</span></td>
                      <td><Meter value={node.cpu_usage_percent} /></td>
                      <td><Meter value={node.memory_usage_percent} /></td>
                      <td><Meter value={node.disk_usage_percent} /></td>
                      <td>{node.temperature_celsius != null ? `${node.temperature_celsius.toFixed(1)}°C` : '—'}</td>
                      <td><span className="priority">{node.container_count ?? 0}</span></td>
                      <td className="cell-time">{formatWhen(node.collected_at, lang)}</td>
                    </tr>
                  ))}
                  {!visibleNodes.length && <tr><td colSpan={9} className="empty">{t.twin.noNodes}</td></tr>}
                </tbody>
              </table>
            </div>

            {inspectedNode && (
              <div className="drilldown-box" id="node-inspector">
                <div className="section-head">
                  <div>
                    <div className="eyebrow">{t.twin.drilldownTitle}</div>
                    <h3>{inspectedNode.name} · {inspectedNode.hostname ?? `#${inspectedNode.id}`}</h3>
                  </div>
                  <div className="trend-controls">
                    <select value={inspectMetric} onChange={e => setInspectMetric(e.target.value)}>
                      <option value="cpu_usage_percent">CPU (%)</option>
                      <option value="memory_usage_percent">RAM (%)</option>
                      <option value="disk_usage_percent">Disk (%)</option>
                      <option value="temperature_celsius">Temp (°C)</option>
                    </select>
                    <button type="button" className="compact-action secondary" onClick={() => setInspectedNodeId(null)}>
                      {t.twin.closeInspector}
                    </button>
                  </div>
                </div>

                <SparkChart points={inspectHistory} emptyLabel={t.kpi.noData} />

                <div className="drilldown-grid">
                  <div>
                    <div className="eyebrow">{t.twin.containersTitle}</div>
                    <div className="ar-mini-list">
                      {inspectedContainers.map(c => (
                        <div key={c.id} className="ar-mini-row">
                          <div>
                            <strong>{c.name}</strong>
                            <div className="cell-muted">{c.image} · {c.status} · CPU {c.cpu_usage_percent.toFixed(1)}% · RAM {c.memory_usage_mb.toFixed(0)}MB · Restarts: {c.restarted_count}</div>
                          </div>
                          <button
                            type="button"
                            className="compact-action secondary"
                            disabled={pending === `container-${c.id}`}
                            onClick={() => void restartContainer(c.id)}
                          >
                            {t.twin.restartContainer}
                          </button>
                        </div>
                      ))}
                      {!inspectedContainers.length && <div className="cell-muted">{t.twin.noContainers}</div>}
                    </div>
                  </div>

                  {canWrite && (
                    <div>
                      <div className="eyebrow">{t.twin.markerTitle}</div>
                      <form className="inline-subform vertical" onSubmit={e => void saveMarker(e)}>
                        <div className="inline-row">
                          <select value={markerTypeInput} onChange={e => setMarkerTypeInput(e.target.value)}>
                            <option value="QR">QR</option>
                            <option value="ARUCO">ARUCO</option>
                          </select>
                          <input
                            value={markerCodeInput}
                            onChange={e => setMarkerCodeInput(e.target.value)}
                            placeholder={`arimms://node/NODE-0${inspectedNode.id}`}
                            required
                          />
                          <button type="submit" className="compact-action" disabled={pending === 'save-marker'}>{t.twin.saveMarker}</button>
                        </div>
                      </form>

                      <div className="eyebrow edit-node-eyebrow">{t.twin.editNodeTitle}</div>
                      <form className="ticket-form grid-3 edit-node-form" onSubmit={e => void updateInspectedNode(e)}>
                        <label>{t.twin.rackLabel}
                          <select value={editNodeRackId} onChange={e => setEditNodeRackId(e.target.value)}>
                            {racks.map(rk => <option key={rk.id} value={rk.id}>{rk.name}</option>)}
                          </select>
                        </label>
                        <label>{t.twin.nodeName}<input value={editNodeName} onChange={e => setEditNodeName(e.target.value)} required /></label>
                        <label>{t.twin.hostname}<input value={editNodeHost} onChange={e => setEditNodeHost(e.target.value)} required /></label>
                        <label>{t.twin.ipAddress}<input value={editNodeIp} onChange={e => setEditNodeIp(e.target.value)} required /></label>
                        <label>{t.twin.uPosition}<input type="number" min={1} value={editNodeU} onChange={e => setEditNodeU(e.target.value)} required /></label>
                        <label>{t.twin.powerWatts}<input type="number" min={1} value={editNodePower} onChange={e => setEditNodePower(e.target.value)} required /></label>
                        <label>{t.twin.statusLabel}
                          <select value={editNodeStatus} onChange={e => setEditNodeStatus(e.target.value)}>
                            <option value="ONLINE">ONLINE</option>
                            <option value="WARNING">WARNING</option>
                            <option value="CRITICAL">CRITICAL</option>
                            <option value="UNAVAILABLE">UNAVAILABLE</option>
                            <option value="MAINTENANCE">MAINTENANCE</option>
                          </select>
                        </label>
                        <div className="ticket-form-footer">
                          <button type="submit" className="compact-action" disabled={pending === `update-node-${inspectedNode.id}`}>{t.twin.saveNodeBtn}</button>
                        </div>
                      </form>
                    </div>
                  )}
                </div>
              </div>
            )}
          </section>
        </>
      )}

      {tab === 'my-work' && showData && (
        <>
          <section className="panel">
            <div className="section-head">
              <h2>{t.myWork.tickets}</h2>
              <span className="list-count">{openTickets.length}</span>
            </div>
            <div className="ticket-list">
              {myWorkTickets.map(item => (
                <article className="ticket-row" key={item.id}>
                  <div className="ticket-main">
                    <strong>#{item.id} · {item.title}</strong>
                    <p>{item.node_name} · {item.priority} · {item.status.replaceAll('_', ' ')}</p>
                    {item.assigned_to_username && (
                      <span className="ticket-meta">{t.tickets.assignedTo}: {item.assigned_to_username}</span>
                    )}
                  </div>
                  <div className="ticket-side">
                    <span className={`ticket-status ticket-status-${item.status.toLowerCase()}`}>
                      {item.closure_status === 'PENDING' ? t.tickets.closurePending : item.status.replaceAll('_', ' ')}
                    </span>
                    {canWrite && item.status === 'OPEN' && (
                      <button className="compact-action" onClick={() => void startWork(item.id)}>
                        {t.tickets.assignBtn}
                      </button>
                    )}
                    {item.status === 'IN_PROGRESS' && (
                      <button className="compact-action secondary" onClick={() => setTab('overview')}>
                        {t.tickets.notesBtn}
                      </button>
                    )}
                  </div>
                </article>
              ))}
              {!myWorkTickets.length && <div className="empty">{t.myWork.noTickets}</div>}
            </div>
          </section>
          {canWrite && (
            <section className="panel">
              <div className="section-head">
                <h2>{t.myWork.alerts}</h2>
                <span className="list-count">{alerts.length}</span>
              </div>
              <div className="alert-list">
                {alerts.map(alert => (
                  <article className="alert-row" key={alert.id}>
                    <span className={`severity severity-${alert.severity.toLowerCase()}`}>{alert.severity}</span>
                    <div>
                      <strong>{alert.node_name} · {alert.alert_type}</strong>
                      <p>{alert.message}</p>
                    </div>
                    <button
                      type="button"
                      className="compact-action"
                      disabled={alert.status !== 'OPEN'}
                      onClick={() => void acknowledgeAlert(alert)}
                    >
                      {alert.status === 'OPEN' ? t.alerts.acknowledge : alert.status}
                    </button>
                  </article>
                ))}
                {!alerts.length && <div className="empty">{t.myWork.noAlerts}</div>}
              </div>
            </section>
          )}
        </>
      )}

      {tab === 'handover' && showData && (
        <HandoverTab
          token={token}
          lang={lang}
          openTickets={openTickets}
          alertsCount={alerts.length}
          handoverAvailable={handoverAvailable}
          handoverNotes={handoverNotes}
          onNotesChange={setHandoverNotes}
          onNotice={setNotice}
          onError={setError}
        />
      )}

      {tab === 'ar' && (
        <ArScannerTab
          token={token}
          lang={lang}
          onRestartContainer={id => restartContainer(id, true)}
          onAddTicketNote={addTicketNote}
          onSubmitClosure={submitClosure}
        />
      )}

      {tab === 'assets' && showData && (
        <AssetsTab
          lang={lang}
          canWrite={canWrite}
          assets={assets}
          maintenance={maintenance}
          onSaveAsset={async (nodeId, payload) => {
            await submitAction(`asset-${nodeId}`, `/api/assets/${nodeId}`, 'PUT', payload);
            setNotice(`Asset #${nodeId} saved.`);
          }}
        />
      )}

      {tab === 'analytics' && showData && (
        <AnalyticsTab
          token={token}
          lang={lang}
          summary={summary}
          rackCapacity={rackCapacity}
          nodes={nodes}
        />
      )}

      {tab === 'admin' && isAdmin && showData && (
        <AdminTab
          lang={lang}
          users={usersList}
          accountRequests={accountRequests}
          accountRequestsAvailable={accountRequestsAvailable}
          collectors={collectors}
          auditLogs={auditLogs}
          auditFilter={auditFilter}
          auditPage={auditPage}
          auditHasNext={auditHasNext}
          onChangeAuditFilter={entity => {
            setAuditFilter(entity);
            setAuditPage(0);
          }}
          onChangeAuditPage={setAuditPage}
          onSaveUser={async payload => {
            await submitAction('save-user', '/api/users', 'POST', payload);
            setNotice('User account saved.');
          }}
          onReviewAccountRequest={async (item, decision) => {
            const response = await fetch(apiUrl(`/api/account-requests/${item.id}/review`), { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ decision, role_name: item.requested_role }) });
            const data = await response.json().catch(() => ({}));
            if (!response.ok) throw new Error(data.error || t.admin.accountReviewFailed);
            await refresh(token, user, refreshOptsRef.current);
            return data.recovery_code ?? null;
          }}
          onIssueRecoveryCode={async userId => {
            const response = await fetch(apiUrl(`/api/auth/users/${userId}/recovery-code`), { method: 'POST', headers: { Authorization: `Bearer ${token}` } });
            const data = await response.json().catch(() => ({}));
            if (!response.ok) throw new Error(data.error || t.admin.recoveryCodeFailed);
            return data.code ?? null;
          }}
          onManageCollector={async payload => {
            const res = await submitAction('manage-collector', '/api/collectors', 'POST', payload);
            const nextKey = res.api_key ? String(res.api_key) : null;
            if (nextKey) {
              setIssuedApiKey(nextKey);
              setCopiedKey(false);
            }
            setNotice('Collector agent updated.');
            return nextKey;
          }}
        />
      )}
      </div>
    </main>
  );
}
