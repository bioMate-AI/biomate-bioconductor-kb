/**
 * AfterRunReport — 7-tab inline after-run panel for the v2 workflow surface.
 *
 * Tabs (per A3 audit recommendation, docs/20260528_AFTERRUN_FINDINGS.md):
 *   Findings    — always shown (AI-fallback covers every workflow)
 *   Outputs     — always shown (step file list)
 *   Methods     — shown when /api/invocations/:id/methods-report returns
 *                 a non-stub report (i.e. tool_versions or methods_text present)
 *   Parameters  — always shown
 *   Software    — "Coming soon" placeholder for v0; v1 will read
 *                 pipeline_info/software_versions.yml (~98% catalog)
 *   Citations   — shown when /api/workflows/:name/citations returns ≥1 entry
 *                 (cryo-EM RAG + qc_evidence.yaml gate DOIs)
 *   QC audit    — shown when /api/workflows/runs/:id/qc-events returns ≥1 event
 *
 * Hides empty tabs entirely rather than showing placeholders — per audit,
 * placeholders read as "this product is unfinished".
 */
import React, { useEffect, useMemo, useState } from "react";
import { FindingsCard } from "@/components/findings-card";

interface AfterRunReportProps {
  runId: string;
  invocationId?: string;       // backend Galaxy/Nextflow invocation id (for /qc-events)
  workflowName?: string;
  parameters?: Record<string, unknown>;
  /** Pre-fetched outputs from the parent's executionRun state — preferred
   *  over a separate /steps fetch which doesn't exist as an endpoint. */
  outputs?: OutputFile[];
  /** Run state for the failure section + Outputs header directory link. */
  executionStatus?: string;
  errorMessage?: string;
  nextflowOutputDir?: string;
  logTail?: string[];
  failedSteps?: string[];
  /** Inline autofix summary from currentRun.execution.nextflowStatus.autofix —
   *  if state === 'failed' here, the run only "failed" after exhausting fix
   *  attempts; the FailedRunSection should make that visible. */
  autofix?: {
    state?: 'idle' | 'analyzing' | 'fixing' | 'restarting' | 'succeeded' | 'failed';
    source?: 'auto' | 'manual' | 'unknown';
    active?: boolean;
    message?: string;
    totalAttempts?: number;
  };
  onContinueAnalysis?: (suggestion: string) => void;
}

type TabId = "findings" | "outputs" | "methods" | "params" | "qc";
// "software" + "citations" will rejoin once their backend routes exist.

interface OutputFile {
  step: string;
  name: string;
  path: string;
  ext: string;
}

