'use client';

import { FormEvent, useState } from 'react';
import { getCopy } from '@/lib/i18n';
import type { AssetRow, Lang, MaintenanceRow } from '@/lib/types';

type Props = {
  lang: Lang;
  canWrite: boolean;
  assets: AssetRow[];
  maintenance: MaintenanceRow[];
  onSaveAsset: (nodeId: number, payload: Record<string, unknown>) => Promise<void>;
};

export function AssetsTab({ lang, canWrite, assets, maintenance, onSaveAsset }: Props) {
  const t = getCopy(lang);
  const [editingNodeId, setEditingNodeId] = useState<number | null>(null);
  const [cpuModel, setCpuModel] = useState('');
  const [cpuCores, setCpuCores] = useState('8');
  const [ramGb, setRamGb] = useState('32');
  const [storageGb, setStorageGb] = useState('1000');
  const [osName, setOsName] = useState('');
  const [osVersion, setOsVersion] = useState('');
  const [vendor, setVendor] = useState('');
  const [modelNumber, setModelNumber] = useState('');
  const [serialNumber, setSerialNumber] = useState('');
  const [warrantyEnd, setWarrantyEnd] = useState('');
  const [supportContact, setSupportContact] = useState('');
  const [saving, setSaving] = useState(false);

  function startEdit(row: AssetRow) {
    setEditingNodeId(row.node_id);
    setCpuModel(row.cpu_model ?? 'Intel Xeon');
    setCpuCores(String(row.cpu_cores ?? 8));
    setRamGb(String(row.total_ram_gb ?? 32));
    setStorageGb(String(row.total_storage_gb ?? 1000));
    setOsName(row.os_name ?? 'Ubuntu Server');
    setOsVersion(row.os_version ?? '24.04 LTS');
    setVendor(row.vendor ?? 'Dell');
    setModelNumber(row.model_number ?? 'PowerEdge');
    setSerialNumber(row.serial_number ?? `SN-${row.node_id}`);
    setWarrantyEnd(row.warranty_end ? new Date(row.warranty_end).toISOString().slice(0, 10) : '');
    setSupportContact(row.support_contact ?? '');
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (editingNodeId == null) return;
    setSaving(true);
    try {
      await onSaveAsset(editingNodeId, {
        cpu_model: cpuModel,
        cpu_cores: Number(cpuCores),
        total_ram_gb: Number(ramGb),
        total_storage_gb: Number(storageGb),
        os_name: osName,
        os_version: osVersion,
        vendor,
        model_number: modelNumber,
        serial_number: serialNumber,
        warranty_end: warrantyEnd || null,
        support_contact: supportContact || null,
      });
      setEditingNodeId(null);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="tab-stack">
      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">{t.assets.eyebrow}</div>
            <h2>{t.assets.title}</h2>
          </div>
          <span className="refresh-label">{assets.length} nodes</span>
        </div>

        {editingNodeId != null && canWrite && (
          <form className="ticket-form grid-3" onSubmit={e => void handleSubmit(e)}>
            <label>{t.assets.cpuModel}<input value={cpuModel} onChange={e => setCpuModel(e.target.value)} required /></label>
            <label>{t.assets.cpuCores}<input type="number" min={1} value={cpuCores} onChange={e => setCpuCores(e.target.value)} required /></label>
            <label>{t.assets.ramGb}<input type="number" min={1} step="0.5" value={ramGb} onChange={e => setRamGb(e.target.value)} required /></label>
            <label>{t.assets.storageGb}<input type="number" min={1} step="1" value={storageGb} onChange={e => setStorageGb(e.target.value)} required /></label>
            <label>{t.assets.osName}<input value={osName} onChange={e => setOsName(e.target.value)} required /></label>
            <label>{t.assets.osVersion}<input value={osVersion} onChange={e => setOsVersion(e.target.value)} required /></label>
            <label>{t.assets.vendor}<input value={vendor} onChange={e => setVendor(e.target.value)} required /></label>
            <label>{t.assets.modelNumber}<input value={modelNumber} onChange={e => setModelNumber(e.target.value)} required /></label>
            <label>{t.assets.serialNumber}<input value={serialNumber} onChange={e => setSerialNumber(e.target.value)} required /></label>
            <label>{t.assets.warrantyEnd}<input type="date" value={warrantyEnd} onChange={e => setWarrantyEnd(e.target.value)} /></label>
            <label>{t.assets.supportContact}<input value={supportContact} onChange={e => setSupportContact(e.target.value)} /></label>
            <div className="ticket-form-footer">
              <button type="button" className="secondary" onClick={() => setEditingNodeId(null)}>{t.assets.cancelEdit}</button>
              <button type="submit" disabled={saving}>{t.assets.saveAsset}</button>
            </div>
          </form>
        )}

        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Node</th>
                <th>{t.assets.cpuModel} / OS</th>
                <th>NICs</th>
                <th>{t.assets.vendor} / SN</th>
                <th>{t.assets.warrantyEnd}</th>
                {canWrite && <th />}
              </tr>
            </thead>
            <tbody>
              {assets.map(a => (
                <tr key={a.node_id}>
                  <td>
                    <span className="node-cell">
                      <span className="node-name">{a.node_name}</span>
                      <span className="node-id">{a.ip_address}</span>
                    </span>
                  </td>
                  <td>
                    <div>{a.cpu_model ? `${a.cpu_model} (${a.cpu_cores}c · ${a.total_ram_gb}G · ${a.total_storage_gb}G)` : '—'}</div>
                    <div className="cell-muted">{a.os_name ? `${a.os_name} ${a.os_version}` : '—'}</div>
                  </td>
                  <td className="cell-muted">{a.nics || '—'}</td>
                  <td>
                    <div>{a.vendor ? `${a.vendor} ${a.model_number}` : '—'}</div>
                    <div className="cell-muted">{a.serial_number || '—'}</div>
                  </td>
                  <td>
                    <span className={`status warranty-${a.warranty_status.toLowerCase()}`}>
                      {a.warranty_status}
                      {a.days_remaining != null && (
                        a.days_remaining >= 0
                          ? ` (${a.days_remaining} ${t.assets.daysLeft})`
                          : ` (${Math.abs(a.days_remaining)}d ${t.assets.expiredDays})`
                      )}
                    </span>
                  </td>
                  {canWrite && (
                    <td>
                      <button type="button" className="compact-action secondary" onClick={() => startEdit(a)}>
                        {t.assets.editAsset}
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel">
        <div className="section-head">
          <div>
            <div className="eyebrow">Service Trail</div>
            <h2>{t.assets.maintTitle}</h2>
          </div>
          <span className="refresh-label">{maintenance.length}</span>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Node</th>
                <th>{t.tickets.maintenanceType}</th>
                <th>{t.tickets.summary}</th>
                <th>{t.admin.actor}</th>
                <th>{t.admin.timeUtc}</th>
              </tr>
            </thead>
            <tbody>
              {maintenance.map(m => (
                <tr key={m.id}>
                  <td>
                    <span className="node-cell">
                      <span className="node-name">{m.node_name}</span>
                      {m.ticket_id && <span className="node-id">#{m.ticket_id}</span>}
                    </span>
                  </td>
                  <td><span className="priority">{m.maintenance_type}</span></td>
                  <td>
                    <div>{m.description}</div>
                    {m.resolution_notes && <div className="cell-muted">{m.resolution_notes}</div>}
                  </td>
                  <td>{m.performed_by_username}</td>
                  <td className="cell-time">{new Date(m.performed_at).toLocaleString()}</td>
                </tr>
              ))}
              {!maintenance.length && (
                <tr><td colSpan={5} className="empty">{t.assets.noMaint}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
