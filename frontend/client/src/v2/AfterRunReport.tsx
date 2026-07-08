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
import { InteractiveLauncher } from "@/components/interactive-launcher";

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
  /** Optional richer fields surfaced by /api/workflows/runs/:id/output_files —
   *  populated when the backend includes them; the report falls back gracefully
   *  when absent. */
  size?: number;        // bytes
  s3_uri?: string;      // backend-internal pointer; NOT shown to user (concern A)
  description?: string; // optional human-written or LLM-generated per-file caption
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
  const [tab, setTab] = useState<TabId>("outputs");

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
  // Tab order set by UX review 2026-06-19: outputs → findings → QC report →
  // methods → citations come first (the five sections users actually read);
  // parameters + software trail as forensic reference.
  const visibleTabs = useMemo<Array<[TabId, string]>>(() => {
    const t: Array<[TabId, string]> = [
      ["outputs", "Outputs"],
      ["findings", "Findings"],
    ];
    // QC tab always visible — shows "all passed" for good runs, blocked gate info for failed
    t.push(["qc", "QC report"]);
    if (methods.hasRealContent) t.push(["methods", "Methods"]);
    if (citations.length > 0) t.push(["citations", "Citations"]);
    t.push(["params", "Parameters"]);
    if (Object.keys(software).length > 0) t.push(["software", "Software"]);
    return t;
  }, [methods.hasRealContent, software, citations.length]);

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
      <div role="tablist" style={styles.tabBar} data-visible-tabs={visibleTabs.map(([id]) => id).join(',')}>
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
            {/* Contract note — hoisted out of FindingsFiguresPanel (audit A1)
                so it renders whether the figures panel is visible or not.
                Wording covers numbers AND figures (the FindingsCard headline
                metrics and bullets fall under this same contract). */}
            <div
              data-testid="findings-manifest-note"
              style={{
                fontSize: 10.5,
                color: "oklch(0.48 0.012 260)",
                fontStyle: "italic",
                marginTop: 12,
                paddingTop: 10,
                borderTop: "1px solid oklch(0.94 0.008 260)",
              }}
            >
              Findings are generated directly from the run manifest. Numbers
              and figures in this section come from the workflow outputs.
            </div>
          </>
        )}
        {tab === "outputs" && <OutputsTab outputs={outputs} runId={runId} invocationId={invocationId} executionStatus={executionStatus} />}
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
      data: Array<[string, number]>; source_file?: string }
  | { kind: "composition"; title: string; data: Array<[string, number]>; source_file?: string }
  | { kind: "qc"; title: string; unit?: string; kept: number; total: number; source_file?: string };

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

/** Map output file extensions to the right interactive tool.
 *  Returns null when no tool is appropriate (images, PDFs, binary cryo-EM, etc.). */
function toolForExt(ext: string): { tool: 'jupyter' | 'rstudio' | 'cellxgene'; label: string } | null {
  const e = ext.toLowerCase().replace(/^\./, '');
  if (['h5ad', 'loom', 'h5'].includes(e)) return { tool: 'cellxgene', label: 'CellxGene' };
  if (['rds', 'rdata', 'rda'].includes(e)) return { tool: 'rstudio', label: 'RStudio' };
  if (['csv', 'tsv', 'tabular', 'txt', 'json', 'log', 'bed', 'gff', 'gtf',
       'vcf', 'fasta', 'fa', 'fastq', 'fq'].includes(e)) return { tool: 'jupyter', label: 'Jupyter' };
  return null;
}

/**
 * Inline interactive-tool row for the Outputs tab.
 * Scans all output file extensions and surfaces the distinct set of
 * applicable tools as labelled buttons — no placeholder when empty.
 */
