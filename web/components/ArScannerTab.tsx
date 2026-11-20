'use client';

import { FormEvent, useCallback, useEffect, useRef, useState } from 'react';
import { getCopy } from '@/lib/i18n';
import type { Lang, MarkerLookupResult } from '@/lib/types';

type Props = {
  token: string;
  lang: Lang;
  onRestartContainer: (containerDbId: number) => Promise<void>;
  onAddTicketNote: (ticketId: number, noteText: string) => Promise<void>;
  onSubmitClosure: (ticketId: number, summary: string, details: string, mtype: string) => Promise<void>;
};

type DetectedBarcode = { rawValue?: string };
type BarcodeDetectorInstance = {
  detect: (source: HTMLVideoElement) => Promise<DetectedBarcode[]>;
};
type BarcodeDetectorCtor = new (opts?: { formats?: string[] }) => BarcodeDetectorInstance;

const QUICK_MARKERS = [
  'arimms://node/NODE-01',
  'arimms://node/NODE-02',
  'arimms://node/NODE-03',
  'arimms://node/NODE-04',
  '1',
  '2',
  '3',
  '4',
];

export function ArScannerTab({
  token,
  lang,
  onRestartContainer,
  onAddTicketNote,
  onSubmitClosure,
}: Props) {
  const t = getCopy(lang);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const [cameraOn, setCameraOn] = useState(false);
  const [cameraStarting, setCameraStarting] = useState(false);
  const [cameraError, setCameraError] = useState('');
  const [barcodeSupported, setBarcodeSupported] = useState(true);
  const [codeInput, setCodeInput] = useState('arimms://node/NODE-01');
  const [lookup, setLookup] = useState<MarkerLookupResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [scanError, setScanError] = useState('');
  const [arNotice, setArNotice] = useState('');
  const [restartingId, setRestartingId] = useState<number | null>(null);
  const cameraRequest = useRef(0);
  const lookupRequest = useRef(0);

  const [activeNoteTicketId, setActiveNoteTicketId] = useState<number | null>(null);
  const [noteText, setNoteText] = useState('');
  const [closureTicketId, setClosureTicketId] = useState<number | null>(null);
  const [closureSummary, setClosureSummary] = useState('');
  const [closureDetails, setClosureDetails] = useState('');
  const [closureType, setClosureType] = useState('CORRECTIVE');

  const performLookup = useCallback(async (rawCode: string) => {
    const clean = rawCode.trim();
    if (!clean) return;
    const request = ++lookupRequest.current;
    setLoading(true);
    setScanError('');
    try {
      const res = await fetch(`/api/markers/lookup?code=${encodeURIComponent(clean)}`, {
        headers: { Authorization: `Bearer ${token}` },
        cache: 'no-store',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
      if (request !== lookupRequest.current) return;
      setLookup(data as MarkerLookupResult);
      setCodeInput(clean);
    } catch (err) {
      if (request !== lookupRequest.current) return;
      setLookup(null);
      setScanError(err instanceof Error ? err.message : 'Marker lookup failed.');
    } finally {
      if (request === lookupRequest.current) setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    void performLookup('arimms://node/NODE-01');
  }, [performLookup]);

  const stopCamera = useCallback(() => {
    cameraRequest.current++;
    if (streamRef.current) {
      for (const track of streamRef.current.getTracks()) track.stop();
      streamRef.current = null;
    }
    if (videoRef.current) videoRef.current.srcObject = null;
    setCameraOn(false);
    setCameraStarting(false);
  }, []);

  useEffect(() => () => stopCamera(), [stopCamera]);

  async function startCamera() {
    setCameraError('');
    if (!navigator.mediaDevices?.getUserMedia) {
      setCameraError(t.ar.cameraUnavailable);
      return;
    }
    const request = ++cameraRequest.current;
    setCameraStarting(true);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' } },
        audio: false,
      });
      if (request !== cameraRequest.current) {
        stream.getTracks().forEach(track => track.stop());
        return;
      }
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play().catch(() => undefined);
      }
      const ctor = (window as unknown as { BarcodeDetector?: BarcodeDetectorCtor }).BarcodeDetector;
      if (request !== cameraRequest.current) return;
      setBarcodeSupported(Boolean(ctor));
      setCameraOn(true);
    } catch {
      if (request !== cameraRequest.current) return;
      setCameraError(t.ar.cameraUnavailable);
      setCameraOn(false);
    } finally {
      if (request === cameraRequest.current) setCameraStarting(false);
    }
  }

  useEffect(() => {
    if (!cameraOn) return;
    const ctor = (window as unknown as { BarcodeDetector?: BarcodeDetectorCtor }).BarcodeDetector;
    if (!ctor) return;
    let detector: BarcodeDetectorInstance | null = null;
    try {
      detector = new ctor({ formats: ['qr_code', 'code_128', 'data_matrix'] });
    } catch {
      setBarcodeSupported(false);
      return;
    }
    let busy = false;
    const timer = window.setInterval(async () => {
      if (busy || !videoRef.current || videoRef.current.readyState < 2 || !detector) return;
      busy = true;
      try {
        const codes = await detector.detect(videoRef.current);
        const hit = codes.find(c => c.rawValue)?.rawValue?.trim();
        if (hit && hit !== codeInput) {
          void performLookup(hit);
        }
      } catch {
        // Ignore single-frame detection failure
      } finally {
        busy = false;
      }
    }, 650);
    return () => window.clearInterval(timer);
  }, [cameraOn, codeInput, performLookup]);

  function onSubmitSearch(e: FormEvent) {
    e.preventDefault();
    void performLookup(codeInput);
  }

  async function handleRestart(containerId: number, name: string) {
    if (!window.confirm(`${name}\n\n${t.twin.confirmRestart}`)) return;
    setRestartingId(containerId);
    try {
      await onRestartContainer(containerId);
      await performLookup(codeInput);
    } catch { /* Shown by the dashboard. */ }
    finally { setRestartingId(null); }
  }

  async function handleAddNote(e: FormEvent, ticketId: number) {
    e.preventDefault();
    if (!noteText.trim()) return;
    await onAddTicketNote(ticketId, noteText.trim());
    setNoteText('');
    setActiveNoteTicketId(null);
    setArNotice(`Note added to ticket #${ticketId}.`);
    await performLookup(codeInput);
  }

  async function handleSubmitClosure(e: FormEvent, ticketId: number) {
    e.preventDefault();
    if (!closureSummary.trim() || !closureDetails.trim()) return;
    await onSubmitClosure(ticketId, closureSummary.trim(), closureDetails.trim(), closureType);
    setClosureTicketId(null);
    setClosureSummary('');
    setClosureDetails('');
    setArNotice(`Closure request submitted for ticket #${ticketId}.`);
    await performLookup(codeInput);
  }

  const node = lookup?.node;

  return (
    <section className="panel ar-panel">
      <div className="section-head">
        <div>
          <h2>{t.ar.title}</h2>
        </div>
        <div className="ar-controls">
          {!cameraOn ? (
            <button type="button" disabled={cameraStarting} onClick={() => void startCamera()}>{cameraStarting ? t.ar.startingCamera : t.ar.startCamera}</button>
          ) : (
            <button type="button" className="secondary" onClick={stopCamera}>{t.ar.stopCamera}</button>
          )}
        </div>
      </div>

      <form className="ar-search-bar" onSubmit={onSubmitSearch}>
        <input
          aria-label={t.ar.manualLabel}
          value={codeInput}
          onChange={e => setCodeInput(e.target.value)}
          placeholder={t.ar.manualPlaceholder}
        />
        <button type="submit" disabled={loading || !codeInput.trim()}>{loading ? t.ar.lookingUp : t.ar.scanBtn}</button>
      </form>

      <div className="ar-presets">
        <span className="eyebrow">{t.ar.quickMarkers}:</span>
        {QUICK_MARKERS.map(marker => (
          <button
            key={marker}
            type="button"
            className={`chip-btn ${codeInput === marker ? 'active' : ''}`}
            onClick={() => void performLookup(marker)}
          >
            {marker}
          </button>
        ))}
      </div>

      {cameraError && <div className="notice-muted">{cameraError}</div>}
      {cameraOn && !barcodeSupported && <div className="notice-muted">{t.ar.barcodeUnsupported}</div>}
      {scanError && <div className="error banner" role="alert">{scanError}</div>}
      {arNotice && <div className="notice banner" role="status">{arNotice}</div>}

      <div className="ar-viewport" hidden={!cameraOn}>
        <video
          ref={videoRef}
          muted
          playsInline
          className={`ar-video ${cameraOn ? 'visible' : 'hidden'}`}
        />
        <div className="ar-reticle" aria-hidden="true">
          <span className="corner tl" />
          <span className="corner tr" />
          <span className="corner bl" />
          <span className="corner br" />
        </div>
      </div>

        {node && (
          <div className="ar-hud" aria-busy={loading}>
            <div className="ar-hud-header">
              <div>
                <div className="ar-lock-tag">
                  {t.ar.hudLive}
                </div>
                <h3>{node.node_name}</h3>
                <p className="ar-sub">
                  {node.site_name} / {node.room_name} / {node.rack_name} · U{node.rack_position_u} · {node.ip_address}
                </p>
              </div>
              <div className="ar-badges">
                <span className={`status status-${node.status.toLowerCase()}`}>{node.status}</span>
                <span className="marker-pill">{node.marker_type}: {node.marker_code}</span>
              </div>
            </div>

            <div className="ar-hud-gauges">
              <div className="ar-gauge">
                <span>CPU</span>
                <strong>{node.cpu_usage_percent != null ? `${node.cpu_usage_percent.toFixed(1)}%` : '—'}</strong>
              </div>
              <div className="ar-gauge">
                <span>RAM</span>
                <strong>{node.memory_usage_percent != null ? `${node.memory_usage_percent.toFixed(1)}%` : '—'}</strong>
              </div>
              <div className="ar-gauge">
                <span>Disk</span>
                <strong>{node.disk_usage_percent != null ? `${node.disk_usage_percent.toFixed(1)}%` : '—'}</strong>
              </div>
              <div className="ar-gauge">
                <span>Temp</span>
                <strong>{node.temperature_celsius != null ? `${node.temperature_celsius.toFixed(1)}°C` : '—'}</strong>
              </div>
              <div className="ar-gauge">
                <span>Power</span>
                <strong>{node.power_consumption_watts}W</strong>
              </div>
              <div className="ar-gauge">
                <span>{t.ar.hudCoords}</span>
                <strong>
                  {node.coord_x != null ? `(${node.coord_x}, ${node.coord_y}, ${node.coord_z})` : '—'}
                </strong>
              </div>
            </div>

            <div className="ar-hud-grid">
              <div className="ar-card">
                <div className="eyebrow">{t.ar.hudSpecs} & {t.ar.hudWarranty}</div>
                <p>{node.cpu_model ? `${node.cpu_model} (${node.cpu_cores}c · ${node.total_ram_gb}GB RAM · ${node.total_storage_gb}GB)` : '—'}</p>
                <p className="cell-muted">{node.os_name ? `${node.os_name} ${node.os_version}` : ''}</p>
                <p className="cell-muted">
                  {node.vendor ? `${node.vendor} ${node.model_number} · SN: ${node.serial_number}` : ''}
                </p>
                {node.warranty_end && (
                  <p className="cell-muted">
                    {t.ar.hudWarranty}: {new Date(node.warranty_end).toLocaleDateString()}
                  </p>
                )}
              </div>

              <div className="ar-card">
                <div className="eyebrow">{t.ar.hudWorkloads} ({lookup?.containers.length ?? 0})</div>
                <div className="ar-mini-list">
                  {lookup?.containers.map(c => (
                    <div key={c.id} className="ar-mini-row">
                      <div>
                        <strong>{c.name}</strong>
                        <span className="cell-muted"> · {c.status} · CPU {c.cpu_usage_percent.toFixed(1)}%</span>
                      </div>
                      <button
                        type="button"
                        className="compact-action secondary"
                        disabled={restartingId !== null}
                        onClick={() => void handleRestart(c.id, c.name)}
                      >
                        {restartingId === c.id ? t.ar.restarting : t.twin.restartContainer}
                      </button>
                    </div>
                  ))}
                  {!lookup?.containers.length && <span className="cell-muted">{t.twin.noContainers}</span>}
                </div>
              </div>

              <div className="ar-card">
                <div className="eyebrow">{t.ar.hudAlerts} ({lookup?.alerts.length ?? 0})</div>
                <div className="ar-mini-list">
                  {lookup?.alerts.map(a => (
                    <div key={a.id} className="ar-mini-row">
                      <span className={`severity severity-${a.severity.toLowerCase()}`}>{a.severity}</span>
                      <span>{a.message}</span>
                    </div>
                  ))}
                  {!lookup?.alerts.length && <span className="cell-muted">{t.ar.hudNoAlerts}</span>}
                </div>
              </div>

              <div className="ar-card">
                <div className="eyebrow">{t.ar.hudTickets} ({lookup?.tickets.length ?? 0})</div>
                <div className="ar-mini-list">
                  {lookup?.tickets.map(tk => (
                    <div key={tk.id} className="ar-ticket-box">
                      <div className="ar-mini-row">
                        <div>
                          <strong>#{tk.id} {tk.title}</strong>
                          <span className="cell-muted"> · {tk.status}</span>
                        </div>
                        <div className="ar-ticket-btns">
                          <button
                            type="button"
                            className="compact-action secondary"
                            onClick={() => setActiveNoteTicketId(activeNoteTicketId === tk.id ? null : tk.id)}
                          >
                            {t.tickets.notesBtn}
                          </button>
                          {tk.status !== 'CLOSED' && (
                            <button
                              type="button"
                              className="compact-action"
                              onClick={() => setClosureTicketId(closureTicketId === tk.id ? null : tk.id)}
                            >
                              {t.tickets.requestClosure}
                            </button>
                          )}
                        </div>
                      </div>

                      {activeNoteTicketId === tk.id && (
                        <form className="inline-subform" onSubmit={e => void handleAddNote(e, tk.id)}>
                          <input
                            value={noteText}
                            onChange={e => setNoteText(e.target.value)}
                            placeholder={t.tickets.addNotePlaceholder}
                            required
                          />
                          <button type="submit" className="compact-action">{t.tickets.addNoteBtn}</button>
                        </form>
                      )}

                      {closureTicketId === tk.id && (
                        <form className="inline-subform vertical" onSubmit={e => void handleSubmitClosure(e, tk.id)}>
                          <input
                            value={closureSummary}
                            onChange={e => setClosureSummary(e.target.value)}
                            placeholder={t.tickets.summary}
                            required
                          />
                          <textarea
                            rows={2}
                            value={closureDetails}
                            onChange={e => setClosureDetails(e.target.value)}
                            placeholder={t.tickets.resolutionDetails}
                            required
                          />
                          <div className="inline-row">
                            <select value={closureType} onChange={e => setClosureType(e.target.value)}>
                              <option value="CORRECTIVE">CORRECTIVE</option>
                              <option value="PREVENTIVE">PREVENTIVE</option>
                              <option value="EMERGENCY">EMERGENCY</option>
                              <option value="INSPECTION">INSPECTION</option>
                            </select>
                            <button type="submit" className="compact-action">{t.tickets.submitClosure}</button>
                          </div>
                        </form>
                      )}
                    </div>
                  ))}
                  {!lookup?.tickets.length && <span className="cell-muted">{t.ar.hudNoTickets}</span>}
                </div>
              </div>
            </div>
          </div>
        )}
    </section>
  );
}