export function AfterRunReport({
  runId,
  invocationId,
  workflowName,
  parameters,
  outputs: outputsProp,
  executionStatus,
  errorMessage,
  nextflowOutputDir,
  logTail,
  failedSteps,
  autofix,
  onContinueAnalysis,
}: AfterRunReportProps) {
  const isFailed = executionStatus === "failed" || executionStatus === "cancelled" || executionStatus === "error";
  const [tab, setTab] = useState<TabId>("findings");

  // Outputs come from the parent's executionRun state (no /steps endpoint exists).
  const outputs = outputsProp ?? [];
  // Methods + QC events keyed off invocationId (the backend Nextflow id), falling back to runId.
  const idForBackend = invocationId || runId;
  const methods = useFetchMethods(idForBackend);
  const qcEvents = useFetchQcEvents(idForBackend);
  // Findings fetched here too (alongside FindingsCard's own fetch) so the
  // comprehensive download report can inline real findings prose (PM must-fix #2).
  const findings = useFetchFindings(runId);
  // workflowName param kept for future Citations tab; suppress unused-var warning.
  void workflowName;

  // Lightweight download-UX state — keeps users from double-clicking and
  // gives a clear "started" signal (PM must-fix #4, client-side portion).
  const [downloadState, setDownloadState] = useState<'idle' | 'preparing'>('idle');
  const [downloadToast, setDownloadToast] = useState<string | null>(null);

  // Compute which optional tabs to show based on real data presence.
  // Software + Citations intentionally hidden until their backend routes ship
  // (per A3 audit + user direction 2026-05-29). Re-enable by appending:
  //   t.push(["software", "Software"]);          // needs /api/invocations/:id/software
  //   if (citations.length > 0) t.push([...]);   // needs /api/workflows/:name/citations
  const visibleTabs = useMemo<Array<[TabId, string]>>(() => {
    const t: Array<[TabId, string]> = [
      ["findings", "Findings"],
      ["outputs", "Outputs"],
    ];
    if (methods.hasRealContent) t.push(["methods", "Methods"]);
    t.push(["params", "Parameters"]);
    if (qcEvents.length > 0) t.push(["qc", "QC audit"]);
    return t;
  }, [methods.hasRealContent, qcEvents.length]);

  const handleDownload = () => {
    if (downloadState !== 'idle') return; // dedup double-click
    setDownloadState('preparing');
    const md = buildFullReportMarkdown({
      runId,
      workflowName,
      parameters,
      outputs,
      methods: methods.text,
      qcEvents,
      findings,
    });
    const blob = new Blob([md], { type: "text/markdown;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `biomate-run-${runId}.md`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    setDownloadToast('Report downloaded — check your browser');
    setTimeout(() => setDownloadState('idle'), 2000);
    setTimeout(() => setDownloadToast(null), 4000);
  };

  return (
    <div className="after-run-report" style={styles.root}>
      <div style={styles.head}>
        <span style={styles.kicker}>After run</span>
        <span style={{ flex: 1 }} />
        {downloadToast && (
          <span style={styles.toast} role="status">{downloadToast}</span>
        )}
        <button
          type="button"
          onClick={handleDownload}
          disabled={downloadState !== 'idle'}
          style={{
            ...styles.linkish,
            background: "none",
            border: "none",
            cursor: downloadState === 'idle' ? "pointer" : "default",
            padding: 0,
            opacity: downloadState === 'idle' ? 1 : 0.6,
          }}
          title="Download a comprehensive markdown report stitching every tab"
          data-testid="afterrun-download-report"
        >
          ↓ {downloadState === 'preparing' ? 'Preparing…' : 'Download report'}
        </button>
      </div>

      {/* PM must-fix #1: failed-run section above the tab bar. Shown for
          failed / cancelled runs so users get error context + a path forward
          (Run again) without having to read every tab. */}
      {isFailed && (
        <FailedRunSection
          status={executionStatus || 'failed'}
          errorMessage={errorMessage}
          failedSteps={failedSteps}
          logTail={logTail}
          autofix={autofix}
          invocationId={invocationId}
          runId={runId}
          parameters={parameters}
        />
      )}
      <div role="tablist" style={styles.tabBar}>
        {visibleTabs.map(([id, label]) => (
          <button
            key={id}
            role="tab"
            aria-selected={tab === id}
            onClick={() => setTab(id)}
            data-testid={`after-tab-${id}`}
            style={{
              ...styles.tab,
              ...(tab === id ? styles.tabActive : null),
            }}
          >
            {label}
          </button>
        ))}
      </div>
      <div style={styles.body}>
        {tab === "findings" && (
          <FindingsCard runId={runId} onContinueAnalysis={onContinueAnalysis} />
        )}
        {tab === "outputs" && <OutputsTab outputs={outputs} runId={runId} invocationId={invocationId} />}
        {tab === "methods" && <MethodsTab methods={methods} />}
        {tab === "params" && <ParametersTab parameters={parameters} runId={runId} />}
        {tab === "qc" && <QcAuditTab events={qcEvents} />}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// FailedRunSection — shown above the tab bar when execution status is
// 'failed' or 'cancelled'. Surfaces the offending step, error message, and
// log tail, plus a Run-again-with-edits CTA that fires a CustomEvent.
// ---------------------------------------------------------------------------

interface AutofixSummary {
  state?: 'idle' | 'analyzing' | 'fixing' | 'restarting' | 'succeeded' | 'failed';
  source?: 'auto' | 'manual' | 'unknown';
  active?: boolean;
  message?: string;
  totalAttempts?: number;
}

function FailedRunSection({
  status,
  errorMessage,
  failedSteps,
  logTail,
  autofix,
  invocationId,
  runId,
  parameters,
}: {
  status: string;
  errorMessage?: string;
  failedSteps?: string[];
  logTail?: string[];
  autofix?: AutofixSummary;
  invocationId?: string;
  runId: string;
  parameters?: Record<string, unknown>;
}) {
  const cancelled = status === 'cancelled';
  const tail = (logTail || []).slice(-20);
  const totalLines = logTail?.length || 0;

  // Detailed per-attempt history (lazy-fetched only when user expands).
  const [historyOpen, setHistoryOpen] = useState(false);
  const [history, setHistory] = useState<any[] | null>(null);
  useEffect(() => {
    if (!historyOpen || history !== null || !invocationId) return;
    fetch(`/api/galaxy/workflows/_/invocations/${invocationId}/autofix3/sessions`, { credentials: 'include' })
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        if (!d) return;
        const arr = Array.isArray(d) ? d : (d.sessions || d.attempts || []);
        setHistory(arr);
      })
      .catch(() => setHistory([]));
  }, [historyOpen, history, invocationId]);

  const autofixTried = !!(autofix && (autofix.totalAttempts || (autofix.state && autofix.state !== 'idle')));
  const autofixExhausted = autofix?.state === 'failed' && (autofix.totalAttempts || 0) > 0;

  const handleRunAgain = () => {
    // PM must-fix #3 — explicit CTA. Wire-up to the existing run-again-with-
    // edits flow is a follow-up; for now we surface a CustomEvent that
    // chat-with-artifacts can listen for, plus a temporary visible signal.
    window.dispatchEvent(
      new CustomEvent('biomate:run-again-with-edits', {
        detail: { runId, parameters },
      }),
    );
    // eslint-disable-next-line no-console
    console.info('[AfterRunReport] run-again-with-edits dispatched for run', runId);
    alert('Run again with edits — opening the parameter editor (wire-up pending)');
  };

  return (
    <div style={styles.failedSection} data-testid="afterrun-failed-section">
      <div style={styles.failedHead}>
        <span
          style={{
            ...styles.failedBadge,
            background: cancelled ? 'oklch(0.85 0.01 240)' : 'oklch(0.92 0.05 25)',
            color: cancelled ? 'oklch(0.30 0.01 260)' : 'oklch(0.40 0.18 25)',
          }}
        >
          {cancelled ? 'Run cancelled' : 'Run failed'}
        </span>
        <button
          type="button"
          onClick={handleRunAgain}
          style={styles.runAgainBtn}
          data-testid="afterrun-run-again-failed"
        >
          ↻ Run again with edits
        </button>
      </div>

      {/* Autofix narrative — most informative signal first. Distinguishes
          "failed after 15 fix attempts" (autofix exhausted) from "failed on
          first attempt with no autofix run" (autofix never ran). */}
      {autofixTried && (
        <div style={styles.autofixBox} data-testid="afterrun-autofix-summary">
          <div style={styles.autofixHead}>
            <span style={styles.autofixLabel}>Auto-fix</span>
            <span style={{
              ...styles.autofixState,
              color: autofix?.state === 'failed' ? 'oklch(0.40 0.18 25)'
                   : autofix?.state === 'succeeded' ? 'oklch(0.35 0.13 145)'
                   : 'oklch(0.40 0.12 245)',
            }}>
              {autofix?.state ?? 'unknown'}
            </span>
            {(autofix?.totalAttempts ?? 0) > 0 && (
              <span style={styles.autofixAttempts}>
                {autofix?.totalAttempts} attempt{(autofix?.totalAttempts ?? 0) === 1 ? '' : 's'}
              </span>
            )}
          </div>
          {autofixExhausted ? (
            <p style={styles.autofixMsg}>
              BioMate auto-fix tried <strong>{autofix?.totalAttempts}</strong> remediation{(autofix?.totalAttempts ?? 0) === 1 ? '' : 's'} and could not recover the run. See the underlying error and log tail below for the final failure.
            </p>
          ) : autofix?.state === 'succeeded' ? (
            <p style={styles.autofixMsg}>
              Auto-fix recovered the run after {autofix.totalAttempts ?? 0} attempt(s). This is unusual if you're seeing this section — the run should be marked completed.
            </p>
          ) : autofix?.message ? (
            <p style={styles.autofixMsg}>{autofix.message}</p>
          ) : null}
          {invocationId && (
            <button
              type="button"
              onClick={() => setHistoryOpen((v) => !v)}
              style={styles.autofixToggle}
              data-testid="afterrun-autofix-toggle"
            >
              {historyOpen ? '▾ Hide attempt history' : '▸ Show attempt history'}
            </button>
          )}
          {historyOpen && (
            <div style={{ marginTop: 6 }}>
              {history === null ? (
                <span style={styles.empty}>Loading attempts…</span>
              ) : history.length === 0 ? (
                <span style={styles.empty}>No detailed attempt history recorded.</span>
              ) : (
                <ol style={styles.autofixHistList}>
                  {history.map((h: any, i: number) => (
                    <li key={i} style={styles.autofixHistItem}>
                      <strong>#{(h.attempt ?? i + 1)}</strong>
                      {h.issue_type && <span> · {h.issue_type}</span>}
                      {h.fix_summary && <span> — {h.fix_summary}</span>}
                      {h.result && <span style={{ marginLeft: 6, opacity: 0.7 }}>[{h.result}]</span>}
                    </li>
                  ))}
                </ol>
              )}
            </div>
          )}
        </div>
      )}

      {errorMessage && (
        <pre style={styles.errorBlock} data-testid="afterrun-error-message">
          {errorMessage}
        </pre>
      )}

      {failedSteps && failedSteps.length > 0 && (
        <div style={styles.failedStepBox}>
          <div style={styles.failedStepLabel}>Failed step(s)</div>
          <ul style={styles.failedStepList}>
            {failedSteps.map((s, i) => (
              <li key={i} style={styles.failedStepItem}>{s}</li>
            ))}
          </ul>
        </div>
      )}

      {tail.length > 0 && (
        <div style={{ marginTop: 8 }}>
          <div style={styles.failedStepLabel}>
            Log tail {totalLines > tail.length ? `(showing last ${tail.length} of ${totalLines})` : `(${tail.length} lines)`}
          </div>
          <pre style={styles.logTailBlock}>{tail.join('\n')}</pre>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Data hooks — each tab fetches its own endpoint, gracefully tolerating 404s.
// ---------------------------------------------------------------------------

interface FindingsKeyResult {
  // Backend findings endpoint uses `metric` (canonical name) + `value` +
  // `interpretation` (one-sentence context). Older clients sometimes used
  // `label`; keep the alias for back-compat.
  metric?: string;
  label?: string;
  value?: string;
  interpretation?: string;
}

interface FindingsData {
  status: string;
  summary?: string;
  key_results?: Array<FindingsKeyResult | string>;
  caveats?: string[];
  next_steps?: string[];
  reportMd?: string;
}

function useFetchFindings(runId: string): FindingsData | null {
  const [data, setData] = useState<FindingsData | null>(null);
  useEffect(() => {
    if (!runId) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const start = Date.now();
    const poll = async () => {
      try {
        const r = await fetch(`/api/workflows/runs/${runId}/findings`, { credentials: "include" });
        if (!r.ok || cancelled) return;
        const j: FindingsData = await r.json();
        if (cancelled) return;
        setData(j);
        if (j.status === "pending" && Date.now() - start < 60_000) {
          timer = setTimeout(poll, 5000);
        }
      } catch { /* ignore */ }
    };
    poll();
    return () => { cancelled = true; if (timer) clearTimeout(timer); };
  }, [runId]);
  return data;
}

interface MethodsData {
  text: string;
  toolVersions: Record<string, string>;
  hasRealContent: boolean;
}

function useFetchMethods(invocationId: string): MethodsData {
  const [data, setData] = useState<MethodsData>({ text: "", toolVersions: {}, hasRealContent: false });
  useEffect(() => {
    if (!invocationId) return;
    let cancelled = false;
    fetch(`/api/invocations/${invocationId}/methods-report`, { credentials: "include" })
      .then((r) => (r.ok ? r.text() : ""))
      .then((text) => {
        if (cancelled) return;
        // Stub detector: per A3 audit, the local fallback writes 5 lines
        // ending with "No QC events recorded for this invocation."
        const isStub = !text || /No QC events recorded/.test(text) || text.length < 200;
        setData({ text, toolVersions: {}, hasRealContent: !isStub });
      })
      .catch(() => { /* ignore */ });
    return () => { cancelled = true; };
  }, [invocationId]);
  return data;
}

// Citations tab is commented out until /api/workflows/:name/citations
// backend route ships. Restoration template kept inline near the visibleTabs
// builder for re-enabling later.

interface QcEvent {
  ts?: string;
  gate?: string;
  status?: string;
  message?: string;
  measured?: string | number;
  threshold?: string | number;
}

function useFetchQcEvents(invocationId: string): QcEvent[] {
  const [events, setEvents] = useState<QcEvent[]>([]);
  useEffect(() => {
    if (!invocationId) return;
    let cancelled = false;
    // Backend route lives at /api/invocations/:id/qc-events (nextflow_executor.py:4478)
    fetch(`/api/invocations/${invocationId}/qc-events`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        const arr = Array.isArray(data) ? data : data.events || [];
        setEvents(arr);
      })
      .catch(() => { /* not all workflows emit QC; tab simply hides */ });
    return () => { cancelled = true; };
  }, [invocationId]);
  return events;
}

// ---------------------------------------------------------------------------
// Tab body components
// ---------------------------------------------------------------------------

function OutputsTab({
  outputs,
  runId,
  invocationId,
}: { outputs: OutputFile[]; runId: string; invocationId?: string }) {
  // Total size summary (when present in the output records)
  const totalCount = outputs.length;
  const dlAllUrl = invocationId ? `/api/invocations/${invocationId}/download-all` : null;
  const reproUrl = `/api/nextflow/runs/${runId}/reproducibility`;

  if (totalCount === 0) {
    return (
      <div style={styles.tabContent}>
        <p style={styles.empty}>No output files registered yet.</p>
        {/* Bulk-download actions still visible so the user can pull a partial bundle. */}
        <div style={styles.bulkActions}>
          {dlAllUrl && (
            <a href={dlAllUrl} download style={styles.bulkBtn} data-testid="afterrun-download-all">
              ↓ Download all as ZIP
            </a>
          )}
          <a href={reproUrl} download style={{ ...styles.bulkBtn, ...styles.bulkBtnSecondary }}>
            ↓ Reproducibility bundle
          </a>
        </div>
      </div>
    );
  }

  const byStep = outputs.reduce<Record<string, OutputFile[]>>((acc, o) => {
    (acc[o.step] = acc[o.step] || []).push(o);
    return acc;
  }, {});

  return (
    <div style={styles.tabContent}>
      {/* Bulk-download actions — for intermediate / large outputs where
          per-file preview isn't useful, the user grabs everything as a
          ZIP and inspects locally. */}
      <div style={styles.bulkActions}>
        {dlAllUrl && (
          <a href={dlAllUrl} download style={styles.bulkBtn} data-testid="afterrun-download-all">
            ↓ Download all ({totalCount}) as ZIP
          </a>
        )}
        <a
          href={reproUrl}
          download
          style={{ ...styles.bulkBtn, ...styles.bulkBtnSecondary }}
          title="Configs, command scripts, logs, versions.yml — enough to re-run elsewhere"
        >
          ↓ Reproducibility bundle
        </a>
      </div>

      {Object.entries(byStep).map(([step, files]) => (
        <div key={step} style={{ marginBottom: 12 }}>
          <div style={styles.outputStep}>{step}</div>
          <ul style={styles.outputList}>
            {files.map((f) => {
              const fileUrl = `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(f.path || f.name)}&download=1`;
              return (
                <li key={f.path || f.name} style={styles.outputItem}>
                  <a
                    href={fileUrl}
                    download
                    style={{ ...styles.outputName, textDecoration: 'none', color: 'inherit' }}
                    title={`Download ${f.name}`}
                  >
                    {f.name}
                  </a>
                  <span style={styles.outputExt}>{f.ext}</span>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </div>
  );
}

function MethodsTab({ methods }: { methods: MethodsData }) {
  if (!methods.hasRealContent) {
    return <p style={styles.empty}>Methods report not available for this workflow.</p>;
  }
  return (
    <pre style={styles.methodsBody}>{methods.text}</pre>
  );
}

function ParametersTab({
  parameters,
  runId,
}: { parameters?: Record<string, unknown>; runId?: string }) {
  const entries = parameters ? Object.entries(parameters) : [];

  // PM must-fix #3: Run-again-with-edits CTA at the top of the tab so iteration
  // is one click away. Fires a CustomEvent that the parent can hook into; v0
  // also surfaces a visible signal so the user knows the click registered.
  const handleRunAgain = () => {
    if (!runId) return;
    window.dispatchEvent(
      new CustomEvent('biomate:run-again-with-edits', {
        detail: { runId, parameters },
      }),
    );
    // eslint-disable-next-line no-console
    console.info('[AfterRunReport] run-again-with-edits dispatched (params tab) for run', runId);
    alert('Run again with edits — opening the parameter editor (wire-up pending)');
  };

  return (
    <div style={styles.tabContent}>
      <div style={{ marginBottom: 10 }}>
        <button
          type="button"
          onClick={handleRunAgain}
          style={styles.runAgainBtn}
          data-testid="afterrun-run-again-params"
        >
          ↻ Run again with edits
        </button>
      </div>
      {entries.length === 0 ? (
        <p style={styles.empty}>No parameter values recorded.</p>
      ) : (
        <table style={styles.kvTable}>
          <tbody>
            {entries.map(([k, v]) => (
              <tr key={k}>
                <td style={styles.kvKey}>{k}</td>
                <td style={styles.kvVal}>{String(v)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

// SoftwareTab + CitationsTab removed for v0 — restore when backend routes
// /api/invocations/:id/software and /api/workflows/:name/citations ship.

function QcAuditTab({ events }: { events: QcEvent[] }) {
  return (
    <div style={styles.tabContent}>
      <table style={styles.qcTable}>
        <thead>
          <tr>
            <th>Time</th>
            <th>Gate</th>
            <th>Status</th>
            <th>Measured</th>
            <th>Threshold</th>
            <th>Message</th>
          </tr>
        </thead>
        <tbody>
          {events.map((e, i) => (
            <tr key={i}>
              <td style={styles.qcCell}>{e.ts ?? ""}</td>
              <td style={styles.qcCell}>{e.gate ?? ""}</td>
              <td style={{ ...styles.qcCell, color: qcStatusColor(e.status) }}>{e.status ?? ""}</td>
              <td style={styles.qcCell}>{e.measured ?? ""}</td>
              <td style={styles.qcCell}>{e.threshold ?? ""}</td>
              <td style={styles.qcCell}>{e.message ?? ""}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * Build a comprehensive markdown report stitching every visible tab into
 * one document. Lives client-side so no new backend route is needed for v0.
 * Future: add a server-side DOCX/PDF generator and switch the download
 * button to call it.
 */
function buildFullReportMarkdown(args: {
  runId: string;
  workflowName?: string;
  parameters?: Record<string, unknown>;
  outputs: OutputFile[];
  methods: string;
  qcEvents: QcEvent[];
  findings?: FindingsData | null;
}): string {
  const { runId, workflowName, parameters, outputs, methods, qcEvents, findings } = args;
  const lines: string[] = [];
  lines.push(`# BioMate Run Report`);
  lines.push("");
  lines.push(`- **Run ID**: \`${runId}\``);
  if (workflowName) lines.push(`- **Workflow**: ${workflowName}`);
  lines.push(`- **Generated**: ${new Date().toISOString()}`);
  lines.push("");

  // Findings — inlined from useFetchFindings (PM must-fix #2). Falls back to a
  // pending notice if the AI analysis hasn't completed yet at click time.
  lines.push(`## Findings`);
  lines.push("");
  if (!findings || findings.status === "pending" || !findings.summary) {
    lines.push(`_Findings analysis is still pending. Re-download in a minute to_`);
    lines.push(`_capture the structured AI summary, key results, caveats, and next steps._`);
    lines.push("");
  } else {
    if (findings.summary) {
      lines.push(`### Summary`);
      lines.push("");
      lines.push(findings.summary);
      lines.push("");
    }
    if (findings.key_results?.length) {
      lines.push(`### Key results`);
      lines.push("");
      for (const k of findings.key_results) {
        if (typeof k === "string") {
          lines.push(`- ${k}`);
        } else {
          // Backend uses `metric`; older payloads used `label`. Fall back gracefully.
          const name = k.metric ?? k.label ?? "(unnamed)";
          const val = k.value ?? "";
          const interp = k.interpretation ? `  \n    _${k.interpretation}_` : "";
          lines.push(`- **${name}**: ${val}${interp}`);
        }
      }
      lines.push("");
    }
    if (findings.caveats?.length) {
      lines.push(`### Caveats`);
      lines.push("");
      for (const c of findings.caveats) lines.push(`- ${c}`);
      lines.push("");
    }
    if (findings.next_steps?.length) {
      lines.push(`### Recommended next steps`);
      lines.push("");
      for (const n of findings.next_steps) lines.push(`- ${n}`);
      lines.push("");
    }
  }

  // Outputs
  lines.push(`## Outputs`);
  lines.push("");
  if (outputs.length === 0) {
    lines.push(`_No output files registered for this run._`);
  } else {
    const byStep: Record<string, OutputFile[]> = {};
    for (const o of outputs) (byStep[o.step] = byStep[o.step] || []).push(o);
    for (const [step, files] of Object.entries(byStep)) {
      lines.push(`### ${step || "(unspecified step)"}`);
      lines.push("");
      lines.push(`| File | Type |`);
      lines.push(`|------|------|`);
      for (const f of files) lines.push(`| ${f.name} | ${f.ext || "—"} |`);
      lines.push("");
    }
  }

  // Methods
  if (methods && methods.trim()) {
    lines.push(`## Methods`);
    lines.push("");
    lines.push("```");
    lines.push(methods.trim());
    lines.push("```");
    lines.push("");
  }

  // Parameters
  lines.push(`## Parameters`);
  lines.push("");
  const params = parameters ? Object.entries(parameters) : [];
  if (params.length === 0) {
    lines.push(`_No parameter values recorded._`);
  } else {
    lines.push(`| Parameter | Value |`);
    lines.push(`|-----------|-------|`);
    for (const [k, v] of params) lines.push(`| \`${k}\` | ${String(v)} |`);
  }
  lines.push("");

  // QC audit
  if (qcEvents.length > 0) {
    lines.push(`## QC Audit`);
    lines.push("");
    lines.push(`| Time | Gate | Status | Measured | Threshold | Message |`);
    lines.push(`|------|------|--------|----------|-----------|---------|`);
    for (const e of qcEvents) {
      lines.push(
        `| ${e.ts ?? ""} | ${e.gate ?? ""} | ${e.status ?? ""} | ${e.measured ?? ""} | ${e.threshold ?? ""} | ${(e.message ?? "").replace(/\|/g, "\\|")} |`,
      );
    }
    lines.push("");
  }

  lines.push(`---`);
  lines.push(`_Generated by BioMate AfterRunReport (v2 preview). Software`);
  lines.push(`versions and citation tabs will appear once their backend routes`);
  lines.push(`ship — see docs/20260528_AFTERRUN_FINDINGS.md._`);

  return lines.join("\n");
}

function qcStatusColor(status: string | undefined): string {
  if (!status) return "inherit";
  if (/pass|ok|advis/i.test(status)) return "oklch(0.55 0.13 145)";
  if (/halt|fail|block/i.test(status)) return "oklch(0.55 0.18 25)";
  return "inherit";
}

// ---------------------------------------------------------------------------
// Inline styles — kept local so this component doesn't depend on v2 CSS tokens
// (which are scoped to [data-v2-ui]). Lets us mount AfterRunReport anywhere.
// ---------------------------------------------------------------------------

const styles: Record<string, React.CSSProperties> = {
  root: { display: "flex", flexDirection: "column", gap: 8, padding: 12 },
  head: { display: "flex", alignItems: "center", gap: 8 },
  kicker: { fontSize: 10.5, textTransform: "uppercase", letterSpacing: "0.07em", color: "oklch(0.48 0.012 260)", fontWeight: 600 },
  linkish: { fontSize: 11.5, color: "oklch(0.55 0.14 245)", textDecoration: "none", display: "inline-flex", alignItems: "center", gap: 4 },
  tabBar: { display: "flex", gap: 4, borderBottom: "1px solid oklch(0.92 0.005 240)" },
  tab: { background: "transparent", border: "none", padding: "8px 12px", fontSize: 12.5, color: "oklch(0.48 0.012 260)", cursor: "pointer", borderBottom: "2px solid transparent", marginBottom: -1 },
  tabActive: { color: "oklch(0.22 0.01 260)", borderBottomColor: "oklch(0.55 0.14 245)", fontWeight: 500 },
  body: { paddingTop: 8 },
  empty: { fontSize: 12, color: "oklch(0.48 0.012 260)", fontStyle: "italic", padding: "16px 4px" },
  tabContent: { fontSize: 12.5 },
  bulkActions: { display: "flex", gap: 8, marginBottom: 12, flexWrap: "wrap" as React.CSSProperties["flexWrap"] },
  bulkBtn: { display: "inline-flex", alignItems: "center", gap: 6, padding: "6px 12px", fontSize: 12, color: "white", background: "oklch(0.55 0.14 245)", borderRadius: 6, textDecoration: "none", cursor: "pointer" },
  bulkBtnSecondary: { background: "oklch(0.93 0.01 240)", color: "oklch(0.22 0.01 260)" },
  outputStep: { fontSize: 11, fontWeight: 600, color: "oklch(0.35 0.01 260)", marginBottom: 4, textTransform: "uppercase", letterSpacing: "0.04em" },
  outputList: { listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 3 },
  outputItem: { display: "flex", justifyContent: "space-between", padding: "4px 8px", background: "oklch(0.98 0.003 240)", borderRadius: 4 },
  outputName: { fontFamily: "JetBrains Mono, ui-monospace, monospace", fontSize: 11.5, color: "oklch(0.22 0.01 260)" },
  outputExt: { fontSize: 10, color: "oklch(0.48 0.012 260)", textTransform: "uppercase" },
  methodsBody: { fontSize: 11.5, fontFamily: "ui-monospace, monospace", background: "oklch(0.97 0.003 240)", padding: 12, borderRadius: 6, whiteSpace: "pre-wrap", maxHeight: 480, overflowY: "auto" },
  kvTable: { width: "100%", borderCollapse: "collapse" as React.CSSProperties["borderCollapse"] },
  kvKey: { padding: "4px 8px", fontSize: 11.5, fontWeight: 500, color: "oklch(0.35 0.01 260)", verticalAlign: "top", whiteSpace: "nowrap" },
  kvVal: { padding: "4px 8px", fontSize: 11.5, fontFamily: "ui-monospace, monospace", color: "oklch(0.22 0.01 260)", wordBreak: "break-all" },
  comingSoon: { fontSize: 12, color: "oklch(0.48 0.012 260)", padding: 16, background: "oklch(0.98 0.003 240)", borderRadius: 6, lineHeight: 1.5 },
  citationsList: { listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 6 },
  citationItem: { padding: "6px 8px", fontSize: 11.5, background: "oklch(0.98 0.003 240)", borderRadius: 4 },
  citationDoi: { color: "oklch(0.48 0.012 260)", fontFamily: "ui-monospace, monospace" },
  qcTable: { width: "100%", borderCollapse: "collapse" as React.CSSProperties["borderCollapse"], fontSize: 11 },
  qcCell: { padding: "4px 6px", borderBottom: "1px solid oklch(0.93 0.005 240)", textAlign: "left", verticalAlign: "top" },

  // Failed-run section styles (PM must-fix #1)
  failedSection: { padding: "10px 12px", margin: "0 0 8px", background: "oklch(0.98 0.018 25)", borderRadius: 6, border: "1px solid oklch(0.88 0.04 25)" },
  failedHead: { display: "flex", alignItems: "center", gap: 8, marginBottom: 6 },
  failedBadge: { padding: "3px 9px", fontSize: 11, fontWeight: 600, borderRadius: 999, textTransform: "uppercase", letterSpacing: "0.04em" },
  runAgainBtn: { marginLeft: "auto", padding: "6px 12px", fontSize: 12, fontWeight: 500, background: "oklch(0.55 0.14 245)", color: "white", border: "none", borderRadius: 6, cursor: "pointer" },
  errorBlock: { fontSize: 11.5, fontFamily: "ui-monospace, monospace", background: "white", color: "oklch(0.40 0.18 25)", padding: 8, borderRadius: 4, whiteSpace: "pre-wrap", margin: "6px 0", border: "1px solid oklch(0.92 0.04 25)" },
  failedStepBox: { marginTop: 6 },
  failedStepLabel: { fontSize: 10.5, textTransform: "uppercase", letterSpacing: "0.05em", color: "oklch(0.48 0.012 260)", marginBottom: 4, fontWeight: 600 },
  failedStepList: { listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column", gap: 3 },
  failedStepItem: { fontSize: 12, fontFamily: "ui-monospace, monospace", padding: "3px 8px", background: "white", borderRadius: 4, color: "oklch(0.22 0.01 260)" },
  logTailBlock: { fontSize: 11, fontFamily: "ui-monospace, monospace", background: "oklch(0.18 0.01 260)", color: "oklch(0.92 0.005 240)", padding: 10, borderRadius: 6, whiteSpace: "pre-wrap", maxHeight: 200, overflowY: "auto", margin: 0 },

  // Autofix narrative (inside FailedRunSection)
  autofixBox: { padding: "8px 10px", margin: "0 0 8px", background: "white", borderRadius: 6, border: "1px solid oklch(0.92 0.04 245)" },
  autofixHead: { display: "flex", alignItems: "center", gap: 8, marginBottom: 4 },
  autofixLabel: { fontSize: 10.5, textTransform: "uppercase", letterSpacing: "0.05em", color: "oklch(0.48 0.012 260)", fontWeight: 700 },
  autofixState: { fontSize: 11.5, fontWeight: 600, padding: "2px 8px", borderRadius: 999, background: "oklch(0.96 0.012 260)" },
  autofixAttempts: { fontSize: 11, color: "oklch(0.48 0.012 260)", marginLeft: "auto" },
  autofixMsg: { fontSize: 12.5, margin: "4px 0 6px", lineHeight: 1.45, color: "oklch(0.30 0.01 260)" },
  autofixToggle: { fontSize: 11, border: "none", background: "transparent", color: "oklch(0.40 0.12 245)", cursor: "pointer", padding: 0 },
  autofixHistList: { listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 3 },
  autofixHistItem: { fontSize: 11.5, fontFamily: "ui-monospace, monospace", padding: "3px 8px", background: "oklch(0.98 0.005 260)", borderRadius: 4 },

  // Download-UX toast (PM must-fix #4)
  toast: { fontSize: 11, padding: "3px 8px", background: "oklch(0.92 0.04 145)", color: "oklch(0.30 0.13 145)", borderRadius: 12, marginRight: 8 },
};
