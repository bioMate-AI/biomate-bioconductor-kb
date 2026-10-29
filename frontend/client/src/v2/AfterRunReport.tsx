import { normalizeQcEvents, qcActionTaken, qcResultLabel, type QcAssessment } from "@shared/qc-assessment";
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
import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ArrowDownToLine, FileJson, FileText, FileCode, FileSpreadsheet, Image as ImageIcon, Dna, Database, File as FileIcon } from "lucide-react";
import { tOr } from "@/lib/i18n";
import { FindingsCard } from "@/components/findings-card";
import { StepOutputPreview } from "@/components/step-output-preview";
import { useInteractiveToolsAvailable } from "@/hooks/use-interactive-tools";
import { TrajectoryView, type TrajectoryRow, type TrajectoryKind } from "@/components/trajectory-view";
import ReactMarkdown from "react-markdown";

// Strip raw Nextflow debug log lines down to a readable one-liner.
// Input:  "Jul-22 07:56:33.018 [Task monitor] DEBUG ... name: STEP (DESeq2); ... exit: 1; error: Essential container...; workDir: s3://..."
// Output: "DESeq2 exited with code 1 — Essential container in task exited"
function humanizeNfError(msg: string): string {
  if (!msg) return msg;
  // Extract structured fields from TaskPollingMonitor log lines
  const nameM  = msg.match(/name:\s*[^;]+\(([^)]+)\)/);
  const exitM  = msg.match(/exit:\s*(\d+)/);
  const errorM = msg.match(/error:\s*(?:nextflow\.exception\.\w+:\s*)?([^;]+?)(?:;\s*workDir|$)/);
  if (nameM || exitM || errorM) {
    const step  = nameM  ? nameM[1].trim()  : '';
    const code  = exitM  ? exitM[1]         : '';
    const cause = errorM ? errorM[1].trim() : '';
    const parts: string[] = [];
    if (step)  parts.push(step + (code ? ` exited with code ${code}` : ' failed'));
    if (cause && cause !== step) parts.push(cause);
    return parts.join(' — ') || msg.slice(0, 300);
  }
  // Fallback: strip timestamp + log-level prefix, cap at 300 chars
  return msg.replace(/^\S+\s+\[.*?\]\s+\w+\s+[\w.]+\s+-\s+/, '').slice(0, 300);
}
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
  /** Project this run is associated with (if any) — used to link to the
   *  project file tree and to auto-populate the Save-to-Project picker. */
  projectId?: string;
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
  /** C2 (cross-stream contract): deep-link target tab opened on mount — passed by
   *  the workflow panel when chat "Open in Summary / Outputs / Report" is clicked. */
  targetTab?: "summary" | "outputs" | "report";
}