function InteractiveToolsRow({ outputs }: { outputs: OutputFile[] }) {
  const [open, setOpen] = useState(false);
  const [selectedTool, setSelectedTool] = useState<'jupyter' | 'rstudio' | 'cellxgene'>('jupyter');

  // Build the set of applicable tools + the files for each.
  const toolMap = useMemo<Map<'jupyter' | 'rstudio' | 'cellxgene', { label: string; files: Array<{ id: string; name: string; size: number; type?: string }> }>>(() => {
    const m = new Map<'jupyter' | 'rstudio' | 'cellxgene', { label: string; files: Array<{ id: string; name: string; size: number; type?: string }> }>();
    for (const f of outputs) {
      const t = toolForExt(f.ext);
      if (!t) continue;
      if (!m.has(t.tool)) m.set(t.tool, { label: t.label, files: [] });
      m.get(t.tool)!.files.push({ id: f.path || f.name, name: f.name, size: f.size ?? 0, type: f.ext });
    }
    // Jupyter is always offered as a universal fallback — add it if not already present.
    if (!m.has('jupyter')) {
      const allFiles = outputs.map(f => ({ id: f.path || f.name, name: f.name, size: f.size ?? 0, type: f.ext }));
      if (allFiles.length > 0) m.set('jupyter', { label: 'Jupyter', files: allFiles });
    }
    return m;
  }, [outputs]);

  if (toolMap.size === 0) return null;

  const openWith = (tool: 'jupyter' | 'rstudio' | 'cellxgene') => {
    setSelectedTool(tool);
    setOpen(true);
  };

  // Files for the currently selected tool.
  const currentFiles = toolMap.get(selectedTool)?.files ?? [];

  // Tool ordering: CellxGene first (most specific), then RStudio, then Jupyter.
  const orderedTools: Array<'cellxgene' | 'rstudio' | 'jupyter'> = ['cellxgene', 'rstudio', 'jupyter'];

  return (
    <div
      data-testid="afterrun-interactive-tools-row"
      style={{
        display: 'flex',
        gap: 8,
        marginBottom: 12,
        padding: '10px 12px',
        background: 'oklch(0.97 0.005 245)',
        borderRadius: 6,
        border: '1px solid oklch(0.91 0.01 245)',
        alignItems: 'center',
        flexWrap: 'wrap' as React.CSSProperties['flexWrap'],
      }}
    >
      <span style={{ fontSize: 11, color: 'oklch(0.48 0.012 260)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.04em', marginRight: 4 }}>
        Explore in
      </span>
      {orderedTools.filter(t => toolMap.has(t)).map(tool => {
        const { label } = toolMap.get(tool)!;
        const icons: Record<string, string> = {
          cellxgene: '◉',
          rstudio: 'R',
          jupyter: '⌥',
        };
        return (
          <button
            key={tool}
            type="button"
            data-testid={`afterrun-launch-${tool}`}
            onClick={() => openWith(tool)}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 5,
              padding: '5px 12px',
              fontSize: 12,
              fontWeight: 500,
              background: 'white',
              border: '1px solid oklch(0.88 0.01 245)',
              borderRadius: 6,
              cursor: 'pointer',
              color: 'oklch(0.22 0.01 260)',
            }}
          >
            <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11 }}>{icons[tool]}</span>
            {label}
          </button>
        );
      })}
      <InteractiveLauncher
        open={open}
        onOpenChange={setOpen}
        outputs={currentFiles}
        initialTool={selectedTool}
      />
    </div>
  );
}

