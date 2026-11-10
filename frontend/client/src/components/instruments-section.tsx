// Instruments section for the Connectors (workspace connections) dialog.
// Surfaces the real instrument API already in the backend:
//   GET/POST/PATCH/DELETE /api/instruments, GET /api/instruments/:id/health,
//   GET /api/instruments/events, PATCH /api/instruments/events/:id
// Per the data-centric v2 design (§0.9), an instrument is a data-source
// connector that lives in the workspace-connections surface — not a new nav
// item. Every row shows its residency (where it runs), per the design's
// "residency on every row, no exceptions" rule.
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { INSTRUMENT_TYPES, type Instrument, type InstrumentType, type InstrumentEvent } from '@shared/schema';

type Residency = 'on-prem' | 'cloud';
const TYPE_META: Record<InstrumentType, { label: string; kind: 'local' | 'cloud' | 'file'; residency: Residency; port?: number }> = {
  opentrons:      { label: 'Opentrons OT-2 / Flex', kind: 'local', residency: 'on-prem', port: 31950 },
  minknow:        { label: 'Nanopore MinKNOW',       kind: 'local', residency: 'on-prem', port: 9501 },
  epu:            { label: 'Thermo EPU / cryo-EM',   kind: 'local', residency: 'on-prem', port: 8080 },
  flow_cytometer: { label: 'Flow cytometer',         kind: 'file',  residency: 'on-prem' },
  lcms:           { label: 'LC-MS',                  kind: 'file',  residency: 'on-prem' },
  qpcr:           { label: 'qPCR',                   kind: 'file',  residency: 'on-prem' },
  plate_reader:   { label: 'Plate reader',           kind: 'file',  residency: 'on-prem' },
  sila2:          { label: 'SiLA2 device (gRPC)',    kind: 'local', residency: 'on-prem', port: 50051 },
  basespace:      { label: 'Illumina BaseSpace',     kind: 'cloud', residency: 'cloud' },
  benchling:      { label: 'Benchling ELN / LIMS',   kind: 'cloud', residency: 'cloud' },
};

const STATUS_STYLE: Record<string, { bg: string; fg: string; label: string }> = {
  online:  { bg: 'oklch(0.93 0.07 150)', fg: 'oklch(0.38 0.12 150)', label: 'Online' },
  offline: { bg: 'oklch(0.93 0.05 25)',  fg: 'oklch(0.45 0.16 25)',  label: 'Offline' },
  error:   { bg: 'oklch(0.93 0.05 25)',  fg: 'oklch(0.45 0.16 25)',  label: 'Error' },
  unknown: { bg: 'var(--muted)',         fg: 'var(--muted-foreground)', label: 'Not checked' },
};

const inputStyle: React.CSSProperties = {
  fontSize: 'var(--fs-meta)', padding: '6px 8px', border: '1px solid var(--border)', borderRadius: 6,
  background: 'var(--background)', color: 'var(--foreground)', width: '100%',
};
const btn = (variant: 'primary' | 'ghost' | 'outline'): React.CSSProperties => ({
  fontSize: 'var(--fs-meta)', fontWeight: 600, padding: '5px 10px', borderRadius: 6, cursor: 'pointer',
  border: variant === 'outline' ? '1px solid var(--border)' : 'none',
  background: variant === 'primary' ? 'var(--foreground)' : 'transparent',
  color: variant === 'primary' ? 'var(--background)' : 'var(--muted-foreground)',
});

function Badge({ children, bg, fg }: { children: React.ReactNode; bg: string; fg: string }) {
  return <span style={{ fontSize: 'var(--fs-xs)', fontWeight: 600, padding: '1px 6px', borderRadius: 999, background: bg, color: fg }}>{children}</span>;
}

