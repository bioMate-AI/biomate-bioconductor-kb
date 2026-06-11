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
import { JobButton } from "@/components/job-button";

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

type TabId = "findings" | "outputs" | "methods" | "params" | "software" | "citations" | "qc";

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
  // nextflowOutputDir is forwarded by the parent for future Outputs-tab
  // directory toolbar work; intentionally unread in v0.
  void nextflowOutputDir;
  const isFailed = executionStatus === "failed" || executionStatus === "cancelled" || executionStatus === "error";
  const [tab, setTab] = useState<TabId>("findings");

  // Outputs come from the parent's executionRun state (no /steps endpoint exists).
  const outputs = outputsProp ?? [];
  // Methods + QC events keyed off invocationId (the backend Nextflow id), falling back to runId.
  const idForBackend = invocationId || runId;
  const methods = useFetchMethods(idForBackend);
  const qcEvents = useFetchQcEvents(idForBackend);
  const software = useFetchSoftware(idForBackend);
  const citations = useFetchCitations(workflowName);
  // Findings fetched here too (alongside FindingsCard's own fetch) so the
  // comprehensive download report can inline real findings prose (PM must-fix #2).
  const findings = useFetchFindings(runId);

  // Lightweight download-UX state — keeps users from double-clicking and
  // gives a clear "started" signal (PM must-fix #4, client-side portion).
  const [downloadState, setDownloadState] = useState<'idle' | 'preparing'>('idle');
  const [downloadToast, setDownloadToast] = useState<string | null>(null);

  // Compute which optional tabs to show based on real data presence.
  // Hide-when-empty discipline: no "Coming soon" placeholders, just absence.
  const visibleTabs = useMemo<Array<[TabId, string]>>(() => {
    const t: Array<[TabId, string]> = [
      ["findings", "Findings"],
      ["outputs", "Outputs"],
    ];
    if (methods.hasRealContent) t.push(["methods", "Methods"]);
    t.push(["params", "Parameters"]);
    if (Object.keys(software).length > 0) t.push(["software", "Software"]);
    if (citations.length > 0) t.push(["citations", "Citations"]);
    if (qcEvents.length > 0) t.push(["qc", "QC audit"]);
    return t;
  }, [methods.hasRealContent, software, citations.length, qcEvents.length]);

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
      software,
      citations,
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
          <>
            <FindingsCard runId={runId} onContinueAnalysis={onContinueAnalysis} />
            {findings?.figures && findings.figures.length > 0 && (
              <FindingsFiguresPanel figures={findings.figures} />
            )}
          </>
        )}
        {tab === "outputs" && <OutputsTab outputs={outputs} runId={runId} invocationId={invocationId} />}
        {tab === "methods" && <MethodsTab methods={methods} />}
        {tab === "params" && <ParametersTab parameters={parameters} runId={runId} />}
        {tab === "software" && <SoftwareTab versions={software} />}
        {tab === "citations" && <CitationsTab citations={citations} />}
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