// Merged surface: "Results" (findings summary banner on top + each output as an
// inline preview) and "Reproducibility record". Findings and Outputs — previously
// separate tabs — are now one scrollable Results view (user request): the
// interpretation sits above the artifacts it was read from. Methods / resolved
// parameters / software / citations / QC report / trajectory remain collapsible
// sections nested INSIDE the Reproducibility record tab.
// After-run = three tabs (user-decided): Summary · Outputs · Report. The former
// "Reproducibility record" tab is removed — its content (Methods / Software /
// Citations / QC) folds into the Report document; the step-by-step trajectory
// moves into the per-step detail panel (StepDeep).
type TabId = "summary" | "outputs" | "report";

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
  projectId,
  targetTab,
}: AfterRunReportProps) {
  // nextflowOutputDir is forwarded by the parent for future Outputs-tab
  // directory toolbar work; intentionally unread in v0.
  void nextflowOutputDir;
  const isFailed = executionStatus === "failed" || executionStatus === "cancelled" || executionStatus === "error";
  // Landing tab is Summary; a chat deep-link may target Outputs or Report (C2).
  const [tab, setTab] = useState<TabId>(targetTab ?? "summary");
  // Re-open the deep-linked tab when the panel is asked to (targetTab changes).
  useEffect(() => { if (targetTab) setTab(targetTab); }, [targetTab]);

  // §7.8 — a findings number links to the output it was read from: jump to the
  // Outputs tab and scroll that file's card into view (best-effort DOM match on
  // the file path/name; if unmatched the user still lands on the file list).
  const handleOpenOutput = useCallback((ref: string) => {
    setTab("outputs");
    requestAnimationFrame(() => requestAnimationFrame(() => {
      try {
        const esc = (window as any).CSS?.escape ? (window as any).CSS.escape(ref) : ref.replace(/["\\]/g, '\\$&');
        const el = document.querySelector(`[data-output-ref-card="${esc}"]`)
          || Array.from(document.querySelectorAll('[data-output-ref-card]'))
               .find(n => (n.getAttribute('data-output-ref-card') || '').endsWith(ref));
        (el as HTMLElement | undefined)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      } catch { /* landing on the Outputs tab is enough */ }
    }));
  }, []);

  // Outputs come from the parent's executionRun state (no /steps endpoint exists).
  const outputs = outputsProp ?? [];
  // Methods + QC events keyed off invocationId (the backend Nextflow id), falling back to runId.
  const idForBackend = invocationId || runId;
  const methods = useFetchMethods(idForBackend);
  const qcEvents = useFetchQcEvents(idForBackend);
  // Agent trajectory commented out 2026-10-28 (user request): no real backend
  // endpoint; the Full Step View's per-step log is the trajectory. Re-enable the
  // fetch (useFetchTrajectory, below) when a real agent-trajectory endpoint ships.
  // const trajectoryRows = useFetchTrajectory(runId);
  const software = useFetchSoftware(idForBackend);
  const citations = useFetchCitations(workflowName);
  // Findings fetched here too (alongside FindingsCard's own fetch) so the
  // comprehensive download report can inline real findings prose (PM must-fix #2).
  const findings = useFetchFindings(runId);

  // The in-panel Report document (§2.2) — the same comprehensive report the
  // Download menu produces, rendered as a scrolling 8-section doc in the Report tab.
  const reportMarkdown = useMemo(() => buildFullReportMarkdown({
    runId,
    workflowName,
    parameters,
    outputs,
    methods: methods.text,
    qcEvents,
    findings,
    software,
    citations,
  }), [runId, workflowName, parameters, outputs, methods.text, qcEvents, findings, software, citations]);

  // Lightweight download-UX state — keeps users from double-clicking and
  // gives a clear "started" signal (PM must-fix #4, client-side portion).
  const [downloadState, setDownloadState] = useState<'idle' | 'preparing'>('idle');
  const [deckState, setDeckState] = useState<'idle' | 'preparing'>('idle');
  // Item 4 (UI refinement): the two separate download links merged into one
  // "Download" control that unfolds a menu (Markdown report · PPTX deck).
  const [downloadMenuOpen, setDownloadMenuOpen] = useState(false);
  const [downloadToast, setDownloadToast] = useState<string | null>(null);

  // Accepted design: exactly three top-level tabs, Summary first. Everything
  // that used to be a peer tab (Methods, Parameters, Software, Citations, QC
  // report, Trajectory) is now a collapsible section inside the record tab —
  // still reachable, just re-nested (nothing is hidden or discarded).
  const visibleTabs: Array<[TabId, string]> = [
    ["summary", tOr('afterrun.tab.summary', "Summary")],
    ["outputs", tOr('afterrun.tab.outputs', "Outputs")],
    ["report", tOr('afterrun.tab.report', "Report")],
  ];

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
    setDownloadToast(tOr('afterrun.report_downloaded', 'Report downloaded — check your browser'));
    setTimeout(() => setDownloadState('idle'), 2000);
    setTimeout(() => setDownloadToast(null), 4000);
  };

  // Export the same comprehensive report as a PowerPoint deck (.pptx), rendered
  // on-prem by Pandoc on the server — data never leaves the estate.
  const handleDownloadDeck = async () => {
    if (deckState !== 'idle') return;
    setDeckState('preparing');
    try {
      const md = buildFullReportMarkdown({
        runId, workflowName, parameters, outputs,
        methods: methods.text, qcEvents, findings, software, citations,
      });
      const resp = await fetch('/api/reports/convert', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ markdown: md, format: 'pptx', filename: `biomate-run-${runId}` }),
      });
      if (!resp.ok) throw new Error(`Export failed (${resp.status})`);
      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `biomate-run-${runId}.pptx`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      setDownloadToast(tOr('afterrun.deck_downloaded', 'Deck (PPTX) downloaded — check your browser'));
    } catch {
      setDownloadToast(tOr('afterrun.deck_failed', 'Deck export failed — try the markdown report'));
    } finally {
      setDeckState('idle');
      setTimeout(() => setDownloadToast(null), 4000);
    }
  };

  return (
    <div className="after-run-report" style={styles.root}>
      <div style={styles.head}>
        <span style={styles.kicker}>{tOr('afterrun.kicker', 'After run')}</span>
        <span style={{ flex: 1 }} />
        {downloadToast && (
          <span style={styles.toast} role="status">{downloadToast}</span>
        )}
        <div style={{ position: 'relative' }} data-testid="afterrun-download">
          <button
            type="button"
            onClick={() => setDownloadMenuOpen((o) => !o)}
            style={{ ...styles.linkish, background: "none", border: "none", cursor: "pointer", padding: 0 }}
            aria-haspopup="menu"
            aria-expanded={downloadMenuOpen}
            data-testid="afterrun-download-toggle"
          >
            ↓ {tOr('afterrun.download', 'Download')} ▾
          </button>
          {downloadMenuOpen && (
            <>
              <div onClick={() => setDownloadMenuOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 19 }} />
              <div
                role="menu"
                data-testid="afterrun-download-menu"
                style={{
                  position: 'absolute', right: 0, top: '100%', marginTop: 6, zIndex: 20,
                  minWidth: 210, display: 'flex', flexDirection: 'column', gap: 2, padding: 4,
                  background: 'var(--bm-surface, #fff)',
                  border: '1px solid var(--bm-border, oklch(0.90 0.005 260))',
                  borderRadius: 8, boxShadow: '0 6px 20px rgba(16,24,40,0.12)',
                }}
              >
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => { setDownloadMenuOpen(false); handleDownload(); }}
                  disabled={downloadState !== 'idle'}
                  style={{ ...styles.linkish, background: "none", border: "none", textAlign: 'left', padding: '7px 10px', borderRadius: 6, cursor: downloadState === 'idle' ? "pointer" : "default", opacity: downloadState === 'idle' ? 1 : 0.6 }}
                  title={tOr('afterrun.download_report_title', 'Download a comprehensive markdown report stitching every tab')}
                  data-testid="afterrun-download-report"
                >
                  ↓ {downloadState === 'preparing' ? tOr('afterrun.preparing', 'Preparing…') : tOr('afterrun.download_report_md', 'Markdown report')}
                </button>
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => { setDownloadMenuOpen(false); handleDownloadDeck(); }}
                  disabled={deckState !== 'idle'}
                  style={{ ...styles.linkish, background: "none", border: "none", textAlign: 'left', padding: '7px 10px', borderRadius: 6, cursor: deckState === 'idle' ? "pointer" : "default", opacity: deckState === 'idle' ? 1 : 0.6 }}
                  title={tOr('afterrun.download_deck_title', 'Export this report as a PowerPoint deck (.pptx), rendered on-prem — no external service')}
                  data-testid="afterrun-download-deck"
                >
                  ↓ {deckState === 'preparing' ? tOr('afterrun.preparing', 'Preparing…') : tOr('afterrun.download_deck_pptx', 'PowerPoint deck (PPTX)')}
                </button>
              </div>
            </>
          )}
        </div>
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
        {/* Results (landing tab) — merged Findings + Outputs. The run's headline
            findings summary (marked as the immutable "run original") sits on top
            as a banner; below it, each output renders as an inline preview. A
            finding number links down to the output card it was read from. */}
        {tab === "summary" && (
            <div data-testid="after-summary-tab">
              <div style={styles.runOriginalRow}>
                <span style={styles.runOriginalBadge} data-testid="after-run-original-badge">
                  {tOr('afterrun.run_original', 'Run original')}
                </span>
                <span style={styles.runOriginalHint}>
                  {tOr('afterrun.run_original_hint', 'The unedited record of what this run produced. Reports you edit are saved alongside it; this original is never overwritten.')}
                </span>
              </div>
              {/* Findings banner. Fixed 2026-10-20 (item 15): for multi-compound
                  runs the card now drops the un-attributed headline chips and
                  shows the full per-compound Key Results table, so it's always
                  clear which entity a number belongs to (see findings-card.tsx
                  `multiEntity`). */}
              <FindingsCard
                runId={runId}
                onContinueAnalysis={onContinueAnalysis}
                executionStatus={executionStatus}
                onOpenOutput={handleOpenOutput}
              />
              {qcEvents.some(e => e.status === 'fail' || e.status === 'advisory') && (
                <section data-testid="completed-qc-findings" style={{ marginTop: 12 }}>
                  <h3 style={{ fontSize: 13, fontWeight: 600 }}>{tOr('afterrun.qc_findings', 'QC findings')}</h3>
                  <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
                    <thead><tr><th align="left">Check</th><th align="left">Observed</th><th align="left">Flag condition</th><th align="left">Result</th></tr></thead>
                    <tbody>{qcEvents.filter(e => e.status === 'fail' || e.status === 'advisory').map((e, i) => (
                      <tr key={i} style={{ borderTop: '1px solid var(--border)' }}>
                        <td>{e.gate ?? '—'}</td><td>{e.measured ?? '—'}</td>
                        <td>{e.operator ? `${e.operator} ` : ''}{e.threshold ?? '—'}</td><td>{qcResultLabel(e.status)}</td>
                      </tr>
                    ))}</tbody>
                  </table>
                </section>
              )}
              {findings?.figures && findings.figures.length > 0 && (
                <FindingsFiguresPanel figures={findings.figures} />
              )}
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
                {tOr('afterrun.findings_manifest_note', 'Findings are generated directly from the run manifest. Numbers and figures in this section come from the workflow outputs.')}
              </div>
            </div>
        )}
        {/* Outputs — files the run produced, grouped by producing step. */}
        {tab === "outputs" && (
          <div data-testid="after-outputs-tab">
            <OutputsTab
              outputs={outputs}
              runId={runId}
              invocationId={invocationId}
              executionStatus={executionStatus}
              projectId={projectId}
            />
          </div>
        )}
        {/* Report — the editable after-run document; the former reproducibility
            record (Methods / Software / Citations / QC) folds in below. Scrolls. */}
        {tab === "report" && (
          <div data-testid="after-report-tab">
            <div style={styles.runOriginalRow}>
              <span style={styles.runOriginalBadge}>{tOr('afterrun.tab.report', 'Report')}</span>
              <span style={styles.runOriginalHint}>
                {tOr('afterrun.report_hint', 'Question · Answer · Data · Method · Results · Quality checks · Caveats · Citations. Edits save as a new version; the run original is never overwritten.')}
              </span>
            </div>
            <div className="bmx-report-doc" data-testid="after-report-doc" style={{
              border: '1px solid var(--border)', borderRadius: 10, background: 'var(--bg-elev, #fff)',
              padding: '18px 20px', marginTop: 10, maxHeight: '58vh', overflow: 'auto',
              fontSize: 13, lineHeight: 1.55, color: 'var(--text)',
            }}>
              <ReactMarkdown>{reportMarkdown}</ReactMarkdown>
            </div>
            {/* Reproducibility record commented out 2026-10-28 (user request): the
                Methods / Parameters / Software / Citations / QC accordion is removed
                from the Report tab. The report document above already carries Method /
                Results / Quality-checks / Citations sections. Re-enable by uncommenting.
            <div style={{ marginTop: 16, paddingTop: 14, borderTop: "1px solid var(--border)" }}>
              <ReproducibilityRecordTab
                runId={runId}
                methods={methods}
                workflowName={workflowName}
                parameters={parameters}
                software={software}
                citations={citations}
                qcEvents={qcEvents}
              />
            </div>
            */}
          </div>
        )}
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
    // PM must-fix #3 — explicit CTA. Handled by chat-with-artifacts'
    // 'biomate:run-again-with-edits' listener, which re-opens the workflow
    // panel and launches the run with the prior (or edited) parameters.
    window.dispatchEvent(
      new CustomEvent('biomate:run-again-with-edits', {
        detail: { runId, parameters },
      }),
    );
    // eslint-disable-next-line no-console
    console.info('[AfterRunReport] run-again-with-edits dispatched for run', runId);
    setCtaToast(tOr('afterrun.rerunning_toast', 'Re-running with your parameters — see the run panel.'));
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
          {cancelled ? tOr('afterrun.run_cancelled', 'Run cancelled') : tOr('afterrun.run_failed', 'Run failed')}
        </span>
        <button
          type="button"
          onClick={handleRunAgain}
          style={styles.runAgainBtn}
          data-testid="afterrun-run-again-failed"
        >
          ↻ {tOr('afterrun.run_again_edits', 'Run again with edits')}
        </button>
      </div>

      {/* Autofix narrative — most informative signal first. Distinguishes
          "failed after 15 fix attempts" (autofix exhausted) from "failed on
          first attempt with no autofix run" (autofix never ran). */}
      {autofixTried && (
        <div style={styles.autofixBox} data-testid="afterrun-autofix-summary">
          <div style={styles.autofixHead}>
            <span style={styles.autofixLabel}>{tOr('afterrun.autofix', 'Auto-fix')}</span>
            <span style={{
              ...styles.autofixState,
              color: autofix?.state === 'failed' ? 'oklch(0.40 0.18 25)'
                   : autofix?.state === 'succeeded' ? 'oklch(0.35 0.13 145)'
                   : 'oklch(0.40 0.12 245)',
            }}>
              {autofix?.state ?? tOr('afterrun.unknown', 'unknown')}
            </span>
            {(autofix?.totalAttempts ?? 0) > 0 && (
              <span style={styles.autofixAttempts}>
                {tOr('afterrun.attempts', '{{n}} attempt{{s}}', { n: autofix?.totalAttempts ?? 0, s: (autofix?.totalAttempts ?? 0) === 1 ? '' : 's' })}
              </span>
            )}
          </div>
          {autofixExhausted ? (
            <p style={styles.autofixMsg}>
              {tOr('afterrun.autofix_exhausted', 'BioMate auto-fix tried {{n}} remediation(s) and could not recover the run. See the underlying error and log tail below for the final failure.', { n: autofix?.totalAttempts ?? 0 })}
            </p>
          ) : autofix?.state === 'succeeded' ? (
            <p style={styles.autofixMsg}>
              {tOr('afterrun.autofix_succeeded', "Auto-fix recovered the run after {{n}} attempt(s). This is unusual if you're seeing this section — the run should be marked completed.", { n: autofix.totalAttempts ?? 0 })}
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
              {historyOpen ? tOr('afterrun.hide_history', '▾ Hide attempt history') : tOr('afterrun.show_history', '▸ Show attempt history')}
            </button>
          )}
          {historyOpen && (
            <div style={{ marginTop: 6 }}>
              {history === null ? (
                <span style={styles.empty}>{tOr('afterrun.loading_attempts', 'Loading attempts…')}</span>
              ) : history.length === 0 ? (
                <span style={styles.empty}>{tOr('afterrun.no_history', 'No detailed attempt history recorded.')}</span>
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
          {humanizeNfError(errorMessage)}
        </pre>
      )}

      {failedSteps && failedSteps.length > 0 && (
        <div style={styles.failedStepBox}>
          <div style={styles.failedStepLabel}>{tOr('afterrun.failed_steps', 'Failed step(s)')}</div>
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
            {tOr('afterrun.log_tail', 'Log tail')} {totalLines > tail.length ? tOr('afterrun.log_tail_showing', '(showing last {{n}} of {{total}})', { n: tail.length, total: totalLines }) : tOr('afterrun.log_tail_lines', '({{n}} lines)', { n: tail.length })}
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
  // Entity attribution + provenance (findings framework, migration step 1 — optional
  // until the emitter migrates to FindingRecord). See
  // docs/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md.
  entity?: string;
  source_file?: string;
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

type QcEvent = QcAssessment;

/**
 * useFetchTrajectory — best-effort fetch of the agent/step decision log for the
 * Trajectory tab. No backend agent-trajectory endpoint ships yet; this probes
 * a forward-looking route and returns [] (honest empty) on any failure, so the
 * TrajectoryView renders its own "No entries" empty state rather than fabricated
 * rows. When the backend event log lands, this is the single wiring point.
 */
function useFetchTrajectory(runId: string): TrajectoryRow[] {
  const [rows, setRows] = useState<TrajectoryRow[]>([]);
  useEffect(() => {
    if (!runId) return;
    let cancelled = false;
    fetch(`/api/workflows/runs/${encodeURIComponent(runId)}/trajectory`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        const arr: any[] = Array.isArray(data) ? data : data.rows || data.events || [];
        const allowed: TrajectoryKind[] = ["route", "tool", "clarify", "note", "gate"];
        const mapped: TrajectoryRow[] = arr
          .map((e) => ({
            t: String(e.t ?? e.ts ?? ""),
            kind: (allowed.includes(e.kind) ? e.kind : "note") as TrajectoryKind,
            k: String(e.k ?? e.title ?? e.kind ?? "Event"),
            d: String(e.d ?? e.detail ?? e.message ?? ""),
            meta: e.meta ? String(e.meta) : undefined,
          }));
        setRows(mapped);
      })
      .catch(() => { /* no agent-trajectory endpoint yet — honest empty state */ });
    return () => { cancelled = true; };
  }, [runId]);
  return rows;
}

function useFetchQcEvents(invocationId: string): QcEvent[] {
  const [events, setEvents] = useState<QcEvent[]>([]);
  useEffect(() => {
    setEvents([]);
    if (!invocationId) return;
    let cancelled = false;
    fetch(`/api/invocations/${invocationId}/qc-events`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (cancelled || !data) return;
        setEvents(normalizeQcEvents(data));
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

  // Only offer tools actually provisioned in this environment (optimistic until
  // the probe resolves; hidden once known-unavailable) — consistent with the
  // per-viewer buttons in StepOutputPreview so we never show a dead 400 launch.
  const { data: itAvail } = useInteractiveToolsAvailable();
  // Tool ordering: CellxGene first (most specific), then RStudio, then Jupyter.
  const orderedTools: Array<'cellxgene' | 'rstudio' | 'jupyter'> = ['cellxgene', 'rstudio', 'jupyter'];
  const availableTools = orderedTools.filter(
    (t) => toolMap.has(t) && (!itAvail || itAvail.tools[t]),
  );

  // Hide the whole row when there are no applicable tools, or when availability
  // is known and none are provisioned.
  if (toolMap.size === 0 || (itAvail && availableTools.length === 0)) return null;

  const openWith = (tool: 'jupyter' | 'rstudio' | 'cellxgene') => {
    setSelectedTool(tool);
    setOpen(true);
  };

  // Files for the currently selected tool.
  const currentFiles = toolMap.get(selectedTool)?.files ?? [];

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
      {/* One "Interactive panel" entry (not a button per tool): it opens the
          launcher where files are selected and the environment is chosen. The
          hint names the bundled environments (Jupyter / RStudio / CellxGene) so
          the single button isn't opaque. */}
      {(() => {
        const toolNames: Record<string, string> = { jupyter: 'Jupyter', rstudio: 'RStudio', cellxgene: 'CellxGene' };
        const primaryTool = availableTools[0] ?? 'jupyter';
        const names = availableTools.map((t) => toolNames[t]);
        const hint = names.length <= 1
          ? names[0]
          : `${names.slice(0, -1).join(', ')} & ${names[names.length - 1]}`;
        return (
          <>
            <button
              type="button"
              data-testid="afterrun-launch-interactive"
              onClick={() => openWith(primaryTool)}
              style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                padding: '5px 12px', fontSize: 12, fontWeight: 500,
                background: 'white', border: '1px solid oklch(0.88 0.01 245)',
                borderRadius: 6, cursor: 'pointer', color: 'oklch(0.22 0.01 260)',
              }}
            >
              <span style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11 }}>⌥</span>
              {tOr('afterrun.interactive_panel', 'Interactive panel')}
            </button>
            <span style={{ fontSize: 11, color: 'oklch(0.55 0.012 260)' }}>
              {tOr('afterrun.interactive_hint', 'Pick files, then open in {{tools}}', { tools: hint })}
            </span>
          </>
        );
      })()}
      <InteractiveLauncher
        open={open}
        onOpenChange={setOpen}
        outputs={currentFiles}
        initialTool={selectedTool}
        datasetFormat={currentFiles?.[0]?.name?.split(".").pop()?.toLowerCase() || ""}
      />
    </div>
  );
}

// Known heavy / binary-ish extensions: never AUTO-render an inline preview for
// these (the modal still previews them on explicit click). Density maps,
// single-cell/AnnData, R objects, BAM, CryoSPARC datasets.
const HEAVY_EXTS = new Set(["mrc", "map", "mrcs", "rec", "h5ad", "loom", "h5", "rds", "rdata", "rda", "bam", "cs", "csg"]);
// Above this byte size an otherwise-previewable file is treated as heavy and
// only previewed on demand (via the modal), not inlined.
const INLINE_SIZE_CAP = 3_000_000;
// How many (filtered) output cards to render before "Show more".
const OUTPUT_RENDER_CAP = 24;

/** Human-readable byte size; returns "" when size is absent/unknown. */
function humanSize(bytes?: number): string {
  if (bytes == null || !Number.isFinite(bytes) || bytes < 0) return "";
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = bytes / 1024, i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(v >= 10 ? 0 : 1)} ${units[i]}`;
}

/**
 * Mount children only once scrolled near the viewport — so a long outputs
 * gallery doesn't fire N step-file fetches on mount. Falls back to mounting
 * immediately where IntersectionObserver is unavailable (e.g. jsdom in tests).
 */
function LazyMount({ children, minHeight = 56 }: { children: React.ReactNode; minHeight?: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    if (visible) return;
    if (typeof IntersectionObserver === "undefined") { setVisible(true); return; }
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) { setVisible(true); io.disconnect(); }
    }, { rootMargin: "300px" });
    io.observe(el);
    return () => io.disconnect();
  }, [visible]);
  return (
    <div ref={ref}>
      {visible ? children : (
        <div style={{ minHeight, display: "flex", alignItems: "center", justifyContent: "center", color: "var(--text-muted)", fontSize: 11 }}>
          {tOr("afterrun.preview_lazy", "Scroll to load preview…")}
        </div>
      )}
    </div>
  );
}

function OutputsTab({
  outputs,
  runId,
  invocationId,
  executionStatus,
  projectId: initialProjectId,
}: {
  outputs: OutputFile[];
  runId: string;
  invocationId?: string;
  executionStatus?: string;
  projectId?: string;
}) {
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
            const rawStep = parts.length >= 2 ? parts[parts.length - 2] : "";
            // Don't surface an opaque run/history id (76d11493) as the step label.
            const isOpaqueId = /^[0-9a-f]{6,}$/i.test(rawStep) || /^[0-9a-f]{8}-[0-9a-f-]{8,}$/i.test(rawStep) || /^\d+$/.test(rawStep);
            const step = isOpaqueId ? "" : rawStep;
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
  // Inline-preview cards the user has collapsed (keyed by card key).
  const [collapsedCards, setCollapsedCards] = useState<Set<string>>(new Set());
  // Search box + render cap ("Show more") for long output lists.
  const [query, setQuery] = useState("");
  const [showAll, setShowAll] = useState(false);

  // Save-to-Project state — declared before any early return (Rules of Hooks).
  const [savedProjectId, setSavedProjectId] = useState<string | undefined>(initialProjectId);
  const [projects, setProjects] = useState<Array<{ id: string; name: string }>>([]);
  const [showProjectPicker, setShowProjectPicker] = useState(false);
  const [selectedProjectId, setSelectedProjectId] = useState<string>("");
  const [saveState, setSaveState] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const [savedProjectName, setSavedProjectName] = useState<string>("");

  // Fetch project list lazily when the picker is opened.
  useEffect(() => {
    if (!showProjectPicker || projects.length > 0) return;
    fetch("/api/projects", { credentials: "include" })
      .then(r => r.ok ? r.json() : Promise.reject())
      .then((data: any) => {
        const list = Array.isArray(data) ? data : (data?.projects ?? []);
        setProjects(list.map((p: any) => ({ id: String(p.id || p._id || ""), name: String(p.name || p.title || "Untitled") })));
        if (list.length > 0 && !selectedProjectId) setSelectedProjectId(String(list[0].id || list[0]._id || ""));
      })
      .catch(() => { /* picker still shows, just no options */ });
  }, [showProjectPicker, projects.length, selectedProjectId]);

  const handleSaveToProject = async () => {
    if (!selectedProjectId || saveState === "saving") return;
    setSaveState("saving");
    try {
      const r = await fetch(`/api/workflows/runs/${encodeURIComponent(runId)}/save-to-project`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({ projectId: selectedProjectId }),
      });
      if (!r.ok) {
        const j = await r.json().catch(() => ({}));
        throw new Error(j?.error || `HTTP ${r.status}`);
      }
      const proj = projects.find(p => p.id === selectedProjectId);
      setSavedProjectId(selectedProjectId);
      setSavedProjectName(proj?.name || "Project");
      setSaveState("saved");
      setShowProjectPicker(false);
    } catch (e: any) {
      console.error("[SaveToProject]", e);
      setSaveState("error");
      setTimeout(() => setSaveState("idle"), 3000);
    }
  };

  if (totalCount === 0) {
    return (
      <div style={styles.tabContent}>
        <p style={styles.empty}>
          {executionStatus === 'failed'
            ? tOr('afterrun.no_outputs_failed', 'No outputs — run did not complete successfully.')
            : tOr('afterrun.no_outputs_yet', 'No output files registered yet.')}
        </p>
      </div>
    );
  }

  const fileUrl = (f: OutputFile, download = false) =>
    `/api/workflows/runs/${runId}/step-file?path=${encodeURIComponent(f.path || f.name)}${download ? '&download=1' : ''}`;

  // Monochrome lucide glyphs at --text-muted (design spec 14 uses restrained
  // neutral line icons, not color emoji — emoji clash with the palette and
  // render per-OS). One icon component per file family.
  const iconForExt = (ext: string) => {
    const common = { size: 14, style: { color: 'var(--text-muted)', flexShrink: 0 } as React.CSSProperties };
    if (['png','jpg','jpeg','gif','svg','webp','tiff'].includes(ext)) return <ImageIcon {...common} />;
    if (['csv','tsv','xlsx'].includes(ext)) return <FileSpreadsheet {...common} />;
    if (['html','htm'].includes(ext)) return <FileCode {...common} />;
    if (['pdf'].includes(ext)) return <FileText {...common} />;
    if (['json','yaml','yml'].includes(ext)) return <FileJson {...common} />;
    if (['fastq','fq','fa','fasta'].includes(ext)) return <Dna {...common} />;
    if (['bam','vcf','bed','gtf','gff'].includes(ext)) return <Database {...common} />;
    return <FileIcon {...common} />;
  };

  // Mirrors the file types StepOutputPreview can render a viewer for: images,
  // tables, text/logs, pdf/html, structures, density maps, single-cell + R
  // objects (launchers), sequences/annotations, and JSON chart sidecars.
  const canPreview = (ext: string) =>
    [
      'png','jpg','jpeg','gif','svg','webp',
      'csv','tsv','tab','html','htm','txt','text','log','json','yaml','yml','md','pdf',
      'pdb','mmcif','cif','ent',
      'mrc','map','mrcs','rec',
      'h5ad','loom','h5',
      'rds','rdata','rda',
      'fasta','fa','faa','fna','vcf','bed','gff','gtf','sam',
    ].includes(ext);

  // AUTO-inline a preview only for a previewable file that is light: not a known
  // heavy/binary type and (when the size is known) under the size cap. Heavy /
  // large / unknown-large previewable files get a compact card with an on-demand
  // "preview" (opens the modal) — we never auto-fetch a huge/binary artifact.
  const shouldInlinePreview = (f: OutputFile) => {
    if (!canPreview(f.ext)) return false;
    if (HEAVY_EXTS.has((f.ext || '').toLowerCase())) return false;
    if (typeof f.size === 'number' && f.size > INLINE_SIZE_CAP) return false;
    return true;
  };

  const q = query.trim().toLowerCase();
  const filtered = q
    ? effectiveOutputs.filter((f) =>
        (f.name || '').toLowerCase().includes(q) || (f.ext || '').toLowerCase().includes(q))
    : effectiveOutputs;
  const shown = showAll ? filtered : filtered.slice(0, OUTPUT_RENDER_CAP);
  const cardKey = (f: OutputFile, i: number) => (f.path || f.name) + '::' + i;

  return (
    <div style={styles.tabContent}>
      {/* Bulk-download actions */}
      <div style={styles.bulkActions}>
        {invocationId && (
          <JobButton
            kind="download_all_zip"
            payload={{ invocationId, runId }}
            label={tOr('afterrun.download_all_zip', '↓ Download all ({{n}}) as ZIP', { n: totalCount })}
            onReady={triggerDownload}
            className="afterrun-download-all-btn"
          />
        )}
        <a
          href={reproUrl}
          download
          style={{ ...styles.bulkBtn, ...styles.bulkBtnSecondary }}
          title={tOr('afterrun.repro_bundle_title', 'Configs, command scripts, logs, versions.yml — enough to re-run elsewhere')}
        >
          ↓ {tOr('afterrun.repro_bundle', 'Reproducibility bundle')}
        </a>

        {/* Save-to-Project affordance */}
        {savedProjectId ? (
          <a
            href="/files"
            data-testid="afterrun-saved-open-datahub"
            style={{ ...styles.bulkBtn, background: 'oklch(0.93 0.07 145)', color: 'oklch(0.35 0.12 145)', border: '1px solid oklch(0.78 0.10 145)', textDecoration: 'none', display: 'inline-flex', alignItems: 'center', gap: 4 }}
            title={tOr('afterrun.saved_open_title', 'Open in the data hub — the saved outputs are first-class dataset objects there (quality, lineage, versions)')}
          >
            ✓ {tOr('afterrun.saved_open', 'Saved to {{name}} — open in Files ↗', { name: savedProjectName || tOr('afterrun.project_fallback', 'project') })}
          </a>
        ) : (
          <div style={{ position: 'relative', display: 'inline-block' }}>
            <button
              onClick={() => setShowProjectPicker(v => !v)}
              style={{ ...styles.bulkBtn, ...styles.bulkBtnSecondary, cursor: 'pointer', border: '1px solid var(--border)' }}
              title={tOr('afterrun.save_project_title', 'Copy outputs to your project file browser')}
            >
              📁 {tOr('afterrun.save_to_project', 'Save to Project')}
            </button>
            {showProjectPicker && (
              <div style={{
                position: 'absolute', top: '100%', left: 0, zIndex: 50, marginTop: 4,
                background: 'var(--surface, #fff)', border: '1px solid var(--border)',
                borderRadius: 8, padding: 12, boxShadow: '0 4px 16px rgba(0,0,0,0.1)',
                minWidth: 240,
              }}>
                <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 8, color: 'var(--text)' }}>
                  {tOr('afterrun.save_outputs_to_project', 'Save outputs to project')}
                </div>
                {projects.length === 0 ? (
                  <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>{tOr('afterrun.loading', 'Loading…')}</div>
                ) : (
                  <select
                    value={selectedProjectId}
                    onChange={e => setSelectedProjectId(e.target.value)}
                    style={{ width: '100%', fontSize: 12, padding: '4px 8px', borderRadius: 4, border: '1px solid var(--border)', marginBottom: 8 }}
                  >
                    {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                )}
                <div style={{ display: 'flex', gap: 6 }}>
                  <button
                    onClick={handleSaveToProject}
                    disabled={!selectedProjectId || saveState === 'saving' || projects.length === 0}
                    style={{ flex: 1, fontSize: 12, padding: '4px 10px', borderRadius: 4, cursor: 'pointer', background: 'oklch(0.22 0.01 260)', color: '#fff', border: 'none', opacity: saveState === 'saving' ? 0.6 : 1 }}
                  >
                    {saveState === 'saving' ? tOr('afterrun.saving', 'Saving…') : saveState === 'error' ? tOr('afterrun.error_retry', 'Error — retry') : tOr('afterrun.save', 'Save')}
                  </button>
                  <button
                    onClick={() => setShowProjectPicker(false)}
                    style={{ fontSize: 12, padding: '4px 10px', borderRadius: 4, cursor: 'pointer', background: 'transparent', border: '1px solid var(--border)', color: 'var(--text)' }}
                  >
                    {tOr('afterrun.cancel', 'Cancel')}
                  </button>
                </div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 8 }}>
                  {tOr('afterrun.files_appear', "Files will appear in the project's Files tab.")}
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      <InteractiveToolsRow outputs={effectiveOutputs} />

      {/* Outputs gallery — each output as an inline preview card. */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap', margin: '2px 0 10px' }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-muted)' }} data-testid="outputs-heading">
          {tOr('afterrun.outputs_heading', 'Outputs')} ({totalCount})
        </span>
        <input
          type="text"
          value={query}
          onChange={(e) => { setQuery(e.target.value); setShowAll(false); }}
          placeholder={tOr('afterrun.outputs_search_ph', 'Search outputs…')}
          data-testid="outputs-search"
          style={{ fontSize: 12, padding: '3px 8px', borderRadius: 4, border: '1px solid var(--border)', background: 'var(--bg, transparent)', color: 'var(--text)', minWidth: 160 }}
        />
        <span style={{ fontSize: 11, color: 'var(--text-muted)' }} data-testid="outputs-count">
          {tOr('afterrun.showing_n_of_m', 'showing {{n}} of {{m}}', { n: shown.length, m: filtered.length })}
          {filtered.length !== totalCount && ` (${tOr('afterrun.filtered_from', 'filtered from {{t}}', { t: totalCount })})`}
        </span>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }} data-testid="output-files-table">
        {[...shown].sort((a, b) => String(a.step || '~~').localeCompare(String(b.step || '~~'))).map((f, i, arr) => {
          const key = cardKey(f, i);
          const canPrev = canPreview(f.ext);
          const inline = shouldInlinePreview(f);
          const collapsed = collapsedCards.has(key);
          const sizeLabel = humanSize(f.size);
          // §3.1 — group outputs under a per-producing-step header (sorted by step
          // so same-step files are contiguous; header shown on each step change).
          const showStepHeader = i === 0 || String(arr[i - 1].step || '') !== String(f.step || '');
          return (
            <React.Fragment key={key}>
              {showStepHeader && f.step && (
                <div data-testid="output-step-group" style={{
                  fontSize: 11, fontWeight: 600, letterSpacing: '.04em', textTransform: 'uppercase',
                  color: 'var(--text-muted)', margin: i === 0 ? '0 0 2px' : '12px 0 2px',
                }}>{f.step}</div>
              )}
            <div
              data-testid="output-card"
              data-output-ref-card={f.path || f.name}
              style={{ border: '1px solid var(--border)', borderRadius: 8, padding: 10 }}
            >
              {/* Card header */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12 }}>
                <span style={{ display: 'inline-flex', alignItems: 'center' }}>{iconForExt(f.ext)}</span>
                <span style={{ fontFamily: 'ui-monospace, monospace', fontWeight: 600, color: 'var(--text)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 260 }} title={f.name}>{f.name}</span>
                <span style={{ color: 'var(--text-muted)', textTransform: 'uppercase', fontSize: 10 }}>{f.ext || '—'}</span>
                {f.step && (
                  <span style={{ color: 'var(--text-muted)', fontSize: 10, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 120 }} title={f.step}>· {f.step}</span>
                )}
                <span style={{ flex: 1 }} />
                {sizeLabel && <span style={{ color: 'var(--text-muted)', fontSize: 10 }}>{sizeLabel}</span>}
                {canPrev && (
                  <button
                    onClick={() => setPreviewFile(f)}
                    style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', color: 'var(--accent, oklch(0.55 0.18 260))', fontSize: 11 }}
                    title={tOr('afterrun.view_fullsize', 'Open full size')}
                  >{inline ? tOr('afterrun.view', 'view') : tOr('afterrun.preview', 'preview')}</button>
                )}
                <a
                  href={fileUrl(f, true)}
                  download
                  title={tOr('afterrun.download', 'Download')}
                  aria-label={tOr('afterrun.download', 'Download')}
                  style={{ color: 'var(--accent, oklch(0.55 0.18 260))', display: 'inline-flex', alignItems: 'center', gap: 3, textDecoration: 'none', fontSize: 11 }}
                ><ArrowDownToLine size={12} />{tOr('afterrun.dl', 'dl')}</a>
              </div>

              {/* Inline preview (lazy-mounted) ONLY for light previewable files.
                  Heavy/binary/large files preview on demand via the "preview" modal. */}
              {inline && !collapsed && (
                <LazyMount>
                  <StepOutputPreview
                    runId={runId}
                    file={{ name: f.name, path: f.path || f.name, extension: f.ext }}
                    projectId={savedProjectId}
                    onClose={() => setCollapsedCards((s) => { const n = new Set(s); n.add(key); return n; })}
                  />
                </LazyMount>
              )}
              {inline && collapsed && (
                <button
                  onClick={() => setCollapsedCards((s) => { const n = new Set(s); n.delete(key); return n; })}
                  style={{ marginTop: 6, background: 'none', border: 'none', padding: 0, cursor: 'pointer', color: 'var(--accent, oklch(0.55 0.18 260))', fontSize: 11 }}
                >{tOr('afterrun.show_preview', 'Show preview')}</button>
              )}
            </div>
            </React.Fragment>
          );
        })}
        {filtered.length === 0 && (
          <p style={{ ...styles.empty, fontSize: 12 }} data-testid="outputs-no-match">
            {tOr('afterrun.no_outputs_match', 'No outputs match your search.')}
          </p>
        )}
        {!showAll && filtered.length > shown.length && (
          <button
            onClick={() => setShowAll(true)}
            data-testid="outputs-show-more"
            style={{ alignSelf: 'flex-start', fontSize: 12, padding: '5px 10px', borderRadius: 4, cursor: 'pointer', background: 'transparent', border: '1px solid var(--border)', color: 'var(--text)' }}
          >{tOr('afterrun.show_n_more', 'Show {{n}} more', { n: filtered.length - shown.length })}</button>
        )}
      </div>

      {/* Inline preview overlay */}
      {previewFile && (
        <div
          onClick={() => setPreviewFile(null)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.45)', zIndex: 9999, display: 'flex', alignItems: 'flex-start', justifyContent: 'flex-end' }}
        >
          {/* The output-file detail view is a PANE, not a centered pop-up
              (design spec 08/12): a right-anchored side panel. Height fits its
              CONTENT up to the viewport (maxHeight 100vh) — a non-previewable
              artefact (.rds etc.) shows a compact card (spec 14.2) instead of a
              near-empty full-height void; a big table/image still fills the pane. */}
          <div
            onClick={e => e.stopPropagation()}
            style={{ background: 'var(--bg, #fff)', padding: 20, width: 'min(1080px, 96vw)', maxWidth: 'none', height: 'auto', maxHeight: '100vh', overflow: 'auto', borderLeft: '1px solid var(--border, #e5e7eb)', boxShadow: '-8px 0 32px rgba(0,0,0,0.18)' }}
          >
            {previewFile.step && (
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 8 }}>{previewFile.step}</div>
            )}
            {/* Rich evidence viewer — StepOutputPreview resolves the right viewer
                by file type (image/pdf/html/text plus structure pLDDT·PAE,
                sequence tracks, hit grids, density maps, cryo charts, single-cell
                / R-object launchers). Fetches the same step-file endpoint the
                Outputs table already uses, so no new backend surface. */}
            <StepOutputPreview
              runId={runId}
              file={{ name: previewFile.name, path: previewFile.path || previewFile.name, extension: previewFile.ext }}
              onClose={() => setPreviewFile(null)}
              projectId={savedProjectId}
              maxHClass="max-h-[70vh]"
            />
            <div style={{ marginTop: 10, display: 'flex', justifyContent: 'flex-end' }}>
              <a href={fileUrl(previewFile, true)} download style={{ fontSize: 12, color: 'var(--accent, oklch(0.55 0.18 260))' }}>↓ {tOr('afterrun.download', 'Download')}</a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * MethodsTab — the methods report as an editable file object (v2 Spec 12,
 * scoped increment). Default view is the read-only report; an "Edit" toggle
 * opens the same content in the proven TipTap document editor
 * (RegulatoryDocumentEditor) so the user can revise the AI-generated methods
 * prose and save an edited version (downloaded as markdown).
 *
 * SCOPE / DEFERRED (per docs/20260909_V2GAP_SEARCH_FILES_REPORTS_CONNECTORS.md
 * Surface A): the full Spec-12 report-as-file thesis — server-side
 * `fileVersions(id)` versioning, chat-propose-diff (before/after accept/reject),
 * the report appearing in the project file tree, and multi-format
 * (PDF/DOCX/HTML/ZIP) export — is NOT built here. This increment delivers the
 * edit-and-save affordance only; the edited version is saved as a local
 * markdown download, not a persisted server-side new version. Versioning is
 * deferred: there is no backend endpoint to append a report version, so
 * fabricating a version chip would be dishonest.
 */
export function MethodsTab({
  methods,
  workflowName,
  runId,
}: {
  methods: MethodsData;
  workflowName?: string;
  runId?: string;
}) {
  const [editing, setEditing] = useState(false);
  // Live plain-text mirror of the editor content, kept via onEdit so Save can
  // export exactly what the user sees. Seeded from the report text.
  const [editedText, setEditedText] = useState<string>(methods.text);
  const [savedToast, setSavedToast] = useState<string | null>(null);
  // The report is a versioned object (#22): v0 is the immutable run original,
  // edits are appended server-side. Loaded from GET /api/runs/:id/report/versions.
  const [versions, setVersions] = useState<Array<{ version: number; immutable?: boolean; note?: string; createdAt?: string | null }>>([]);
  const loadVersions = async () => {
    if (!runId) return;
    try {
      const r = await fetch(`/api/runs/${encodeURIComponent(runId)}/report/versions`, { credentials: "include" });
      if (r.ok) { const d = await r.json(); if (Array.isArray(d?.versions)) setVersions(d.versions); }
    } catch { /* offline — leave list empty */ }
  };

  // Re-seed when the source report changes (a fresh run / cache fill) — but
  // NOT while the user is mid-edit, or a report refresh would silently clobber
  // their in-progress edits. `editing` is intentionally NOT a dependency:
  // re-seeding is driven by a source-text change only, and reads the current
  // editing flag at that moment; adding it would also fire on the exit-edit
  // transition and reset unsaved edits.
  useEffect(() => {
    if (!editing) setEditedText(methods.text);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [methods.text]);

  // Load persisted report versions on mount / run change.
  useEffect(() => {
    loadVersions();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runId]);

  if (!methods.hasRealContent) {
    return <p style={styles.empty}>{tOr('afterrun.methods_unavailable', 'Methods report not available for this workflow.')}</p>;
  }

  // Offline / no-run fallback: download the edit locally.
  const handleSaveEditedLocal = (labelPrefix = "Edited methods report downloaded") => {
    const blob = new Blob([editedText], { type: "text/markdown;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    const base = (workflowName || "methods").replace(/[^\w.-]+/g, "-").slice(0, 60);
    const suffix = runId ? `-${runId}` : "";
    a.download = `biomate-methods-${base}${suffix}-edited.md`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    setSavedToast(labelPrefix);
    setTimeout(() => setSavedToast(null), 4000);
  };

  // Server-first: persist a REAL version (#22). The immutable run-original (v0)
  // is seeded from the current report; this edit is appended and keeps the runId
  // back-link. Falls back to a local download when offline / no runId.
  const handleSaveVersion = async () => {
    if (runId) {
      try {
        const r = await fetch(`/api/runs/${encodeURIComponent(runId)}/report/versions`, {
          method: "POST",
          credentials: "include",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: editedText, note: "edited in report viewer", currentMarkdown: methods.text }),
        });
        if (r.ok) {
          const d = await r.json();
          await loadVersions();
          setSavedToast(`Saved as version v${d?.version?.version ?? "?"} (persisted)`);
          setTimeout(() => setSavedToast(null), 4000);
          return;
        }
      } catch { /* fall through to local download */ }
    }
    handleSaveEditedLocal(runId ? "Server unavailable — downloaded locally" : "Edited methods report downloaded");
  };

  return (
    <div data-testid="methods-tab">
      <div style={styles.methodsToolbar}>
        <span style={styles.methodsToolbarLabel}>
          {editing ? tOr('afterrun.methods_editing', "Editing methods report") : tOr('afterrun.methods_report', "Methods report")}
        </span>
        <span style={{ flex: 1 }} />
        {savedToast && (
          <span style={styles.toast} role="status" data-testid="methods-save-toast">
            {savedToast}
          </span>
        )}
        {editing ? (
          <>
            <button
              type="button"
              onClick={handleSaveVersion}
              style={styles.methodsEditBtn}
              data-testid="methods-save-edited"
              title={tOr('afterrun.methods_save_version_title', 'Save a new persisted version of the report (immutable run-original kept). Falls back to a local download offline.')}
            >
              ⤴ {tOr('afterrun.methods_save_version', 'Save version')}
            </button>
            <button
              type="button"
              onClick={() => setEditing(false)}
              style={styles.methodsDoneBtn}
              data-testid="methods-done-editing"
            >
              {tOr('afterrun.methods_done', 'Done editing')}
            </button>
          </>
        ) : (
          <button
            type="button"
            onClick={() => setEditing(true)}
            style={styles.methodsEditBtn}
            data-testid="methods-edit-toggle"
            title={tOr('afterrun.methods_edit_title', 'Edit the methods report in place')}
          >
            ✎ {tOr('afterrun.methods_edit', 'Edit')}
          </button>
        )}
      </div>

      {versions.length > 0 && (
        <div data-testid="report-versions" style={{ margin: "6px 0 10px", fontSize: 12 }}>
          <div style={{ color: "var(--text-muted)", marginBottom: 4 }}>{tOr('afterrun.report_versions', 'Report versions')}</div>
          {versions.slice().sort((a, b) => a.version - b.version).map((v) => (
            <div key={v.version} data-testid={`report-version-${v.version}`} style={{ display: "flex", gap: 8, alignItems: "center", padding: "1px 0" }}>
              <span className="mono" style={{ fontWeight: 600 }}>v{v.version}</span>
              {v.immutable
                ? <span style={{ fontSize: 10, padding: "0 5px", borderRadius: 4, background: "oklch(0.93 0.03 260)", color: "oklch(0.35 0.05 260)" }}>{tOr('afterrun.immutable_original', 'immutable run original')}</span>
                : <span style={{ color: "var(--text-muted)" }}>{v.note || tOr('afterrun.edit_note', 'edit')}</span>}
              {v.createdAt && <span style={{ color: "var(--text-muted)" }}>· {String(v.createdAt).slice(0, 10)}</span>}
            </div>
          ))}
        </div>
      )}

      {editing ? (
        <div style={styles.methodsEditor} data-testid="methods-editor">
          {/* Simple prose editor for the methods report. Replaced the IND §2.6
              RegulatoryDocumentEditor (item 18): its §2.6.1–§2.6.6 section tabs and
              AI/edited counters are for a regulatory Module-2.6 assembly, not an
              after-run methods report (which has its own 1./2./3. sections) — so it
              showed a wrong section sequence and a meaningless "N edited" count. */}
          <textarea
            value={editedText}
            onChange={(e) => setEditedText(e.target.value)}
            data-testid="methods-editor-textarea"
            spellCheck={false}
            style={{
              width: "100%", minHeight: 420, resize: "vertical",
              fontFamily: "var(--font-mono, ui-monospace, monospace)", fontSize: 13,
              lineHeight: 1.55, padding: 12, border: "1px solid var(--border)",
              borderRadius: 8, background: "var(--surface, #fff)", color: "var(--text)",
              whiteSpace: "pre-wrap",
            }}
          />
        </div>
      ) : (
        <pre style={styles.methodsBody} data-testid="methods-readonly">{methods.text}</pre>
      )}
    </div>
  );
}

interface ReproRecord {
  recordVersion: string;
  runId: string;
  workflowName: string;
  status: string;
  createdAt: string | null;
  completedAt: string | null;
  parameters: Record<string, unknown>;
  inputBindings: any[];
  outputs: Array<{ id?: string; name: string; fileType?: string; sizeBytes?: number; sha256?: string | null }>;
  outputCount: number;
}

const reproKey: React.CSSProperties = { padding: "3px 8px 3px 0", color: "#666", whiteSpace: "nowrap", verticalAlign: "top", width: "1%" };
const reproH: React.CSSProperties = { fontWeight: 600, fontSize: 12, margin: "14px 0 6px" };
const reproTable: React.CSSProperties = { width: "100%", borderCollapse: "collapse", fontSize: 12 };
const reproTh: React.CSSProperties = { textAlign: "left", color: "#666", fontWeight: 600, padding: "2px 8px 4px 0", borderBottom: "1px solid #eee" };
const reproEmpty: React.CSSProperties = { fontSize: 12, color: "#888", fontStyle: "italic" };

function fmtBytes(n?: number): string {
  if (typeof n !== "number" || !isFinite(n)) return "—";
  if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
  if (n >= 1024) return (n / 1024).toFixed(1) + " KB";
  return n + " B";
}

/**
 * Collapsible <details> section for the Reproducibility record tab. Matches the
 * accepted design (RunSurface.jsx: <details><summary>…</summary></details>).
 * The first section is opened by default (`defaultOpen`).
 */
function ReproSection({
  title,
  testId,
  defaultOpen = false,
  children,
}: {
  title: string;
  testId?: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  return (
    <details open={defaultOpen} style={styles.reproDetails} data-testid={testId}>
      <summary style={styles.reproSummary}>{title}</summary>
      <div style={styles.reproSectionBody}>{children}</div>
    </details>
  );
}

/**
 * ReproducibilityRecordTab — the unified after-run audit trail (accepted
 * design). It leads with the reproducibility record (identity + resolved
 * parameters + bound inputs + outputs), then folds the former peer tabs
 * (resolved Parameters, Methods, Software, Citations, QC report, Trajectory)
 * as expandable <details> sections. Nothing is deleted — each section reuses
 * its original tab body; they are simply re-nested here.
 */
function ReproducibilityRecordTab({
  runId,
  methods,
  workflowName,
  parameters,
  software,
  citations,
  qcEvents,
  // trajectoryRows,  (commented out 2026-10-28 — trajectory lives in the Full Step View)
}: {
  runId: string;
  methods: MethodsData;
  workflowName?: string;
  parameters?: Record<string, unknown>;
  software: Record<string, string>;
  citations: Citation[];
  qcEvents: QcEvent[];
  // trajectoryRows: TrajectoryRow[];  (commented out 2026-10-28)
}) {
  return (
    <div style={styles.tabContent} data-testid="after-record-tab">
      <span
        style={{ fontSize: 11.5, color: "oklch(0.48 0.012 260)", fontStyle: "italic", display: "block", marginBottom: 10 }}
        data-testid="record-intro"
      >
        {tOr('afterrun.record_intro', 'The complete audit trail is kept together. Expand the part you need; nothing is hidden or discarded.')}
      </span>

      {/* Identity + bound inputs/outputs — opened by default. */}
      <ReproSection title={tOr('afterrun.section.record', 'Reproducibility record')} testId="record-section-record" defaultOpen>
        <ReproducibilityTab runId={runId} />
      </ReproSection>

      <ReproSection title={tOr('afterrun.section.resolved_params', 'Resolved parameters')} testId="record-section-params">
        <ParametersTab parameters={parameters} runId={runId} />
      </ReproSection>

      <ReproSection title={tOr('afterrun.section.methods', 'Methods')} testId="record-section-methods">
        <MethodsTab methods={methods} workflowName={workflowName} runId={runId} />
      </ReproSection>

      <ReproSection title={tOr('afterrun.section.software', 'Software')} testId="record-section-software">
        <SoftwareTab versions={software} />
      </ReproSection>

      <ReproSection title={tOr('afterrun.section.citations', 'Citations')} testId="record-section-citations">
        <CitationsTab citations={citations} />
      </ReproSection>

      <ReproSection title={tOr('afterrun.section.qc_report', 'QC report')} testId="record-section-qc">
        <QcAuditTab events={qcEvents} outputs={[]} />
      </ReproSection>

      {/* Trajectory section removed 2026-10-20 (UI refinement item 17): there is
          no backend agent-trajectory endpoint, so it was always "No entries of
          this kind", and it duplicates the per-step record already shown in the
          Full Step View (the step view IS the trajectory). Re-add when a real
          agent-trajectory endpoint ships. */}
    </div>
  );
}

/**
 * Reproducibility tab (Phase 2) — renders the unified reproducibility record
 * (GET /api/runs/:id/reproducibility-record): workflow identity + resolved
 * parameters + bound inputs + outputs. Fetched lazily when the tab is opened.
 * SHA-256 shows a dash until the checksum increment populates it.
 */
function ReproducibilityTab({ runId }: { runId: string }) {
  const [rec, setRec] = useState<ReproRecord | null>(null);
  const [err, setErr] = useState(false);
  const [hashing, setHashing] = useState(false);
  useEffect(() => {
    if (!runId) return;
    let cancelled = false;
    fetch(`/api/runs/${runId}/reproducibility-record`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((d) => { if (!cancelled) setRec(d); })
      .catch(() => { if (!cancelled) setErr(true); });
    return () => { cancelled = true; };
  }, [runId]);

  if (err) return <div style={styles.tabContent} data-testid="repro-error">{tOr('afterrun.repro_error', 'Reproducibility record unavailable for this run.')}</div>;
  if (!rec) return <div style={styles.tabContent} data-testid="repro-loading">{tOr('afterrun.repro_loading', 'Loading reproducibility record…')}</div>;

  const paramEntries = Object.entries(rec.parameters || {});
  const downloadJson = () => {
    const blob = new Blob([JSON.stringify(rec, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `biomate-repro-${rec.runId}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  // Checksums are opt-in (hashing bytes is bounded but not free), so the default
  // record shows "—". This re-fetches with ?checksums=1 to populate SHA-256 on
  // demand — the tamper-evidence a reproducibility record is for.
  const anyUnhashed = (rec.outputs || []).some((o: any) => !o.sha256);
  const computeChecksums = async () => {
    if (hashing) return;
    setHashing(true);
    try {
      const r = await fetch(`/api/runs/${runId}/reproducibility-record?checksums=1`, { credentials: "include" });
      if (r.ok) setRec(await r.json());
    } catch { /* leave dashes — harmless */ }
    finally { setHashing(false); }
  };

  return (
    <div style={styles.tabContent} data-testid="repro-tab">
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 10 }}>
        <span style={{ fontSize: 11, opacity: 0.7 }}>{tOr('afterrun.repro_record_v', 'Reproducibility record v{{v}}', { v: rec.recordVersion })}</span>
        <span style={{ flex: 1 }} />
        <button type="button" onClick={downloadJson} style={styles.runAgainBtn} data-testid="repro-download-json">↓ {tOr('afterrun.download_record_json', 'Download record (JSON)')}</button>
      </div>

      <table style={{ ...reproTable, marginBottom: 4 }}><tbody>
        <tr><td style={reproKey}>{tOr('afterrun.field.workflow', 'Workflow')}</td><td>{rec.workflowName}</td></tr>
        <tr><td style={reproKey}>{tOr('afterrun.field.run_id', 'Run id')}</td><td style={{ fontFamily: "monospace" }}>{rec.runId}</td></tr>
        <tr><td style={reproKey}>{tOr('afterrun.field.status', 'Status')}</td><td>{rec.status}</td></tr>
        <tr><td style={reproKey}>{tOr('afterrun.field.created', 'Created')}</td><td>{rec.createdAt || "—"}</td></tr>
        <tr><td style={reproKey}>{tOr('afterrun.field.completed', 'Completed')}</td><td>{rec.completedAt || "—"}</td></tr>
      </tbody></table>

      <div style={reproH}>{tOr('afterrun.parameters_count', 'Parameters ({{n}})', { n: paramEntries.length })}</div>
      {paramEntries.length ? (
        <table style={reproTable}><tbody>
          {paramEntries.map(([k, v]) => (
            <tr key={k}><td style={reproKey}>{k}</td><td style={{ fontFamily: "monospace", wordBreak: "break-word" }}>{typeof v === "object" ? JSON.stringify(v) : String(v)}</td></tr>
          ))}
        </tbody></table>
      ) : <div style={reproEmpty}>{tOr('afterrun.no_parameters', 'No parameters recorded.')}</div>}

      <div style={reproH}>{tOr('afterrun.input_bindings_count', 'Input bindings ({{n}})', { n: rec.inputBindings?.length || 0 })}</div>
      {rec.inputBindings?.length ? (
        <table style={reproTable}><tbody>
          {rec.inputBindings.map((b: any, i: number) => (
            <tr key={i}><td style={reproKey}>{b?.stepId ?? i}</td><td style={{ fontFamily: "monospace", wordBreak: "break-word" }}>{b?.name || b?.datasetId || JSON.stringify(b)}</td></tr>
          ))}
        </tbody></table>
      ) : <div style={reproEmpty}>{tOr('afterrun.no_bound_inputs', 'No bound inputs recorded (run predates input-binding capture, or has none).')}</div>}

      <div style={{ ...reproH, display: "flex", alignItems: "center", gap: 10 }}>
        <span>{tOr('afterrun.outputs_count', 'Outputs ({{n}})', { n: rec.outputCount })}</span>
        {rec.outputs?.length ? (
          anyUnhashed ? (
            <button
              type="button"
              onClick={computeChecksums}
              disabled={hashing}
              data-testid="repro-compute-checksums"
              title={tOr('afterrun.compute_checksums_title', 'Compute SHA-256 for each output (bounded: ≤25 files, ≤25 MB each)')}
              style={{ background: "none", border: "none", padding: 0, cursor: hashing ? "default" : "pointer", fontSize: 11, color: "var(--accent, oklch(0.55 0.18 260))" }}
            >
              {hashing ? tOr('afterrun.computing_checksums', "Computing checksums…") : tOr('afterrun.compute_checksums', "↻ Compute checksums")}
            </button>
          ) : (
            <span style={{ fontSize: 11, color: "oklch(0.55 0.12 155)" }} data-testid="repro-checksums-done">{tOr('afterrun.checksums_done', 'SHA-256 computed')} ✓</span>
          )
        ) : null}
      </div>
      {rec.outputs?.length ? (
        <table style={reproTable}>
          <thead><tr><th style={reproTh}>{tOr('afterrun.col_name', 'Name')}</th><th style={reproTh}>{tOr('afterrun.col_type', 'Type')}</th><th style={reproTh}>{tOr('afterrun.col_size', 'Size')}</th><th style={reproTh}>{tOr('afterrun.col_sha256', 'SHA-256')}</th></tr></thead>
          <tbody>
            {rec.outputs.map((o, i) => (
              <tr key={o.id || i}>
                <td style={{ wordBreak: "break-word" }}>{o.name}</td>
                <td>{o.fileType || "—"}</td>
                <td>{fmtBytes(o.sizeBytes)}</td>
                <td style={{ fontFamily: "monospace", fontSize: 10 }} title={o.sha256 || "not yet hashed"}>{o.sha256 ? o.sha256.slice(0, 16) + "…" : "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : <div style={reproEmpty}>{tOr('afterrun.no_outputs_resolved', 'No outputs resolved for this run.')}</div>}
    </div>
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
    // Handled by chat-with-artifacts' 'biomate:run-again-with-edits' listener,
    // which re-opens the workflow panel and launches with these parameters.
    window.dispatchEvent(
      new CustomEvent('biomate:run-again-with-edits', {
        detail: { runId, parameters },
      }),
    );
    // eslint-disable-next-line no-console
    console.info('[AfterRunReport] run-again-with-edits dispatched (params tab) for run', runId);
    setCtaToast(tOr('afterrun.rerunning_toast', 'Re-running with your parameters — see the run panel.'));
    setTimeout(() => setCtaToast(null), 4000);
  };

  return (
    <div style={styles.tabContent}>
      {/* "Run again with edits" button removed 2026-10-20 (UI refinement): it
          dispatched an immediate re-run, so the "with edits" label was wrong —
          there was no chance to edit. Re-running lives on the workflow panel
          footer ("Run again"), which opens the editable param view. */}
      {entries.length === 0 ? (
        <p style={styles.empty}>{tOr('afterrun.no_param_values', 'No parameter values recorded.')}</p>
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
  /** Outputs for the run (from the reproducibility record). Used ONLY to decide
   *  whether the content-addressed / tamper-evident guarantee can be stated
   *  honestly: it is claimed only for outputs that actually carry a sha256.
   *  Optional — omitted callers get the honest "computed on demand" wording. */
  outputs?: Array<{ sha256?: string | null }>;
  /** Optional reviewer record from the backend; omit to hide the e-sig block. */
  eSignature?: {
    reviewer?: string;
    reviewedAt?: string;
    sigShort?: string;
    totpVerified?: boolean;
  };
}

function isPassedStatus(status?: string): boolean {
  return status === "pass";
}

function deriveAction(e: QcEvent): string {
  return qcActionTaken(e);
}

function QcAuditTab({ events, outputs, eSignature }: QcAuditTabProps) {
  // Honesty gate (#25): only claim content-addressed / tamper-evident storage
  // for outputs that actually carry a sha256. Many runs leave sha256 empty, so
  // asserting the guarantee unconditionally would be dishonest.
  const hashedCount = (outputs ?? []).filter(o => !!o?.sha256).length;
  const totalOutputs = (outputs ?? []).length;
  const anyHashed = hashedCount > 0;
  const allHashed = totalOutputs > 0 && hashedCount === totalOutputs;
  const passed = events.filter(e => isPassedStatus(e.status)).length;
  const failed = events.filter(e => e.status === "fail").length;
  const other = events.length - passed - failed;

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
          color: 'var(--text-muted)',
        }}>
          <div style={{ fontWeight: 600, fontSize: 15 }} data-testid="qc-unavailable">{tOr('afterrun.qc_no_results', 'QC results unavailable')}</div>
          <div style={{ fontSize: 13, color: 'var(--text-muted)', maxWidth: 320 }}>
            {tOr('afterrun.qc_no_results_detail', 'No QC evaluations were recorded. This does not establish that the checks passed.')}
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
          { label: tOr('afterrun.qc_recorded', 'Checks recorded'), value: events.length, color: undefined, testid: 'qc-stat-evaluated' },
          { label: tOr('afterrun.qc_passed', 'Passed'),           value: passed,        color: 'oklch(0.62 0.16 145)', testid: 'qc-stat-passed' },
          { label: tOr('afterrun.qc_failed_checks', 'Flagged'), value: failed, color: 'oklch(0.62 0.16 60)', testid: 'qc-stat-failed' },
          { label: tOr('afterrun.qc_other_checks', 'Advisory / unavailable'), value: other, color: undefined, testid: 'qc-stat-other' },
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
          {tOr('afterrun.qc_none_fired', 'No QC gates fired for this run.')}
        </div>
      ) : (
        <>
          <div style={{ fontSize: 11, color: 'oklch(0.48 0.012 260)', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 6 }}>
            {tOr('afterrun.qc_log_title', 'Gate evaluation log')}
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
                <th style={{ padding: '7px 8px' }}>{tOr('afterrun.qc_col_ts', 'Timestamp (UTC)')}</th>
                <th style={{ padding: '7px 8px' }}>{tOr('afterrun.qc_col_gate', 'Gate')}</th>
                <th style={{ padding: '7px 8px' }}>{tOr('afterrun.qc_col_threshold', 'Threshold')}</th>
                <th style={{ padding: '7px 8px' }}>{tOr('afterrun.qc_col_observed', 'Observed')}</th>
                <th style={{ padding: '7px 8px' }}>{tOr('afterrun.qc_col_result', 'Result')}</th>
                <th style={{ padding: '7px 8px' }}>{tOr('afterrun.qc_col_action', 'Action')}</th>
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
                      {qcResultLabel(e.status)}
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
              {tOr('afterrun.chain_of_custody', 'Chain of custody')}
            </div>
            <span data-testid="qc-custody-copy">
              {allHashed ? (
                tOr('afterrun.custody_all', 'All {{n}} recorded outputs are content-addressed by SHA-256 checksum, so each corresponds to a tamper-evident manifest entry. Parameter sets and gate decisions above are versioned alongside them.', { n: hashedCount })
              ) : anyHashed ? (
                tOr('afterrun.custody_some', '{{n}} of {{total}} recorded outputs carry a SHA-256 checksum and are content-addressed (tamper-evident); the remaining outputs are not yet hashed — their checksums are computed on demand. Parameter sets and gate decisions above are versioned with the run manifest.', { n: hashedCount, total: totalOutputs })
              ) : (
                tOr('afterrun.custody_none', 'Parameter sets and gate decisions above are versioned with the run manifest. Output checksums are computed on demand and are not yet hashed for this run, so content-addressed / tamper-evident storage is not asserted here.')
              )}
              {' '}{tOr('afterrun.custody_no_override', 'No human override modified this run.')}
            </span>
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
              <div style={{ fontWeight: 600, marginBottom: 4 }}>{tOr('afterrun.e_signature', 'Operator e-signature')}</div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'oklch(0.40 0.012 260)' }}>
                <span>
                  {eSignature.reviewer && <>{tOr('afterrun.reviewed_by', 'Reviewed by')} {eSignature.reviewer}</>}
                  {eSignature.reviewedAt && <> · {eSignature.reviewedAt}</>}
                  {eSignature.totpVerified && <> · {tOr('afterrun.totp_verified', 'TOTP verified')}</>}
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
          <div><b style={{ color: "oklch(0.22 0.012 260)" }}>{fig.kept.toLocaleString()}</b>{" "}{fig.unit ?? tOr('afterrun.retained', 'retained')}</div>
          <div style={{ fontSize: 10.5, color: "oklch(0.48 0.012 260)" }}>
            {tOr('afterrun.dropped_of', '{{dropped}} dropped of {{total}}', { dropped: (fig.total - fig.kept).toLocaleString(), total: fig.total.toLocaleString() })}
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
        {tOr('afterrun.headline_figures', 'Headline figures')}
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
                {tOr('afterrun.from_source', 'from {{file}}', { file: fig.source_file })}
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
  if (entries.length === 0) return <p style={styles.empty}>{tOr('afterrun.no_software', 'No software versions recorded.')}</p>;
  return (
    <div style={styles.tabContent}>
      <p style={{ fontSize: 11, color: 'oklch(0.48 0.012 260)', marginBottom: 8 }}>
        {tOr('afterrun.software_source_pre', 'Sourced from')} <code>versions.yml</code> {tOr('afterrun.software_source_post', 'emitted by each pipeline step.')}
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
  if (citations.length === 0) return <p style={styles.empty}>{tOr('afterrun.no_citations', 'No citations registered.')}</p>;
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
  const { runId, workflowName, parameters, outputs, methods, qcEvents: rawQcEvents, findings, software, citations } = args;
  const qcEvents = normalizeQcEvents(rawQcEvents);
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

  // Summary tab — "run original" badge marking the immutable record.
  runOriginalRow: { display: "flex", alignItems: "center", gap: 8, marginBottom: 10, flexWrap: "wrap" as React.CSSProperties["flexWrap"] },
  runOriginalBadge: { fontSize: 10, fontWeight: 700, textTransform: "uppercase", letterSpacing: "0.05em", color: "oklch(0.35 0.01 260)", background: "oklch(0.93 0.01 240)", border: "1px solid oklch(0.85 0.01 245)", borderRadius: 999, padding: "3px 9px", whiteSpace: "nowrap" },
  runOriginalHint: { fontSize: 11, color: "oklch(0.48 0.012 260)", lineHeight: 1.4 },

  // Reproducibility record — collapsible <details> sections.
  reproDetails: { border: "1px solid oklch(0.92 0.008 260)", borderRadius: 6, padding: "0 10px", background: "oklch(0.99 0.002 240)" },
  reproSummary: { fontSize: 12.5, fontWeight: 600, color: "oklch(0.30 0.01 260)", cursor: "pointer", padding: "9px 2px", listStyle: "revert" },
  reproSectionBody: { paddingBottom: 8 },
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
  methodsToolbar: { display: "flex", alignItems: "center", gap: 8, marginBottom: 8 },
  methodsToolbarLabel: { fontSize: 11, fontWeight: 600, color: "oklch(0.45 0.012 260)", textTransform: "uppercase", letterSpacing: "0.04em" },
  methodsEditBtn: { fontSize: 11, fontWeight: 600, color: "oklch(0.45 0.15 260)", background: "none", border: "1px solid oklch(0.85 0.03 260)", borderRadius: 5, padding: "3px 9px", cursor: "pointer" },
  methodsDoneBtn: { fontSize: 11, fontWeight: 500, color: "oklch(0.45 0.012 260)", background: "none", border: "1px solid oklch(0.88 0.01 260)", borderRadius: 5, padding: "3px 9px", cursor: "pointer" },
  methodsEditor: { border: "1px solid oklch(0.9 0.008 260)", borderRadius: 6, height: 480, overflow: "hidden", display: "flex", flexDirection: "column" },
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
