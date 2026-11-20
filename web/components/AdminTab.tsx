'use client';

import { FormEvent, useEffect, useState } from 'react';
import { downloadCsv } from '@/lib/csv';
import { getCopy } from '@/lib/i18n';
import type { AccountAccessRequest, AuditLogRow, CollectorAgentRow, Lang, UserRow } from '@/lib/types';

type Props = {
  lang: Lang;
  users: UserRow[];
  accountRequests: AccountAccessRequest[];
  accountRequestsAvailable: boolean;
  collectors: CollectorAgentRow[];
  auditLogs: AuditLogRow[];
  auditFilter: string;
  auditPage: number;
  auditHasNext: boolean;
  onChangeAuditFilter: (entity: string) => void;
  onChangeAuditPage: (nextPage: number) => void;
  onSaveUser: (payload: Record<string, unknown>) => Promise<void>;
  onReviewAccountRequest: (request: AccountAccessRequest, decision: 'APPROVE' | 'REJECT') => Promise<string | null>;
  onIssueRecoveryCode: (userId: number) => Promise<string | null>;
  onManageCollector: (payload: Record<string, unknown>) => Promise<string | null>;
};

const AUDIT_ENTITIES = ['', 'ALERT', 'TICKET', 'NODE', 'SITE', 'ROOM', 'RACK', 'THRESHOLD', 'ASSET', 'CONTAINER', 'AGENT', 'USER', 'DATABASE'];

