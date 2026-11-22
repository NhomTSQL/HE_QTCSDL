'use client';

import { FormEvent, useState } from 'react';
import { apiFetch } from '@/lib/api';
import { getCopy } from '@/lib/i18n';
import type { Lang, TicketRow } from '@/lib/types';

export type HandoverNoteRow = {
  id: number;
  username: string;
  note: string;
  created_at: string;
};

type Props = {
  token: string;
  lang: Lang;
  openTickets: TicketRow[];
  alertsCount: number;
  handoverAvailable: boolean;
  handoverNotes: HandoverNoteRow[];
  onNotesChange: (notes: HandoverNoteRow[]) => void;
  onNotice: (message: string) => void;
  onError: (message: string) => void;
};

export function HandoverTab({
  token,
  lang,
  openTickets,
  alertsCount,
  handoverAvailable,
  handoverNotes,
  onNotesChange,
  onNotice,
  onError,
}: Props) {
  const t = getCopy(lang);
  const [handoverDraft, setHandoverDraft] = useState('');

  async function addHandover(event: FormEvent) {
    event.preventDefault();
    const response = await apiFetch('/api/handover', {
      method: 'POST',
      token,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ note: handoverDraft }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      onError(data.error || t.handover.failed);
      return;
    }
    setHandoverDraft('');
    onNotice(t.handover.saved);
    const refreshed = await apiFetch('/api/handover', { token });
    if (refreshed.ok) {
      onNotesChange(await refreshed.json());
    }
  }

  return (
    <section className="panel">
      <div className="section-head">
        <div>
          <h2>{t.handover.title}</h2>
          <p className="section-sub">{t.handover.subtitle}</p>
        </div>
        <span className="list-count">
          {openTickets.length} {t.myWork.tickets.toLowerCase()} · {alertsCount} {t.myWork.alerts.toLowerCase()}
        </span>
      </div>
      {!handoverAvailable && (
        <div className="notice-muted" role="status">{t.handover.migration}</div>
      )}
      <div className="handover-snapshot">
        <h3>{t.handover.activeWork}</h3>
        {openTickets.slice(0, 12).map(item => (
          <p key={item.id}>#{item.id} · {item.node_name} · {item.title} · {item.status.replaceAll('_', ' ')}</p>
        ))}
        {!openTickets.length && <p>{t.handover.noActiveWork}</p>}
      </div>
      {handoverAvailable && (
        <form className="ticket-form handover-form" onSubmit={e => void addHandover(e)}>
          <label>
            {t.handover.note}
            <textarea rows={4} maxLength={1000} value={handoverDraft} onChange={e => setHandoverDraft(e.target.value)} required />
          </label>
          <div className="ticket-form-footer">
            <button disabled={!handoverDraft.trim()}>{t.handover.save}</button>
          </div>
        </form>
      )}
      <div className="handover-notes">
        {handoverNotes.map(note => (
          <article key={note.id}>
            <p>{note.note}</p>
            <span>{note.username} · {new Date(note.created_at).toLocaleString(lang === 'vi' ? 'vi-VN' : 'en-US')}</span>
          </article>
        ))}
        {handoverAvailable && !handoverNotes.length && <p className="empty">{t.handover.noNotes}</p>}
      </div>
    </section>
  );
}