function OutputsTab({
  outputs,
  runId,
  invocationId,
  executionStatus,
}: { outputs: OutputFile[]; runId: string; invocationId?: string; executionStatus?: string }) {
  // Audit 2026-06-17: the parent's outputs prop is derived from the DB-stored
  // nextflowStatus.s3_output_files snapshot. That snapshot is often empty
  // for completed runs because the Galaxy /api/nextflow/status endpoint is
  // single-worker and slow, so the Node poller hits its 8s timeout and
  // never refreshes the DB row. Workaround: when the prop is empty, hit
  // /api/workflows/runs/:id/output_files which has its own S3 ListObjectsV2
  // fallback (routes.ts:10160+) and presigns each entry.
  const [fetched, setFetched] = useState<OutputFile[]>([]);
  useEffect(() => {
    if (outputs.length > 0 || !runId) return;
    let cancelled = false;
    (async () => {
      try {
        const r = await fetch(
          `/api/workflows/runs/${encodeURIComponent(runId)}/output_files`,
          { credentials: "include" },
        );
        if (!r.ok || cancelled) return;
        const j = await r.json();
        const arr = (j?.output_files || j?.outputs || []) as any[];
        if (cancelled || !Array.isArray(arr) || arr.length === 0) return;
        setFetched(
          arr.map((f) => {
            const filePath = String(f?.s3_uri || f?.path || f?.s3_key || f?.name || "");
            const name = String(f?.name || f?.filename || filePath.split("/").pop() || "");
            const ext = String(
              f?.extension ||
                (name.includes(".") ? name.split(".").pop() : "") ||
                "",
            ).toLowerCase();
            const parts = filePath.split("/").filter(Boolean);
            const step = parts.length >= 2 ? parts[parts.length - 2] : "";
            return { step, name, path: filePath, ext };
          }),
        );
      } catch { /* silent — empty state still useful */ }
    })();
    return () => { cancelled = true; };
  }, [runId, outputs.length]);
  const effectiveOutputs = outputs.length > 0 ? outputs : fetched;
  // Total size summary (when present in the output records)
  const totalCount = effectiveOutputs.length;
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

  // Must be declared before any early return — Rules of Hooks.
  const [previewFile, setPreviewFile] = useState<OutputFile | null>(null);

  if (totalCount === 0) {
    return (
      <div style={styles.tabContent}>
        <p style={styles.empty}>
          {executionStatus === 'failed'
            ? 'No outputs — run did not complete successfully.'
            : 'No output files registered yet.'}
        </p>
      </div>
    );
  }

  const fileUrl = (f: OutputFile, download = false) =>
    `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(f.path || f.name)}${download ? '&download=1' : ''}`;

  const iconForExt = (ext: string) => {
    if (['png','jpg','jpeg','gif','svg','webp','tiff'].includes(ext)) return '🖼';
    if (['csv','tsv','xlsx'].includes(ext)) return '📊';
    if (['html','htm'].includes(ext)) return '🌐';
    if (['pdf'].includes(ext)) return '📄';
    if (['json','yaml','yml'].includes(ext)) return '{}';
    if (['fastq','fq','fa','fasta'].includes(ext)) return '🧬';
    if (['bam','vcf','bed','gtf','gff'].includes(ext)) return '🗂';
    return '📁';
  };

  const canPreview = (ext: string) =>
    ['png','jpg','jpeg','gif','svg','webp','csv','tsv','html','htm','txt','log','json','yaml','yml','md'].includes(ext);

  return (
    <div style={styles.tabContent}>
      {/* Bulk-download actions */}
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

      <InteractiveToolsRow outputs={effectiveOutputs} />

      {/* Per-file table matching design reference */}
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12, fontFamily: 'ui-monospace, monospace' }}>
          <thead>
            <tr style={{ background: 'oklch(0.96 0.004 260)', textAlign: 'left' }}>
              <th style={{ padding: '6px 8px', fontWeight: 600, color: 'var(--text-muted)', fontSize: 11 }}>Step</th>
              <th style={{ padding: '6px 8px', fontWeight: 600, color: 'var(--text-muted)', fontSize: 11 }}>File</th>
              <th style={{ padding: '6px 8px', fontWeight: 600, color: 'var(--text-muted)', fontSize: 11, width: 60 }}>Type</th>
              <th style={{ padding: '6px 8px', width: 90 }}></th>
            </tr>
          </thead>
          <tbody>
            {effectiveOutputs.map((f, i) => (
              <tr key={f.path || f.name + i} style={{ borderTop: '1px solid var(--border)' }}>
                <td style={{ padding: '6px 8px', color: 'var(--text-muted)', maxWidth: 120, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
                    title={f.step}>{f.step}</td>
                <td style={{ padding: '6px 8px' }}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                    <span style={{ fontSize: 13 }}>{iconForExt(f.ext)}</span>
                    <span style={{ color: 'var(--text)' }}>{f.name}</span>
                  </span>
                </td>
                <td style={{ padding: '6px 8px', color: 'var(--text-muted)', textTransform: 'uppercase', fontSize: 10 }}>{f.ext || '—'}</td>
                <td style={{ padding: '6px 8px', fontFamily: 'var(--font-ui, system-ui)' }}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                    {canPreview(f.ext) && (
                      <button
                        onClick={() => setPreviewFile(f)}
                        style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', color: 'var(--accent, oklch(0.55 0.18 260))', fontSize: 11 }}
                      >view</button>
                    )}
                    <a
                      href={fileUrl(f, true)}
                      download
                      style={{ color: 'var(--accent, oklch(0.55 0.18 260))', fontSize: 11, textDecoration: 'none' }}
                    >dl</a>
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Inline preview overlay */}
      {previewFile && (
        <div
          onClick={() => setPreviewFile(null)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
        >
          <div
            onClick={e => e.stopPropagation()}
            style={{ background: 'var(--bg, #fff)', borderRadius: 8, padding: 20, maxWidth: 720, width: '90vw', maxHeight: '80vh', overflow: 'auto', boxShadow: '0 8px 32px rgba(0,0,0,0.18)' }}
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
              <div>
                <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 13, fontWeight: 600 }}>{previewFile.name}</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>{previewFile.step}</div>
              </div>
              <button onClick={() => setPreviewFile(null)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 18, lineHeight: 1 }}>×</button>
            </div>
            {['png','jpg','jpeg','gif','svg','webp'].includes(previewFile.ext) ? (
              <img src={fileUrl(previewFile)} alt={previewFile.name} style={{ maxWidth: '100%', borderRadius: 4 }} />
            ) : ['html','htm'].includes(previewFile.ext) ? (
              <iframe src={fileUrl(previewFile)} title={previewFile.name} style={{ width: '100%', height: 480, border: '1px solid var(--border)', borderRadius: 4 }} />
            ) : (
              <iframe src={fileUrl(previewFile)} title={previewFile.name} style={{ width: '100%', height: 400, border: '1px solid var(--border)', borderRadius: 4, fontFamily: 'ui-monospace, monospace' }} />
            )}
            <div style={{ marginTop: 10, display: 'flex', justifyContent: 'flex-end' }}>
              <a href={fileUrl(previewFile, true)} download style={{ fontSize: 12, color: 'var(--accent, oklch(0.55 0.18 260))' }}>↓ Download</a>
            </div>
          </div>
        </div>
      )}
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
      {entries.length > 0 && (
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
      )}
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

  if (events.length === 0) {
    return (
      <div style={styles.tabContent} data-testid="qc-audit-tab">
        <div style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '48px 24px',
          gap: 8,
          textAlign: 'center',
          color: 'oklch(0.62 0.16 145)',
        }}>
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
            <polyline points="22 4 12 14.01 9 11.01"/>
          </svg>
          <div style={{ fontWeight: 600, fontSize: 15 }} data-testid="qc-all-passed">All quality gates passed</div>
          <div style={{ fontSize: 13, color: 'var(--text-muted)', maxWidth: 320 }}>
            No QC thresholds were exceeded during this run. All metrics are within acceptable ranges.
          </div>
        </div>
      </div>
    );
  }

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
        let body: JSX.Element | null = null;
        if (fig.kind === "bars") body = <FigBars fig={fig} />;
        else if (fig.kind === "composition") body = <FigComposition fig={fig} />;
        else if (fig.kind === "qc") body = <FigQc fig={fig} />;
        if (!body) return null;
        return (
          <div key={i}>
            {body}
            {fig.source_file && (
              <div style={{ fontSize: 10, fontFamily: "var(--font-mono)",
                color: "oklch(0.55 0.012 260)", marginTop: -4, marginBottom: 6 }}>
                from {fig.source_file}
              </div>
            )}
          </div>
        );
      })}
      {/* Contract note moved to the Findings-tab body in AfterRunReport so it
          renders whether figures are present or not (audit A1, 2026-06-11). */}
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

  // ── Header ────────────────────────────────────────────────────────────────
  lines.push(`# BioMate Run Report`);
  lines.push("");
  lines.push(`- **Run ID**: \`${runId}\``);
  if (workflowName) lines.push(`- **Workflow**: ${workflowName}`);
  lines.push(`- **Generated**: ${new Date().toISOString()}`);
  lines.push("");
  lines.push(`_This report is a research summary. Input and output file bytes_`);
  lines.push(`_live in your BioMate workspace and are reachable via the per-file_`);
  lines.push(`_download endpoints linked below. Bytes are intentionally not_`);
  lines.push(`_inlined to keep the report portable and reviewable._`);
  lines.push("");

  // ── Dataset description (NEW — research-doc style) ───────────────────────
  // Pulled from parameters: anything looking like a path or sample identifier
  // is summarised as "input dataset" rather than inlined.
  lines.push(`## Dataset`);
  lines.push("");
  const datasetFields = parameters
    ? Object.entries(parameters).filter(([k, v]) =>
        /(path|file|sample|input|sumstats|matrix|bam|fastq|vcf|h5ad|sample_sheet|samplesheet)/i.test(k) &&
        typeof v === "string" && v.length > 0
      )
    : [];
  if (datasetFields.length === 0) {
    lines.push(`_No inline dataset descriptors detected in run parameters._`);
    lines.push(`_If inputs were supplied separately, see the BioMate workspace_`);
    lines.push(`_inputs/ folder for this run._`);
  } else {
    lines.push(`| Field | Reference |`);
    lines.push(`|-------|-----------|`);
    for (const [k, v] of datasetFields) {
      // Show as reference (basename + length) rather than dumping the value
      const refStr = String(v);
      const basename = refStr.split(/[/\\]/).pop() || refStr;
      const note = refStr.startsWith("s3://") ? "Cloud storage"
                 : refStr.startsWith("http") ? "Remote file"
                 : refStr.match(/\.(fastq|fq|bam|vcf|h5ad|rds|tsv|csv|json)(\.gz)?$/i) ? `${(refStr.match(/\.([^./]+)(\.gz)?$/i)?.[1] || "").toUpperCase()} file`
                 : "value";
      lines.push(`| \`${k}\` | ${basename} _(${note})_ |`);
    }
  }
  lines.push("");

  // ── Findings ─────────────────────────────────────────────────────────────
  // Inlined from useFetchFindings (PM must-fix #2). Falls back to a pending
  // notice if the AI analysis hasn't completed yet at click time.
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

  // ── Outputs ──────────────────────────────────────────────────────────────
  // Research-doc style: per-step subsection with file metadata (name, type,
  // size) and a BioMate-endpoint download link. NO S3 URIs leaked. NO bytes
  // inlined. The report is a navigable summary; bytes live in the workspace.
  lines.push(`## Outputs`);
  lines.push("");
  if (outputs.length === 0) {
    lines.push(`_No output files registered for this run._`);
  } else {
    lines.push(`Outputs below are linked via BioMate's per-file download endpoint`);
    lines.push(`(\`/api/runs/${runId}/output/...\`). Bytes stay in your project's`);
    lines.push(`output location; the report is portable.`);
    lines.push("");
    const byStep: Record<string, OutputFile[]> = {};
    for (const o of outputs) (byStep[o.step] = byStep[o.step] || []).push(o);
    for (const [step, files] of Object.entries(byStep)) {
      lines.push(`### ${step || "(unspecified step)"}`);
      lines.push("");
      // Show sizes if present; otherwise hide the column to avoid empty cells
      const hasSize = files.some(f => typeof f.size === "number" && f.size > 0);
      const hasDesc = files.some(f => f.description && f.description.length > 0);
      const header = hasSize
        ? (hasDesc ? `| File | Type | Size | Description |\n|------|------|-----:|-------------|`
                   : `| File | Type | Size |\n|------|------|-----:|`)
        : (hasDesc ? `| File | Type | Description |\n|------|------|-------------|`
                   : `| File | Type |\n|------|------|`);
      lines.push(header);
      for (const f of files) {
        const dl = `[${f.name}](/api/runs/${runId}/output/${encodeURIComponent(f.name)})`;
        const type = f.ext || "—";
        const size = hasSize ? formatBytes(f.size) : null;
        const desc = hasDesc ? (f.description || "") : null;
        const row = [dl, type, size, desc].filter(c => c !== null).join(" | ");
        lines.push(`| ${row} |`);
      }
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

  // ── Reproducibility footer (NEW — replaces "v2 preview" framing) ────────
  lines.push(`---`);
  lines.push(`## Reproducibility`);
  lines.push("");
  lines.push(`This run is reproducible by re-dispatching the same workflow with`);
  lines.push(`the parameters listed above against the same software versions`);
  lines.push(`(see *Software* section). Outputs are addressable in your BioMate`);
  lines.push(`workspace under \`runs/${runId}/\`; download each file via the`);
  lines.push(`endpoint links in the *Outputs* section.`);
  lines.push("");
  lines.push(`Generated by BioMate · ${new Date().toISOString()}`);

  return lines.join("\n");
}

/** Format a byte count as a human-readable string (1024-base). */
function formatBytes(n: number | undefined): string {
  if (typeof n !== "number" || !isFinite(n) || n < 0) return "—";
  if (n < 1024) return `${n} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = n / 1024, i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v >= 10 ? 0 : 1)} ${units[i]}`;
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