export function AdminTab({
  lang,
  users,
  accountRequests,
  accountRequestsAvailable,
  collectors,
  auditLogs,
  auditFilter,
  auditPage,
  auditHasNext,
  onChangeAuditFilter,
  onChangeAuditPage,
  onSaveUser,
  onReviewAccountRequest,
  onIssueRecoveryCode,
  onManageCollector,
}: Props) {
  const t = getCopy(lang);
  const [showForm, setShowForm] = useState(false);
  const [editId, setEditId] = useState<number | null>(null);
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [fullName, setFullName] = useState('');
  const [roleName, setRoleName] = useState('FIELD_TECHNICIAN');
  const [isActive, setIsActive] = useState(true);
  const [password, setPassword] = useState('');
  const [saving, setSaving] = useState(false);
  const [issuedRecoveryCode, setIssuedRecoveryCode] = useState('');
  const [issuedRecoveryUser, setIssuedRecoveryUser] = useState('');
  const [keyAgent, setKeyAgent] = useState<CollectorAgentRow | null>(null);
  const [customApiKey, setCustomApiKey] = useState('');
  const [rotatedKey, setRotatedKey] = useState('');
  const [rotatedAgentLabel, setRotatedAgentLabel] = useState('');
  const [copiedCollectorKey, setCopiedCollectorKey] = useState(false);

  useEffect(() => {
    if (!rotatedKey) return;
    const timer = setTimeout(() => {
      setRotatedKey('');
      setRotatedAgentLabel('');
      setCopiedCollectorKey(false);
    }, 10000);
    return () => clearTimeout(timer);
  }, [rotatedKey]);

  function openCreate() {
    setEditId(null);
    setUsername('');
    setEmail('');
    setFullName('');
    setRoleName('FIELD_TECHNICIAN');
    setIsActive(true);
    setPassword('');
    setShowForm(true);
  }

  function openEdit(u: UserRow) {
    setEditId(u.id);
    setUsername(u.username);
    setEmail(u.email);
    setFullName(u.full_name);
    setRoleName(u.role_name);
    setIsActive(Boolean(u.is_active));
    setPassword('');
    setShowForm(true);
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      await onSaveUser({
        ...(editId != null ? { id: editId } : {}),
        username,
        email,
        full_name: fullName,
        role_name: roleName,
        is_active: isActive,
        ...(password ? { password } : {}),
      });
      setShowForm(false);
    } finally {
      setSaving(false);
    }
  }

  async function issueRecoveryCode(user: UserRow) {
    setSaving(true);
    try {
      const code = await onIssueRecoveryCode(user.id);
      if (code) { setIssuedRecoveryCode(code); setIssuedRecoveryUser(user.username); }
    } finally { setSaving(false); }
  }

  return (
    <div className="tab-stack">
      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">{t.admin.eyebrow}</div>
            <h2>{t.admin.title}</h2>
          </div>
          <button type="button" className="compact-action" onClick={() => (showForm ? setShowForm(false) : openCreate())}>
            {showForm ? t.assets.cancelEdit : t.admin.addUser}
          </button>
        </div>

        {showForm && (
          <form className="ticket-form grid-3" onSubmit={e => void handleSubmit(e)}>
            <label>{t.username}<input value={username} onChange={e => setUsername(e.target.value)} required /></label>
            <label>{t.admin.email}<input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></label>
            <label>{t.admin.fullName}<input value={fullName} onChange={e => setFullName(e.target.value)} required /></label>
            <label>{t.admin.role}
              <select value={roleName} onChange={e => setRoleName(e.target.value)}>
                <option value="ADMINISTRATOR">ADMINISTRATOR</option>
                <option value="SYSTEM_OPERATOR">SYSTEM_OPERATOR</option>
                <option value="FIELD_TECHNICIAN">FIELD_TECHNICIAN</option>
              </select>
            </label>
            <label>{t.admin.newPassword}
              <input type="password" value={password} onChange={e => setPassword(e.target.value)} minLength={password ? 8 : undefined} required={editId == null} />
            </label>
            <label className="checkbox-field">
              <input type="checkbox" checked={isActive} onChange={e => setIsActive(e.target.checked)} />
              <span>{t.admin.activeLabel}</span>
            </label>
            <div className="ticket-form-footer">
              <button type="submit" disabled={saving}>{t.admin.saveUser}</button>
            </div>
          </form>
        )}

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>{t.username}</th>
                <th>{t.admin.fullName}</th>
                <th>{t.admin.email}</th>
                <th>{t.admin.role}</th>
                <th>{t.twin.colStatus}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {users.map(u => (
                <tr key={u.id}>
                  <td>#{u.id}</td>
                  <td><strong>{u.username}</strong></td>
                  <td>{u.full_name}</td>
                  <td className="cell-muted">{u.email}</td>
                  <td><span className="priority">{t.roles[u.role_name] ?? u.role_name}</span></td>
                  <td>
                    <span className={`status ${u.is_active ? 'status-online' : 'status-unavailable'}`}>
                      {u.is_active ? 'ACTIVE' : 'DISABLED'}
                    </span>
                  </td>
                  <td>
                    <div className="ticket-actions-wrap">
                      <button type="button" className="compact-action secondary" onClick={() => openEdit(u)}>
                        {t.admin.editUser}
                      </button>
                      <button
                        type="button"
                        className="compact-action secondary"
                        disabled={saving || !u.is_active}
                        onClick={() => void issueRecoveryCode(u)}
                      >
                        {t.admin.issueRecoveryCode}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel">
        <div className="section-head">
          <div>
            <h2>{t.admin.accountRequests}</h2>
            <p className="section-sub">{t.admin.accountRequestsHelp}</p>
          </div>
          <span className="list-count">{accountRequests.length}</span>
        </div>
        {!accountRequestsAvailable && (
          <div className="notice-muted" role="status">{t.admin.accountRequestsMigration}</div>
        )}
        {issuedRecoveryCode && (
          <div className="notice banner" role="status">
            <strong>{issuedRecoveryUser}</strong>: <code>{issuedRecoveryCode}</code>
            <p>{t.admin.recoveryCodeOneTime}</p>
            <button
              type="button"
              className="compact-action secondary"
              onClick={() => { void navigator.clipboard?.writeText(issuedRecoveryCode); }}
            >
              {t.twin.copyKey}
            </button>
            <button type="button" className="compact-action secondary" onClick={() => setIssuedRecoveryCode('')}>
              {t.close}
            </button>
          </div>
        )}
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>{t.username}</th>
                <th>{t.admin.fullName}</th>
                <th>{t.admin.email}</th>
                <th>{t.admin.role}</th>
                <th>{t.requestNote}</th>
                <th>{t.admin.createdAt}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {accountRequests.map(item => (
                <tr key={item.id}>
                  <td><strong>{item.username}</strong></td>
                  <td>{item.full_name}</td>
                  <td>{item.email}</td>
                  <td>{t.roles[item.requested_role] ?? item.requested_role}</td>
                  <td>{item.note || '—'}</td>
                  <td>{new Date(item.created_at).toLocaleString(lang === 'vi' ? 'vi-VN' : 'en-US')}</td>
                  <td>
                    <div className="ticket-actions-wrap">
                      <button
                        type="button"
                        className="compact-action"
                        disabled={saving}
                        onClick={async () => {
                          setSaving(true);
                          try {
                            const code = await onReviewAccountRequest(item, 'APPROVE');
                            if (code) {
                              setIssuedRecoveryCode(code);
                              setIssuedRecoveryUser(item.username);
                            }
                          } finally {
                            setSaving(false);
                          }
                        }}
                      >
                        {t.admin.approveAccess}
                      </button>
                      <button
                        type="button"
                        className="compact-action secondary"
                        disabled={saving}
                        onClick={() => void onReviewAccountRequest(item, 'REJECT')}
                      >
                        {t.admin.rejectAccess}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {!accountRequests.length && <tr><td colSpan={7} className="empty">{t.admin.noAccountRequests}</td></tr>}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">Telemetry Agents</div>
            <h2>{t.admin.collectorsTitle}</h2>
          </div>
          <span className="refresh-label">{collectors.length} agents</span>
        </div>
        {rotatedKey && (
          <div className="notice banner key-banner" role="status">
            <div>
              <span>{t.admin.rotatedKeyNotice} <strong>{rotatedAgentLabel}</strong>: <code>{rotatedKey}</code></span>
              <p className="section-sub">{t.admin.rotatedKeyEnvHint}</p>
            </div>
            <div className="ticket-actions-wrap">
              <button
                type="button"
                className="compact-action"
                onClick={() => {
                  void navigator.clipboard?.writeText(rotatedKey);
                  setCopiedCollectorKey(true);
                }}
              >
                {copiedCollectorKey ? t.twin.copied : t.twin.copyKey}
              </button>
              <button type="button" className="compact-action secondary" onClick={() => setRotatedKey('')}>
                {t.close}
              </button>
            </div>
          </div>
        )}
        {keyAgent && (
          <form
            className="ticket-form"
            onSubmit={async e => {
              e.preventDefault();
              setSaving(true);
              try {
                const issued = await onManageCollector({
                  id: keyAgent.id,
                  node_id: keyAgent.node_id,
                  agent_version: keyAgent.agent_version,
                  status: 'ACTIVE',
                  rotate_key: true,
                  ...(customApiKey.trim() ? { api_key: customApiKey.trim() } : {}),
                });
                if (issued) {
                  setRotatedKey(issued);
                  setRotatedAgentLabel(`#${keyAgent.id} · ${keyAgent.node_name}`);
                  setCopiedCollectorKey(false);
                }
                setKeyAgent(null);
                setCustomApiKey('');
              } finally {
                setSaving(false);
              }
            }}
          >
            <label>
              {t.admin.customApiKeyLabel} (#{keyAgent.id} · {keyAgent.node_name})
              <input
                value={customApiKey}
                onChange={e => setCustomApiKey(e.target.value)}
                placeholder={t.admin.customApiKeyPlaceholder}
              />
            </label>
            <div className="ticket-form-footer">
              <button type="submit" disabled={saving}>{t.admin.applyApiKey}</button>
              <button type="button" className="secondary" disabled={saving} onClick={() => setCustomApiKey('demo-node-key-001')}>
                {t.admin.useDemoKey}
              </button>
              <button type="button" className="secondary" onClick={() => { setKeyAgent(null); setCustomApiKey(''); }}>
                {t.assets.cancelEdit}
              </button>
            </div>
          </form>
        )}
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Node</th>
                <th>{t.admin.agentVersion}</th>
                <th>{t.twin.colStatus}</th>
                <th>{t.admin.heartbeatAge}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {collectors.map(agent => (
                <tr key={agent.id}>
                  <td>#{agent.id}</td>
                  <td>
                    <span className="node-cell">
                      <span className="node-name">{agent.node_name}</span>
                      <span className="node-id">{agent.rack_name} · {agent.ip_address}</span>
                    </span>
                  </td>
                  <td><span className="priority">{agent.agent_version}</span></td>
                  <td>
                    <span className={`status ${agent.status === 'ACTIVE' ? 'status-online' : 'status-unavailable'}`}>
                      {agent.status}
                    </span>
                  </td>
                  <td className="cell-time">
                    {agent.last_heartbeat_at ? `${new Date(agent.last_heartbeat_at).toLocaleString()} (${agent.seconds_since_heartbeat ?? 0}s)` : '—'}
                  </td>
                  <td>
                    <div className="ticket-actions-wrap">
                      <button
                        type="button"
                        className="compact-action secondary"
                        onClick={() => void onManageCollector({
                          id: agent.id,
                          node_id: agent.node_id,
                          agent_version: agent.agent_version,
                          status: agent.status === 'ACTIVE' ? 'INACTIVE' : 'ACTIVE',
                        })}
                      >
                        {t.admin.toggleAgent}
                      </button>
                      <button
                        type="button"
                        className="compact-action"
                        onClick={() => {
                          setKeyAgent(agent);
                          setCustomApiKey('');
                        }}
                      >
                        {t.admin.rotateKey}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">Compliance · Immutable</div>
            <h2>{t.admin.auditTitle}</h2>
          </div>
          <div className="trend-controls">
            <select value={auditFilter} onChange={e => onChangeAuditFilter(e.target.value)} aria-label={t.admin.filterEntity}>
              {AUDIT_ENTITIES.map(ent => (
                <option key={ent || 'ALL'} value={ent}>{ent || t.admin.allEntities}</option>
              ))}
            </select>
            <button
              type="button"
              className="compact-action secondary"
              disabled={!auditLogs.length}
              onClick={() => downloadCsv(
                `ar-imms-audit-logs-p${auditPage + 1}.csv`,
                ['id', 'username', 'action', 'target_entity', 'target_id', 'details_json', 'timestamp'],
                auditLogs.map(log => [
                  log.id,
                  log.username ?? 'SYSTEM',
                  log.action,
                  log.target_entity,
                  log.target_id,
                  log.details_json,
                  log.timestamp,
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
                <th>ID</th>
                <th>{t.admin.actor}</th>
                <th>{t.admin.action}</th>
                <th>{t.admin.target}</th>
                <th>{t.admin.details}</th>
                <th>{t.admin.timeUtc}</th>
              </tr>
            </thead>
            <tbody>
              {auditLogs.map(log => (
                <tr key={log.id}>
                  <td className="cell-muted">#{log.id}</td>
                  <td>{log.username ?? 'SYSTEM'}</td>
                  <td><span className="priority">{log.action}</span></td>
                  <td>{log.target_entity}{log.target_id ? ` #${log.target_id}` : ''}</td>
                  <td className="mono-cell">{log.details_json ?? '—'}</td>
                  <td className="cell-time">{new Date(log.timestamp).toLocaleString()}</td>
                </tr>
              ))}
              {!auditLogs.length && (
                <tr><td colSpan={6} className="empty">{t.admin.noAudits}</td></tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="pager-bar">
          <button
            type="button"
            className="compact-action secondary"
            disabled={auditPage === 0}
            onClick={() => onChangeAuditPage(Math.max(0, auditPage - 1))}
          >
            {t.prevPage}
          </button>
          <span>{t.pageLabel} {auditPage + 1}</span>
          <button
            type="button"
            className="compact-action secondary"
            disabled={!auditHasNext}
            onClick={() => onChangeAuditPage(auditPage + 1)}
          >
            {t.nextPage}
          </button>
        </div>
      </section>
    </div>
  );
}
