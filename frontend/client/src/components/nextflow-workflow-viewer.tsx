import React, { useState, useEffect, useRef } from 'react';
import '@/styles/workflow-panel.css';
import { useRunAgainParamCarryover } from '@/hooks/useRunAgainParamCarryover';
import { analytics } from '@/lib/analytics';
import { emitUxEvent } from "@/lib/ux-telemetry";
import { PhaseCard } from "./phase-card";
import { ParameterGroup } from "./parameter-group";
import { StepOutputPreview } from "./step-output-preview";
import { StepAdjustModal } from "./step-adjust-modal";
import { Loader2, CheckCircle2, XCircle, AlertTriangle, Download, RotateCcw, Square, ChevronRight, Settings2, ShieldCheck, Activity, Clock, SkipForward } from "lucide-react";
import { ReportConfusionButton } from "./feedback/report-confusion-button";
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt";
import { ChatOutputAttachments } from "./chat-output-attachments";
import { FindingsCard } from "./findings-card";
import type { PrereqChecklist } from "@/lib/prereq-normalizer";
import { GalaxyDatasetBrowser } from "./galaxy-dataset-browser";
import { useToast } from "@/hooks/use-toast";
import { LicenseGate } from "./license-gate";
import { AutoLoopPanel } from "./auto-loop-panel";
import type { AutoLoopPanelState } from "./auto-loop-panel";
import { stripAnsi } from "@/lib/utils";
import { AfterRunReport } from "@/v2/AfterRunReport";

interface NextflowWorkflowViewerProps {
  workflowId?: string;
  invocationId?: string;
  executionBlockedReason?: string;
  prereqChecklist?: PrereqChecklist;
  workflowDefinition?: any; // Nextflow definition
  initialParams?: any;
  lastSubmittedParams?: Record<string, any>;
  onExecute?: (params: any) => void;
  onPause?: () => void;
  onResume?: () => void;
  onCancel?: () => void;
  status?: 'idle' | 'running' | 'paused' | 'completed' | 'failed' | 'pending_review';
  errorMessage?: string;
  progress?: number;
  onParameterChange?: (id: string, value: any) => void;
  sessionId?: string;
  runId?: string;
  autofix?: {
    state: "idle" | "analyzing" | "fixing" | "restarting" | "succeeded" | "failed";
    source?: "auto" | "manual" | "unknown";
    active?: boolean;
    message?: string;
    totalAttempts?: number;
  };
  nextflowStatus?: any;
  dataVerification?: any;
  onAdjustViaChat?: (message: string) => void;
  /**
   * Workflow-progress chat lines (delivered via the SSE `chat_progress` event).
   * Backend narrator emits these on lifecycle transitions; the host component
   * appends them as short italic messages to the current chat session.
   * See backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py
   */
  onWorkflowProgress?: (event: { kind: string; friendly_message: string; ts?: number; technical?: any }) => void;
  executionEngine?: string;
  /** Execution metrics from status API (includes perStepLlmCost). */
  executionMetrics?: {
    runtime?: { totalSeconds?: number; perStepSeconds?: Record<string, number> };
    perStepLlmCost?: Record<string, number | null>;
    [key: string]: any;
  };
  /**
   * Called during drag with the new panel width in px.
   * When provided the component renders a drag handle on its left edge.
   * The parent should apply the width to the panel container.
   */
  onResize?: (width: number) => void;
}

type ViewerParameter = {
  id: string;
  name: string;
  type: 'string' | 'number' | 'boolean' | 'select' | 'file';
  label: string;
  value?: any;
  defaultValue?: any;
  description?: string;
  required?: boolean;
  group?: string;
  options?: { label: string; value: any }[];
  minimum?: number;
  maximum?: number;
  /** Whether this value was pre-filled by the AI (shows KnowledgeBadge + Override button) */
  autoFilled?: boolean;
  /** Scientific rationale for the AI-recommended value */
  rationale?: string;
};

type ViewerPhaseStatus = 'pending' | 'running' | 'completed' | 'failed' | 'paused';

type ViewerPhase = {
  id: string;
  name: string;
  description?: string;
  status: ViewerPhaseStatus;
  toolId?: string;
  parameters?: Record<string, unknown>;
  inputs?: Record<string, unknown>;
  outputFiles?: Array<{ name: string; path: string; extension: string }>;
  /** Phase group key (e.g. 'A'–'E' for cryo-EM) from the backend steps API */
  phase_group?: string;
  /** Human-readable phase group label (e.g. 'Phase A — Motion Correction & CTF') */
  phase_label?: string;
  /** Phase-level summary text returned by the backend (from phases.summary) */
  summary?: string;
  /** Whether auto-loop QC is enabled for this phase (from phases.autoloop) */
  autoloop?: boolean;
};

type StepExecutionState = {
  backendState?: string;
  phaseStatus: ViewerPhaseStatus;
  jobId?: string;
  startedAt?: string;
  lastRunAt?: string;
  runCount: number;
  outputsCount?: number;
  isExecuting: boolean;
  errorMessage?: string;
};

type QCGateFailure = { metric: string; value: number; threshold: number; operator: string; message: string };

type QCGateData = {
  processName: string;
  qcMetrics: Record<string, number>;
  failures: Array<QCGateFailure | string>;
  suggestions: Array<{
    parameter: string;
    currentValue: any;
    suggestedValue: any;
    reason: string;
    confidence: number;
  }>;
};

// Human-readable labels for QC threshold metric keys
const QC_THRESHOLD_LABELS: Record<string, { label: string; unit?: string }> = {
  reads_surviving_pct: { label: 'Reads Surviving Trim', unit: '%' },
  alignment_rate: { label: 'Alignment Rate', unit: '%' },
  mito_fraction_pct: { label: 'Mitochondrial Reads', unit: '%' },
  fit_quality: { label: 'CTF Fit Quality', unit: '' },
  mapped_pct: { label: 'Mapped Reads', unit: '%' },
  duplicate_rate: { label: 'Duplicate Rate', unit: '%' },
  assigned_reads_pct: { label: 'Assigned Reads', unit: '%' },
  median_cv_coverage: { label: 'Median CV Coverage', unit: '' },
  tss_enrichment: { label: 'TSS Enrichment Score', unit: '' },
  frip_score: { label: 'FRiP Score', unit: '' },
  nrf_score: { label: 'Non-Redundant Fraction', unit: '' },
  median_fragment_length: { label: 'Median Fragment Length', unit: 'bp' },
  min_particles: { label: 'Minimum Particle Count', unit: '' },
  min_resolution: { label: 'Minimum Resolution', unit: 'Å' },
  resolution_angstrom: { label: 'Resolution', unit: 'Å' },
  ctf_fit_quality: { label: 'CTF Fit Quality', unit: '' },
  snr_db: { label: 'Signal-to-Noise Ratio', unit: 'dB' },
  peptides_identified: { label: 'Peptides Identified', unit: '' },
  protein_fdr: { label: 'Protein FDR', unit: '' },
  sequence_depth: { label: 'Sequencing Depth', unit: '' },
  good_barcodes_pct: { label: 'Valid Barcodes', unit: '%' },
  median_genes_per_cell: { label: 'Median Genes / Cell', unit: '' },
};

function inferParamType(value: any, backendType?: string): ViewerParameter['type'] {
  // Backend now emits explicit type — trust it when present.
  if (backendType === 'file') return 'file';
  if (backendType === 'boolean') return 'boolean';
  if (backendType === 'integer' || backendType === 'float') return 'number';
  if (backendType === 'select') return 'select';
  // Fallback: infer from JS typeof
  if (typeof value === "number") return "number";
  if (typeof value === "boolean") return "boolean";
  return "string";
}