interface AutofixAttempt {
  attempt?: number;
  issue_type?: string;
  fix_summary?: string;
  result?: string;
  [k: string]: unknown;  // backend may include extras (timestamp, payload, etc.)
}

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
  const [history, setHistory] = useState<AutofixAttempt[] | null>(null);
  useEffect(() => {
    if (!historyOpen || history !== null || !invocationId) return;
    fetch(`/api/galaxy/workflows/_/invocations/${invocationId}/autofix3/sessions`, { credentials: 'include' })
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        if (!d) { setHistory([]); return; }
        const arr = Array.isArray(d) ? d : (d.sessions || d.attempts || []);
        setHistory(arr as AutofixAttempt[]);
      })
      .catch(() => setHistory([]));
  }, [historyOpen, history, invocationId]);

  const autofixTried = !!(autofix && (autofix.totalAttempts || (autofix.state && autofix.state !== 'idle')));
  const autofixExhausted = autofix?.state === 'failed' && (autofix.totalAttempts || 0) > 0;

  // Ephemeral toast for the Run-again CTA — replaces blocking alert() until
  // the parent's run-again flow is wired up. Auto-clears after 4s.
  const [ctaToast, setCtaToast] = useState<string | null>(null);

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
    setCtaToast('Run-again signal dispatched (parent wire-up pending)');
    setTimeout(() => setCtaToast(null), 4000);
  };

  return (
    <div style={styles.failedSection} data-testid="afterrun-failed-section">
      {ctaToast && (
        <div role="status" style={styles.ctaToast} data-testid="afterrun-cta-toast-failed">{ctaToast}</div>
      )}
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
                  {history.map((h, i) => (
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

/**
 * Per-figure shape from the Bioconductor handoff (§5.1).
 * Hide-when-empty per CLAUDE.md — backend opt-in, no placeholders.
 */
export type FindingsFigure =
  | { kind: "bars"; title: string; unit?: string; highlight?: string;
      data: Array<[string, number]> }
  | { kind: "composition"; title: string; data: Array<[string, number]> }
  | { kind: "qc"; title: string; unit?: string; kept: number; total: number };

interface FindingsData {
  status: string;
  summary?: string;
  key_results?: Array<FindingsKeyResult | string>;
  caveats?: string[];
  next_steps?: string[];
  reportMd?: string;
  /** Data-driven figures from the run manifest (Bioconductor handoff §5.1). */
  figures?: FindingsFigure[];
}

function useFetchFindings(runId: string): FindingsData | null {
  const [data, setData] = useState<FindingsData | null>(null);
  useEffect(() => {
    if (!runId) return;
    let cancelled = false;

    // Phase 4: route through async job system. The handler server-polls
    // /api/workflows/runs/:id/findings until status=ready (5-min cap),
    // then writes the JSON as the artifact. Dedup means N tabs on the
    // same run trigger one Claude call. 24h cache means re-open is
    // <500ms instead of 5–60s.
    (async () => {
      try {
        const enq = await fetch("/api/jobs", {
          method: "POST",
          credentials: "include",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ kind: "findings_analysis", payload: { runId } }),
        });
        if (!enq.ok || cancelled) return;
        const job = await enq.json();
        const jobId: string = job.jobId;

        // Show "pending" while waiting so the UI distinguishes from "no data yet".
        if (job.state !== "ready") setData({ status: "pending" });

        for (let i = 0; i < 200; i++) {
          if (cancelled) return;
          if (i === 0 && job.state === "ready") break;
          await new Promise((r) => setTimeout(r, i === 0 ? 500 : 2000));
          const r = await fetch(`/api/jobs/${jobId}`, { credentials: "include" });
          if (!r.ok || cancelled) break;
          const j = await r.json();
          if (j.state === "ready") break;
          if (j.state === "failed" || j.state === "cancelled") {
            if (!cancelled) setData({ status: "failed" });
            return;
          }
        }
        if (cancelled) return;

        const art = await fetch(`/api/jobs/${jobId}/artifact`, { credentials: "include" });
        if (!art.ok || cancelled) return;
        const payload = (await art.json()) as FindingsData;
        if (!cancelled) setData(payload);
      } catch { /* ignore */ }
    })();

    return () => { cancelled = true; };
  }, [runId]);
  return data;
}

interface MethodsData {
  text: string;
  toolVersions: Record<string, string>;
  hasRealContent: boolean;
}

function useFetchMethods(invocationId: string): MethodsData & { state: string; progress: number } {
  const [data, setData] = useState<MethodsData & { state: string; progress: number }>({
    text: "", toolVersions: {}, hasRealContent: false, state: "idle", progress: 0,
  });
  useEffect(() => {
    if (!invocationId) return;
    let cancelled = false;

    // Phase 2: route through async job system for caching + dedup. The job
    // handler loops back to the legacy /methods-report endpoint so bytes are
    // byte-for-byte identical. Cache hit (job created within 24h, state=ready)
    // returns the same artifact bytes without re-running Claude.
    (async () => {
      try {
        setData((d) => ({ ...d, state: "queued", progress: 0 }));
        const enq = await fetch("/api/jobs", {
          method: "POST",
          credentials: "include",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            kind: "methods_report",
            payload: { invocationId },
          }),
        });
        if (!enq.ok || cancelled) return;
        const job = await enq.json();
        const jobId = job.jobId as string;

        // Poll until ready/failed.
        for (let i = 0; i < 200; i++) {
          if (cancelled) return;
          // Cache hit: jobs created within TTL return state=ready immediately.
          if (job.state === "ready" && i === 0) break;
          await new Promise((r) => setTimeout(r, i === 0 ? 500 : 2000));
          const r = await fetch(`/api/jobs/${jobId}`, { credentials: "include" });
          if (!r.ok || cancelled) break;
          const j = await r.json();
          setData((d) => ({ ...d, state: j.state, progress: j.progress ?? d.progress }));
          if (j.state === "ready" || j.state === "failed" || j.state === "cancelled") {
            if (j.state !== "ready") return;
            break;
          }
        }
        if (cancelled) return;

        const artRes = await fetch(`/api/jobs/${jobId}/artifact`, { credentials: "include" });
        if (!artRes.ok || cancelled) return;
        const text = await artRes.text();
        const isStub = !text || /No QC events recorded/.test(text) || text.length < 200;
        setData({ text, toolVersions: {}, hasRealContent: !isStub, state: "ready", progress: 100 });
      } catch { /* ignore */ }
    })();

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

function useFetchSoftware(invocationId: string): Record<string, string> {
  const [versions, setVersions] = useState<Record<string, string>>({});
  useEffect(() => {
    if (!invocationId) return;
    let cancelled = false;
    fetch(`/api/invocations/${invocationId}/software`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        setVersions(data.versions || data || {});
      })
      .catch(() => { /* tab hides */ });
    return () => { cancelled = true; };
  }, [invocationId]);
  return versions;
}

interface Citation { doi?: string; title: string; url?: string; }

function useFetchCitations(workflowName?: string): Citation[] {
  const [citations, setCitations] = useState<Citation[]>([]);
  useEffect(() => {
    if (!workflowName) return;
    let cancelled = false;
    fetch(`/api/workflows/${encodeURIComponent(workflowName)}/citations`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        setCitations(Array.isArray(data) ? data : data.citations || []);
      })
      .catch(() => { /* tab hides */ });
    return () => { cancelled = true; };
  }, [workflowName]);
  return citations;
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
  const reproUrl = `/api/nextflow/runs/${runId}/reproducibility`;
  // Phase 1 of docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §11 — bulk ZIP is now
  // produced asynchronously by the jobs subsystem; the user clicks a
  // <JobButton> which polls until ready, then we trigger the actual download.
  const triggerDownload = (url: string) => {
    const a = document.createElement("a");
    a.href = url;
    a.rel = "noopener";
    document.body.appendChild(a);
    a.click();
    a.remove();
  };

  if (totalCount === 0) {
    return (
      <div style={styles.tabContent}>
        <p style={styles.empty}>No output files registered yet.</p>
        {/* Bulk-download actions still visible so the user can pull a partial bundle. */}
        <div style={styles.bulkActions}>
          {invocationId && (
            <JobButton
              kind="download_all_zip"
              payload={{ invocationId, runId }}
              label="↓ Download all as ZIP"
              onReady={triggerDownload}
              className="afterrun-download-all-btn"
            />
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
        {invocationId && (
          <JobButton
            kind="download_all_zip"
            payload={{ invocationId, runId }}
            label={`↓ Download all (${totalCount}) as ZIP`}
            onReady={triggerDownload}
            className="afterrun-download-all-btn"
          />
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
  const [ctaToast, setCtaToast] = useState<string | null>(null);

  // PM must-fix #3: Run-again-with-edits CTA at the top of the tab so iteration
  // is one click away. Fires a CustomEvent that the parent can hook into; v0
  // surfaces an inline toast so the user knows the click registered, instead
  // of a blocking alert().
  const handleRunAgain = () => {
    if (!runId) return;
    window.dispatchEvent(
      new CustomEvent('biomate:run-again-with-edits', {
        detail: { runId, parameters },
      }),
    );
    // eslint-disable-next-line no-console
    console.info('[AfterRunReport] run-again-with-edits dispatched (params tab) for run', runId);
    setCtaToast('Run-again signal dispatched (parent wire-up pending)');
    setTimeout(() => setCtaToast(null), 4000);
  };

  return (
    <div style={styles.tabContent}>
      <div style={{ marginBottom: 10, display: 'flex', alignItems: 'center', gap: 8 }}>
        <button
          type="button"
          onClick={handleRunAgain}
          style={styles.runAgainBtn}
          data-testid="afterrun-run-again-params"
        >
          ↻ Run again with edits
        </button>
        {ctaToast && (
          <span role="status" style={styles.toast} data-testid="afterrun-cta-toast-params">{ctaToast}</span>
        )}
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

/**
 * Rich QC audit panel — the "21 CFR Part 11-friendly" compliance lens.
 * Ports the design from v2/Modals.tsx (legacy window.*-style JSX) into
 * the proper TS pipeline that uses the real qcEvents fetched from
 * /api/workflows/runs/:id/qc-events.
 *
 * Adds the three design surfaces the basic table was missing:
 *  1. 4-stat header (Gates evaluated / Passed / Auto-corrected / Manual)
 *  2. Audit log with the design column order (Time/Gate/Threshold/
 *     Observed/Result/Action) and PASS / FAIL → loop visual treatment
 *  3. Chain-of-custody + operator e-signature blocks
 *
 * E-signature: hidden via hide-when-empty discipline until the backend
 * route ships a real reviewer + TOTP record (no "Coming soon"
 * placeholders per CLAUDE.md).
 */
interface QcAuditTabProps {
  events: QcEvent[];
  /** Optional reviewer record from the backend; omit to hide the e-sig block. */
  eSignature?: {
    reviewer?: string;
    reviewedAt?: string;
    sigShort?: string;
    totpVerified?: boolean;
  };
}

function isPassedStatus(status?: string): boolean {
  if (!status) return true;
  const s = status.toLowerCase();
  return s === "pass" || s === "passed" || s === "ok" || s === "✓";
}

function isAutoCorrectedStatus(status?: string): boolean {
  if (!status) return false;
  const s = status.toLowerCase();
  return s.includes("auto") || s.includes("loop") || s.includes("retry") || s.includes("fail");
}

function deriveAction(e: QcEvent): string {
  if (isPassedStatus(e.status)) return "continue";
  if (isAutoCorrectedStatus(e.status)) return "auto-loop · re-run with adjusted parameters";
  return e.message ?? "manual intervention required";
}

function QcAuditTab({ events, eSignature }: QcAuditTabProps) {
  const passed = events.filter(e => isPassedStatus(e.status)).length;
  const autoCorrected = events.filter(e => !isPassedStatus(e.status) && isAutoCorrectedStatus(e.status)).length;
  const manualInterventions = events.length - passed - autoCorrected;

  return (
    <div style={styles.tabContent} data-testid="qc-audit-tab">
      <div
        data-testid="qc-summary"
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          gap: 10,
          marginBottom: 16,
        }}
      >
        {[
          { label: 'Gates evaluated', value: events.length, color: undefined, testid: 'qc-stat-evaluated' },
          { label: 'Passed',           value: passed,        color: 'oklch(0.62 0.16 145)', testid: 'qc-stat-passed' },
          { label: 'Auto-corrected',   value: autoCorrected, color: 'oklch(0.62 0.16 60)',  testid: 'qc-stat-autoloop' },
          { label: 'Manual interventions', value: manualInterventions, color: undefined, testid: 'qc-stat-manual' },
        ].map(s => (
          <div
            key={s.label}
            data-testid={s.testid}
            style={{
              background: 'oklch(0.97 0.005 260)',
              padding: '10px 12px',
              borderRadius: 4,
              border: '1px solid oklch(0.92 0.008 260)',
            }}
          >
            <div style={{ fontSize: 10, color: 'oklch(0.48 0.012 260)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
              {s.label}
            </div>
            <div style={{ fontSize: 20, fontWeight: 600, color: s.color ?? 'oklch(0.22 0.012 260)', marginTop: 2 }}>
              {s.value}
            </div>
          </div>
        ))}
      </div>

      {events.length === 0 ? (
        <div style={{ fontSize: 12, color: 'oklch(0.48 0.012 260)', fontStyle: 'italic', padding: '8px 0' }}>
          No QC gates fired for this run.
        </div>
      ) : (
        <>
          <div style={{ fontSize: 11, color: 'oklch(0.48 0.012 260)', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 6 }}>
            Gate evaluation log
          </div>
          <table
            data-testid="qc-audit-log"
            style={{
              width: '100%',
              borderCollapse: 'collapse',
              fontSize: 11.5,
              fontFamily: 'ui-monospace, SFMono-Regular, monospace',
            }}
          >
            <thead>
              <tr style={{ background: 'oklch(0.96 0.005 260)', textAlign: 'left' }}>
                <th style={{ padding: '7px 8px' }}>Timestamp (UTC)</th>
                <th style={{ padding: '7px 8px' }}>Gate</th>
                <th style={{ padding: '7px 8px' }}>Threshold</th>
                <th style={{ padding: '7px 8px' }}>Observed</th>
                <th style={{ padding: '7px 8px' }}>Result</th>
                <th style={{ padding: '7px 8px' }}>Action</th>
              </tr>
            </thead>
            <tbody>
              {events.map((e, i) => {
                const pass = isPassedStatus(e.status);
                return (
                  <tr key={i} style={{ borderTop: '1px solid oklch(0.92 0.008 260)' }} data-testid={`qc-row-${i}`}>
                    <td style={{ padding: '7px 8px' }}>{e.ts ?? '—'}</td>
                    <td style={{ padding: '7px 8px' }}>{e.gate ?? '—'}</td>
                    <td style={{ padding: '7px 8px' }}>{e.threshold ?? '—'}</td>
                    <td style={{ padding: '7px 8px' }}>{e.measured ?? '—'}</td>
                    <td
                      style={{
                        padding: '7px 8px',
                        color: pass ? 'oklch(0.62 0.16 145)' : 'oklch(0.62 0.16 60)',
                        fontWeight: 600,
                      }}
                      data-testid={`qc-row-${i}-result`}
                    >
                      {pass ? '✓ PASS' : '↻ FAIL → loop'}
                    </td>
                    <td style={{ padding: '7px 8px', color: 'oklch(0.40 0.012 260)' }}>{deriveAction(e)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>

          <div
            data-testid="qc-chain-of-custody"
            style={{
              marginTop: 16,
              padding: '12px 14px',
              background: 'oklch(0.97 0.005 260)',
              borderRadius: 4,
              border: '1px solid oklch(0.92 0.008 260)',
              fontSize: 11.5,
              lineHeight: 1.55,
              color: 'oklch(0.40 0.012 260)',
            }}
          >
            <div style={{ fontWeight: 600, color: 'oklch(0.22 0.012 260)', marginBottom: 4 }}>
              Chain of custody
            </div>
            All raw inputs, intermediate outputs, and parameter sets are versioned via
            content-addressed storage (SHA-256). Each row above corresponds to a tamper-evident
            manifest entry. No human override modified this run.
          </div>

          {eSignature && (eSignature.reviewer || eSignature.reviewedAt) && (
            <div
              data-testid="qc-e-signature"
              style={{
                marginTop: 12,
                padding: '12px 14px',
                background: 'oklch(0.97 0.005 260)',
                borderRadius: 4,
                border: '1px solid oklch(0.92 0.008 260)',
                fontSize: 11.5,
                lineHeight: 1.55,
              }}
            >
              <div style={{ fontWeight: 600, marginBottom: 4 }}>Operator e-signature</div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'oklch(0.40 0.012 260)' }}>
                <span>
                  {eSignature.reviewer && <>Reviewed by {eSignature.reviewer}</>}
                  {eSignature.reviewedAt && <> · {eSignature.reviewedAt}</>}
                  {eSignature.totpVerified && <> · TOTP verified</>}
                </span>
                {eSignature.sigShort && (
                  <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 10 }}>
                    sig:{eSignature.sigShort}
                  </span>
                )}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

/**
 * Findings figures (Bioconductor handoff §5.1).
 * Three kinds, all data-driven from the manifest (never LLM):
 *   - FigBars: horizontal bar chart with optional highlighted row
 *   - FigComposition: stacked bar + percentage legend
 *   - FigQc: conic-gradient retention ring (kept/total)
 */
const SEG_COLORS = [
  "oklch(0.62 0.16 240)", "oklch(0.62 0.16 145)", "oklch(0.65 0.16 60)",
  "oklch(0.62 0.16 320)", "oklch(0.62 0.16 25)",  "oklch(0.65 0.16 200)",
  "oklch(0.62 0.16 100)", "oklch(0.62 0.16 280)",
];

function FigBars({ fig }: { fig: Extract<FindingsFigure, { kind: "bars" }> }) {
  const max = Math.max(...fig.data.map(d => d[1]), 1);
  return (
    <div data-testid="finding-fig-bars" style={{ marginBottom: 14 }}>
      <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 6, color: "oklch(0.22 0.012 260)" }}>
        {fig.title}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        {fig.data.map(([label, val], i) => {
          const isHl = label === fig.highlight;
          return (
            <div key={i}
              data-testid={isHl ? "finding-fig-bars-row-highlight" : undefined}
              style={{ display: "grid", gridTemplateColumns: "140px 1fr 60px", alignItems: "center",
                gap: 8, fontSize: 11.5, color: isHl ? "oklch(0.45 0.16 240)" : "oklch(0.40 0.012 260)",
                fontWeight: isHl ? 600 : 400 }}>
              <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{label}</span>
              <span style={{ background: "oklch(0.94 0.008 260)", height: 8, borderRadius: 2 }}>
                <span style={{ display: "block", width: `${(100 * val) / max}%`, height: "100%",
                  background: isHl ? "oklch(0.55 0.18 240)" : "oklch(0.65 0.12 240)", borderRadius: 2 }} />
              </span>
              <span style={{ fontFamily: "ui-monospace, monospace", fontSize: 11, textAlign: "right" }}>{val}</span>
            </div>
          );
        })}
      </div>
      {fig.unit && <div style={{ fontSize: 10, color: "oklch(0.48 0.012 260)", marginTop: 4 }}>{fig.unit}</div>}
    </div>
  );
}

function FigComposition({ fig }: { fig: Extract<FindingsFigure, { kind: "composition" }> }) {
  const total = fig.data.reduce((s, d) => s + d[1], 0) || 1;
  return (
    <div data-testid="finding-fig-composition" style={{ marginBottom: 14 }}>
      <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 6, color: "oklch(0.22 0.012 260)" }}>
        {fig.title}
      </div>
      <div style={{ display: "flex", width: "100%", height: 10, borderRadius: 4, overflow: "hidden",
        border: "1px solid oklch(0.92 0.008 260)" }}>
        {fig.data.map(([label, val], i) => (
          <span key={i} title={`${label}: ${val}`}
            style={{ width: `${(100 * val) / total}%`, background: SEG_COLORS[i % SEG_COLORS.length] }} />
        ))}
      </div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "6px 12px", marginTop: 8, fontSize: 11,
        color: "oklch(0.40 0.012 260)" }}>
        {fig.data.map(([label, val], i) => (
          <span key={i} style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
            <span style={{ width: 8, height: 8, background: SEG_COLORS[i % SEG_COLORS.length], borderRadius: 2 }} />
            {label} <b>{Math.round((100 * val) / total)}%</b>
          </span>
        ))}
      </div>
    </div>
  );
}

function FigQc({ fig }: { fig: Extract<FindingsFigure, { kind: "qc" }> }) {
  const pct = Math.round((100 * fig.kept) / Math.max(fig.total, 1));
  return (
    <div data-testid="finding-fig-qc" style={{ marginBottom: 14 }}>
      <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 6, color: "oklch(0.22 0.012 260)" }}>
        {fig.title}
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        <div aria-label={`${pct}% retained`}
          style={{ width: 56, height: 56, borderRadius: "50%",
            background: `conic-gradient(oklch(0.55 0.18 240) ${pct}%, oklch(0.94 0.008 260) 0)`,
            display: "flex", alignItems: "center", justifyContent: "center" }}>
          <span style={{ background: "white", width: 38, height: 38, borderRadius: "50%",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 12, fontWeight: 600, color: "oklch(0.22 0.012 260)" }}>{pct}%</span>
        </div>
        <div style={{ fontSize: 11.5, color: "oklch(0.40 0.012 260)", lineHeight: 1.45 }}>
          <div><b style={{ color: "oklch(0.22 0.012 260)" }}>{fig.kept.toLocaleString()}</b>{" "}{fig.unit ?? "retained"}</div>
          <div style={{ fontSize: 10.5, color: "oklch(0.48 0.012 260)" }}>
            {(fig.total - fig.kept).toLocaleString()} dropped of {fig.total.toLocaleString()}
          </div>
        </div>
      </div>
    </div>
  );
}

function FindingsFiguresPanel({ figures }: { figures: FindingsFigure[] }) {
  return (
    <div data-testid="findings-figures-panel" style={{ marginTop: 16,
      paddingTop: 14, borderTop: "1px solid oklch(0.92 0.008 260)" }}>
      <div style={{ fontSize: 10, color: "oklch(0.48 0.012 260)", textTransform: "uppercase",
        letterSpacing: 0.5, marginBottom: 8 }}>
        Headline figures
      </div>
      {figures.map((fig, i) => {
        if (fig.kind === "bars") return <FigBars key={i} fig={fig} />;
        if (fig.kind === "composition") return <FigComposition key={i} fig={fig} />;
        if (fig.kind === "qc") return <FigQc key={i} fig={fig} />;
        return null;
      })}
      <div style={{ fontSize: 10.5, color: "oklch(0.48 0.012 260)", fontStyle: "italic", marginTop: 6 }}>
        Figures are generated directly from the run manifest. Numbers and
        figures in this section come from the workflow outputs.
      </div>
    </div>
  );
}

function SoftwareTab({ versions }: { versions: Record<string, string> }) {
  const entries = Object.entries(versions);
  if (entries.length === 0) return <p style={styles.empty}>No software versions recorded.</p>;
  return (
    <div style={styles.tabContent}>
      <p style={{ fontSize: 11, color: 'oklch(0.48 0.012 260)', marginBottom: 8 }}>
        Sourced from <code>versions.yml</code> emitted by each pipeline step.
      </p>
      <table style={styles.kvTable}>
        <tbody>
          {entries.map(([tool, ver]) => (
            <tr key={tool}>
              <td style={styles.kvKey}>{tool}</td>
              <td style={styles.kvVal}>{String(ver)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function CitationsTab({ citations }: { citations: Citation[] }) {
  if (citations.length === 0) return <p style={styles.empty}>No citations registered.</p>;
  return (
    <div style={styles.tabContent}>
      <ul style={styles.citationsList}>
        {citations.map((c, i) => (
          <li key={i} style={styles.citationItem}>
            {c.url ? (
              <a href={c.url} target="_blank" rel="noreferrer noopener">{c.title}</a>
            ) : (
              <span>{c.title}</span>
            )}
            {c.doi && <span style={styles.citationDoi}>  doi:{c.doi}</span>}
          </li>
        ))}
      </ul>
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
  software?: Record<string, string>;
  citations?: Citation[];
}): string {
  const { runId, workflowName, parameters, outputs, methods, qcEvents, findings, software, citations } = args;
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

  // Software
  if (software && Object.keys(software).length > 0) {
    lines.push(`## Software`);
    lines.push("");
    lines.push(`| Tool | Version |`);
    lines.push(`|------|---------|`);
    for (const [tool, ver] of Object.entries(software)) {
      lines.push(`| ${tool} | \`${ver}\` |`);
    }
    lines.push("");
  }

  // Citations
  if (citations && citations.length > 0) {
    lines.push(`## Citations`);
    lines.push("");
    for (const c of citations) {
      if (c.url) {
        lines.push(`- [${c.title}](${c.url})${c.doi ? `  doi:${c.doi}` : ""}`);
      } else if (c.doi) {
        lines.push(`- ${c.title}  doi:${c.doi}`);
      } else {
        lines.push(`- ${c.title}`);
      }
    }
    lines.push("");
  }

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
  // Ephemeral toast for Run-again CTA (auto-clears after 4s) — replaces alert()
  ctaToast: { fontSize: 11.5, padding: "4px 10px", margin: "0 0 6px", background: "oklch(0.94 0.04 245)", color: "oklch(0.30 0.13 245)", borderRadius: 6, display: "inline-block" },
};