export function InstrumentsSection() {
  const qc = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState('');
  const [type, setType] = useState<InstrumentType | ''>('');
  const [host, setHost] = useState('');
  const [port, setPort] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [outputDir, setOutputDir] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  const instrumentsQ = useQuery<{ instruments: Instrument[] }>({ queryKey: ['/api/instruments'] });
  const eventsQ = useQuery<{ events: InstrumentEvent[] }>({ queryKey: ['/api/instruments/events'] });

  const resetForm = () => { setName(''); setType(''); setHost(''); setPort(''); setApiKey(''); setOutputDir(''); setFormError(null); setShowAdd(false); };

  const registerM = useMutation({
    mutationFn: async () => {
      const meta = type ? TYPE_META[type] : undefined;
      const body: Record<string, unknown> = { name, type };
      if (host) body.host = host;
      if (port) body.port = Number(port);
      if (apiKey) body.apiKey = apiKey;
      if (meta?.kind === 'file' && outputDir) body.config = { outputDir };
      await apiRequest('POST', '/api/instruments', body);
    },
    onSuccess: () => { resetForm(); qc.invalidateQueries({ queryKey: ['/api/instruments'] }); },
    onError: (e: any) => setFormError(e?.message || 'Failed to register instrument'),
  });
  const deleteM = useMutation({
    mutationFn: async (id: string) => { await apiRequest('DELETE', `/api/instruments/${id}`); },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['/api/instruments'] }),
  });
  const healthM = useMutation({
    mutationFn: async (id: string) => { await apiRequest('GET', `/api/instruments/${id}/health`); },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['/api/instruments'] }),
  });
  const eventM = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: 'launched' | 'dismissed' }) => {
      await apiRequest('PATCH', `/api/instruments/events/${id}`, { status });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['/api/instruments/events'] }),
  });

  // Launch = mark the event launched, then open a chat with a pre-filled draft.
  // App.tsx reads ?draft= and fills the composer WITHOUT auto-sending — the
  // user reviews and sends, consistent with "nothing runs until you confirm".
  const launchEvent = async (ev: InstrumentEvent) => {
    await eventM.mutateAsync({ id: ev.id, status: 'launched' });
    const loc = ev.filePath || ev.fcsDir || ev.directory;
    const draft = `Run the "${ev.workflowId}" workflow on the ${ev.experimentType} data from ${ev.source}${loc ? ` (${loc})` : ''}.`;
    window.location.assign(`/?draft=${encodeURIComponent(draft)}`);
  };

  const instruments = instrumentsQ.data?.instruments ?? [];
  const events = eventsQ.data?.events ?? [];
  const selectedMeta = type ? TYPE_META[type] : undefined;
  const canSubmit = name.trim().length > 0 && type !== '' && !registerM.isPending;

  return (
    <div data-testid="instruments-section" style={{ padding: '14px 20px', display: 'flex', flexDirection: 'column', gap: 20 }}>
      <p style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)', margin: 0 }}>
        Register a lab instrument or cloud service. A BioMate connector on your lab network (or a cloud service
        you've keyed) watches it and posts new-data events below; launching an event opens a chat draft to run
        the matching workflow, which you review before sending. Residency is shown on every row.
      </p>

      {/* New data events */}
      <section>
        <h3 style={{ fontSize: 'var(--fs-meta)', fontWeight: 700, margin: '0 0 8px', color: 'var(--foreground)' }}>
          New data events {events.length > 0 && <span data-testid="events-count">({events.length})</span>}
        </h3>
        {eventsQ.isLoading ? (
          <p style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)' }}>Loading…</p>
        ) : events.length === 0 ? (
          <p data-testid="events-empty" style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)' }}>
            No new data events. When a connected instrument produces data, it appears here as a workflow-launch suggestion.
          </p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {events.map((ev) => (
              <div key={ev.id} data-testid="instrument-event" style={{ border: '1px solid var(--border)', borderRadius: 8, padding: '10px 12px', display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'flex-start' }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontSize: 'var(--fs-meta)', fontWeight: 600, color: 'var(--foreground)' }}>{ev.description}</div>
                  <div style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)', marginTop: 2 }}>{ev.message}</div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 6 }}>
                    <Badge bg="var(--muted)" fg="var(--muted-foreground)">{ev.source}</Badge>
                    <Badge bg="var(--muted)" fg="var(--muted-foreground)">{ev.experimentType}</Badge>
                    <Badge bg="oklch(0.88 0.06 260)" fg="oklch(0.35 0.12 260)">→ {ev.workflowId}</Badge>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 6, flexShrink: 0 }}>
                  <button data-testid="event-launch" disabled={eventM.isPending} style={btn('primary')} onClick={() => launchEvent(ev)}>Launch</button>
                  <button data-testid="event-dismiss" disabled={eventM.isPending} style={btn('ghost')} onClick={() => eventM.mutate({ id: ev.id, status: 'dismissed' })}>Dismiss</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* My instruments */}
      <section>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ fontSize: 'var(--fs-meta)', fontWeight: 700, margin: 0, color: 'var(--foreground)' }}>
            My instruments {instruments.length > 0 && <span data-testid="instruments-count">({instruments.length})</span>}
          </h3>
          <button data-testid="button-add-instrument" style={btn('outline')} onClick={() => setShowAdd((v) => !v)}>+ Add instrument</button>
        </div>

        {showAdd && (
          <div data-testid="add-instrument-form" style={{ border: '1px solid var(--border)', borderRadius: 8, padding: 12, marginBottom: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
            <input data-testid="input-instrument-name" style={inputStyle} placeholder="Name — e.g. Lab OT-2 (Bench 3)" value={name} onChange={(e) => setName(e.target.value)} />
            <select data-testid="select-instrument-type" style={inputStyle} value={type} onChange={(e) => setType(e.target.value as InstrumentType)}>
              <option value="">Instrument type…</option>
              {INSTRUMENT_TYPES.map((t) => <option key={t} value={t}>{TYPE_META[t].label}</option>)}
            </select>
            {selectedMeta?.kind === 'local' && (
              <div style={{ display: 'flex', gap: 8 }}>
                <input data-testid="input-instrument-host" style={{ ...inputStyle, flex: 2 }} placeholder="Host / IP (e.g. 192.168.1.50)" value={host} onChange={(e) => setHost(e.target.value)} />
                <input data-testid="input-instrument-port" style={{ ...inputStyle, flex: 1 }} placeholder={`Port (${selectedMeta.port})`} value={port} onChange={(e) => setPort(e.target.value)} />
              </div>
            )}
            {selectedMeta?.kind === 'cloud' && (
              <input data-testid="input-instrument-apikey" type="password" style={inputStyle} placeholder="API key / token" value={apiKey} onChange={(e) => setApiKey(e.target.value)} />
            )}
            {selectedMeta?.kind === 'file' && (
              <input data-testid="input-instrument-outputdir" style={inputStyle} placeholder="Watched output directory (e.g. /data/qpcr)" value={outputDir} onChange={(e) => setOutputDir(e.target.value)} />
            )}
            {selectedMeta && (
              <p style={{ fontSize: 'var(--fs-micro)', color: 'var(--muted-foreground)', margin: 0 }}>
                Residency: <strong>{selectedMeta.residency === 'cloud' ? 'cloud — data leaves your estate' : 'on-prem — stays inside your network'}</strong>
              </p>
            )}
            {formError && <p data-testid="form-error" style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.55 0.2 25)', margin: 0 }}>{formError}</p>}
            <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
              <button style={btn('ghost')} onClick={resetForm}>Cancel</button>
              <button data-testid="button-submit-instrument" disabled={!canSubmit} style={{ ...btn('primary'), opacity: canSubmit ? 1 : 0.5 }} onClick={() => registerM.mutate()}>
                {registerM.isPending ? 'Saving…' : 'Register'}
              </button>
            </div>
          </div>
        )}

        {instrumentsQ.isLoading ? (
          <p style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)' }}>Loading…</p>
        ) : instruments.length === 0 ? (
          <p data-testid="instruments-empty" style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)' }}>
            No instruments registered yet. Add one above to track its connectivity and receive its data events.
          </p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {instruments.map((inst) => {
              const meta = TYPE_META[inst.type as InstrumentType];
              const st = STATUS_STYLE[inst.status] || STATUS_STYLE.unknown;
              return (
                <div key={inst.id} data-testid="instrument-row" style={{ border: '1px solid var(--border)', borderRadius: 8, padding: '10px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}>
                  <div style={{ minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                      <span style={{ fontSize: 'var(--fs-meta)', fontWeight: 600, color: 'var(--foreground)' }}>{inst.name}</span>
                      <span data-testid="instrument-status" data-status={inst.status}><Badge bg={st.bg} fg={st.fg}>{st.label}</Badge></span>
                      {meta && <Badge bg="var(--muted)" fg="var(--muted-foreground)">{meta.residency}</Badge>}
                    </div>
                    <div style={{ fontSize: 'var(--fs-meta)', color: 'var(--muted-foreground)', marginTop: 2 }}>
                      {meta?.label || inst.type}
                      {inst.host && ` · ${inst.host}${inst.port ? `:${inst.port}` : ''}`}
                      {inst.lastError && <span style={{ color: 'oklch(0.55 0.18 25)' }}> · {inst.lastError}</span>}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 6, flexShrink: 0 }}>
                    <button data-testid="button-check-health" disabled={healthM.isPending} style={btn('outline')} onClick={() => healthM.mutate(inst.id)}>
                      {healthM.isPending ? 'Checking…' : 'Check'}
                    </button>
                    <button data-testid="button-delete-instrument" disabled={deleteM.isPending} style={btn('ghost')} onClick={() => deleteM.mutate(inst.id)}>Remove</button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>
    </div>
  );
}