function prettifyParamLabel(raw: string): string {
  return raw
    .replace(/_/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function buildViewerParameters(workflowDefinition: any, currentParams: Record<string, any>): ViewerParameter[] {
  // Prefer structured required_params / optional_params when the backend .nf parser populated them.
  const reqList: any[] = Array.isArray(workflowDefinition?.required_params) ? workflowDefinition.required_params : [];
  const optList: any[] = Array.isArray(workflowDefinition?.optional_params) ? workflowDefinition.optional_params : [];
  if (reqList.length > 0 || optList.length > 0) {
    // Build structured params from required/optional lists
    const structuredNames = new Set([...reqList, ...optList].map((p: any) => p?.name).filter(Boolean));
    const structured = [...reqList, ...optList]
      .filter((p: any) => p?.name && !String(p.name).startsWith("__"))
      .map((p: any) => {
        const userValue = currentParams[p.name];
        const defaultVal = p.default ?? null;
        return {
          id: p.name,
          name: p.name,
          type: inferParamType(userValue ?? defaultVal, p.type),
          label: p.label || prettifyParamLabel(p.name),
          description: p.description,
          value: userValue !== undefined ? userValue : (p.value !== undefined ? p.value : (defaultVal !== null ? defaultVal : "")),
          defaultValue: defaultVal,
          required: reqList.some((r: any) => r.name === p.name),
          group: p.group || undefined,
          options: Array.isArray(p.options) ? p.options : undefined,
          minimum: p.minimum != null ? Number(p.minimum) : undefined,
          maximum: p.maximum != null ? Number(p.maximum) : undefined,
          autoFilled: p.autoFilled === true,
          rationale: p.rationale || undefined,
        };
      });
    // Also include inline_parameters entries not already covered by structured params
    const fromInline = workflowDefinition?.inline_parameters && typeof workflowDefinition.inline_parameters === "object"
      ? workflowDefinition.inline_parameters
      : {};
    // Use the dominant group from schema params so inline extras don't create a second group
    const dominantGroup = structured.find(p => p.group)?.group;
    const extraInline = Object.entries(fromInline)
      .filter(([key]) => !key.startsWith("__") && !structuredNames.has(key))
      .map(([key, value]) => ({
        id: key,
        name: key,
        type: inferParamType(value),
        label: prettifyParamLabel(key),
        value: currentParams[key] !== undefined ? currentParams[key] : value,
        defaultValue: undefined,
        required: false,
        autoFilled: true,
        group: dominantGroup,
      }));
    return [...structured, ...extraInline];
  }

  // Fallback: old flat-map from parameters / inline_parameters keys.
  const fromWorkflow = workflowDefinition?.parameters && typeof workflowDefinition.parameters === "object"
    ? workflowDefinition.parameters
    : {};
  const fromInline = workflowDefinition?.inline_parameters && typeof workflowDefinition.inline_parameters === "object"
    ? workflowDefinition.inline_parameters
    : {};
  const merged: Record<string, any> = {
    ...fromWorkflow,
    ...fromInline,
    ...currentParams,
  };

  return Object.entries(merged)
    .filter(([key]) => !key.startsWith("__"))
    .map(([key, value]) => ({
      id: key,
      name: key,
      type: inferParamType(value),
      label: prettifyParamLabel(key),
      value,
      defaultValue: fromWorkflow[key],
      required: false,
      // Mark inline-param entries as autoFilled so the viewer's
      // "default-open when autoFilled present" logic triggers and so the
      // input rows show the LLM-prefill visual badge.
      autoFilled: Object.prototype.hasOwnProperty.call(fromInline, key),
    }));
}

function normalizeBackendState(state: unknown): string {
  if (typeof state !== "string") return "unknown";
  return state.toLowerCase();
}

function mapBackendToPhaseStatus(state: string): ViewerPhaseStatus {
  if (state === "ok" || state === "completed") return "completed";
  if (state === "error" || state === "failed" || state === "cancelled") return "failed";
  if (state === "paused") return "paused";
  if (state === "running" || state === "queued") return "running";
  return "pending";
}

function isTerminalBackendState(state: string): boolean {
  return state === "ok" || state === "completed" || state === "error" || state === "failed" || state === "cancelled";
}

async function readApiErrorMessage(response: Response): Promise<string> {
  try {
    const payload = await response.json();
    if (typeof payload?.message === "string" && payload.message.trim().length > 0) {
      return payload.message;
    }
    if (typeof payload?.error === "string" && payload.error.trim().length > 0) {
      return payload.error;
    }
  } catch {
    // Fallback to plain text for non-JSON responses.
  }

  try {
    const text = await response.text();
    if (text.trim().length > 0) {
      return text;
    }
  } catch {
    // Keep default below.
  }
  return `Request failed (${response.status})`;
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function DownloadCommandsPanel({ runId }: { runId: string }) {
  const [data, setData] = useState<any>(null);

  useEffect(() => {
    fetch(`/api/workflows/runs/${runId}/download_commands`)
      .then(r => r.json())
      .then(d => setData(d))
      .catch(() => {});
  }, [runId]);

  if (!data?.download_commands) return null;

  const files: Array<{ name: string; size: number; extension: string; download_url: string | null }> =
    data.files ?? [];
  const downloadableFiles = files.filter(f => f.download_url && f.size > 0);

  // Only show this panel when there are individual presigned file links.
  // Bulk download is already covered by the "Download All" button above.
  if (downloadableFiles.length === 0) return null;

  return (
    <div data-testid="download-commands-panel">
      {downloadableFiles.map((f) => (
        <div key={f.name} className="output-file">
          <a href={f.download_url!} download={f.name}>{f.name}</a>
          <span className="size">{formatFileSize(f.size)}</span>
        </div>
      ))}
    </div>
  );
}



// ---------------------------------------------------------------------------
// Track 3D: Pre-run cost estimate badge
// Commented out — static lookup table values are not accurate enough to show
// users. Actual infrastructure cost should appear on the per-user billing page
// sourced from real Lago billing events.
// ---------------------------------------------------------------------------
// function CostEstimateBadge({ nextflowPath, sampleCount }: { nextflowPath: string; sampleCount?: number }) {
//   const [estimate, setEstimate] = React.useState<{
//     cost_min_usd: number;
//     cost_max_usd: number;
//     estimated_runtime_hours: number;
//   } | null>(null);
//
//   React.useEffect(() => {
//     if (!nextflowPath) return;
//     const params = new URLSearchParams({ nextflow_path: nextflowPath });
//     if (sampleCount) params.set('sample_count', String(sampleCount));
//     fetch(`/api/workflows/estimate_cost?${params}`)
//       .then(r => r.ok ? r.json() : null)
//       .then(data => data && setEstimate(data))
//       .catch(() => {});
//   }, [nextflowPath, sampleCount]);
//
//   if (!estimate) return null;
//   return (
//     <div className="text-xs text-muted-foreground flex items-center gap-1 mt-1" data-testid="cost-estimate-badge">
//       <span>Est. cost:</span>
//       <span className="font-medium text-foreground">
//         ${estimate.cost_min_usd}–${estimate.cost_max_usd}
//       </span>
//       <span>·</span>
//       <span>{estimate.estimated_runtime_hours}h runtime</span>
//     </div>
//   );
// }

// ── PhaseGroupSection ─────────────────────────────────────────────────────────
// Reference design (PhaseCard.jsx + Step): uses .phase / .phase-head / .phase-body / .step CSS classes

interface PhaseGroup {
  key: string;
  label: string;
  steps: any[];
  phaseParams: string[];
}

const STEP_NUMBERS = ['①','②','③','④','⑤','⑥','⑦','⑧','⑨','⑩',
                      '⑪','⑫','⑬','⑭','⑮','⑯','⑰','⑱','⑲','⑳'];

/** Returns true when an autoloop phase key matches a group key. */
function autoloopPhaseMatches(groupKey: string, autoloopPhase: string | undefined): boolean {
  if (!autoloopPhase) return false;
  if (groupKey === 'all') return true;
  const norm = autoloopPhase.toLowerCase().replace(/^phase_/, '');
  const key = groupKey.toLowerCase();
  return norm === key || norm.startsWith(key + '_') || key.startsWith(norm + '_');
}

function PhaseGroupSection({
  group,
  renderedParameters,
  params,
  onParamChange,
  onRun,
  onSkip,
  onStopPhase,
  onPreviewFile,
  onAdjustAndRerun,
  activeRunId,
  executionBlockedReason,
  isPrereqBlocked,
  isAutofixActive,
  isGlobalExecutionActive,
  autoLoopPanelState,
  autoloopEnabled,
  autoloopLocked,
  onToggleAutoloop,
  onDismissAutoloop,
  onAcceptAutoloop,
  qcThresholds,
  qcOverrides,
  onQcChange,
  paramGroupToPhaseKey,
  qcAdvisoryByStep,
  isFirstPhase,
}: {
  group: PhaseGroup;
  renderedParameters: any[];
  params: Record<string, any>;
  onParamChange: (id: string, val: any) => void;
  onRun: (phase: any) => void;
  onSkip: (id: string) => void;
  onStopPhase?: () => void;
  onPreviewFile: (file: any) => void;
  onAdjustAndRerun: (step: any) => void;
  activeRunId: string | null | undefined;
  executionBlockedReason?: string;
  isPrereqBlocked: boolean;
  isAutofixActive: boolean;
  isGlobalExecutionActive: boolean;
  autoLoopPanelState?: AutoLoopPanelState;
  autoloopEnabled: boolean;
  autoloopLocked?: boolean;
  onToggleAutoloop: () => void;
  onDismissAutoloop: () => void;
  onAcceptAutoloop?: (paramChanges: Record<string, unknown>) => void;
  qcThresholds: Array<{ key: string; label: string; unit: string; direction: string; value: number; modified: boolean; rationale?: string }>;
  qcOverrides: Record<string, number>;
  onQcChange: (key: string, val: number | null) => void;
  /** Pre-built map from normalized group name → phase key, computed once at panel mount. */
  paramGroupToPhaseKey: Map<string, string>;
  /** Gap 1 (inverse) — near-threshold advisories keyed by process_name. */
  qcAdvisoryByStep?: Record<string, { metric?: string; value?: any; threshold?: any }[]>;
  /** True for the first phase in groupedPhases; auto-expanded on panel open
   *  so the PARAMETERS summary is visible without a click (UI audit
   *  2026-06-14 found the summary was hidden on first render when no
   *  phase was already running). */
  isFirstPhase?: boolean;
}) {
  const { steps, label, phaseParams } = group;
  const [qcEditorOpen, setQcEditorOpen] = React.useState(false);

  const completedCount = steps.filter(s =>
    ['completed', 'ok', 'COMPLETED'].includes(String(s.status))
  ).length;
  const anyRunning = steps.some(s =>
    ['running', 'RUNNING', 'SUBMITTED', 'submitted'].includes(String(s.status))
  );
  const anyFailed = steps.some(s =>
    ['failed', 'FAILED', 'error', 'cancelled'].includes(String(s.status))
  );
  const allDone = completedCount === steps.length && steps.length > 0;

  // Auto-expand when running, failed, or a QC gate/autoloop event fires for this phase
  const hasGateForPhase = !!(autoLoopPanelState?.gateResults &&
    autoloopPhaseMatches(group.key, autoLoopPanelState.gateResults.phase));
  // Auto-expand first phase on panel open so the PARAMETERS summary line is
  // visible without a click. UI audit 2026-06-14 (docs/sge-audit-2026-06-14/)
  // surfaced that schema-grounded prefill was working but the user couldn't
  // see the filled-in params until they manually expanded a phase.
  const [open, setOpen] = useState(
    () => anyRunning || anyFailed || hasGateForPhase || !!isFirstPhase,
  );
  React.useEffect(() => {
    if (anyRunning || anyFailed || hasGateForPhase) setOpen(true);
  }, [anyRunning, anyFailed, hasGateForPhase]);

  // Use the param names collected from step bodies during phase parsing.
  // phaseParams is built by _enrich_steps_with_phase_info and holds the
  // params.* references found in each phase's process blocks.
  const phaseRenderedParams = renderedParameters.filter(p =>
    phaseParams.includes(p.id || p.name || '')
  );
  const [phaseParamsOpen, setPhaseParamsOpen] = React.useState(false);

  // Phase status and letter badge
  const phaseStatus = anyFailed ? 'failed' : anyRunning ? 'running' : allDone ? 'completed' : 'pending';
  const letter = group.key === 'all' ? String(Math.min(steps.length, 9)) : group.key.toUpperCase().charAt(0);
  const dashIdx = label.indexOf('—');
  const phaseTitle = dashIdx > -1 ? label.slice(0, dashIdx).trim() : label;
  const phaseSub   = dashIdx > -1 ? label.slice(dashIdx + 1).trim() : '';

  const canRunPhase = !!activeRunId && !isGlobalExecutionActive && !isAutofixActive && !isPrereqBlocked && !executionBlockedReason;

  return (
    <div className={`phase ${phaseStatus}${open ? ' open' : ''}`} data-testid={`phase-group-${group.key}`} data-status={phaseStatus}>
      {/* Phase header — always visible, click to toggle */}
      <div className="phase-head" onClick={() => setOpen(o => !o)} role="button" aria-expanded={open}>
        <span className="caret"><ChevronRight className="h-3.5 w-3.5" /></span>
        <div className="letter">{letter}</div>
        <div className="titles">
          <div className="title">{phaseTitle}</div>
          {phaseSub && <div className="sub">{phaseSub}</div>}
        </div>
        {phaseStatus === 'running' && (
          <span className="chip run">
            <Loader2 className="h-2.5 w-2.5 animate-spin" style={{display:'inline-block'}}/>
            RUNNING
          </span>
        )}
        {phaseStatus === 'completed' && <span className="chip ok">DONE</span>}
        {phaseStatus === 'failed'    && <span className="chip err">FAILED</span>}
        {phaseStatus === 'pending' && (
          <span className="progress-chip">{steps.length} step{steps.length !== 1 ? 's' : ''}</span>
        )}
        {(phaseStatus === 'running' || phaseStatus === 'completed') && (
          <span className="progress-chip">{completedCount}/{steps.length}</span>
        )}
        {/* Run Phase button — always visible in header so test can find it pre-run */}
        {!allDone && !anyRunning && (
          <button
            className="btn sm"
            disabled={!canRunPhase}
            onClick={(e) => { e.stopPropagation(); steps.forEach((s: any) => onRun(s)); }}
            data-testid={`button-run-phase-${group.key}`}
            title={canRunPhase ? `Run all steps in ${phaseTitle}` : "Start the workflow first to enable phase-level execution"}
          >
            Run
          </button>
        )}
      </div>

      {/* Phase body — visible when expanded */}
      {open && (
        <div className="phase-body">
          {/* Per-phase parameters — shown inline, before steps */}
          {phaseRenderedParams.length > 0 && (
            <div className="phase-params">
              <div className="phase-params-head" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '4px 14px', borderBottom: '1px solid var(--border)' }}>
                <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                  Parameters
                  <span style={{ fontWeight: 400, marginLeft: 4, color: 'var(--text-dim)' }}>
                    ({phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).length > 0
                      ? `${phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).length} required`
                      : `${phaseRenderedParams.length} configured`})
                  </span>
                </span>
                <button
                  className="linkish"
                  style={{ fontSize: 10 }}
                  onClick={() => setPhaseParamsOpen(o => !o)}
                  data-testid={`phase-params-toggle-${group.key}`}
                >
                  {phaseParamsOpen ? 'collapse' : 'edit'}
                </button>
              </div>
              {/* Compact summary row when collapsed */}
              {!phaseParamsOpen && (
                <div style={{ padding: '4px 14px 6px', fontSize: 11, color: 'var(--text-muted)', lineHeight: 1.4 }}>
                  {phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).length > 0 ? (
                    <span style={{ color: 'var(--warn)' }}>
                      {phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).map(p => p.label).join(', ')} — required
                    </span>
                  ) : (
                    phaseRenderedParams.slice(0, 4).map(p =>
                      `${p.label}: ${p.value ?? p.defaultValue ?? '—'}`
                    ).join(' · ')
                  )}
                </div>
              )}
              {/* Full editable param list when expanded */}
              {phaseParamsOpen && (
                <div style={{ padding: '6px 14px 8px', display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {phaseRenderedParams.map(p => (
                    <div key={p.id} className="param-row" style={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: 8, alignItems: 'center' }}>
                      <span className="k" style={{ fontSize: 11, color: p.required && (!p.value || p.value === '') ? 'var(--warn)' : 'var(--text-muted)' }}>
                        {p.label}{p.required ? ' *' : ''}
                      </span>
                      {p.type === 'boolean' ? (
                        <button
                          type="button"
                          className={`switch${(p.value === true || p.value === 'true') ? ' on' : ''}`}
                          onClick={() => onParamChange(p.id, !(p.value === true || p.value === 'true'))}
                          style={{ flexShrink: 0 }}
                        />
                      ) : p.options ? (
                        <select
                          className="v"
                          value={String(p.value ?? p.defaultValue ?? '')}
                          style={{ fontSize: 11, padding: '2px 4px', background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 3, color: 'var(--text)' }}
                          onChange={e => onParamChange(p.id, e.target.value)}
                        >
                          {p.options.map((o: string) => <option key={o} value={o}>{o}</option>)}
                        </select>
                      ) : (
                        <input
                          type={p.type === 'number' ? 'number' : 'text'}
                          className="v"
                          value={String(p.value ?? p.defaultValue ?? '')}
                          placeholder={p.required ? 'required' : ''}
                          style={{ fontSize: 11, padding: '2px 6px', width: 140, background: 'var(--surface)',
                            border: `1px solid ${p.required && (!p.value || p.value === '') ? 'var(--warn)' : 'var(--border)'}`,
                            borderRadius: 3, color: 'var(--text)', fontFamily: p.type === 'file' ? 'var(--font-mono)' : undefined }}
                          onChange={e => onParamChange(p.id, e.target.value)}
                        />
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Step rows */}
          {steps.map((step: any, idx: number) => {
            const s = String(step.status || '').toLowerCase();
            const isRunning = ['running','submitted'].includes(s);
            const isDone    = ['completed','ok'].includes(s);
            const isFailed  = ['failed','error','cancelled'].includes(s);
            const stepStatus = isDone ? 'completed' : isRunning ? 'running' : isFailed ? 'failed' : 'pending';
            const hasOutputs = (step.outputFiles?.length ?? 0) > 0;

            return (
              <div
                key={step.id}
                className={`step ${stepStatus}`}
                data-testid={`phase-card-${step.id}`}
                data-status={s}
              >
                <div className="step-head">
                  <div className={`name${isFailed ? ' dim' : ''}`}>
                    {STEP_NUMBERS[idx] ?? `${idx + 1}.`}&nbsp;{step.name}
                  </div>
                  {(() => {
                    const adv = qcAdvisoryByStep?.[String(step.processName || step.name || '')];
                    if (!adv || adv.length === 0) return null;
                    const head = adv[0];
                    const more = adv.length - 1;
                    return (
                      <span
                        data-testid={`phase-step-advisory-${step.id}`}
                        title={adv.map((a) => `${a.metric}: ${a.value} (threshold ${a.threshold})`).join(', ')}
                        style={{ marginLeft: 6, fontSize: 10, fontWeight: 600, padding: '1px 5px', borderRadius: 4, background: 'oklch(0.95 0.06 80)', color: 'oklch(0.45 0.15 70)' }}
                      >
                        ⚠ {head.metric}{more > 0 ? ` +${more}` : ''}
                      </span>
                    );
                  })()}
                  {isRunning && <span className="chip run" style={{marginLeft:'auto'}}><Loader2 className="h-2.5 w-2.5 animate-spin" style={{display:'inline-block'}}/>RUNNING</span>}
                  {isDone    && <span className="chip ok"  style={{marginLeft:'auto'}}>DONE</span>}
                  {isFailed  && <span className="chip err" style={{marginLeft:'auto'}}>FAILED</span>}
                  <div className="actions">
                    {(isDone || isFailed) && (
                      <button
                        className="btn ghost sm"
                        onClick={(e) => { e.stopPropagation(); onRun(step); }}
                        data-testid={`button-run-step-${step.id}`}
                      >Rerun</button>
                    )}
                    {!isRunning && !isDone && step.parameters && Object.keys(step.parameters).length > 0 && (
                      <button
                        className="btn ghost sm"
                        onClick={(e) => { e.stopPropagation(); onAdjustAndRerun(step); }}
                        data-testid={`button-adjust-step-${step.id}`}
                      >Params</button>
                    )}
                    {/* Skip step — no backend API, UI-only; hidden until backend skip endpoint added
                    {!isRunning && !isDone && (
                      <button
                        className="btn ghost sm danger"
                        onClick={(e) => { e.stopPropagation(); onSkip(step.id); }}
                        title="Skip step"
                        data-testid={`button-skip-step-${step.id}`}
                      >Skip</button>
                    )} */}
                  </div>
                </div>

                {/* Param meta (first 3 params inline, non-running non-done) */}
                {!isRunning && !isDone && step.parameters && Object.keys(step.parameters).length > 0 && (
                  <div className="step-meta">
                    {Object.entries(step.parameters as Record<string,unknown>).slice(0,3).map(([k,v]) => `${k}: ${v}`).join(' · ')}
                  </div>
                )}

                {/* Output files */}
                {hasOutputs && (
                  <div className="step-outputs">
                    {(step.outputFiles as any[]).slice(0,4).map((f: any, fi: number) => (
                      <span className="output-file" key={fi}>
                        <span className="fn" title={f.name}>{f.name}</span>
                        <span
                          className="act"
                          onClick={() => onPreviewFile(f)}
                          data-testid={`phase-card-preview-btn-${f.name}`}
                        >view</span>
                        {activeRunId && (
                          <a
                            className="act"
                            href={`/api/workflows/runs/${encodeURIComponent(activeRunId)}/step-file?path=${encodeURIComponent(f.path)}&download=1`}
                            data-testid={`phase-card-download-btn-${f.name}`}
                          >dl</a>
                        )}
                      </span>
                    ))}
                    {step.outputFiles.length > 4 && (
                      <span className="output-file">
                        <span className="fn">+{step.outputFiles.length - 4} more</span>
                      </span>
                    )}
                  </div>
                )}
              </div>
            );
          })}

          {/* QC Gates block — shown for every phase that has autoloop or QC thresholds */}
          {qcThresholds.length > 0 && (
            <div className="qc-block">
              <div className="qc-head" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <span>QC Gates</span>
                <button
                  className="linkish"
                  style={{ fontSize: 10 }}
                  onClick={() => setQcEditorOpen(o => !o)}
                  data-testid={`qc-edit-toggle-${group.key}`}
                >
                  {qcEditorOpen ? 'done' : 'edit'}
                </button>
              </div>
              {qcThresholds.map(t => (
                <div className="qc-gate" key={t.key} data-qc-key={t.key}>
                  <span className="metric">{t.label}</span>
                  <span className="op">{t.direction === 'min' ? '≥' : '≤'}</span>
                  {qcEditorOpen ? (
                    <input
                      type="number"
                      className="v"
                      style={{ width: 60, textAlign: 'right', fontSize: 11,
                        background: t.modified ? 'var(--accent-soft)' : 'var(--surface)',
                        border: `1px solid ${t.modified ? 'var(--accent)' : 'var(--border)'}`,
                        borderRadius: 3, padding: '1px 4px', color: 'var(--text)', fontFamily: 'var(--font-mono)' }}
                      value={t.value}
                      step="any"
                      onChange={e => { const v = parseFloat(e.target.value); if (!isNaN(v)) onQcChange(t.key, v); }}
                      onBlur={e => { if (isNaN(parseFloat(e.target.value))) onQcChange(t.key, null); }}
                    />
                  ) : (
                    <span className="thr" style={{ color: t.modified ? 'var(--accent)' : undefined }}>
                      {t.value}{t.unit}
                    </span>
                  )}
                  {t.modified && qcEditorOpen && (
                    <button
                      className="linkish"
                      style={{ fontSize: 10, color: 'var(--warn)' }}
                      title="Reset to default"
                      onClick={() => onQcChange(t.key, null)}
                    >×</button>
                  )}
                </div>
              ))}
              <div className="qc-autoloop" style={autoloopLocked ? { opacity: 0.45, cursor: 'not-allowed' } : undefined}>
                <span
                  className={`switch${autoloopEnabled ? ' on' : ''}`}
                  onClick={autoloopLocked ? undefined : onToggleAutoloop}
                  role="switch"
                  aria-checked={autoloopEnabled}
                  aria-disabled={autoloopLocked}
                  data-testid={`autoloop-toggle-${group.key}`}
                  style={autoloopLocked ? { pointerEvents: 'none' } : undefined}
                />
                <span
                  title={autoloopLocked
                    ? "Auto-loop is currently disabled while end-to-end testing is in progress. It will be enabled once testing is complete."
                    : "When ON: if a quality check fails, BioMate adjusts parameters and retries the phase automatically (up to 3 times). When OFF: a review card appears so you can approve or reject the suggested fix before continuing."
                  }
                >
                  Self-correct on QC failure <span style={{fontFamily:'var(--font-mono)', color:'var(--text-dim)'}}>(max 3×)</span>
                  {autoloopLocked && <span style={{marginLeft: 6, fontSize: '0.75em', color: 'var(--text-dim)', fontStyle: 'italic'}}>(coming soon)</span>}
                </span>
              </div>
            </div>
          )}

          {/* AutoLoopPanel when gate results match this phase */}
          {autoloopEnabled && autoLoopPanelState?.gateResults &&
            autoloopPhaseMatches(group.key, autoLoopPanelState.gateResults.phase) && (
            <div style={{padding:'8px 14px 0 40px'}}>
              <AutoLoopPanel
                state={autoLoopPanelState}
                currentParams={params}
                onDismiss={onDismissAutoloop}
                onAccept={onAcceptAutoloop}
              />
            </div>
          )}

          {/* Phase actions */}
          <div className="phase-actions">
            {anyRunning && onStopPhase && (
              <button
                className="btn sm"
                data-testid={`button-stop-phase-${group.key}`}
                onClick={onStopPhase}
              >
                Stop phase
              </button>
            )}
            {/* Skip phase — no backend API, UI-only; hidden until backend skip endpoint added
            {!allDone && (
              <button
                className="btn ghost sm danger"
                onClick={() => onSkip(group.key)}
              >
                Skip phase
              </button>
            )} */}
            <span style={{flex:1}}/>
            {/* "View phase outputs" link — commented out per UX review 2026-06-19.
                Outputs already render inline under each step row when the phase is open,
                so this scroll-to-outputs link was redundant.
            {allDone && (
              <button
                className="linkish"
                style={{fontSize:12}}
                onClick={() => {
                  setOpen(true);
                  setTimeout(() => {
                    const el = document.querySelector(`[data-testid="phase-group-${group.key}"] .step-outputs`);
                    el?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                  }, 120);
                }}
              >View phase outputs</button>
            )}
            */}
          </div>
        </div>
      )}
    </div>
  );
}

export function NextflowWorkflowViewer({
  workflowId,
  invocationId,
  executionBlockedReason,
  prereqChecklist,
  workflowDefinition,
  initialParams,
  lastSubmittedParams,
  onExecute,
  onPause,
  onResume,
  onCancel,
  status = 'idle',
  errorMessage,
  progress = 0,
  onParameterChange,
  sessionId,
  runId,
  autofix,
  nextflowStatus,
  executionEngine,
  onAdjustViaChat,
  onWorkflowProgress,
  executionMetrics,
  onResize,
}: NextflowWorkflowViewerProps) {
  const { toast } = useToast();
  const [params, setParams] = useState<Record<string, any>>(
    initialParams || workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {}
  );
  // Tracks param keys the user has explicitly overridden via EditableParamRow.
  // Stored as a ref (not state) so the useEffect sees the live value without needing
  // it in the dependency array, and without triggering extra re-renders.
  const userOverriddenParams = useRef<Set<string>>(new Set());

  // Late-binding: workflowDefinition.inline_parameters is populated by
  // chat-with-artifacts.tsx AFTER chat-stream's final event lands — which is
  // typically AFTER this component already mounted with an empty params {}.
  // useState's initializer only runs once at mount, so without this effect the
  // LLM-extracted target_a / target_b / indication / format never reach the
  // form inputs even though they're in the workflow object. Merge them in,
  // but skip keys the user has explicitly overridden via the editor.
  // Verified via /api/chat/stream live: final event carries
  //   "inlineParameters":{"target_a":"PD-1","target_b":"VEGF",...}
  // which chat-with-artifacts spreads onto workflowDefinition.inline_parameters
  // before re-rendering this component.
  React.useEffect(() => {
    const incoming =
      (workflowDefinition?.inline_parameters && typeof workflowDefinition.inline_parameters === 'object'
        ? workflowDefinition.inline_parameters
        : null) ||
      (workflowDefinition?.parameters && typeof workflowDefinition.parameters === 'object'
        ? workflowDefinition.parameters
        : null);
    if (!incoming) return;
    const incomingKeys = Object.keys(incoming);
    if (incomingKeys.length === 0) return;
    setParams(prev => {
      let changed = false;
      const next: Record<string, any> = { ...prev };
      for (const k of incomingKeys) {
        if (userOverriddenParams.current.has(k)) continue; // respect user edits
        const v = (incoming as Record<string, any>)[k];
        if (v === undefined || v === null || v === '') continue;
        if (prev[k] !== v) {
          next[k] = v;
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [workflowDefinition?.inline_parameters, workflowDefinition?.parameters]);

  const { showingSubmittedParams, resetToDefaults } = useRunAgainParamCarryover({
    status, runId, lastSubmittedParams, userOverriddenParams, setParams,
    defaults: initialParams || workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {},
  });
  // Drag-to-resize refs — used by the panel-resizer drag handle
  const resizingRef = useRef(false);
  const resizeStartXRef = useRef(0);
  const resizeStartWRef = useRef(0);
  const [logs, setLogs] = useState<string[]>([]);
  const [lastUpdateAt, setLastUpdateAt] = useState<Date>(new Date());
  // Workflow-panel top tabs (per 20260608 horizontal-layout redesign).
  // Default is status-aware (computed in effect below):
  //   idle / pending_review → Settings (user needs to configure params)
  //   running / paused      → Phases   (user wants to watch live progress)
  //   completed / failed    → After-run (user wants results)
  // Manual switches override the auto-default for the rest of the session.
  const [activeTab, setActiveTab] = useState<'settings' | 'phases' | 'after-run'>('phases');
  const [tabAutoDefault, setTabAutoDefault] = useState<boolean>(true);
  // Global parameters collapsible — collapsed by default (phases shown first per design spec)
  const [globalParamsOpen, setGlobalParamsOpen] = useState<boolean>(false);

  // Status-aware tab default — see the activeTab declaration above for the policy.
  // Only auto-switches while the user hasn't manually picked a tab (tabAutoDefault).
  useEffect(() => {
    if (!tabAutoDefault) return;
    const next: 'settings' | 'phases' | 'after-run' =
      status === 'idle' || status === 'pending_review' ? 'settings'
      : status === 'running' || status === 'paused' ? 'phases'
      : status === 'completed' || status === 'failed' ? 'after-run'
      : 'phases';
    setActiveTab(next);
  }, [status, tabAutoDefault]);
  const [previewFile, setPreviewFile] = useState<{ name: string; path: string; extension: string } | null>(null);
  const [adjustStep, setAdjustStep] = useState<{ id: string; name: string; processName?: string; parameters?: Record<string, any> } | null>(null);
  // When user reruns from a step, track the new runId so the viewer polls the right run
  const [rerunRunId, setRerunRunId] = useState<string | null>(null);
  const activeRunId = rerunRunId ?? runId;

  // QC governance settings
  const [qcSettingsOpen, setQcSettingsOpen] = useState(false);
  const [pauseAtQcFailures, setPauseAtQcFailures] = useState(true);
  const [qcProfile, setQcProfile] = useState('');
  // Phase C — output location picker state. Defaults to BioMate-managed.
  // user_s3 is "Advanced" — see tooltip in the picker UI for setup docs.
  const [outputLocationType, setOutputLocationType] = useState<'default' | 'project' | 'user_s3'>('default');
  const [userS3Uri, setUserS3Uri] = useState<string>('');
  // projectId for "My project folder" — sourced from the active chat session's
  // project_id. Falls back to undefined → option is hidden when no project.
  const projectId = (workflowDefinition as any)?.projectId ?? null;
  const [availableQcProfiles, setAvailableQcProfiles] = useState<Array<{ id: string; description: string; domain_hint: string; overrides: Record<string, number> }>>([]);
  const [qcDefaults, setQcDefaults] = useState<Record<string, { bound: number; direction: string; rationale?: string }>>({});
  const [qcOverrides, setQcOverrides] = useState<Record<string, number>>({});

  // C3: validate environment state

  const [browsingForParam, setBrowsingForParam] = useState<{ id: string; label: string } | null>(null);
  const [sessionDatasets, setSessionDatasets] = useState<Array<{ id: string; name: string; file_type?: string; file_path?: string | null; source_url?: string | null; galaxy_dataset_id?: string }>>([]);

  // Lazy-load workflow phase steps when workflowDefinition has a nextflow_path
  // but steps is empty (e.g. sessions created before steps parsing was deployed).
  // null = fetch not started / in progress; {} = fetch done but no steps; {...} = steps loaded
  const [lazySteps, setLazySteps] = useState<Record<string, any> | null>(null);
  const [lazyStepsFetching, setLazyStepsFetching] = useState(false);
  useEffect(() => {
    const nfPath = workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath;
    const existingSteps = workflowDefinition?.steps;
    const hasSteps = existingSteps && typeof existingSteps === 'object' && Object.keys(existingSteps).length > 0;
    if (!hasSteps && nfPath) {
      setLazyStepsFetching(true);
      fetch(`/api/nextflow/steps?nextflow_path=${encodeURIComponent(nfPath)}`)
        .then(r => r.ok ? r.json() : null)
        .then(data => { setLazySteps(data?.steps ?? {}); })
        .catch(() => { setLazySteps({}); })
        .finally(() => setLazyStepsFetching(false));
    }
  }, [workflowDefinition]);

  // Fetch session-uploaded datasets so the param browser can return real file paths to Nextflow
  useEffect(() => {
    fetch('/api/datasets/session')
      .then(r => r.ok ? r.json() : { datasets: [] })
      .then(data => setSessionDatasets(data.datasets || []))
      .catch(() => {});
  }, []);

  // D4: error recovery state — auto-triggered when workflow fails
  const [errorExplanation, setErrorExplanation] = useState<{
    error_type: string;
    human_summary: string;
    suggested_fix: string;
    chat_prompt: string;
    llm_used: boolean;
  } | null>(null);
  const [errorExplaining, setErrorExplaining] = useState(false);
  const [logsOpen, setLogsOpen] = useState(false);


  const [stepExecutionById, setStepExecutionById] = useState<Record<string, StepExecutionState>>({});
  const [skippedPhaseIds, setSkippedPhaseIds] = useState<Set<string>>(new Set());
  const [confirmSkipPhaseId, setConfirmSkipPhaseId] = useState<string | null>(null);
  const stepPollersRef = React.useRef<Record<string, ReturnType<typeof setInterval>>>({});

  // QC gate inline panel state (SSE-triggered)
  const [showQcInline, setShowQcInline] = useState(false);
  const [qcGateData, setQCGateData] = useState<QCGateData | null>(null);
  // Gap 1 (inverse) — near-threshold QC advisories keyed by process_name.
  // The narrator already emits a chat line via workflow.qc_gate_warning; here
  // we surface the same information in the panel so the user sees the
  // annotation on the step card. Backend emit site:
  // backend/lib/galaxy/jobs/qc_trace_monitor.py:5744.
  const [qcAdvisoryByStep, setQcAdvisoryByStep] = useState<Record<string, { metric?: string; value?: any; threshold?: any }[]>>({});
  const [qcGateSecondsLeft, setQcGateSecondsLeft] = useState<number | null>(null);
  // Low-confidence "Confirm anyway" auto-proceed countdown
  const [lowConfSecondsLeft, setLowConfSecondsLeft] = useState<number | null>(null);
  const lowConfTimerRef = React.useRef<ReturnType<typeof setInterval> | null>(null);
  const qcGateTimerRef = React.useRef<ReturnType<typeof setInterval> | null>(null);
  // Don't block the user on decisions. After this many seconds with no input
  // the system auto-proceeds with the safest default and tells the user in chat.
  const QC_GATE_TIMEOUT_S = 10;
  const LOW_CONF_TIMEOUT_S = 10;
  const [autoLoopPanel, setAutoLoopPanel] = useState<AutoLoopPanelState>({
    gateResults: null,
    remediations: [],
    complete: null,
  });
  // Per-phase auto-loop toggle: true = enabled (default), false = user suppressed
  const [autoloopMap, setAutoloopMap] = useState<Record<string, boolean>>({});
  // Ref mirrors state so SSE event handlers always read the latest value synchronously.
  // Updated inside the state setter (not in useEffect) to avoid async timing gaps.
  const autoloopMapRef = React.useRef<Record<string, boolean>>({});
  const [isApplyingSuggestions, setIsApplyingSuggestions] = useState(false);;

  // Billing usage meter
  const [usageMeter, setUsageMeter] = useState<{ used: number; limit: number } | null>(null);
  useEffect(() => {
    fetch('/api/users/me/usage', { credentials: 'include' })
      .then(r => r.ok ? r.json() : null)
      .then((d: any) => d && setUsageMeter(d))
      .catch(() => {});
  }, []);

  const phases = React.useMemo<ViewerPhase[]>(() => {
    // Prefer stored steps; fall back to lazily-fetched steps for old sessions
    const stepsSource = (
      workflowDefinition?.steps && typeof workflowDefinition.steps === "object" && Object.keys(workflowDefinition.steps).length > 0
        ? workflowDefinition.steps
        : lazySteps ?? {}
    );
    if (Object.keys(stepsSource).length > 0) {
      return Object.entries(stepsSource).map(([stepKey, rawStep], index) => {
        const step = (rawStep || {}) as Record<string, unknown>;
        return {
          id: String(step.id || stepKey || `step-${index}`),
          name: String(step.name || step.label || step.tool_id || `Step ${index + 1}`),
          status: "pending",
          description: String(step.annotation || step.description || ""),
          toolId: typeof step.tool_id === "string" ? step.tool_id : undefined,
          parameters: step.parameters && typeof step.parameters === "object" ? (step.parameters as Record<string, unknown>) : {},
          inputs: step.inputs && typeof step.inputs === "object" ? (step.inputs as Record<string, unknown>) : {},
          summary: typeof step.summary === "string" ? step.summary : undefined,
          autoloop: typeof step.autoloop === "boolean" ? step.autoloop : undefined,
          phase_group: typeof step.phase_group === "string" && step.phase_group ? step.phase_group : undefined,
          phase_label: typeof step.phase_label === "string" && step.phase_label ? step.phase_label : undefined,
        };
      });
    }
    // No step data from backend — return empty so the viewer shows a clean idle state
    return [];
  }, [workflowDefinition, lazySteps]);

  useEffect(() => {
    setStepExecutionById((prev) => {
      const next: Record<string, StepExecutionState> = {};
      for (const phase of phases) {
        if (prev[phase.id]) {
          next[phase.id] = prev[phase.id];
        }
      }
      return next;
    });
  }, [phases]);

  const clearStepPoller = React.useCallback((stepId: string) => {
    const timer = stepPollersRef.current[stepId];
    if (timer) {
      clearInterval(timer);
      delete stepPollersRef.current[stepId];
    }
  }, []);

  const refreshStepStatus = React.useCallback(async (stepId: string) => {
    try {
      const response = await fetch(`/api/workflow/step/${encodeURIComponent(stepId)}/status`);
      if (!response.ok) {
        throw new Error(`Status check failed (${response.status})`);
      }

      const payload = await response.json();
      const backendState = normalizeBackendState(payload?.state);
      const phaseStatus = mapBackendToPhaseStatus(backendState);
      const outputsCount = Array.isArray(payload?.outputs) ? payload.outputs.length : 0;

      setStepExecutionById((prev) => ({
        ...prev,
        [stepId]: {
          ...(prev[stepId] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
          backendState,
          phaseStatus,
          jobId: payload?.job_id || prev[stepId]?.jobId,
          startedAt: payload?.started_at || prev[stepId]?.startedAt,
          lastRunAt: payload?.started_at || prev[stepId]?.lastRunAt,
          outputsCount,
          isExecuting: !isTerminalBackendState(backendState),
          errorMessage: backendState === "error" || backendState === "failed" || backendState === "cancelled"
            ? "Step execution failed."
            : undefined,
          runCount: prev[stepId]?.runCount ?? 1,
        },
      }));

      if (isTerminalBackendState(backendState)) {
        clearStepPoller(stepId);
      }
      return backendState;
    } catch (error: any) {
      setStepExecutionById((prev) => ({
        ...prev,
        [stepId]: {
          ...(prev[stepId] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
          phaseStatus: "failed",
          isExecuting: false,
          errorMessage: error?.message || "Unable to refresh step status.",
          runCount: prev[stepId]?.runCount ?? 1,
        },
      }));
      clearStepPoller(stepId);
      return "error";
    }
  }, [clearStepPoller]);

  const beginStepStatusPolling = React.useCallback((stepId: string) => {
    clearStepPoller(stepId);
    void refreshStepStatus(stepId).then((backendState) => {
      if (backendState && !isTerminalBackendState(backendState)) {
        stepPollersRef.current[stepId] = setInterval(() => {
          void refreshStepStatus(stepId);
        }, 2500);
      }
    });
  }, [clearStepPoller, refreshStepStatus]);

  useEffect(() => {
    return () => {
      Object.keys(stepPollersRef.current).forEach((stepId) => clearStepPoller(stepId));
    };
  }, [clearStepPoller]);

  const handleRunStep = React.useCallback(async (phase: ViewerPhase) => {
    if (!activeRunId) return;

    const startedAt = new Date().toISOString();
    emitUxEvent("workflow.run_clicked", {
      workflowId,
      stepId: phase.id,
      invocationId,
    });

    setStepExecutionById((prev) => ({
      ...prev,
      [phase.id]: {
        ...(prev[phase.id] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
        phaseStatus: "running",
        backendState: "queued",
        runCount: (prev[phase.id]?.runCount ?? 0) + 1,
        lastRunAt: startedAt,
        startedAt,
        outputsCount: 0,
        isExecuting: true,
        errorMessage: undefined,
      },
    }));

    try {
      const response = await fetch(
        `/api/workflows/runs/${encodeURIComponent(activeRunId)}/rerun`,
        { method: "POST", headers: { "Content-Type": "application/json" } }
      );
      if (!response.ok) {
        const message = await readApiErrorMessage(response);
        throw new Error(message);
      }
      const payload = await response.json();
      const newRunId: string | undefined = payload?.run_id;
      if (newRunId) {
        setRerunRunId(newRunId);
      }
      setStepExecutionById((prev) => ({
        ...prev,
        [phase.id]: {
          ...(prev[phase.id] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
          backendState: "queued",
          phaseStatus: "running",
          jobId: newRunId,
          isExecuting: true,
        },
      }));
    } catch (error: any) {
      setStepExecutionById((prev) => ({
        ...prev,
        [phase.id]: {
          ...(prev[phase.id] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
          phaseStatus: "failed",
          backendState: "error",
          isExecuting: false,
          errorMessage: error?.message || "Resume failed.",
        },
      }));
    }
  }, [activeRunId, invocationId, workflowId]);

  const handleSkipPhase = React.useCallback((phaseId: string) => {
    setSkippedPhaseIds((prev) => {
      const next = new Set(prev);
      next.add(phaseId);
      return next;
    });
  }, []);

  // When the global Nextflow run reaches a terminal state, clear isExecuting
  // on all steps so their Run Step buttons re-enable.
  useEffect(() => {
    const isTerminal = status === 'completed' || status === 'failed';
    if (!isTerminal) return;
    setStepExecutionById((prev) => {
      const hasExecuting = Object.values(prev).some((e) => e.isExecuting);
      if (!hasExecuting) return prev;
      const next: Record<string, StepExecutionState> = {};
      for (const [id, exec] of Object.entries(prev)) {
        next[id] = exec.isExecuting ? { ...exec, isExecuting: false } : exec;
      }
      return next;
    });
  }, [status]);

  // Build a lookup of process data from nextflowStatus.processes keyed by process name / id
  const nfProcessByName = React.useMemo<Record<string, any>>(() => {
    const procs: any[] = Array.isArray(nextflowStatus?.processes) ? nextflowStatus.processes : [];
    const map: Record<string, any> = {};
    for (const proc of procs) {
      if (proc?.name) map[String(proc.name).toLowerCase()] = proc;
      if (proc?.process) map[String(proc.process).toLowerCase()] = proc;
      if (proc?.id) map[String(proc.id).toLowerCase()] = proc;
    }
    return map;
  }, [nextflowStatus?.processes]);

  const updatedPhases = phases.map((phase, index) => {
    // If the user has manually skipped this phase, mark it as completed so it renders as done
    if (skippedPhaseIds.has(phase.id)) {
      const nfProcSkipped =
        nfProcessByName[phase.id.toLowerCase()] ||
        nfProcessByName[phase.name.toLowerCase()] ||
        null;
      const skippedOutputFiles: Array<{ name: string; path: string; extension: string }> = (
        nfProcSkipped
          ? (nfProcSkipped.task_files || nfProcSkipped.taskFiles || []).map((f: string) => ({
              name: f.split('/').pop() || f,
              path: f,
              extension: (f.split('.').pop() || '').toLowerCase(),
            }))
          : (phase.outputFiles || [])
      );
      return { ...phase, status: 'completed' as ViewerPhaseStatus, outputFiles: skippedOutputFiles };
    }

    let derivedStatus: ViewerPhaseStatus = phase.status;
    // Prefer per-process status from nextflowStatus.processes (P1 fix
    // 2026-06-17): when the backend reports per-process state, use it
    // directly so phases B/C/D can render `running` independently —
    // the workflow-level progress-based heuristic below could only
    // make ONE phase running at a time and would force all phases to
    // `completed` the moment the workflow finished, breaking the
    // per-phase live-narration story the tier-0 tutorial demos depend on.
    const nfProcLookup =
      nfProcessByName[phase.id.toLowerCase()] ||
      nfProcessByName[phase.name.toLowerCase()] ||
      null;
    const rawProcStatus = String(nfProcLookup?.status || nfProcLookup?.state || '').toLowerCase();
    const procStatus: ViewerPhaseStatus | null =
      rawProcStatus.includes('fail') || rawProcStatus.includes('error') || rawProcStatus.includes('cancel')
        ? 'failed'
        : rawProcStatus.includes('run') || rawProcStatus === 'submitted'
          ? 'running'
          : rawProcStatus.includes('complet') || rawProcStatus === 'succeeded' || rawProcStatus === 'ok'
            ? 'completed'
            : null;
    if (procStatus) {
      derivedStatus = procStatus;
    } else if (status === "completed") {
      derivedStatus = "completed";
    } else if (status === "running") {
      const totalPhases = phases.length;
      const currentPhaseIndex = Math.floor((progress / 100) * totalPhases);
      if (index < currentPhaseIndex) derivedStatus = "completed";
      else if (index === currentPhaseIndex) derivedStatus = "running";
      else derivedStatus = "pending";
    }

    // Merge outputFiles from nextflowStatus.processes when available
    const nfProc =
      nfProcessByName[phase.id.toLowerCase()] ||
      nfProcessByName[phase.name.toLowerCase()] ||
      null;
    const rawFiles = nfProc ? (nfProc.task_files || nfProc.taskFiles || []) : (phase.outputFiles || []);
    const outputFiles: Array<{ name: string; path: string; extension: string }> = Array.isArray(rawFiles)
      ? rawFiles.map((f: string) => ({
          name: (f && typeof f === 'string' ? f.split('/').pop() : null) || String(f),
          path: String(f),
          extension: (f && typeof f === 'string' ? f.split('.').pop() : '') || '',
        }))
      : [];

    const stepExecution = stepExecutionById[phase.id];
    if (!stepExecution) {
      return { ...phase, status: derivedStatus, outputFiles };
    }

    return {
      ...phase,
      status: stepExecution.phaseStatus,
      backendState: stepExecution.backendState,
      jobId: stepExecution.jobId,
      startedAt: stepExecution.startedAt,
      lastRunAt: stepExecution.lastRunAt,
      runCount: stepExecution.runCount,
      outputsCount: stepExecution.outputsCount,
      errorMessage: stepExecution.errorMessage,
      isExecuting: stepExecution.isExecuting,
      outputFiles,
    };
  });

  // Group updatedPhases by their phase_group field (A/B/C/D/E for cryo-EM, etc.)
  const groupedPhases = React.useMemo<PhaseGroup[]>(() => {
    const hasGroups = updatedPhases.some((p: any) => p.phase_group);
    if (!hasGroups) {
      const allParams = updatedPhases.flatMap((p: any) => Object.keys(p.parameters || {}));
      const uniqueParams = Array.from(new Set(allParams)) as string[];
      return [{ key: 'all', label: 'Steps', steps: updatedPhases, phaseParams: uniqueParams }];
    }
    const groupMap = new Map<string, { steps: any[]; label: string; phaseParams: string[] }>();
    for (const phase of updatedPhases) {
      const key = (phase.phase_group as string) || 'other';
      // Render convention (per #23):
      //   - "Other Steps"               when no annotation matched (key === 'other')
      //   - "Phase A — Motion Correction" when backend supplied group letter + semantic label
      //   - "Phase A"                    when only the group letter is present
      const semantic = (phase.phase_label as string) || '';
      let label: string;
      if (key === 'other') {
        label = 'Other Steps';
      } else if (semantic && semantic.toLowerCase() !== `phase ${key}`.toLowerCase()) {
        label = `Phase ${key.toUpperCase()} — ${semantic}`;
      } else {
        label = `Phase ${key.toUpperCase()}`;
      }
      if (!groupMap.has(key)) groupMap.set(key, { steps: [], label, phaseParams: [] });
      const group = groupMap.get(key)!;
      group.steps.push(phase);
      for (const pName of Object.keys(phase.parameters || {})) {
        if (!group.phaseParams.includes(pName)) group.phaseParams.push(pName);
      }
    }
    return Array.from(groupMap.entries()).map(([key, g]) => ({ key, ...g }));
  }, [updatedPhases]);

  // QC: derive display thresholds from defaults + auto-detected profile + user edits
  const activeQcProfile = React.useMemo(
    () => availableQcProfiles.find(p => p.id === qcProfile) ?? null,
    [availableQcProfiles, qcProfile]
  );
  const displayedQcThresholds = React.useMemo(() => {
    const merged: Record<string, { bound: number; direction: string; rationale?: string; source: 'default' | 'profile' | 'user' }> = {};
    Object.entries(qcDefaults).forEach(([k, meta]) => {
      merged[k] = { bound: meta.bound, direction: meta.direction, rationale: meta.rationale, source: 'default' };
    });
    if (activeQcProfile) {
      Object.entries(activeQcProfile.overrides).forEach(([k, v]) => {
        merged[k] = { ...(merged[k] || { direction: 'min' }), bound: v as number, source: 'profile' };
      });
    }
    return Object.entries(merged).map(([key, meta]) => ({
      key,
      label: QC_THRESHOLD_LABELS[key]?.label ?? key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
      unit: QC_THRESHOLD_LABELS[key]?.unit ?? '',
      direction: meta.direction,
      rationale: meta.rationale,
      value: qcOverrides[key] !== undefined ? qcOverrides[key] : meta.bound,
      modified: qcOverrides[key] !== undefined,
    }));
  }, [qcDefaults, activeQcProfile, qcOverrides]);

  const handleParamChange = (id: string, value: any) => {
    setParams((prev: any) => ({ ...prev, [id]: value }));
    // Mark as user-overridden so the workflowDefinition useEffect doesn't clobber it
    userOverriddenParams.current.add(id);
    onParameterChange?.(id, value);
  };

  const handleExecute = () => {
    if (prereqChecklist && !prereqChecklist.canRun) {
      return;
    }
    emitUxEvent('workflow.run_clicked', { workflowId, invocationId });
    if (onExecute) {
      onExecute({
        ...params,
        __qcConfig: {
          pauseAtQcFailures,
          ...(qcProfile && { qcProfile }),
          ...(Object.keys(qcOverrides).length > 0 && { qcOverrides }),
        },
        // Phase C — output location, optional. See
        // docs/20260619_OUTPUT_LOCKDOWN_PHASE_B_C_SPEC.md (C.1+C.2).
        // Omitted when user selects "default" — backend falls back to
        // s3://biomate-nextflow-work/nextflow/outputs/<user>/<run>/.
        ...(outputLocationType !== 'default' && {
          __outputLocation: {
            type: outputLocationType,
            ...(outputLocationType === 'project' && projectId ? { projectId } : {}),
            ...(outputLocationType === 'user_s3' && userS3Uri ? { userS3Uri } : {}),
          },
        }),
      });
    }
  };

  const handleRetryWithSuggestions = async () => {
    if (!qcGateData) return;
    setIsApplyingSuggestions(true);
    try {
      const updatedParams = { ...params };
      for (const suggestion of qcGateData.suggestions) {
        updatedParams[suggestion.parameter] = suggestion.suggestedValue;
        if (onParameterChange) onParameterChange(suggestion.parameter, suggestion.suggestedValue);
        setParams((prev: Record<string, any>) => ({ ...prev, [suggestion.parameter]: suggestion.suggestedValue }));
      }
      dismissQcGate('user');
      // Use Nextflow -resume so cached phases are skipped — not a fresh start
      if (activeRunId) {
        await fetch(`/api/workflows/runs/${encodeURIComponent(activeRunId)}/rerun`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify({ params: updatedParams }),
        });
      } else if (onExecute) {
        onExecute(updatedParams);
      }
    } catch (err) {
      console.error('[QC Gate NFViewer] Failed to apply suggestions:', err);
    } finally {
      setIsApplyingSuggestions(false);
    }
  };

  const dismissQcGate = React.useCallback((reason: 'user' | 'timeout') => {
    if (qcGateTimerRef.current) { clearInterval(qcGateTimerRef.current); qcGateTimerRef.current = null; }
    setShowQcInline(false);
    setQCGateData(null);
    setQcGateSecondsLeft(null);
    if (reason === 'timeout') {
      toast({
        title: 'QC gate timed out',
        description: 'No response in 10s — kept current parameters and continued.',
        duration: 6000,
      });
      // Tell the chat layer too so the user sees a friendly progress line.
      onWorkflowProgress?.({
        kind: 'workflow.auto_proceeded',
        friendly_message: "No response — kept current parameters and continued.",
        ts: Date.now() / 1000,
        technical: { decision: 'kept current parameters', source: 'qc_gate_timeout' },
      });
    }
  }, [toast, onWorkflowProgress]);

  // Start countdown when gate card appears; auto-dismiss after QC_GATE_TIMEOUT_S seconds
  React.useEffect(() => {
    if (!showQcInline) return;
    setQcGateSecondsLeft(QC_GATE_TIMEOUT_S);
    qcGateTimerRef.current = setInterval(() => {
      setQcGateSecondsLeft(prev => {
        if (prev === null || prev <= 1) {
          dismissQcGate('timeout');
          return null;
        }
        return prev - 1;
      });
    }, 1000);
    return () => { if (qcGateTimerRef.current) { clearInterval(qcGateTimerRef.current); qcGateTimerRef.current = null; } };
  }, [showQcInline, dismissQcGate]);

  const handleProceedAnyway = () => dismissQcGate('user');

  const handleCancelWorkflow = () => {
    console.log("[QC Gate NFViewer] User cancelled workflow due to QC failures");
    setShowQcInline(false);
    setQCGateData(null);
    onCancel?.();
  };

  const rationale = workflowDefinition?.scientific_rationale;

  // Build a lookup from tool name prefix → hints, so pipeline-level params
  // (e.g., star_index, salmon_index) can be matched to tool-internal hints
  // (outSAMtype, validateMappings) from the scientific rationale.
  const toolHintMap = React.useMemo<Record<string, { rationale: string; toolName: string }>>(() => {
    const map: Record<string, { rationale: string; toolName: string }> = {};
    const hints: any[] = (workflowDefinition?.scientific_rationale?.parameter_hints as any[]) || [];
    // Group hints by tool, build a summary rationale per tool
    const byTool: Record<string, string[]> = {};
    for (const h of hints) {
      if (!h?.tool || !h?.param) continue;
      const toolKey = h.tool.toLowerCase().replace(/[^a-z0-9]/g, '');
      if (!byTool[toolKey]) byTool[toolKey] = [];
      byTool[toolKey].push(`${h.param}: ${h.recommended}`);
    }
    for (const [toolKey, recs] of Object.entries(byTool)) {
      map[toolKey] = { rationale: recs.slice(0, 3).join(' · '), toolName: toolKey };
    }
    return map;
  }, [workflowDefinition?.scientific_rationale?.parameter_hints]);

  // Enrich rendered params with rationale from tool_knowledge hints.
  // Matching strategy: check if the param's id/name contains a known tool name
  // (e.g., star_index → STAR hints, salmon_index → Salmon hints).
  const renderedParameters = React.useMemo(() => {
    const base = buildViewerParameters(workflowDefinition, params);
    if (Object.keys(toolHintMap).length === 0) return base;
    return base.map((p: any) => {
      const pKey = (p.id || p.name || '').toLowerCase().replace(/[^a-z0-9]/g, '');
      // Find any tool whose name is a substring of the param key
      const matchedTool = Object.keys(toolHintMap).find(toolKey => pKey.includes(toolKey));
      if (!matchedTool) return p;
      const hint = toolHintMap[matchedTool];
      // Preserve backend autoFilled=true; add rationale from tool hints if not already set
      return {
        ...p,
        rationale: p.rationale || `${hint.toolName.toUpperCase()} recommendations — ${hint.rationale}`,
        autoFilled: p.autoFilled === true,
      };
    });
  }, [workflowDefinition, params, toolHintMap]);

  // At panel-generation time: build a one-time map from param semantic group → phase key.
  // Each param carries a group name like "Motion Correction" or "CTF Estimation" from the
  // .nf section headers. Match against phase labels so PhaseGroupSection can do a direct lookup.
  const paramGroupToPhaseKey = React.useMemo<Map<string, string>>(() => {
    const map = new Map<string, string>();
    const GLOBAL_GROUPS = new Set(['global', 'advanced', 'infrastructure', 'performance']);
    const tokenize = (s: string) =>
      s.toLowerCase().replace(/[^a-z0-9]/g, ' ').trim().split(/\s+/).filter(w => w.length >= 3);

    for (const p of renderedParameters) {
      const rawGroup = String((p as any).group || '').trim();
      if (!rawGroup) continue;
      const pgNorm = rawGroup.toLowerCase();
      if (GLOBAL_GROUPS.has(pgNorm)) continue;
      if (map.has(pgNorm)) continue; // already mapped

      const groupTokens = tokenize(rawGroup);
      for (const phase of groupedPhases) {
        const phaseTokens = tokenize(phase.label);
        // All group tokens must appear in the phase label tokens (or vice versa for short names)
        const matched = groupTokens.every(gt => phaseTokens.some(pt => pt.includes(gt) || gt.includes(pt)));
        if (matched) {
          map.set(pgNorm, phase.key);
          break;
        }
      }
    }
    return map;
  }, [renderedParameters, groupedPhases]);

  /**
   * Count global params that are required AND still empty.
   * Mirrors the logic inside the Workflow-settings strip IIFE (~line 2490) but
   * hoisted to component scope so the run-button hard gate can read it without
   * duplicating the strip render. Excludes params already pinned to a phase
   * section (those have their own per-phase editor).
   *
   * Used by the Run-button disabled prop so a user can't submit a workflow
   * with empty required fields by ignoring the strip.
   */
  const globalRequiredUnfilledCount = React.useMemo(() => {
    const phasePinned = new Set(
      groupedPhases.filter(g => g.key !== 'all').flatMap(g => g.phaseParams)
    );
    return renderedParameters.filter((p: any) => {
      const pName = p.id || p.name || '';
      if (phasePinned.has(pName)) return false;
      return p.required && (!p.value || p.value === '');
    }).length;
  }, [renderedParameters, groupedPhases]);

  // Derived state: results auto-open on completion; user can override either way.
  // Previously this was useState + useEffect — multiple agents added competing
  // setShowResults(true) hooks, neither of which was reliably firing in production
  // (suspected React batching / mount-timing interaction). Derive cleanly from
  // status to eliminate the race.
  const [showResultsOverride, setShowResultsOverride] = useState<boolean | null>(null);
  const showResults = showResultsOverride !== null
    ? showResultsOverride
    : status === 'completed';
  const handleToggleShowResults = React.useCallback((next: boolean | ((prev: boolean) => boolean)) => {
    setShowResultsOverride(prev => {
      const current = prev !== null ? prev : (status === 'completed');
      return typeof next === 'function' ? next(current) : next;
    });
  }, [status]);
  const [downloadAllPromptOpen, setDownloadAllPromptOpen] = useState(false);

  // ── AI Result Analysis state ───────────────────────────────────────────────
  const [analysisState, setAnalysisState] = useState<'idle' | 'loading' | 'done' | 'error'>('idle');
  const [analysisResult, setAnalysisResult] = useState<{
    summary: string;
    key_findings: Array<{ finding: string; significance: string }>;
    quality_assessment: string;
    next_steps: string[];
    citations: Array<{ tool_or_resource: string; reference: string; relevance: string }>;
    limitations: string;
  } | null>(null);
  const [analysisError, setAnalysisError] = useState<string | null>(null);

  async function handleAnalyzeResults() {
    if (!runId || analysisState === 'loading') return;
    setAnalysisState('loading');
    setAnalysisResult(null);
    setAnalysisError(null);
    try {
      const token = localStorage.getItem('auth_token') ||
        (() => { for (let i = 0; i < localStorage.length; i++) { const v = localStorage.getItem(localStorage.key(i) ?? '') ?? ''; if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v)) return v; } return null; })();
      const r = await fetch(`/api/workflows/runs/${runId}/ai/analyze`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ question: '' }),
      });
      const data = await r.json();
      if (!r.ok || !data.success) throw new Error(data.error || 'Analysis failed');
      setAnalysisResult(data.analysis);
      setAnalysisState('done');
    } catch (e: any) {
      setAnalysisError(e.message || 'Unknown error');
      setAnalysisState('error');
    }
  }
  // Block Run if any required param is still empty (no value provided, no default).
  // Skip this check when prereq recovery mode is active (overrideAllowed=true) — user approved demo path.
  const hasUnfilledRequired = prereqChecklist?.overrideAllowed
    ? false
    : renderedParameters
        .filter((p: any) => p.required === true)
        .some((p: any) => (p.value === '' || p.value === null || p.value === undefined));
  const isPrereqBlocked = (!!prereqChecklist && !prereqChecklist.canRun) || hasUnfilledRequired;
  const [isLicenseBlocked, setIsLicenseBlocked] = useState(false);
  const isGlobalExecutionActive = status === "running" || status === "paused";
  const isAutofixActive =
    autofix?.active === true ||
    ["analyzing", "fixing", "restarting"].includes(autofix?.state || "");

  // Low-confidence "Confirm anyway" — auto-fires the same payload the button
  // sends, so an inattentive user never stalls a workflow. Cancellable by
  // clicking "Fix now", manually confirming, or the panel un-mounting.
  const fireLowConfidenceConfirm = React.useCallback((source: 'user' | 'timeout') => {
    if (lowConfTimerRef.current) { clearInterval(lowConfTimerRef.current); lowConfTimerRef.current = null; }
    setLowConfSecondsLeft(null);
    if (status === 'running' || status === 'completed' || (isPrereqBlocked && !prereqChecklist?.overrideAllowed) || isAutofixActive || isLicenseBlocked) {
      return;
    }
    emitUxEvent(
      source === 'user' ? 'workflow.low_confidence_override_clicked' : 'workflow.low_confidence_auto_proceeded',
      { workflowId, invocationId, runId },
    );
    onExecute?.({
      ...params,
      __executionOverrides: { allowLowConfidence: true, overrideReason: executionBlockedReason, autoProceeded: source === 'timeout' },
    });
    if (source === 'timeout') {
      toast({
        title: 'Auto-proceeded',
        description: 'No response in 10s — confirmed and started the workflow.',
        duration: 6000,
      });
      onWorkflowProgress?.({
        kind: 'workflow.auto_proceeded',
        friendly_message: "No response — confirmed and started the workflow.",
        ts: Date.now() / 1000,
        technical: { decision: 'confirmed low-confidence run', source: 'low_conf_timeout' },
      });
    }
  }, [
    status, isPrereqBlocked, prereqChecklist?.overrideAllowed, isAutofixActive, isLicenseBlocked,
    workflowId, invocationId, runId, params, executionBlockedReason, onExecute, toast, onWorkflowProgress,
  ]);

  // Start the low-conf countdown whenever the blocking reason becomes visible.
  React.useEffect(() => {
    if (!executionBlockedReason) {
      if (lowConfTimerRef.current) { clearInterval(lowConfTimerRef.current); lowConfTimerRef.current = null; }
      setLowConfSecondsLeft(null);
      return;
    }
    if (status === 'running' || status === 'completed' || (isPrereqBlocked && !prereqChecklist?.overrideAllowed) || isAutofixActive || isLicenseBlocked) {
      return;
    }
    setLowConfSecondsLeft(LOW_CONF_TIMEOUT_S);
    lowConfTimerRef.current = setInterval(() => {
      setLowConfSecondsLeft(prev => {
        if (prev === null || prev <= 1) {
          fireLowConfidenceConfirm('timeout');
          return null;
        }
        return prev - 1;
      });
    }, 1000);
    return () => { if (lowConfTimerRef.current) { clearInterval(lowConfTimerRef.current); lowConfTimerRef.current = null; } };
  }, [executionBlockedReason, status, isPrereqBlocked, prereqChecklist?.overrideAllowed, isAutofixActive, isLicenseBlocked, fireLowConfidenceConfirm, LOW_CONF_TIMEOUT_S]);

  // showResults is now derived from `status` — no setShowResults needed on completion.
  useEffect(() => {
    if (status === 'failed') {
      setLogsOpen(true);
    }
  }, [status]);

  // Auto-expand workflow settings when required params are still empty
  useEffect(() => {
    if (hasUnfilledRequired) setGlobalParamsOpen(true);
  }, [hasUnfilledRequired]);

  // Auto-expand when the LLM extracted inline params for the user — they should
  // see what was prefilled before clicking Run (and so the form is actually in
  // the DOM for E2E assertions to read).
  useEffect(() => {
    const inline = (workflowDefinition as any)?.inline_parameters;
    if (inline && typeof inline === 'object' && Object.keys(inline).length > 0) {
      setGlobalParamsOpen(true);
    }
  }, [workflowDefinition]);

  // D4: Auto-fetch error explanation when workflow fails
  useEffect(() => {
    if (status === 'failed' && !errorExplanation && !errorExplaining) {
      const rawLog = logs.slice(-50).join('\n') + (errorMessage ? `\n${errorMessage}` : '');
      if (!rawLog.trim()) return;
      const failedSteps = updatedPhases
        .filter((p: any) => p.status === 'failed')
        .map((p: any) => ({ name: p.processName || p.name, work_dir: p.workDir }));
      setErrorExplaining(true);
      const abortController = new AbortController();
      const explainTimeout = setTimeout(() => abortController.abort(), 30000);
      fetch('/api/workflows/explain_error', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: abortController.signal,
        body: JSON.stringify({
          workflow_name: workflowDefinition?.name || workflowDefinition?.workflow_name,
          error_log: rawLog,
          run_id: runId,
          failed_steps: failedSteps,
        }),
      })
        .then(r => r.json())
        .then(data => setErrorExplanation(data))
        .catch(() => {
          // Show a minimal fallback so the user isn't left staring at "Analyzing…"
          setErrorExplanation({
            human_summary: 'Error analysis timed out. Check the log output above for details.',
            suggested_fix: 'Review the error log and retry the workflow, or contact support if the issue persists.',
            error_type: 'analysis_failed',
            chat_prompt: '',
            llm_used: false,
          });
        })
        .finally(() => { clearTimeout(explainTimeout); setErrorExplaining(false); });
    }
  }, [status]);

  useEffect(() => {
    setLastUpdateAt(new Date());
  }, [status, progress, errorMessage, nextflowStatus, stepExecutionById]);

  useEffect(() => {
    // Merge incoming defaults/initialParams WITHOUT overwriting keys the user has already edited.
    // This prevents streaming workflowDefinition updates from wiping out user-typed param values.
    // Exception: autoFilled values (explicitly injected by the backend based on user intent)
    // always win — they represent the latest user-specified value from the most recent query.
    const computeIncoming = (): { defaults: Record<string, any>; autoFilledKeys: Set<string> } => {
      if (initialParams) return { defaults: initialParams, autoFilledKeys: new Set() };
      const reqList: any[] = Array.isArray(workflowDefinition?.required_params) ? workflowDefinition.required_params : [];
      const optList: any[] = Array.isArray(workflowDefinition?.optional_params) ? workflowDefinition.optional_params : [];
      if (reqList.length > 0 || optList.length > 0) {
        const defaults: Record<string, any> = {};
        const autoFilledKeys = new Set<string>();
        for (const p of [...reqList, ...optList]) {
          if (!p?.name) continue;
          // Prefer p.value (explicit user-specified override) over p.default (schema default)
          const seed = p.value !== undefined && p.value !== null && p.value !== '' ? p.value : p.default;
          if (seed != null) {
            defaults[p.name] = seed;
            // Track which keys were explicitly injected by the backend
            if (p.autoFilled === true && p.value !== undefined && p.value !== null && p.value !== '') {
              autoFilledKeys.add(p.name);
            }
          }
        }
        return { defaults, autoFilledKeys };
      }
      return { defaults: workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {}, autoFilledKeys: new Set() };
    };
    const { defaults: incoming, autoFilledKeys } = computeIncoming();
    setParams(prev => {
      const merged: Record<string, any> = { ...prev };
      for (const [k, v] of Object.entries(incoming)) {
        // Always apply autoFilled values (user explicitly stated them in the query).
        // For other keys, only apply if the user hasn't already edited the field.
        // AutoFilled values are applied unless the user has explicitly overridden this param.
        // Non-autofilled values are applied only when the field is currently unset.
        const userOverrode = userOverriddenParams.current.has(k);
        if (!userOverrode && (autoFilledKeys.has(k) || merged[k] === undefined || merged[k] === null || merged[k] === '')) {
          merged[k] = v;
        }
      }
      return merged;
    });
  }, [initialParams, workflowDefinition]);

  useEffect(() => {
    fetch('/api/qc/profiles')
      .then(r => r.ok ? r.json() : null)
      .then(data => {
        if (data?.profiles) setAvailableQcProfiles(data.profiles);
        if (data?.defaults) setQcDefaults(data.defaults);
      })
      .catch(() => {});
  }, []);

  // Auto-detect QC profile from workflow domain/name
  useEffect(() => {
    if (!availableQcProfiles.length || !workflowDefinition) return;
    if (qcProfile) return; // user already selected one
    const name = (workflowDefinition.name || workflowDefinition.workflow_name || '').toLowerCase();
    const domainMap: Record<string, string[]> = {
      cryo_em: ['cryo', 'cryosparc', 'spa', 'tomography', 'helical', 'subtomogram'],
      rnaseq: ['rnaseq', 'rna-seq', 'transcriptom', 'rna_seq'],
      wgs: ['wgs', 'germline', 'gatk', 'variant_calling', 'sarek'],
      wes: ['wes', 'exome'],
      scrna_seq: ['scrna', 'single_cell', 'scrnaseq', 'cellranger', '10x'],
      metagenomics: ['metagenom', 'amplicon', 'microbiome'],
      drug_discovery: ['admet', 'docking', 'pocket', 'md simulation', 'molecular dynamics', 'fpocket', 'drug'],
      proteomics: ['proteom', 'mass_spec', 'dia', 'dda'],
      epigenomics: ['chipseq', 'atac', 'chip-seq', 'atacseq', 'methylseq', 'bisulfite'],
      spatial: ['spatial', 'visium', 'xenium'],
    };
    for (const [domain, keywords] of Object.entries(domainMap)) {
      if (keywords.some(k => name.includes(k))) {
        const match = availableQcProfiles.find(p => p.domain_hint === domain);
        if (match) { setQcProfile(match.id); break; }
      }
    }
  }, [availableQcProfiles, workflowDefinition]);

  // SSE listener for QC gate events — mirrors workflow-artifact.tsx logic
  useEffect(() => {
    if (!invocationId) return;
    let stopped = false;
    // Reset auto-loop panel when the invocationId changes (new run)
    setAutoLoopPanel({ gateResults: null, remediations: [], complete: null });

    const es = new EventSource(`/api/workflows/${invocationId}/events`);

    // Workflow-progress chat lines from the backend narrator (workflow.submitted,
    // workflow.phase_started, workflow.completed, workflow.failed, etc.). The
    // host component appends each one to the current chat session as a short
    // italic message.
    es.addEventListener("chat_progress", (event: MessageEvent) => {
      if (!onWorkflowProgress) return;
      try {
        const data = JSON.parse(event.data as string);
        // Payload shape: { kind, invocation_id, friendly_message, ts, technical }
        if (data && data.friendly_message && data.kind) {
          onWorkflowProgress({
            kind: String(data.kind),
            friendly_message: String(data.friendly_message),
            ts: typeof data.ts === 'number' ? data.ts : undefined,
            technical: data.technical,
          });
        }
      } catch (err) {
        console.warn("[ChatProgress] Failed to parse chat_progress event:", err);
      }
    });

    es.addEventListener("qc_gate_triggered", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        console.log("[QC Gate NFViewer] Event received:", data);
        const gateData: QCGateData = {
          processName: data.process_name,
          qcMetrics: data.qc_metrics ?? {},
          failures: data.failures ?? [],
          suggestions: data.suggestions ?? [],
        };
        // Determine if auto-loop is enabled for this phase.
        // Auto-loop ON → apply suggestions automatically using Nextflow -resume, no card shown.
        // Auto-loop OFF → show confirmation card and let user decide.
        const phaseKey = data.phase_key ?? data.process_name ?? '';
        const autoloopOn = autoloopMapRef.current[phaseKey] === true;
        if (autoloopOn && gateData.suggestions.length > 0 && activeRunId) {
          // Auto-apply: update params and resume — notify user of what happened
          const phaseName = gateData.processName.includes(":")
            ? gateData.processName.split(":").pop()?.replace(/_/g, " ")
            : gateData.processName.replace(/_/g, " ");
          const failureSummary = gateData.failures
            .map((f: any) => typeof f === 'string' ? f : `${f.metric}: ${f.value} (threshold ${f.threshold})`)
            .join(", ");
          const paramSummary = gateData.suggestions
            .map((s: any) => `${s.parameter}: ${s.currentValue} → ${s.suggestedValue}`)
            .join(", ");
          toast({
            title: `QC gate failed — ${phaseName}`,
            description: `${failureSummary}. Auto-loop adjusting: ${paramSummary} and resuming.`,
            duration: 8000,
          });
          const updatedParams = { ...params };
          for (const s of gateData.suggestions) {
            updatedParams[s.parameter] = s.suggestedValue;
          }
          fetch(`/api/workflows/runs/${encodeURIComponent(activeRunId)}/rerun`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include',
            body: JSON.stringify({ params: updatedParams }),
          }).catch(err => console.error("[QC Gate NFViewer] Auto-rerun failed:", err));
        } else if (autoloopOn && gateData.failures.length > 0) {
          // Auto-loop ON but no actionable suggestions — notify user, no rerun
          const phaseName = gateData.processName.replace(/_/g, " ");
          const failureSummary = gateData.failures
            .map((f: any) => typeof f === 'string' ? f : `${f.metric}: ${f.value} (threshold ${f.threshold})`)
            .join(", ");
          toast({
            title: `QC gate failed — ${phaseName}`,
            description: `${failureSummary}. No auto-fix available — workflow continued.`,
            duration: 10000,
          });
        } else {
          // Auto-loop OFF: show confirmation card with countdown
          setQCGateData(gateData);
          setShowQcInline(true);
        }
      } catch (err) {
        console.error("[QC Gate NFViewer] Failed to parse event:", err);
      }
    });

    es.addEventListener("qc_warning", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        const proc = String(data.process_name || '');
        const warnings = (data.warnings || []) as any[];
        if (!proc || warnings.length === 0) return;
        setQcAdvisoryByStep((prev) => ({ ...prev, [proc]: warnings.map((w) => ({ metric: w.metric, value: w.value, threshold: w.threshold })) }));
        analytics.track('qc_warning', { failing_step: proc, gates_advisory: warnings.length });
      } catch (err) {
        console.error("[QC Warning NFViewer] Failed to parse event:", err);
      }
    });

    // ── Auto-loop reactive QC events ──────────────────────────────────────
    es.addEventListener("autoloop_gate_results", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        // Only reset `complete` when starting a new phase; preserve an already-received
        // phase_complete event for the same phase to avoid out-of-order SSE race.
        setAutoLoopPanel(prev => ({
          ...prev,
          gateResults: data,
          complete: prev.complete?.phase === data.phase ? prev.complete : null,
        }));
      } catch (err) {
        console.error("[AutoLoop] gate_results parse error:", err);
      }
    });

    es.addEventListener("autoloop_update", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        setAutoLoopPanel(prev => ({
          ...prev,
          remediations: data.remediations ?? [],
          complete: {
            phase: data.phase,
            domain: data.domain,
            outcome: "escalated",
            failed_gates: data.failed_gates ?? [],
          },
        }));
      } catch (err) {
        console.error("[AutoLoop] update parse error:", err);
      }
    });

    es.addEventListener("autoloop_phase_complete", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        setAutoLoopPanel(prev => ({ ...prev, complete: data }));
      } catch (err) {
        console.error("[AutoLoop] phase_complete parse error:", err);
      }
    });

    es.addEventListener("autoloop_escalation", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        setAutoLoopPanel(prev => ({
          ...prev,
          complete: {
            phase: data.phase,
            domain: data.domain,
            outcome: "escalated",
            failed_gates: data.failed_gates ?? [],
          },
        }));
      } catch (err) {
        console.error("[AutoLoop] escalation parse error:", err);
      }
    });

    // ── Real-time step & workflow state via SSE (replaces per-step polling) ──
    es.addEventListener("step_state", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        const stepId = String(data.step_id ?? "");
        const backendState = normalizeBackendState(data.step_state);
        const phaseStatus = mapBackendToPhaseStatus(backendState);
        if (!stepId) return;
        setStepExecutionById((prev) => ({
          ...prev,
          [stepId]: {
            ...(prev[stepId] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
            backendState,
            phaseStatus,
            jobId: data.job_id || prev[stepId]?.jobId,
            isExecuting: !isTerminalBackendState(backendState),
            runCount: prev[stepId]?.runCount ?? 1,
          },
        }));
        if (isTerminalBackendState(backendState)) {
          clearStepPoller(stepId);
        }
      } catch (err) {
        console.error("[SSE] step_state parse error:", err);
      }
    });

    es.addEventListener("workflow_state", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        const wfState = normalizeBackendState(data.workflow_state);
        // If workflow reached a terminal state, clear all outstanding pollers
        if (isTerminalBackendState(wfState)) {
          Object.keys(stepPollersRef.current).forEach((sid) => clearStepPoller(sid));
        }
      } catch (err) {
        console.error("[SSE] workflow_state parse error:", err);
      }
    });
    // ─────────────────────────────────────────────────────────────────────

    es.onerror = () => {
      if (!stopped) es.close();
    };

    return () => {
      stopped = true;
      es.close();
    };
  }, [invocationId]);

  useEffect(() => {
    const rawLogTail = Array.isArray(nextflowStatus?.log_tail)
      ? nextflowStatus.log_tail.filter((line: unknown) => typeof line === "string")
      : [];
    if (rawLogTail.length > 0) {
      setLogs(rawLogTail.slice(-120));
      return;
    }
    const statusLine = nextflowStatus?.status
      ? `Pipeline status: ${String(nextflowStatus.status)}`
      : null;
    if (statusLine) {
      setLogs([statusLine]);
    }
  }, [nextflowStatus]);

  const effectiveProgress = Number(
    nextflowStatus?.progressPercent ??
      nextflowStatus?.progress ??
      progress ??
      0
  );

  // Detect the S3 cache-scan phase: running but 0 tasks for >30s.
  // Nextflow scans the entire S3 work dir before emitting any task counts.
  const isScanningCache = status === 'running'
    && (nextflowStatus?.totalTasks ?? 0) === 0
    && !!nextflowStatus?.started_at
    && (Date.now() / 1000 - (nextflowStatus.started_at as number)) > 30;

  const nextflowRunId =
    nextflowStatus?.run_id ??
    nextflowStatus?.runId ??
    nextflowStatus?.nextflow_run_id ??
    nextflowStatus?.nextflowRunId;
  const formatContextValue = (value: unknown) => {
    if (value === null || value === undefined) return "n/a";
    if (typeof value === "string") {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : "n/a";
    }
    const asText = String(value);
    return asText.trim().length > 0 ? asText : "n/a";
  };

  const runtimeArtifacts = React.useMemo(() => {
    const artifacts: string[] = [];
    const pushArtifact = (value: any) => {
      if (!value) return;
      if (typeof value === "string") {
        const trimmed = value.trim();
        if (trimmed) artifacts.push(trimmed);
        return;
      }
      if (Array.isArray(value)) {
        value.forEach(pushArtifact);
        return;
      }
      if (typeof value === "object") {
        Object.values(value).forEach(pushArtifact);
      }
    };

    pushArtifact(nextflowStatus?.outputs);
    pushArtifact(nextflowStatus?.results);
    pushArtifact(nextflowStatus?.output_files);
    pushArtifact(nextflowStatus?.outdir);
    // DEPRECATED 2026-05-21: nextflowStatus.s3_output_files is empty whenever
    // the Galaxy worker restarts mid-run. The user-facing artifact list is
    // already correctly populated by ChatOutputAttachments via
    // /api/runs/:id/outputs (canonical). This artifact-summary triage helper
    // keeps reading the legacy field as a best-effort fallback only — when
    // it's empty here, the real outputs are still visible in the panel below.
    if (Array.isArray(nextflowStatus?.s3_output_files)) {
      for (const f of nextflowStatus.s3_output_files) {
        if (f?.s3_uri) artifacts.push(f.s3_uri);
      }
    }

    if (Array.isArray(nextflowStatus?.log_tail)) {
      for (const line of nextflowStatus.log_tail) {
        if (typeof line !== "string") continue;
        const pathMatches = line.match(/\/[^\s,\]]+/g) || [];
        pathMatches.forEach((candidate) => artifacts.push(candidate));
      }
    }

    return Array.from(new Set(artifacts)).slice(0, 12);
  }, [nextflowStatus]);
  const triageStatus = String(nextflowStatus?.status || status || "idle").toLowerCase();
  const triageNextAction =
    triageStatus === "failed"
      ? "Review the failure reason, inspect recent logs, then retry with corrected inputs or parameters."
      : triageStatus === "completed"
        ? "Open Output Results to verify artifacts and downloadables."
        : triageStatus === "running"
          ? "Monitor logs and wait for terminal status before deciding on retry."
          : "Configure parameters and prerequisites, then run the workflow.";
  const triageLogsHint =
    logs.length > 0
      ? `Latest ${Math.min(logs.length, 120)} log lines are available below.`
      : triageStatus === "running"
        ? "Execution is active; logs may appear shortly."
        : "No runtime logs are available yet.";
  const triageOutputsHint =
    !invocationId
      ? "Outputs are not available until execution starts."
      : triageStatus === "completed" && runtimeArtifacts.length === 0
        ? "Run completed; output hydration may still be in progress."
        : triageStatus === "completed"
          ? `Detected ${runtimeArtifacts.length} runtime artifact${runtimeArtifacts.length === 1 ? "" : "s"}.`
          : "Use View Results to check generated outputs as they arrive.";

  return (
    <div
      className="wf-panel"
      data-testid="workflow-artifact-panel"
      data-debug-inline-params={JSON.stringify(workflowDefinition?.inline_parameters || null)}
      data-debug-rendered-param-count={renderedParameters.length}
      data-debug-rendered-param-ids={renderedParameters.map((p: any) => p.id).join(',')}
    >
      {/* Drag handle on the left edge — lets users resize the panel width.
          Rendered only when the parent supplies an onResize callback. */}
      {onResize && (
        <div
          className="panel-resizer"
          title="Drag to resize"
          onMouseDown={(e: React.MouseEvent) => {
            e.preventDefault();
            resizingRef.current = true;
            resizeStartXRef.current = e.clientX;
            const panelEl = (e.currentTarget as HTMLElement).parentElement;
            resizeStartWRef.current = panelEl ? panelEl.getBoundingClientRect().width : 530;
            document.body.style.cursor = 'ew-resize';
            const onMove = (ev: MouseEvent) => {
              if (!resizingRef.current) return;
              const dx = resizeStartXRef.current - ev.clientX; // dragging left grows width
              const next = Math.max(320, Math.min(900, resizeStartWRef.current + dx));
              onResize(Math.round(next));
            };
            const onUp = () => {
              resizingRef.current = false;
              document.body.style.cursor = '';
              window.removeEventListener('mousemove', onMove);
              window.removeEventListener('mouseup', onUp);
            };
            window.addEventListener('mousemove', onMove);
            window.addEventListener('mouseup', onUp);
          }}
        />
      )}
      <DownloadOutcomePrompt
        open={downloadAllPromptOpen}
        onOpenChange={setDownloadAllPromptOpen}
        invocationId={invocationId}
        sessionId={sessionId}
        runId={runId}
        isDownloadAll={true}
      />

      {/* ── Panel header ─────────────────────────────────────────────────────── */}
      {(() => {
        const wfDomain = (workflowDefinition?.domain || workflowDefinition?.category || '') as string;
        const meaningfulDomain = wfDomain && wfDomain !== 'general' ? wfDomain : '';
        const kickerLabel = meaningfulDomain
          ? `${meaningfulDomain.replace(/_/g, ' ').toUpperCase()} · WORKFLOW`
          : 'WORKFLOW';
        const hasRealPhases = groupedPhases.some((g: any) => g.key !== 'all');
        const phaseCount = hasRealPhases ? groupedPhases.length : 0;
        const stepCount = updatedPhases.length;
        const subtitleParts: string[] = [];
        if (stepCount > 0) subtitleParts.push(`${stepCount} ${stepCount === 1 ? 'process' : 'processes'}`);
        if (phaseCount > 0) subtitleParts.push(`${phaseCount} ${phaseCount === 1 ? 'phase' : 'phases'}`);
        else if (stepCount > 0) subtitleParts.push('no phases');
        const panelSub = subtitleParts.length > 0
          ? subtitleParts.join(' · ')
          : ((workflowDefinition?.description || '') as string).split(/[.—]/)[0].trim().slice(0, 60);
        return (
          <div className="panel-head" data-tour="panel-header">
            <div className="top-row">
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="kicker">{kickerLabel}</div>
                <div className="panel-name">{workflowDefinition?.name || 'Untitled'}</div>
                {panelSub && <div className="panel-sub">{panelSub}</div>}
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                {workflowDefinition?.qc_profile && (
                  <span className="chip ok" style={{ fontSize: '10px' }}>
                    QC: {(workflowDefinition.qc_profile as string).replace(/_/g, ' ')}
                  </span>
                )}
                {/* Only show chip for non-idle states */}
                {status !== 'idle' && (
                  <span
                    className={`chip${status === 'running' ? ' run' : status === 'completed' ? ' ok' : status === 'failed' ? ' err' : ''}`}
                    data-testid="workflow-overall-status-badge"
                    data-status={status}
                  >
                    {status.toUpperCase()}
                  </span>
                )}
                {/* Hidden element keeps test selectors working for idle state */}
                {status === 'idle' && (
                  <span
                    data-testid="workflow-overall-status-badge"
                    data-status="idle"
                    style={{ display: 'none' }}
                  />
                )}
                {(status === 'running' || status === 'paused') && (
                  <button className="iconbtn" data-testid="button-cancel-workflow-panel" onClick={onCancel} title="Cancel">
                    <Square style={{ width: 14, height: 14 }} />
                  </button>
                )}
                {(status === 'completed' || status === 'failed') && (
                  <button className="iconbtn" data-testid="button-restart-workflow-panel" onClick={() => onExecute?.(params)} title="Restart">
                    <RotateCcw style={{ width: 14, height: 14 }} />
                  </button>
                )}
              </div>
            </div>
            {/* Progress bar — commented out per UX review 2026-06-19.
                Status is already conveyed by the header badge + per-phase chip;
                a separate bar duplicated the signal. Re-enable if a user-test
                shows the absence is missed.
            {(status === 'running' || status === 'completed') && effectiveProgress > 0 && (
              <div className="run-bar">
                <div className="progress">
                  <div className="fill" style={{ width: `${effectiveProgress}%` }} />
                </div>
                <span className="pct">{effectiveProgress}%</span>
                {status === 'completed' && stepCount > 0 && (
                  <span className="meta">{stepCount}/{stepCount}</span>
                )}
              </div>
            )}
            */}
          </div>
        );
      })()}

      {/* ── Top-level tabs (Step A MVP — phases tab keeps current view) ─────── */}
      {(() => {
        const hasRealPhases = groupedPhases.some((g: any) => g.key !== 'all');
        const phaseCount = hasRealPhases ? groupedPhases.length : 0;
        const paramCount = renderedParameters.length;
        const showAfterRunDot = status === 'completed' || status === 'failed';
        // Per-tab hover tips so the user can see what each tab contains
        // without clicking. Native `title` keeps this dependency-free.
        const tabTips: Record<'settings' | 'phases' | 'after-run', string> = {
          settings:
            'Workflow-wide datasets and configuration that apply to every phase. Required ones must be set before you run.',
          phases:
            'Phases and steps of the workflow — live progress while running, per-step parameters that only affect a single step, QC thresholds with self-correct toggle, and the output files each step produces.',
          'after-run':
            'Available after the run completes — outputs, findings, QC report, methods write-up, and citations.',
        };
        const tabBtn = (key: 'settings' | 'phases' | 'after-run', label: string, badge?: React.ReactNode): React.ReactElement => (
          <button
            key={key}
            type="button"
            onClick={() => { setActiveTab(key); setTabAutoDefault(false); }}
            data-testid={`panel-tab-${key}`}
            aria-selected={activeTab === key}
            title={tabTips[key]}
            style={{
              background: 'transparent',
              border: 'none',
              padding: '8px 14px',
              cursor: 'pointer',
              fontSize: 13,
              fontWeight: activeTab === key ? 600 : 500,
              color: activeTab === key ? 'var(--text)' : 'var(--text-muted)',
              borderBottom: activeTab === key ? '2px solid var(--text)' : '2px solid transparent',
              display: 'inline-flex',
              alignItems: 'center',
              gap: 6,
            }}
          >
            {label}
            {badge}
          </button>
        );
        const countBadge = (n: number) =>
          n > 0 ? (
            <span style={{
              fontSize: 11,
              fontWeight: 500,
              padding: '1px 7px',
              borderRadius: 999,
              background: 'var(--bm-muted, oklch(0.94 0.005 260))',
              color: 'var(--text-muted)',
            }}>{n}</span>
          ) : null;
        const dotBadge = (
          <span style={{
            display: 'inline-block',
            width: 6,
            height: 6,
            borderRadius: 999,
            background: status === 'failed' ? 'oklch(0.62 0.18 25)' : 'oklch(0.65 0.15 145)',
          }} />
        );
        return (
          <div
            data-testid="panel-tabs"
            style={{
              display: 'flex',
              borderBottom: '1px solid var(--border)',
              padding: '0 6px',
              background: 'var(--bm-bg, transparent)',
            }}
          >
            {/* Settings tab: the existing Workflow-settings collapsible strip
                that today lives at the TOP of panel-body. Same content; just
                moved into its own tab via CSS-hide (no JSX restructure). */}
            {tabBtn('settings', 'Workflow settings', countBadge(paramCount))}
            {tabBtn('phases', 'Phases', countBadge(phaseCount))}
            {tabBtn('after-run', 'After run', showAfterRunDot ? dotBadge : null)}
          </div>
        );
      })()}

      {/* ── After-run tab content (v2 AfterRunReport, embedded inline) ──────── */}
      {activeTab === 'after-run' && (
        <div className="panel-body" data-testid="panel-after-run">
          <AfterRunReport
            runId={runId || invocationId || ''}
            invocationId={invocationId}
            workflowName={workflowDefinition?.name}
            parameters={params as Record<string, unknown>}
            executionStatus={
              status === 'completed' ? 'completed'
              : status === 'failed' ? 'failed'
              : status === 'running' ? 'running'
              : undefined
            }
            errorMessage={errorMessage}
            // P0 fix (2026-06-16 after-run audit): the viewer never forwarded
            // outputs, so the Outputs tab always showed "No output files
            // registered yet" even after a successful AWS Batch run. Build
            // the OutputFile[] from nextflowStatus.s3_output_files — same
            // shape chat-with-artifacts.tsx uses. Galaxy invocations use a
            // different path (outputDatasets); the viewer's surface is
            // nextflow-native so s3_output_files is the source.
            outputs={(() => {
              const s3: any[] = Array.isArray(nextflowStatus?.s3_output_files)
                ? nextflowStatus.s3_output_files
                : [];
              if (s3.length === 0) return [];
              return s3.map((f: any) => {
                const filePath = typeof f === 'string'
                  ? f
                  : (f.s3_uri || f.path || f.key || f.name || '');
                const name = filePath.split('/').filter(Boolean).pop() || '';
                const ext = (name.split('.').pop() || '').toLowerCase();
                // Step label = the prefix segment that looks like a process
                // name (e.g. INVIVO_CART_ATLAS_SAFETY/) — mirrors the
                // chat-with-artifacts derivation so styling is consistent.
                const parts = filePath.split('/');
                const step = parts.length >= 2 ? parts[parts.length - 2] : '';
                return { step, name, path: filePath, ext };
              });
            })()}
          />
        </div>
      )}

      {/* ── Scrollable panel body — shared between Phases AND Settings tabs.
              The body contains: settings strip (visible on Settings tab),
              phase cards + status (visible on Phases tab). Per-section CSS
              hide/show is applied below; the body itself stays mounted on
              either tab so SSE-driven phase state isn't lost on tab switch. */}
      <div style={{ display: (activeTab === 'phases' || activeTab === 'settings') ? 'contents' : 'none' }}>
      <div className="panel-body" data-tour="panel-body" data-testid={activeTab === 'settings' ? 'panel-settings' : 'panel-phases'}>
          {/* ── Phases-tab-only runtime section ─────────────────────────────── */}
          <div style={{ display: activeTab === 'phases' ? 'contents' : 'none' }}>
          {/* Step-wise controls hint — only when real phase groups exist */}
          {status === 'idle' && groupedPhases.some((g: any) => g.key !== 'all') && (
            <div
              data-testid="workflow-step-controls-hint"
              style={{ fontSize: 11, color: 'var(--text-dim)', padding: '4px 18px 0', marginBottom: 2 }}
            >
              Click a phase to expand its steps and parameters. Each phase can be run individually once the workflow starts.
            </div>
          )}
          {/* QC Gate Inline Review Panel — appears when backend fires a qc_gate_triggered SSE event */}
          {showQcInline && qcGateData && (
            <div className="alert warn" data-testid="qc-gate-inline" style={{ marginBottom: 10 }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6 }}>
                <AlertTriangle className="h-3.5 w-3.5" style={{ flexShrink: 0, marginTop: 1 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 600, marginBottom: 2 }}>
                    QC Gate — {qcGateData.processName.includes(":")
                      ? qcGateData.processName.split(":").pop()?.replace(/_/g, " ")
                      : qcGateData.processName.replace(/_/g, " ")} — Review Required
                  </div>
                  {qcGateData.failures.length > 0 && (
                    <div style={{ marginTop: 4 }}>
                      {qcGateData.failures.map((f, i) => {
                        if (typeof f === 'string') {
                          return <div key={i} style={{ opacity: 0.85 }}>{f}</div>;
                        }
                        const fail = f as QCGateFailure;
                        return (
                          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '3px 0', borderBottom: i < qcGateData.failures.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
                            <span style={{ flex: 1, fontSize: 12, color: 'var(--text-2)' }}>{fail.metric}</span>
                            <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 700, color: 'var(--red, #dc2626)', fontSize: 13 }} data-testid="qc-gate-measured">
                              {typeof fail.value === 'number' ? fail.value.toFixed(fail.value < 10 ? 2 : 0) : fail.value}
                            </span>
                            <span style={{ color: 'var(--text-dim)', fontSize: 11 }}>{fail.operator}</span>
                            <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 600, color: 'var(--green, #16a34a)', fontSize: 13 }} data-testid="qc-gate-threshold">
                              {typeof fail.threshold === 'number' ? fail.threshold.toFixed(fail.threshold < 10 ? 2 : 0) : fail.threshold}
                            </span>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  {qcGateData.suggestions.length > 0 && (
                    <div style={{ marginTop: 4 }}>
                      {qcGateData.suggestions.map((s, i) => (
                        <div key={i}>• {s.parameter}: {JSON.stringify(s.currentValue)} → {JSON.stringify(s.suggestedValue)}</div>
                      ))}
                    </div>
                  )}
                  {qcGateSecondsLeft !== null && (
                    <div style={{ marginTop: 6, fontSize: 11, color: 'var(--text-dim)' }} data-testid="qc-gate-countdown">
                      Pipeline continues in {Math.floor(qcGateSecondsLeft / 60)}:{String(qcGateSecondsLeft % 60).padStart(2, '0')} unless you act
                    </div>
                  )}
                  <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
                    {qcGateData.suggestions.length > 0 && (
                      <button className="btn sm" data-testid="qc-gate-apply" onClick={() => { void handleRetryWithSuggestions(); }} disabled={isApplyingSuggestions}>
                        {isApplyingSuggestions ? "Applying…" : "Apply suggestions"}
                      </button>
                    )}
                    <button className="btn ghost sm" data-testid="qc-gate-keep" onClick={handleProceedAnyway}>Keep current</button>
                    <button className="btn ghost sm danger" data-testid="qc-gate-cancel-run" onClick={handleCancelWorkflow}>Cancel run</button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Completion banner — shown when workflow reaches terminal success state */}
          {status === 'completed' && (
            <div className="alert ok" data-testid="workflow-completion-banner" style={{ marginBottom: 10 }}>
              <CheckCircle2 className="h-3.5 w-3.5" style={{ flexShrink: 0 }} />
              <span>Workflow completed. View Results and Download All are available.</span>
            </div>
          )}

          {/* QC Report — always shown for completed runs, summarises measured vs threshold */}
          {status === 'completed' && (() => {
            const qcReport = (nextflowStatus as any)?.qc_report;
            const allMetrics: any[] = qcReport?._all_metrics || [];
            if (allMetrics.length === 0) return null;
            return (
              <div data-testid="qc-report-panel" style={{
                margin: '0 18px 10px', padding: '10px 12px',
                border: '1px solid var(--border)', borderRadius: 'var(--r-md)',
                background: 'var(--bg-elev)',
              }}>
                <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', color: 'var(--text-dim)', marginBottom: 6, textTransform: 'uppercase' }}>
                  QC Results
                </div>
                {allMetrics.map((m: any, i: number) => (
                  <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center', fontSize: 12, padding: '3px 0', borderBottom: i < allMetrics.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
                    <span style={{ flex: 1, color: 'var(--text-2)' }}>{m.name}</span>
                    <span style={{ fontVariantNumeric: 'tabular-nums', color: m.pass ? 'var(--green)' : 'var(--red)', fontWeight: 600 }}>
                      {typeof m.measured === 'number' ? m.measured.toFixed(m.measured < 10 ? 2 : 0) : m.measured}
                      {m.unit ? ` ${m.unit}` : ''}
                    </span>
                    <span style={{ color: 'var(--text-dim)', fontSize: 11 }}>
                      {m.pass ? '✓' : '✗'} thresh {m.threshold}
                    </span>
                  </div>
                ))}
              </div>
            );
          })()}


          </div>{/* end Phases-tab-only runtime section (re-opens after settings strip) */}

          {/* ── Settings-tab-only: the existing Workflow-settings strip ─────── */}
          <div style={{ display: activeTab === 'settings' ? 'contents' : 'none' }}>
          {/* ── Workflow settings strip — TOP of body, before phase list ────── */}
          {/* Design ref: WorkflowPanel.jsx lines 224-242 — "Workflow settings"   */}
          {/* collapsible strip sits at the top so global params frame the run    */}
          {/* before the phase list. Label is "Workflow settings", NOT "Advanced  */}
          {/* settings". Params rendered as ParameterGroup (editable, with AI     */}
          {/* Override flow) rather than plain k/v rows as in the design stub.    */}
          {(() => {
            // Exclude params already shown inside phase sections (via phaseParams).
            const allPhaseParamNames = new Set(
              groupedPhases.filter(g => g.key !== 'all').flatMap(g => g.phaseParams)
            );
            const globalParams = renderedParameters.filter(p => {
              const pName = p.id || p.name || '';
              return !allPhaseParamNames.has(pName);
            });
            const allParamDefs: any[] = [
              ...(workflowDefinition?.required_params || []),
              ...(workflowDefinition?.optional_params || []),
            ];
            const mismatch = allParamDefs.find((p: any) => p?.format_mismatch_warning);
            const requiredParams = globalParams.filter(p => p.required || (p as any).autoFilled);
            const optionalParams = globalParams.filter(p => !p.required && !(p as any).autoFilled);
            const requiredUnfilled = requiredParams.filter(p => p.required && (!p.value || p.value === ''));

            if (globalParams.length === 0 && !mismatch) return null;
            return (
              <div>
                <button
                  type="button"
                  data-testid="button-toggle-workflow-settings"
                  className={`strip${globalParamsOpen ? ' open' : ''}`}
                  onClick={() => setGlobalParamsOpen(p => !p)}
                  title="Workflow settings — input paths, infrastructure, output parameters"
                >
                  <span className="caret"><ChevronRight className="h-3.5 w-3.5" /></span>
                  <span className="label">
                    <Settings2 className="h-3.5 w-3.5" />
                    Workflow settings
                    <span className="hint">({globalParams.length} params)</span>
                    {requiredUnfilled.length > 0 && (
                      <span className="chip err" style={{ fontSize: 10, padding: '1px 5px' }}>Required</span>
                    )}
                  </span>
                </button>
                {globalParamsOpen && (
                  <div className="strip-body">
                    <div style={{ maxHeight: 480, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
                      {mismatch && (
                        <div className="alert warn" data-testid="format-mismatch-warning">
                          <span>⚠️</span><span>{mismatch.format_mismatch_warning}</span>
                        </div>
                      )}
                      {requiredParams.length > 0 && (
                        <ParameterGroup
                          id="params-required"
                          title="Required parameters"
                          description={`${requiredUnfilled.length > 0 ? requiredUnfilled.length + ' still needed · ' : ''}${requiredParams.length} param${requiredParams.length !== 1 ? 's' : ''}`}
                          parameters={requiredParams}
                          onChange={handleParamChange}
                          onBrowseDataset={(paramId, paramLabel) => setBrowsingForParam({ id: paramId, label: paramLabel })}
                          defaultOpen={requiredUnfilled.length > 0 || requiredParams.some(p => (p as any).autoFilled)}
                        />
                      )}
                      {optionalParams.length > 0 && (
                        <ParameterGroup
                          id="params-optional"
                          title="Optional parameters"
                          description={`${optionalParams.length} param${optionalParams.length !== 1 ? 's' : ''} — collapsed by default`}
                          parameters={optionalParams}
                          onChange={handleParamChange}
                          onBrowseDataset={(paramId, paramLabel) => setBrowsingForParam({ id: paramId, label: paramLabel })}
                          defaultOpen={false}
                        />
                      )}
                      {requiredParams.length === 0 && optionalParams.length === 0 && (
                        <ParameterGroup
                          id="params-global"
                          title="Workflow parameters"
                          description={`${globalParams.length} param${globalParams.length !== 1 ? 's' : ''}`}
                          parameters={globalParams}
                          onChange={handleParamChange}
                          onBrowseDataset={(paramId, paramLabel) => setBrowsingForParam({ id: paramId, label: paramLabel })}
                          defaultOpen={true}
                        />
                      )}

                      {/* Phase C — Output location picker. Per
                       *  docs/20260619_OUTPUT_LOCKDOWN_PHASE_B_C_SPEC.md (C.1).
                       *  Default: BioMate-managed (current behavior).
                       *  Project: only shown when chat is in a project.
                       *  My S3 bucket: advanced — user pastes s3:// uri. */}
                      <div data-testid="output-location-section"
                           style={{ borderTop: '1px solid var(--border)', paddingTop: 12, marginTop: 8 }}>
                        <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 6, color: 'var(--text)' }}>
                          Output location
                        </div>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 12 }}>
                          <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                            <input type="radio"
                                   name="output-location"
                                   value="default"
                                   checked={outputLocationType === 'default'}
                                   onChange={() => setOutputLocationType('default')}
                                   data-testid="output-location-default" />
                            <span>Default (BioMate-managed, kept 90 days)</span>
                          </label>
                          {projectId && (
                            <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                              <input type="radio"
                                     name="output-location"
                                     value="project"
                                     checked={outputLocationType === 'project'}
                                     onChange={() => setOutputLocationType('project')}
                                     data-testid="output-location-project" />
                              <span>My project folder</span>
                            </label>
                          )}
                          <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                            <input type="radio"
                                   name="output-location"
                                   value="user_s3"
                                   checked={outputLocationType === 'user_s3'}
                                   onChange={() => setOutputLocationType('user_s3')}
                                   data-testid="output-location-user-s3" />
                            <span title="Advanced — your bucket must grant BioMate's service role write access. See docs/output-location-user-s3-setup.md">
                              My S3 bucket <span style={{ color: 'var(--text-dim)', fontSize: 11 }}>(Advanced)</span>
                            </span>
                          </label>
                          {outputLocationType === 'user_s3' && (
                            <input
                              type="text"
                              placeholder="s3://my-bucket/my-prefix"
                              value={userS3Uri}
                              onChange={(e) => setUserS3Uri(e.target.value)}
                              data-testid="output-location-user-s3-uri"
                              style={{ marginLeft: 22, fontSize: 12, padding: '3px 6px',
                                       border: '1px solid var(--border)', borderRadius: 3,
                                       background: 'var(--surface)', color: 'var(--text)',
                                       fontFamily: 'var(--font-mono)', width: 320 }}
                            />
                          )}
                        </div>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })()}

          <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
            </div>{/* end Settings-tab-only strip */}

            {/* ── Phases-tab-only — phase cards + everything below ──────────── */}
            <div style={{ display: activeTab === 'phases' ? 'contents' : 'none' }}>
            {/* ── Phase section label ──────────────────────────────────────────── */}
            {groupedPhases.length > 0 && (() => {
              const hasRealPhases = groupedPhases.some((g: any) => g.key !== 'all');
              const label = hasRealPhases
                ? `PHASES · ${groupedPhases.length}`
                : `PROCESSES · ${updatedPhases.length}`;
              return (
                <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.08em', color: 'var(--text-dim)', padding: '10px 18px 4px', textTransform: 'uppercase' }}>
                  {label}
                </div>
              );
            })()}

            {/* ── Loading state when steps are being lazily fetched ────────── */}
            {groupedPhases.length === 0 && lazyStepsFetching && (workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath) && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '16px 18px', color: 'var(--text-dim)', fontSize: 13 }}>
                <span style={{ display: 'inline-block', width: 14, height: 14, borderRadius: '50%', border: '2px solid currentColor', borderTopColor: 'transparent', animation: 'spin 0.8s linear infinite' }} />
                Loading workflow steps…
              </div>
            )}
            {/* ── No steps found after fetch completed ─────────────────────── */}
            {groupedPhases.length === 0 && !lazyStepsFetching && lazySteps !== null && (workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath) && (
              <div style={{ padding: '16px 18px', color: 'var(--text-dim)', fontSize: 13 }}>
                Steps will appear here once the workflow runs.
              </div>
            )}

            {/* ── Phase cards ─────────────────────────────────────────────────── */}
            {groupedPhases.length > 0 && (
              <div className="phase-list" data-tour="phase-list">
                {groupedPhases.map((group, idx) => (
                  <PhaseGroupSection
                    key={group.key}
                    group={group}
                    isFirstPhase={idx === 0}
                    renderedParameters={renderedParameters}
                    params={params}
                    onParamChange={handleParamChange}
                    onRun={handleRunStep}
                    onSkip={(id) => setConfirmSkipPhaseId(id)}
                    onStopPhase={onCancel}
                    onPreviewFile={(file) => setPreviewFile(file)}
                    qcThresholds={displayedQcThresholds}
                    qcOverrides={qcOverrides}
                    onQcChange={(key, val) => {
                      if (val === null) setQcOverrides(prev => { const n = {...prev}; delete n[key]; return n; });
                      else setQcOverrides(prev => ({ ...prev, [key]: val }));
                    }}
                    onAdjustAndRerun={(phase) => setAdjustStep({
                      id: phase.id,
                      name: phase.name,
                      processName: phase.processName,
                      parameters: phase.parameters as Record<string, any> | undefined,
                    })}
                    activeRunId={activeRunId}
                    executionBlockedReason={executionBlockedReason}
                    isPrereqBlocked={isPrereqBlocked}
                    isAutofixActive={isAutofixActive}
                    isGlobalExecutionActive={isGlobalExecutionActive}
                    autoLoopPanelState={
                      autoLoopPanel.gateResults &&
                      autoloopPhaseMatches(group.key, autoLoopPanel.gateResults.phase)
                        ? autoLoopPanel
                        : undefined
                    }
                    autoloopEnabled={autoloopMap[group.key] === true}
                    autoloopLocked={true}
                    onToggleAutoloop={() => {
                      // Auto-loop is locked while testing is in progress — no-op
                    }}
                    onDismissAutoloop={() =>
                      setAutoLoopPanel({ gateResults: null, remediations: [], complete: null })
                    }
                    onAcceptAutoloop={(paramChanges) => {
                      setParams(prev => ({ ...prev, ...paramChanges }));
                      setAutoLoopPanel({ gateResults: null, remediations: [], complete: null });
                      handleExecute();
                    }}
                    paramGroupToPhaseKey={paramGroupToPhaseKey}
                    qcAdvisoryByStep={qcAdvisoryByStep}
                  />
                ))}
                <button
                  className="suggest-step-row linkish"
                  data-testid="button-suggest-step"
                  onClick={() => {
                    const lastStep = updatedPhases[updatedPhases.length - 1]?.name || "last step";
                    onAdjustViaChat?.(`Add a step after "${lastStep}" that `);
                  }}
                >
                  + Suggest a new step via chat
                </button>
              </div>
            )}

            {/* ── License gate (informational, stays in body) ─────────────────── */}
            {(workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath) && (status === 'idle' || status === 'pending_review') && (
              <LicenseGate
                nextflowPath={workflowDefinition.nextflow_path || workflowDefinition.nextflowPath}
                onBlockedChange={setIsLicenseBlocked}
              />
            )}

          </div>{/* end flex-column wrapper */}

              {/* Global QC settings removed — QC gates are now shown per-phase inside each phase card */}

              {isAutofixActive && (
                <div className="alert info" data-testid="autofix-active-banner" style={{ marginBottom: 8 }}>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" style={{ flexShrink: 0 }} />
                  <span>Auto-fix in progress ({autofix?.state || "fixing"}) — manual retry disabled to prevent duplicate runs.</span>
                </div>
              )}
              {/* Execution checklist — only shown when hard blockers exist (e.g. domain guard, license gate) */}
              {prereqChecklist && !prereqChecklist.canRun && prereqChecklist.items.some(i => i.status === 'missing' && i.id !== 'input_data' && i.id !== 'required_parameters') && (
                <div className="alert err" data-testid="workflow-prereq-checklist" style={{ flexDirection: 'column', alignItems: 'flex-start', gap: 6, marginBottom: 8 }}>
                  <div style={{ fontWeight: 600 }}>Cannot run — missing prerequisites:</div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 4, width: '100%' }}>
                    {prereqChecklist.items.filter(i => i.status === 'missing' && i.id !== 'input_data' && i.id !== 'required_parameters').map((item) => (
                      <div key={item.id} data-testid={`workflow-prereq-item-${item.id}`} style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                        <span style={{ fontWeight: 500 }}>{item.label}</span>
                        {item.reason && <span style={{ opacity: 0.8 }}>{item.reason}</span>}
                        {item.chatPrompt && onAdjustViaChat && (
                          <button
                            type="button"
                            className="linkish"
                            data-testid={`prereq-chat-link-${item.id}`}
                            onClick={() => onAdjustViaChat(item.chatPrompt!)}
                          >
                            Continue in chat →
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {/* ── Post-run links row ─────────────────────────────────────────── */}
              {(invocationId || status === 'completed') && (
                <div className="results-links">
                  <button
                    className="linkish"
                    onClick={() => handleToggleShowResults((prev) => !prev)}
                    disabled={!invocationId || status === 'failed'}
                    data-testid="button-view-results-link"
                  >
                    {showResults ? 'Hide results' : 'View results'}
                  </button>
                  <span className="sep">·</span>
                  <button
                    className="linkish"
                    onClick={() => {
                      if (!invocationId || status === 'failed') return;
                      emitUxEvent('output.download_clicked', { invocationId, scope: 'all' });
                      window.open(`/api/invocations/${invocationId}/download-all`, '_blank');
                      setDownloadAllPromptOpen(true);
                    }}
                    disabled={!invocationId || status === 'failed'}
                    data-testid="button-download-all-workflow-panel"
                  >
                    Download all
                  </button>
                  <span className="sep">·</span>
                  <button
                    className="linkish"
                    style={{ display: 'inline-flex', alignItems: 'center', gap: 3 }}
                    disabled={status !== 'completed' || !runId || analysisState === 'loading'}
                    onClick={handleAnalyzeResults}
                    data-testid="button-analyze-results"
                  >
                    {analysisState === 'loading' && <Loader2 className="h-2.5 w-2.5 animate-spin" />}
                    {analysisState === 'loading' ? 'Analyzing…' : 'AI analysis'}
                  </button>
                  <span className="sep">·</span>
                  <button
                    className="linkish"
                    disabled={!invocationId || status === 'failed'}
                    onClick={() => {
                      if (!invocationId || status === 'failed') return;
                      window.open(`/api/invocations/${invocationId}/methods-report`, '_blank');
                    }}
                    data-testid="button-download-methods-report"
                    data-invocation-id={invocationId || ''}
                  >
                    Report
                  </button>
                  {(availableQcProfiles.length > 0 || qcGateData !== null) && (
                    <>
                      <span className="sep">·</span>
                      <button
                        className="linkish"
                        disabled={!invocationId || status === 'failed'}
                        onClick={() => {
                          if (!invocationId || status === 'failed') return;
                          window.open(`/api/invocations/${invocationId}/qc-audit-download`, '_blank');
                        }}
                        data-testid="button-download-qc-audit"
                      >
                        QC audit log
                      </button>
                    </>
                  )}
                </div>
              )}

            {/* ── Run metrics strip ─────────────────────────────────────────── */}
              {(nextflowStatus?.duration_s != null || nextflowStatus?.started_at != null) && (
                <div className="metrics-strip" data-testid="run-metrics-strip">
                  {nextflowStatus?.duration_s != null && (
                    <div className="cell" data-testid="run-metric-duration">
                      <div className="lbl">Wall time</div>
                      <div className="val" data-testid="run-metric-duration-value">
                        {nextflowStatus.duration_s < 60
                          ? `${nextflowStatus.duration_s}s`
                          : `${Math.floor(nextflowStatus.duration_s / 60)}m ${nextflowStatus.duration_s % 60}s`}
                      </div>
                    </div>
                  )}
                  {nextflowStatus?.started_at != null && (
                    <div className="cell" data-testid="run-metric-started-at">
                      <div className="lbl">Started</div>
                      <div className="val">{new Date(nextflowStatus.started_at * 1000).toLocaleTimeString()}</div>
                    </div>
                  )}
                  {nextflowStatus?.completed_at != null && (
                    <div className="cell" data-testid="run-metric-completed-at">
                      <div className="lbl">Ended</div>
                      <div className="val">{new Date(nextflowStatus.completed_at * 1000).toLocaleTimeString()}</div>
                    </div>
                  )}
                  {/* LLM cost cell — commented out per UX review 2026-06-19.
                      Per-run cost is not surfaced in the panel; billing lives on
                      the per-user billing page.
                  {executionMetrics?.perStepLlmCost != null && (
                    <div className="cell" data-testid="run-metric-per-step-costs">
                      <div className="lbl">LLM cost</div>
                      <div className="val">
                        {Object.values(executionMetrics.perStepLlmCost).every(v => v === null)
                          ? "—"
                          : `$${Object.values(executionMetrics.perStepLlmCost)
                              .filter((v): v is number => v !== null)
                              .reduce((a, b) => a + b, 0)
                              .toFixed(4)}`}
                      </div>
                    </div>
                  )}
                  */}
                </div>
              )}

              {/* Phase cards are now rendered at the top of the panel — see above */}
              
              {previewFile && activeRunId && (
                <StepOutputPreview
                  runId={activeRunId}
                  file={previewFile}
                  onClose={() => setPreviewFile(null)}
                />
              )}
              {adjustStep && activeRunId && (
                <StepAdjustModal
                  open={!!adjustStep}
                  onOpenChange={(open) => { if (!open) setAdjustStep(null); }}
                  runId={activeRunId}
                  step={adjustStep}
                  workflowDefinition={workflowDefinition}
                  onRerunSubmitted={(newRunId) => {
                    setAdjustStep(null);
                    setRerunRunId(newRunId);
                    onAdjustViaChat?.(`Rerunning workflow from step ${adjustStep.name}. New run ID: ${newRunId}`);
                  }}
                />
              )}

          {/* ── Error recovery card ───────────────────────────────────────────── */}
          {status === 'failed' && (
            <div className="alert err" data-testid="execution-triage-panel" style={{ flexDirection: 'column', alignItems: 'flex-start', gap: 8, margin: '8px 18px' }}>
              <div style={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: 6 }}>
                <XCircle className="h-3.5 w-3.5" style={{ flexShrink: 0 }} />
                Workflow Failed
                {errorExplaining && <span style={{ fontWeight: 400, fontSize: 11, opacity: 0.7 }}>Analyzing error…</span>}
              </div>
              {errorExplanation ? (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, width: '100%' }}>
                  <div><span style={{ fontWeight: 600 }}>What went wrong: </span>{errorExplanation.human_summary}</div>
                  <div><span style={{ fontWeight: 600 }}>Suggested fix: </span>{errorExplanation.suggested_fix}</div>
                  {errorExplanation.chat_prompt && (
                    <button
                      className="btn sm"
                      onClick={() => { setErrorExplanation(null); onAdjustViaChat?.(errorExplanation.chat_prompt); }}
                      data-testid="button-error-fix-chat"
                    >
                      Fix &amp; Retry via Chat
                    </button>
                  )}
                  <div style={{ fontSize: 10, opacity: 0.55 }}>
                    {errorExplanation.error_type}{errorExplanation.llm_used ? ' · AI-analyzed' : ' · pattern-matched'}
                  </div>
                </div>
              ) : errorExplaining ? (
                <span>Analyzing error log…</span>
              ) : errorMessage ? (
                <span>{errorMessage}</span>
              ) : null}
            </div>
          )}

          {(invocationId || runId) && showResults && (
            <div style={{ padding: '8px 0 0' }}>
              <div style={{ padding: '0 18px 6px', fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--text-dim)' }}>Output Results</div>
              <ChatOutputAttachments
                invocationId={invocationId || runId || ''}
                sessionId={sessionId}
                runId={runId}
                executionStatus={status}
                errorMessage={errorMessage}
              />
              {activeRunId && (
                <FindingsCard
                  runId={activeRunId}
                  onContinueAnalysis={onAdjustViaChat}
                />
              )}
            </div>
          )}

          {/* ── AI Analysis Panel ───────────────────────────────────────── */}
          {(analysisState === 'loading' || analysisState === 'done' || analysisState === 'error') && (
            <div className="findings-card" data-testid="ai-analysis-panel">
              <div className="f-h">
                <Activity className="h-3.5 w-3.5" style={{ flexShrink: 0 }} />
                AI Findings Analysis
                {analysisState === 'done' && <span style={{ fontWeight: 400, marginLeft: 'auto', fontSize: 10 }}>claude-sonnet-4-6</span>}
              </div>

              {analysisState === 'loading' && (
                <div className="f-body" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" style={{ flexShrink: 0 }} />
                  Analyzing output files…
                </div>
              )}

              {analysisState === 'error' && (
                <div className="alert err" style={{ margin: '8px 14px' }}>
                  {analysisError || 'Analysis failed. Try again.'}
                </div>
              )}

              {analysisState === 'done' && analysisResult && (
                <>
                  {analysisResult.summary && (
                    <div className="f-body">{analysisResult.summary}</div>
                  )}

                  {analysisResult.key_findings?.length > 0 && (
                    <div className="f-section">
                      <div className="f-section-lbl">Key Findings</div>
                      {analysisResult.key_findings.map((f: any, i: number) => (
                        <div key={i} className="f-row" style={{ flexDirection: 'column' }}>
                          <b>{f.finding}</b>
                          {f.significance && <span>{f.significance}</span>}
                        </div>
                      ))}
                    </div>
                  )}

                  {analysisResult.quality_assessment && (
                    <div className="f-section">
                      <div className="f-section-lbl">Quality Assessment</div>
                      <div style={{ fontSize: 12.5, color: 'var(--text-muted)', lineHeight: 1.5 }}>{analysisResult.quality_assessment}</div>
                    </div>
                  )}

                  {analysisResult.next_steps?.length > 0 && (
                    <div className="f-section">
                      <div className="f-section-lbl">Recommended Next Steps</div>
                      {analysisResult.next_steps.map((step: string, i: number) => (
                        <div key={i} className="f-row">{i + 1}. {step}</div>
                      ))}
                    </div>
                  )}

                  {analysisResult.citations?.length > 0 && (
                    <div className="f-section">
                      <div className="f-section-lbl">Supporting References</div>
                      {analysisResult.citations.map((c: any, i: number) => (
                        <div key={i} className="f-row" style={{ flexDirection: 'column', gap: 1 }}>
                          <b>{c.tool_or_resource}</b>
                          <span className="f-cite">{c.reference}{c.relevance ? ` — ${c.relevance}` : ''}</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {analysisResult.limitations && (
                    <div className="f-section">
                      <div className="alert warn" style={{ margin: 0 }}>
                        <AlertTriangle className="h-3.5 w-3.5" style={{ flexShrink: 0 }} />
                        <span><b>Limitations: </b>{analysisResult.limitations}</span>
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          )}
          </div>{/* end inner Phases-tab-only block (post-strip) */}
      </div>{/* end panel-body */}
      </div>{/* end shared panel-body wrapper (Settings + Phases tabs) */}

      {/* ── Sticky status-aware action bar at panel bottom ────────────────────
              running       → ⏸ Pause   ⏹ Stop
              paused        → ▶ Resume  ⏹ Stop
              completed/fail→ ▶ Run again
              idle/pending  → (no bar — Settings tab + main Run button do it) */}
      {(() => {
        const isRunning   = status === 'running';
        const isPaused    = status === 'paused';
        const isTerminal  = status === 'completed' || status === 'failed';
        if (!isRunning && !isPaused && !isTerminal) return null;

        const barStyle: React.CSSProperties = {
          borderTop: '1px solid var(--border)',
          padding: 10,
          background: 'oklch(0.12 0.005 260)',
          display: 'flex',
          gap: 8,
        };
        const btnBase: React.CSSProperties = {
          flex: 1,
          padding: '10px 14px',
          background: 'transparent',
          color: 'oklch(0.98 0.005 260)',
          border: '1px solid oklch(0.28 0.005 260)',
          borderRadius: 6,
          fontSize: 14,
          fontWeight: 500,
          cursor: 'pointer',
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 8,
        };
        const primary: React.CSSProperties = { ...btnBase, border: 'none' };

        return (
          <div data-testid="panel-action-bar" data-status={status} style={barStyle}>
            {isRunning && (
              <>
                <button
                  type="button"
                  data-testid="panel-action-pause"
                  onClick={onPause}
                  disabled={!onPause}
                  style={btnBase}
                  title="Pause execution"
                ><span>⏸</span><span>Pause</span></button>
                <button
                  type="button"
                  data-testid="panel-action-stop"
                  onClick={onCancel}
                  disabled={!onCancel}
                  style={btnBase}
                  title="Stop execution"
                ><span>⏹</span><span>Stop</span></button>
              </>
            )}
            {isPaused && (
              <>
                <button
                  type="button"
                  data-testid="panel-action-resume"
                  onClick={onResume}
                  disabled={!onResume}
                  style={primary}
                  title="Resume execution"
                ><span>▶</span><span>Resume</span></button>
                <button
                  type="button"
                  data-testid="panel-action-stop"
                  onClick={onCancel}
                  disabled={!onCancel}
                  style={btnBase}
                  title="Stop execution"
                ><span>⏹</span><span>Stop</span></button>
              </>
            )}
            {isTerminal && (
              <button
                type="button"
                data-testid="panel-run-again-cta"
                onClick={() => onExecute?.(params)}
                disabled={!onExecute}
                style={primary}
                title={status === 'failed' ? 'Restart from a fresh state' : 'Run this workflow again'}
              ><span>▶</span><span>{status === 'failed' ? 'Restart' : 'Run again'}</span></button>
            )}
          </div>
        );
      })()}

      {/* ── Sticky footer with primary run action ─────────────────────────────── */}
      <div className="panel-foot" data-tour="run-footer">
        {executionBlockedReason && (
          <div className="alert err" style={{ margin: 0, marginBottom: 6 }}>
            <AlertTriangle className="h-3.5 w-3.5" style={{ flexShrink: 0, marginTop: 1 }} />
            <div className="body">
              <strong>Execution blocked</strong> — {executionBlockedReason}
              {lowConfSecondsLeft !== null && (
                <div data-testid="low-confidence-countdown" style={{ marginTop: 4, fontSize: 11, color: 'var(--text-dim)' }}>
                  Auto-confirming in {lowConfSecondsLeft}s unless you act.
                </div>
              )}
              <div className="act">
                <button
                  className="btn sm"
                  onClick={() => {
                    if (lowConfTimerRef.current) { clearInterval(lowConfTimerRef.current); lowConfTimerRef.current = null; }
                    setLowConfSecondsLeft(null);
                    setGlobalParamsOpen(true);
                  }}
                >
                  Fix now
                </button>
                <button
                  className="btn ghost sm"
                  data-testid="button-confirm-low-confidence-run"
                  disabled={status === 'running' || status === 'completed' || (isPrereqBlocked && !prereqChecklist?.overrideAllowed) || isAutofixActive || isLicenseBlocked}
                  onClick={() => fireLowConfidenceConfirm('user')}
                >
                  Confirm anyway
                </button>
              </div>
            </div>
          </div>
        )}
        <div className="run-primary">
          {!executionBlockedReason && (
            <button
              className="btn primary"
              data-testid="button-run-workflow-panel"
              onClick={() => { if (status === 'completed' || status === 'failed') analytics.track('run_again_clicked', { source: 'panel' }); handleExecute(); }}
              disabled={
                status === 'running'
                || isPrereqBlocked
                || isAutofixActive
                || isLicenseBlocked
                // Hard gate (2026-06-11): block submit when required global
                // params are empty. Without this, a user could ignore the
                // Workflow-settings strip and click Run with blanks.
                // Only enforced on initial run (idle / pending_review) —
                // re-runs of completed / failed runs use the prior params.
                || ((status === 'idle' || status === 'pending_review')
                    && globalRequiredUnfilledCount > 0)
              }
              title={
                (status === 'idle' || status === 'pending_review') && globalRequiredUnfilledCount > 0
                  ? `Fill in ${globalRequiredUnfilledCount} required parameter${globalRequiredUnfilledCount > 1 ? 's' : ''} above before running`
                  : undefined
              }
              data-required-unfilled={
                (status === 'idle' || status === 'pending_review')
                  ? globalRequiredUnfilledCount
                  : undefined
              }
            >
              {status === 'running' ? (
                <><Loader2 className="h-4 w-4 animate-spin" style={{ marginRight: 6 }} />Running…</>
              ) : status === 'failed' ? (
                'Restart'
              ) : status === 'completed' ? (
                'Run again'
              ) : (
                'Confirm and run workflow'
              )}
            </button>
          )}
          {showingSubmittedParams && (status === 'completed' || status === 'failed') && (
            <button type="button" data-testid="button-reset-params-to-defaults" onClick={() => { analytics.track('reset_to_defaults_clicked'); resetToDefaults(); }} title="Showing params from your last run. Click to reset to workflow defaults." style={{ marginLeft: 8, fontSize: 11, color: 'var(--bm-text-dim, oklch(0.55 0.01 260))', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}>Reset to defaults</button>
          )}
        </div>
        <div className="run-foot-meta">
          {status === 'paused' && onResume && (
            <button className="linkish" data-testid="button-resume-workflow-panel" onClick={onResume}>
              Resume
            </button>
          )}
          {usageMeter && usageMeter.used > 0 && (status === 'idle' || status === 'pending_review') && (
            <span data-testid="usage-meter" style={{ fontSize: 11 }}>
              {usageMeter.used.toFixed(1)} / {usageMeter.limit} vCPU-hrs
            </span>
          )}
        </div>
      </div>

      {/* Skip step confirmation dialog — disabled until backend skip endpoint added
      {confirmSkipPhaseId && (
        <div ...>...</div>
      )} */}

      <GalaxyDatasetBrowser
        open={!!browsingForParam}
        onClose={() => setBrowsingForParam(null)}
        paramLabel={browsingForParam?.label}
        sessionDatasets={sessionDatasets.map(d => ({
          id: d.id,
          name: d.name,
          fileType: d.file_type || undefined,
          // Prefer local path (Nextflow reads it directly), fallback to source URL, then Galaxy ID
          path: d.file_path || d.source_url || undefined,
          galaxyDatasetId: d.galaxy_dataset_id || undefined,
        }))}
        onSelect={async (value, name) => {
          if (!browsingForParam) { setBrowsingForParam(null); return; }
          let resolved = value;
          // If value looks like a Galaxy dataset ID (no path separator, no protocol),
          // resolve it to a local file path via the backend.
          if (value && !value.includes('/') && !value.includes('://')) {
            try {
              const r = await fetch(`/api/galaxy/datasets/${encodeURIComponent(value)}/resolve`);
              if (r.ok) {
                const data = await r.json();
                resolved = data.file_path || value;
              }
            } catch { /* keep original value on error */ }
          }
          handleParamChange(browsingForParam.id, resolved);
          toast({ title: `"${name}" selected`, description: `Assigned to ${browsingForParam.label}.` });
          setBrowsingForParam(null);
        }}
      />
    </div>
  );
}
