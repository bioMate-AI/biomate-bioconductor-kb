import type { WorkflowProgressEvent } from "@/lib/workflow-progress-event"
import { canControlExecutionFromQc } from "@shared/qc-assessment";
import { classifyRunFailure } from "@shared/run-failure-classifier";
import React, { useState, useEffect, useRef } from 'react';
import '@/styles/workflow-panel.css';
import { useRunAgainParamCarryover } from '@/hooks/useRunAgainParamCarryover';
import { analytics } from '@/lib/analytics';
import { t, tOr, tStatus } from '@/lib/i18n';
import { HintTip } from '@/components/ui/hint-tip';
import { emitUxEvent } from "@/lib/ux-telemetry";
import { PhaseCard } from "./phase-card";
import { ParameterGroup } from "./parameter-group";
import { derivePrerunInputs, blockingInputRows, runIsBlockedByInputs, type InputMappingRow } from "./input-mapping-status";
import { unboundClinicHardDataFromParams, CLINIC_HARD_REQUIRED_DATA_NAMES } from "../../../shared/workflow-data-inputs";
import { StepOutputPreview } from "./step-output-preview";
import { StepAdjustModal } from "./step-adjust-modal";
import { StepDetail, type StepDetailStep } from "./steps/step-detail";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { VisuallyHidden } from "@radix-ui/react-visually-hidden";
import { Loader2, CheckCircle2, XCircle, AlertTriangle, Download, RotateCcw, Square, ChevronRight, ShieldCheck, Activity, Clock, SkipForward, FolderOpen, Database, Maximize2, Minimize2, Ban } from "lucide-react";
import { useLocation } from 'wouter';
import { ReportConfusionButton } from "./feedback/report-confusion-button";
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt";
import { ChatOutputAttachments } from "./chat-output-attachments";
import { FindingsCard } from "./findings-card";
import type { PrereqChecklist } from "@/lib/prereq-normalizer";
import { GalaxyDatasetBrowser } from "./galaxy-dataset-browser";
import { useToast } from "@/hooks/use-toast";
import { LicenseGate, licenseGatePathForWorkflow } from "./license-gate";
import { cleanParamValueForDisplay, userFacingErrorText, userFacingStepName } from '@/lib/user-facing-text';
import { useLocalizedLabels } from '@/lib/use-localized-labels';
export { cleanParamValueForDisplay, userFacingStepName } from '@/lib/user-facing-text';
import { AutoLoopPanel } from "./auto-loop-panel";
import type { AutoLoopPanelState } from "./auto-loop-panel";
import { ApprovalGate, type ApprovalGateData } from "./approval-gate";
// Hidden from Workflow settings at user request; retain the components for later review.
// import { RolesCard, VerifyPattern, type RolesData, type VerifyKind } from "./roles-verify";
import { SkipDependency, type PhaseSkipInfo } from "./skip-dependency";
import { stripAnsi } from "@/lib/utils";
import { AfterRunReport } from "@/v2/AfterRunReport";
import { useRealtimeRunStatus } from "./useRealtimeRunStatus";

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
  /**
   * A user-cancelled run is terminal like 'failed' (after-run tab, terminal
   * footer) but is NOT a failure — render it neutrally ("Cancelled", gray, no
   * red "FAILED"/"Restart"). We keep `status==='failed'` for the terminal-state
   * machinery and use this flag only to override the user-visible presentation.
   */
  wasCancelled?: boolean;
  errorMessage?: string;
  progress?: number;
  onParameterChange?: (id: string, value: any) => void;
  sessionId?: string;
  runId?: string;
  /**
   * C1 (chat → panel deep-link): when a chat answer links to a specific
   * after-run tab, the host sets this; the panel switches to the After-run
   * tab and forwards it to AfterRunReport (Stream 2 consumes `targetTab`).
   */
  targetAfterRunTab?: 'summary' | 'outputs' | 'report';
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
  onWorkflowProgress?: (event: WorkflowProgressEvent) => void;
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
  onClose?: () => void;
  onToggleExpand?: () => void;
  expanded?: boolean;
  projectName?: string;
  /** When provided, shows a "Go to project" chip in the panel header. */
  projectId?: string;
  /** Called when the backend silently reroutes a failed run to an alternative workflow. */
  onAutoReroute?: (event: { fromWorkflow: string; toWorkflowName: string; reason: string; newRunId: string; newInvocationId: string }) => void;
  /**
   * Called after a successful /rerun call so the parent can restart status
   * polling (useUnifiedExecution stops polling on terminal states — resume
   * needs to re-enable it so the UI reflects the new run's progress).
   */
  onRerunStarted?: (runId: string) => void;
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
  example?: boolean;
  /** Scientific rationale for the AI-recommended value */
  rationale?: string;
};

/** Matches a "Phase X" / "Phase X — Name" prefix a backend label may carry. */
const PHASE_PREFIX_RE = /^phase\s+[a-z0-9]+\s*(?:[—–:-]\s*|$)/i;


/** Backend labels may already include their own phase prefix (possibly with a
 *  different letter — e.g. a `// [Phase B]` source annotation on a
 *  single-phase workflow). Strip it and render the display letter once. */
export function phaseGroupLabel(letter: string, semantic: string): string {
  const prefix = `Phase ${letter.toUpperCase()}`;
  const name = semantic.trim().replace(PHASE_PREFIX_RE, '').trim();
  return name ? `${prefix} — ${name}` : prefix;
}

/** Display letter for the Nth (0-based) lettered phase actually shown:
 *  A, B, C … Z, then 27, 28 … Phase letters are positional, never taken from
 *  the backend group key, so they always start at A and never skip. */
export function phaseDisplayLetter(index: number): string {
  return index < 26 ? String.fromCharCode(65 + index) : String(index + 1);
}

type PhaseGroupStep = { phase_group?: unknown; phase_label?: unknown; parameters?: Record<string, unknown> | null };

/** Group steps by their backend `phase_group` id, in first-seen order. The
 *  backend id stays the group `key` (autoloop gate matching, skip analysis,
 *  test ids); the user-visible `letter`/`label` are assigned by position among
 *  the lettered phases displayed. Ungrouped steps ('other') get no letter. */
export function groupStepsIntoPhases<T extends PhaseGroupStep>(
  steps: T[],
  allStepsLabel: string,
): Array<{ key: string; letter: string; label: string; steps: T[]; phaseParams: string[] }> {
  if (steps.length === 0) return [];
  if (!steps.some(p => p.phase_group)) {
    const uniqueParams = Array.from(new Set(steps.flatMap(p => Object.keys(p.parameters || {}))));
    return [{ key: 'all', letter: String(Math.min(steps.length, 9)), label: allStepsLabel, steps, phaseParams: uniqueParams }];
  }
  const groupMap = new Map<string, { steps: T[]; semantic: string; phaseParams: string[] }>();
  for (const step of steps) {
    const key = (step.phase_group as string) || 'other';
    if (!groupMap.has(key)) groupMap.set(key, { steps: [], semantic: '', phaseParams: [] });
    const group = groupMap.get(key)!;
    if (!group.semantic && typeof step.phase_label === 'string') group.semantic = step.phase_label;
    group.steps.push(step);
    for (const pName of Object.keys(step.parameters || {})) {
      if (!group.phaseParams.includes(pName)) group.phaseParams.push(pName);
    }
  }
  let lettered = 0;
  return Array.from(groupMap.entries()).map(([key, g]) => {
    // Render convention (per #23):
    //   - "Other Steps"                 when no annotation matched (key === 'other')
    //   - "Phase A — Motion Correction" when the backend supplied a semantic label
    //   - "Phase A"                     when only the group id is present
    if (key === 'other') {
      return { key, letter: '·', label: 'Other Steps', steps: g.steps, phaseParams: g.phaseParams };
    }
    const letter = phaseDisplayLetter(lettered++);
    return { key, letter, label: phaseGroupLabel(letter, g.semantic), steps: g.steps, phaseParams: g.phaseParams };
  });
}

/** Recovery advice must describe the same action the footer can actually perform. */
export function failureRecoveryAdvice(action: string | undefined, canResume: boolean): string | null {
  if (action === 'resume' || action === 'resume_more_resources') {
    return canResume ? tOr('panel.diag.advice_resume', 'Resume from last step to reuse completed work.')
      : tOr('panel.diag.advice_no_resume', 'No completed step is available to resume. Review the error and restart after correcting the cause.');
  }
  if (action === 'fix_and_resume') return tOr('panel.diag.advice_fix', 'Adjust your parameters or input files, then run again with edits.');
  if (action === 'check_input') return tOr('panel.diag.advice_check_input', 'Check your input data and parameters against the error, then run again.');
  return null;
}

/** Galaxy failure categories with a locale sentence (panel.diag.cat_*). The
 *  sentences make no resume promise — the advice line below says whether a
 *  resume is possible. arch_compat keeps the server's bilingual message. */
const LOCALIZED_FAILURE_CATEGORIES = new Set([
  'infra_transient', 'resource_memory', 'resource_time', 'config_param',
  'input_data', 'tool_error', 'workflow_code', 'unknown',
]);

/** Server diagnosis cannot promise a checkpoint the recorded run does not have. */
export function failureDiagnosisMessage(message: string, canResume: boolean, category?: string, detail?: string): string {
  if (category && LOCALIZED_FAILURE_CATEGORIES.has(category)) {
    const key = category === 'tool_error' && detail ? 'panel.diag.cat_tool_error_detail' : `panel.diag.cat_${category}`;
    return tOr(key, message, { detail: detail || '' });
  }
  if (canResume) return message;
  return message.replace(/\s*(?:You|It|The run) (?:can|may) resume[^.!?]*(?:[.!?]|$)/gi, '').trim()
    || tOr('panel.run_stopped', 'The run stopped before completing.');
}

type ViewerPhaseStatus = 'pending' | 'running' | 'completed' | 'failed' | 'paused';

type ViewerPhase = {
  id: string;
  name: string;
  description?: string;
  status: ViewerPhaseStatus;
  toolId?: string;
  processName?: string;
  tool?: string;
  toolVersion?: string;
  duration?: string;
  workDir?: string;
  jobId?: string;
  errorMessage?: string;
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

/**
 * Map a viewer step (the objects in PhaseGroup.steps) onto StepDetailStep.
 *
 * The step objects the viewer already holds carry: id, name, processName,
 * status, parameters, outputFiles ({name,path,extension}), workDir, taskFiles.
 * Everything StepDetail renders is derived ONLY from those real fields — no
 * value is invented. Fields the run does not report are omitted so StepDetail
 * shows its honest empty state:
 *   - tool / toolVersion / duration: NOT tracked per step in the viewer's data
 *     → omitted (StepDetail renders "tool not reported" / "(version n/a)" /
 *       "duration n/a").
 *   - inputs: NOT tracked per step → omitted (→ "upstream step output").
 *   - parameters: passed through as-is when present; object-typed metadata
 *     placeholders ({type,label,default}) are dropped so the resolved-params
 *     table shows the scalar runtime values, matching the inline step-meta rule.
 *   - outputs: mapped straight from outputFiles (the same {name,path,extension}
 *     the inline preview and download links already use).
 */
export function recordedProcessPhases(processes: unknown): ViewerPhase[] {
  if (!Array.isArray(processes)) return [];
  return processes.filter(process => process && typeof process === 'object' && (process.name || process.process)).map((process, index) => {
    const name = String(process.name || process.process);
    const raw = String(process.status || process.state || '').toLowerCase();
    const state: ViewerPhaseStatus = /fail|error|cancel/.test(raw) ? 'failed'
      : ['completed', 'succeeded', 'ok', 'cached'].includes(raw) ? 'completed'
      : ['running', 'submitted'].includes(raw) ? 'running' : 'pending';
    return {
      id: String(process.id ?? process.task_id ?? `recorded-task-${index}`), name,
      processName: String(process.process || name), status: state,
      ...reportedStepDetails(process),
      parameters: process.parameters && typeof process.parameters === 'object' ? process.parameters : {},
      toolId: typeof process.tool_id === 'string' ? process.tool_id : undefined,
      tool: typeof process.tool === 'string' ? process.tool : undefined,
      toolVersion: typeof process.tool_version === 'string' ? process.tool_version : undefined,
      duration: typeof process.duration === 'string' ? process.duration : undefined,
      outputFiles: [],
    };
  });
}

/**
 * Normalize a process / step identifier so a planned step and its runtime
 * process match despite nf-core's fully-qualified naming.
 *
 * Nextflow reports a process as `NFCORE_RNASEQ:RNASEQ:FASTQC`, while the planned
 * step carries a short name / tool id (`fastqc`). Reduce both to the LAST
 * `:`-delimited segment, lowercased, with non-alphanumerics stripped, so
 * `NFCORE_RNASEQ:RNASEQ:FASTQC` and `fastqc` both collapse to `fastqc`, and
 * `STAR_ALIGN` / `star_align` both collapse to `staralign`. Strict equality on
 * this key avoids the over-matching that sank the earlier attempt (a loose
 * substring match let one record fill several planned steps).
 */
export function nfcoreProcessKey(name: string | undefined | null): string {
  if (!name || typeof name !== 'string') return '';
  const tail = name.split(':').pop() || name;
  return tail.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function plannedMatchKeys(step: ViewerPhase): string[] {
  const keys = [step.processName, step.toolId, step.name, step.id].map(nfcoreProcessKey).filter(Boolean);
  return Array.from(new Set(keys));
}

/**
 * Merge the planned phase list with the runtime-recorded processes.
 *
 * Why this exists: a stopped / paused run records only the processes that
 * actually started, so returning the recorded list alone made every
 * not-yet-started phase vanish from the panel (founder: "I stopped the first
 * phase and the rest all disappeared"). This merge keeps the full planned list
 * visible while reflecting real runtime status on the phases that ran.
 *
 * Rules (each addresses a HIGH bug the first attempt hit):
 *  - A recorded process is consumed AT MOST ONCE, so one record cannot fill
 *    several identically-named planned steps.
 *  - A matched planned step adopts the runtime status AND evidence
 *    (error/workDir/jobId/duration/tool/outputs), so a FAILED run keeps its
 *    failure detail instead of dropping it.
 *  - An unmatched planned step stays `pending` (the fix — it is no longer
 *    dropped).
 *  - A recorded process that matches no planned step is appended, so a
 *    dynamically-spawned process is never hidden.
 */
export function mergePlannedWithRecorded(planned: ViewerPhase[], recorded: ViewerPhase[]): ViewerPhase[] {
  if (!recorded.length) return planned;   // pre-run / idle: show the plan
  if (!planned.length) return recorded;   // old sessions without planned steps

  const consumed = new Set<number>();
  const merged: ViewerPhase[] = planned.map((step) => {
    const keys = plannedMatchKeys(step);
    const idx = recorded.findIndex(
      (rec, i) => !consumed.has(i) && keys.includes(nfcoreProcessKey(rec.processName || rec.name)),
    );
    if (idx === -1) return step; // keep pending — do NOT drop the planned step
    consumed.add(idx);
    const rec = recorded[idx];
    const hasOutputs = Array.isArray(rec.outputFiles) && rec.outputFiles.length > 0;
    const hasParams = rec.parameters && Object.keys(rec.parameters).length > 0;
    return {
      ...step,
      status: rec.status,
      processName: rec.processName ?? step.processName,
      tool: rec.tool ?? step.tool,
      toolVersion: rec.toolVersion ?? step.toolVersion,
      duration: rec.duration ?? step.duration,
      workDir: rec.workDir ?? step.workDir,
      jobId: rec.jobId ?? step.jobId,
      errorMessage: rec.errorMessage ?? step.errorMessage,
      outputFiles: hasOutputs ? rec.outputFiles : step.outputFiles,
      parameters: hasParams ? rec.parameters : step.parameters,
    };
  });
  // If NOT ONE planned step matched a recorded process, the plan does not
  // correspond to this run — it is a generic placeholder (e.g. a single
  // "Step 1" stub) or a stale plan for a different pipeline. Show the real
  // recorded processes instead of phantom pending steps beside them.
  if (consumed.size === 0) return recorded;
  const extras = recorded.filter((_, i) => !consumed.has(i));
  return [...merged, ...extras];
}

export function qcWorkflowDomain(definition: any, profile?: { domain_hint?: string } | null): string {
  if (profile?.domain_hint) return profile.domain_hint.toLowerCase();
  const explicit = String(definition?.domain || '').toLowerCase();
  const aliases: Record<string, string> = { transcriptomics: 'rnaseq', single_cell: 'scrna_seq', genomics: 'wgs', cryoem: 'cryo_em' };
  const identity = `${definition?.name || ''} ${definition?.nextflow_path || ''}`.toLowerCase();
  if (/scdownstream|scrnaseq|scrna|single.cell|cellranger/.test(identity)) return 'scrna_seq';
  return aliases[explicit] || explicit;
}

// Sequencing-alignment QC metrics — only meaningful for workflows that consume
// raw reads and perform trimming/alignment. Count-matrix differential-expression
// workflows never produce these numbers, so they must not inherit these gates.
const ALIGNMENT_QC_METRICS = new Set<string>([
  'reads_surviving_pct', 'alignment_rate', 'mito_fraction_pct',
  'mapped_pct', 'duplicate_rate', 'assigned_reads_pct',
]);

/**
 * True for count-matrix differential-expression workflows — ones that start from
 * a pre-computed count matrix (+ contrasts / samplesheet CSVs) and declare NO
 * alignment or trimming steps (nf-core/differentialabundance, standalone
 * DESeq2 / limma / edgeR). These are a transcriptomics-domain workflow, so the
 * domain alias (transcriptomics → rnaseq) would otherwise make them inherit the
 * sequencing-alignment QC family. We identify them conservatively by workflow
 * identity (name / nextflow_path) so real sequencing pipelines — including
 * single-cell sequencing like scdownstream — are untouched.
 */
export function isCountMatrixDeWorkflow(definition: any): boolean {
  const identity = `${definition?.name || ''} ${definition?.nextflow_path || ''} ${definition?.workflow_name || ''}`.toLowerCase();
  if (!identity.trim()) return false;
  // Letter-only boundaries so separators (_, -, /, digits, spaces) delimit the
  // token — "limma_voom" / "deseq2" match, "ledger" does not.
  return /differential[_-]?abundance|(?:^|[^a-z])(?:deseq2?|limma|edger)(?=$|[^a-z])/.test(identity);
}

export function reportedStepDetails(process: any): { workDir?: string; jobId?: string; errorMessage?: string } {
  const text = (...values: unknown[]) => values.find(value => typeof value === 'string' && value.trim()) as string | undefined;
  const details = {
    workDir: text(process?.workDir, process?.work_dir, process?.workdir),
    jobId: text(process?.jobId, process?.job_id) ?? (typeof process?.job_id === 'number' && Number.isFinite(process.job_id) ? String(process.job_id) : undefined),
    errorMessage: text(process?.errorMessage, process?.error_message, process?.error),
  };
  return Object.fromEntries(Object.entries(details).filter(([, value]) => value !== undefined));
}

export function buildStepDetailStep(step: any): StepDetailStep {
  const rawParams = (step?.parameters && typeof step.parameters === "object")
    ? (step.parameters as Record<string, unknown>)
    : undefined;
  // Keep only scalar runtime values — object placeholders ({type,label,default})
  // are schema metadata, not the value the step ran with. This mirrors the
  // inline step-meta filter above so the two surfaces agree.
  const parameters = rawParams
    ? Object.fromEntries(
        Object.entries(rawParams).filter(([, v]) => v === null || typeof v !== "object"),
      )
    : undefined;
  const outputs = Array.isArray(step?.outputFiles)
    ? (step.outputFiles as any[])
        .filter((f) => f && typeof f.path === "string" && typeof f.name === "string")
        .map((f) => ({
          name: String(f.name),
          path: String(f.path),
          extension: String(f.extension ?? f.name?.split(".").pop() ?? ""),
          // Thread the real byte size through so the Full Step View / preview
          // shows actual sizes instead of 0 B (it's in step.outputFiles).
          size: typeof f.size === "number" ? f.size : undefined,
        }))
    : [];
  return {
    id: String(step?.id ?? step?.name ?? "step"),
    name: String(step?.name ?? step?.processName ?? "step"),
    processName: step?.processName ? String(step.processName) : undefined,
    status: step?.status ? String(step.status) : undefined,
    // Thread the step annotation through so the detail panel can explain what the
    // step does — real data from the workflow definition, shown only when present.
    description: typeof step?.description === "string" && step.description.trim()
      ? step.description.trim()
      : (typeof step?.summary === "string" && step.summary.trim() ? step.summary.trim() : undefined),
    ...reportedStepDetails(step),
    tool: typeof step?.tool === "string" ? step.tool : undefined,
    toolVersion: typeof step?.toolVersion === "string" ? step.toolVersion : undefined,
    duration: typeof step?.duration === "string" ? step.duration : undefined,
    parameters: parameters && Object.keys(parameters).length > 0 ? parameters : undefined,
    outputs,
  };
}

/**
 * Derive the run KIND word for the panel kicker (Spec 13 §13.4).
 *
 * "Domain and run kind — never 'Workflow' for a run that is not one." A design
 * pipeline is a "Design run", an ad-hoc compute sandbox is "Ad-hoc · sandbox",
 * a model-training harness is a "Training run". Everything else (RNA-seq,
 * variant calling, ADMET, proteomics …) genuinely IS a workflow → "Workflow".
 *
 * The kind is read from an explicit definition field first (run_kind / kind /
 * mode / lane, in that order), then inferred from the domain string. The
 * honest default is "Workflow": a routed pipeline is a workflow unless the
 * definition tells us otherwise.
 */
const RUN_KIND_KEY = { 'Design run': 'design', 'Ad-hoc · sandbox': 'sandbox', 'Training run': 'training', Workflow: 'workflow' } as const;

export function deriveRunKind(workflowDefinition: any): 'Design run' | 'Ad-hoc · sandbox' | 'Training run' | 'Workflow' {
  const explicit = String(
    workflowDefinition?.run_kind ?? workflowDefinition?.kind ?? workflowDefinition?.mode ?? workflowDefinition?.lane ?? ''
  ).toLowerCase();
  if (explicit) {
    if (explicit.includes('design')) return 'Design run';
    if (explicit.includes('sandbox') || explicit === 'adhoc' || explicit === 'ad-hoc' || explicit.includes('compute')) return 'Ad-hoc · sandbox';
    if (explicit.includes('train')) return 'Training run';
    if (explicit.includes('workflow')) return 'Workflow';
  }
  const domain = String(workflowDefinition?.domain ?? workflowDefinition?.category ?? '').toLowerCase();
  // Design & generate (Spec 11 modalities) → design run.
  if (/\bdesign\b|design_generate|generative|molecular_design|de_novo/.test(domain)) return 'Design run';
  // Data-analysis ad-hoc compute → sandbox.
  if (/data_analysis|sandbox|ad[_-]?hoc/.test(domain)) return 'Ad-hoc · sandbox';
  // Model training harness (the four model domains under "Models & training").
  if (/model[_ ]?training|models_and_training|\btraining\b/.test(domain)) return 'Training run';
  return 'Workflow';
}

/**
 * Build the Workflow settings / param-strip rows from a workflow_ga-shaped
 * definition. Exported for unit tests (empty-schema phantom guard).
 *
 * When required_params ∪ optional_params is empty because the .nf was not
 * found, do NOT promote LLM inline_parameters into Recommended rows — that
 * produced the Admet Pred phantom target_pdb / library_file strip (2026-11-13).
 */
export function buildViewerParameters(workflowDefinition: any, currentParams: Record<string, any>): ViewerParameter[] {
  // Prefer structured required_params / optional_params when the backend .nf parser populated them.
  const reqList: any[] = Array.isArray(workflowDefinition?.required_params) ? workflowDefinition.required_params : [];
  const optList: any[] = Array.isArray(workflowDefinition?.optional_params) ? workflowDefinition.optional_params : [];
  if (reqList.length > 0 || optList.length > 0) {
    // Build structured params from required/optional lists
    const structuredNames = new Set([...reqList, ...optList].map((p: any) => p?.name).filter(Boolean));
    // A param declared in BOTH required_params and optional_params must render
    // once, not twice (reqList first → the required entry wins the dedup).
    const seenStructured = new Set<string>();
    const structured = [...reqList, ...optList]
      .filter((p: any) => p?.name && !String(p.name).startsWith("__"))
      .filter((p: any) => { if (seenStructured.has(p.name)) return false; seenStructured.add(p.name); return true; })
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
          required: reqList.some((r: any) => r.name === p.name)
            || CLINIC_HARD_REQUIRED_DATA_NAMES.has(String(p.name || '').toLowerCase()),
          group: p.group || undefined,
          options: Array.isArray(p.options) ? p.options : undefined,
          minimum: p.minimum != null ? Number(p.minimum) : undefined,
          maximum: p.maximum != null ? Number(p.maximum) : undefined,
          autoFilled: p.autoFilled === true,
          // The workflow's own test/demo value (the .nf comment says so) — shown as 示例, kept
          // only while the user has not replaced it.
          example: p.example === true && userValue === undefined,
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

  // Empty schema (missing .nf / orphan catalog): fail honestly — do NOT promote
  // LLM inline_parameters into Recommended rows (target_pdb, library_file, …).
  // Keep only explicit parameters / currentParams without autoFilled badges.
  const fromWorkflow = workflowDefinition?.parameters && typeof workflowDefinition.parameters === "object"
    ? workflowDefinition.parameters
    : {};
  const merged: Record<string, any> = {
    ...fromWorkflow,
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
      autoFilled: false,
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

/** Human-friendly elapsed duration, e.g. "47s", "3m 12s", "1h 04m 09s". */
function formatDuration(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) ms = 0;
  const total = Math.floor(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m ${String(s).padStart(2, '0')}s`;
  if (m > 0) return `${m}m ${String(s).padStart(2, '0')}s`;
  return `${s}s`;
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
  /** Backend phase_group id ('A'…, 'other', or 'all') — identity only. */
  key: string;
  /** Positional display letter (A, B, C…); see groupStepsIntoPhases. */
  letter: string;
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

// ── Multi-value / same-type list params (e.g. a multi-compound smiles_list) ──
// These were rendered as one raw-JSON <textarea> crammed into a 220px right
// column. Detect them so the editor can show a named-entity list (one item per
// row, add/remove) laid out full-width, and serialise back to the wire format
// the param arrived in (a real array, or a JSON-array string).
const LIST_NAME_RE = /(_list$|smiles|compounds?|molecules?|sequences?|inchi|accessions?)/i;
// Only a flat array of SCALARS is a list the one-item-per-row editor can show.
// An array of objects (e.g. antigens=[{id,sequence}]) must NOT be stringified
// into "[object Object]" rows — it falls through to the sample-data table below.
const isScalarArray = (a: any[]): boolean => a.every(x => x == null || typeof x !== 'object');
export function parseListParam(p: any): { items: string[]; fmt: 'array' | 'json' } | null {
  const raw = p?.value ?? p?.defaultValue;
  if (Array.isArray(raw)) return isScalarArray(raw) ? { items: raw.map((x: any) => String(x)), fmt: 'array' } : null;
  if (typeof raw === 'string') {
    const t = raw.trim();
    if (t.startsWith('[')) {
      try { const a = JSON.parse(t); if (Array.isArray(a) && isScalarArray(a)) return { items: a.map((x: any) => String(x)), fmt: 'json' }; } catch { /* not JSON */ }
    }
  }
  return null;
}

/**
 * Render a JSON-string param default (the "built-in sample data" an example
 * runs on) as a readable table instead of a raw blob in the textarea. Returns
 * null for anything that isn't tabular, so the plain editor still shows.
 *   • array of objects      → columns = union of keys, one row per element
 *   • object whose values   → one row per key, columns = union of inner keys
 *     are all objects          (first column is the outer key, e.g. sample id)
 *   • object of scalars/     → a two-column key / value table (non-scalar
 *     arrays                     values are shown as compact JSON)
 */
export function sampleDataTable(raw: string): { headers: string[]; rows: string[][] } | null {
  let data: any;
  try { data = JSON.parse(raw); } catch { return null; }
  const cell = (v: any): string => v == null ? '' : (typeof v === 'object' ? JSON.stringify(v) : String(v));
  const isPlainObj = (v: any) => v != null && typeof v === 'object' && !Array.isArray(v);
  if (Array.isArray(data) && data.length > 0 && data.every(isPlainObj)) {
    const headers = [...data.reduce((s: Set<string>, o: any) => { Object.keys(o).forEach(k => s.add(k)); return s; }, new Set<string>())];
    return { headers, rows: data.map((o: any) => headers.map(h => cell(o[h]))) };
  }
  if (isPlainObj(data)) {
    const entries = Object.entries(data);
    if (entries.length === 0) return null;
    if (entries.every(([, v]) => isPlainObj(v))) {
      const inner = [...entries.reduce((s: Set<string>, [, o]: any) => { Object.keys(o).forEach(k => s.add(k)); return s; }, new Set<string>())];
      return { headers: ['', ...inner], rows: entries.map(([k, o]: any) => [k, ...inner.map(h => cell(o[h]))]) };
    }
    return { headers: ['key', 'value'], rows: entries.map(([k, v]) => [k, cell(v)]) };
  }
  return null;
}
function isListParam(p: any): boolean {
  if (!p || p.type === 'boolean' || p.type === 'number' || p.type === 'file' || p.options) return false;
  if (parseListParam(p)) return true;
  const raw = p.value ?? p.defaultValue;
  const empty = raw == null || raw === '';
  return (p.type === 'list' || p.type === 'array' || LIST_NAME_RE.test(String(p.name || ''))) && (empty || Array.isArray(raw));
}
function serializeListParam(items: string[], fmt: 'array' | 'json'): any {
  return fmt === 'json' ? JSON.stringify(items) : items.slice();
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
  onOpenFullStepView,
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
  onPreviewFile: (file: any, step?: any) => void;
  onAdjustAndRerun: (step: any) => void;
  /** Open the full step-as-object view (StepDetail) for a given step. */
  onOpenFullStepView: (step: any) => void;
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
  const letter = group.letter;
  const dashIdx = label.indexOf('—');
  const phaseTitle = dashIdx > -1 ? label.slice(0, dashIdx).trim() : label;
  const phaseSub   = dashIdx > -1 ? label.slice(dashIdx + 1).trim() : '';

  const canRunPhase = !!activeRunId && !isGlobalExecutionActive && !isAutofixActive && !isPrereqBlocked && !executionBlockedReason;
  // Backend-sourced English labels (phase / step / parameter names) localized for
  // the zh UI via the cached label-translation service; identity elsewhere.
  const phaseTitleSrc = userFacingStepName(phaseSub || phaseTitle);
  const tl = useLocalizedLabels([
    phaseTitleSrc,
    ...steps.map((st: any) => userFacingStepName(st.name)),
    ...phaseRenderedParams.map((p: any) => String(p.label ?? '')),
  ]);

  return (
    <div className={`phase ${phaseStatus}${open ? ' open' : ''}`} data-testid={`phase-group-${group.key}`} data-status={phaseStatus}>
      {/* Phase header — always visible, click to toggle */}
      <div className="phase-head" onClick={() => setOpen(o => !o)} role="button" aria-expanded={open}>
        <span className="caret"><ChevronRight className="h-3.5 w-3.5" /></span>
        <div className="letter">{letter}</div>
        {/* The badge already carries the letter; the semantic name ("Input Download")
            is what a scientist scans for, so it is the title — "Phase A" beside an "A"
            badge was redundant scaffolding (founder phase-view review 2026-11-11). */}
        <div className="titles">
          <div className="title" title={label}>{tl(phaseTitleSrc)}</div>
        </div>
        {phaseStatus === 'running' && (
          <span className="chip run">
            <Loader2 className="h-2.5 w-2.5 animate-spin" style={{display:'inline-block'}}/>
            {tOr('panel.chip.running', 'RUNNING')}
          </span>
        )}
        {phaseStatus === 'completed' && <span className="chip ok">{tOr('panel.chip.done', 'DONE')}</span>}
        {phaseStatus === 'failed'    && <span className="chip err">{tOr('panel.chip.failed', 'FAILED')}</span>}
        {/* Before the workflow launches every phase is "not started" and cannot run on
            its own — saying so on each row (plus a disabled 运行) was pure noise. Show
            only the step count; status + per-phase run appear once a run exists. */}
        {phaseStatus === 'pending' && (
          <span className="progress-chip">
            {activeRunId ? <span>{tOr('panel.phase.not_started', 'Not started')} · </span> : null}
            {tOr('panel.phase.steps_count', '{{n}} step{{s}}', { n: steps.length, s: steps.length !== 1 ? 's' : '' })}
          </span>
        )}
        {(phaseStatus === 'running' || phaseStatus === 'completed') && (
          <span className="progress-chip">{completedCount}/{steps.length}</span>
        )}
        {/* Run Phase button — only once a run exists (it can never be used pre-launch). */}
        {!!activeRunId && !allDone && !anyRunning && (
          <button
            className="btn sm"
            disabled={!canRunPhase}
            onClick={(e) => { e.stopPropagation(); steps.forEach((s: any) => onRun(s)); }}
            data-testid={`button-run-phase-${group.key}`}
            title={canRunPhase ? tOr('panel.phase.run_all_tip', 'Run all steps in {{phase}}', { phase: phaseTitle }) : tOr('panel.phase.run_disabled_tip', 'Start the workflow first to enable phase-level execution')}
          >
            {tOr('panel.phase.run', 'Run')}
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
                <span style={{ fontSize: 'var(--fs-micro)', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                  {tOr('panel.parameters', 'Parameters')}
                  <span style={{ fontWeight: 400, marginLeft: 4, color: 'var(--text-dim)' }}>
                    ({phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).length > 0
                      ? tOr('panel.params_required_count', '{{n}} required', { n: phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).length })
                      : tOr('panel.params_configured_count', '{{n}} configured', { n: phaseRenderedParams.length })})
                  </span>
                </span>
                <button
                  className="linkish"
                  style={{ fontSize: 'var(--fs-xs)' }}
                  onClick={() => setPhaseParamsOpen(o => !o)}
                  data-testid={`phase-params-toggle-${group.key}`}
                >
                  {phaseParamsOpen ? tOr('panel.collapse', 'collapse') : tOr('panel.edit_action', 'edit')}
                </button>
              </div>
              {/* Compact summary row when collapsed */}
              {!phaseParamsOpen && (
                <div style={{ padding: '4px 14px 6px', fontSize: 'var(--fs-micro)', color: 'var(--text-muted)', lineHeight: 1.4 }}>
                  {phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).length > 0 ? (
                    <span style={{ color: 'var(--warn)' }}>
                      {tOr('panel.required_suffix', '{{labels}} — required', { labels: phaseRenderedParams.filter(p => p.required && (!p.value || p.value === '')).map(p => p.label).join(', ') })}
                    </span>
                  ) : (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                      {phaseRenderedParams.slice(0, 4).map(p => {
                        const shown = cleanParamValueForDisplay(p.value ?? p.defaultValue) || '—';
                        const isFile = /^[^\s/]+\.[A-Za-z0-9]{1,8}(?:\.gz)?$/.test(shown);
                        return (
                          <div key={p.id} style={{ display: 'grid', gridTemplateColumns: 'minmax(72px, max-content) 1fr', columnGap: 10, alignItems: 'center', minWidth: 0 }}>
                            <span style={{ color: 'var(--text-dim)' }}>{tl(String(p.label ?? ''))}</span>
                            {isFile ? (
                              <span className="mono" title={shown} style={{ justifySelf: 'start', maxWidth: '100%', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', padding: '1px 6px', borderRadius: 4, background: 'var(--surface)', border: '1px solid var(--border)', color: 'var(--text)', fontFamily: 'var(--font-mono)' }}>{shown}</span>
                            ) : (
                              <span style={{ color: 'var(--text)', overflowWrap: 'anywhere', minWidth: 0 }}>{shown}</span>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}
              {/* Full editable param list when expanded */}
              {phaseParamsOpen && (
                <div style={{ padding: '6px 14px 8px', display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {phaseRenderedParams.map(p => {
                    const missing = p.required && (!p.value || p.value === '');
                    const labelCol = missing ? 'var(--warn)' : 'var(--text-muted)';
                    const borderCol = missing ? 'var(--warn)' : 'var(--border)';
                    const label = <span className="k" style={{ fontSize: 'var(--fs-micro)', color: labelCol }}>{tl(String(p.label ?? ''))}{p.required ? ' *' : ''}</span>;

                    // Multi-value input of the same type (e.g. a multi-compound
                    // smiles_list) → a named-entity list editor, full-width: one
                    // item per row (mono, individually editable) with Add/Remove.
                    if (isListParam(p)) {
                      const info = parseListParam(p);
                      const items = info ? info.items : [];
                      const fmt: 'array' | 'json' = info ? info.fmt : 'array';
                      const commit = (next: string[]) => onParamChange(p.id, serializeListParam(next, fmt));
                      return (
                        <div key={p.id} className="param-row param-row--block" data-param={p.id} data-param-kind="list">
                          <span className="k" style={{ fontSize: 'var(--fs-micro)', color: labelCol }}>
                            {tl(String(p.label ?? ''))}{p.required ? ' *' : ''}
                            <span className="hint" style={{ marginLeft: 6, fontSize: 'var(--fs-xs)', color: 'var(--text-dim)' }}>
                              {items.length} {items.length === 1 ? tOr('panel.item', 'item') : tOr('panel.items', 'items')}
                            </span>
                          </span>
                          <div className="param-list" style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                            {items.map((it, i) => (
                              <div key={i} className="param-list-row" style={{ display: 'grid', gridTemplateColumns: '20px 1fr auto', gap: 6, alignItems: 'center' }}>
                                <span className="mono" style={{ fontSize: 'var(--fs-xs)', color: 'var(--text-dim)', textAlign: 'right' }}>{i + 1}</span>
                                <input
                                  className="v mono"
                                  value={it}
                                  spellCheck={false}
                                  placeholder={p.required ? tOr('panel.required', 'required') : ''}
                                  style={{ width: '100%', fontSize: 'var(--fs-micro)', padding: '3px 6px', background: 'var(--surface)', border: `1px solid ${borderCol}`, borderRadius: 4, color: 'var(--text)', fontFamily: 'var(--font-mono)' }}
                                  onChange={e => { const next = items.slice(); next[i] = e.target.value; commit(next); }}
                                />
                                <button type="button" className="btn ghost sm" title={tOr('panel.remove', 'Remove')} style={{ fontSize: 'var(--fs-micro)', padding: '1px 7px', lineHeight: 1 }} onClick={() => commit(items.filter((_, j) => j !== i))}>✕</button>
                              </div>
                            ))}
                            <button type="button" className="btn ghost sm" data-testid={`param-add-${p.id}`} style={{ alignSelf: 'flex-start', fontSize: 'var(--fs-micro)', padding: '2px 8px' }} onClick={() => commit([...items, ''])}>
                              + {tOr('panel.add_item', 'Add')}
                            </button>
                          </div>
                        </div>
                      );
                    }

                    // Long single value → full-width stacked field (not a 220px
                    // box crammed into the right column).
                    const strVal = String(p.value ?? p.defaultValue ?? '');
                    // A param bound to a STORED file (s3://, gs://, file://) is shown as
                    // its filename, read-only: the storage path is never user-facing and
                    // is not something to hand-edit. Change it by attaching another file
                    // or clearing it (founder no-S3 rule; phase-view review 2026-11-11).
                    if (/^(?:s3|gs|file):\/\//i.test(strVal.trim())) {
                      const fname = cleanParamValueForDisplay(strVal) || strVal.replace(/\/+$/, '').split('/').pop() || '';
                      return (
                        <div key={p.id} className="param-row" data-param={p.id} data-param-kind="stored-file" style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 8, alignItems: 'center' }}>
                          {label}
                          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
                            <span className="mono" title={fname} data-testid={`param-file-${p.id}`}
                              style={{ maxWidth: 180, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', padding: '1px 6px', borderRadius: 4, background: 'var(--surface)', border: '1px solid var(--border)', color: 'var(--text)', fontFamily: 'var(--font-mono)', fontSize: 'var(--fs-micro)' }}>
                              {fname || tOr('panel.staged_file', 'staged file')}
                            </span>
                            <button type="button" className="linkish" style={{ fontSize: 'var(--fs-xs)' }}
                              onClick={() => onParamChange(p.id, '')} data-testid={`param-file-clear-${p.id}`}>
                              {tOr('panel.clear', 'clear')}
                            </button>
                          </span>
                        </div>
                      );
                    }
                    const isLong = p.type !== 'number' && p.type !== 'file' && p.type !== 'boolean' && !p.options &&
                      (strVal.length > 40 || strVal.trimStart().startsWith('{'));
                    if (isLong) {
                      const sample = sampleDataTable(strVal);
                      return (
                        <div key={p.id} className="param-row param-row--block" data-param={p.id} data-param-kind="long">
                          {label}
                          {sample && (
                            <details data-testid={`param-sample-preview-${p.id}`} style={{ marginTop: 4 }}>
                              <summary style={{ cursor: 'pointer', fontSize: 'var(--fs-micro)', color: 'var(--text-muted)', userSelect: 'none' }}>
                                {tOr('panel.view_sample_data', 'View sample data')}
                                <span style={{ marginLeft: 6, color: 'var(--text-dim)' }}>
                                  {tOr('panel.rows_count', '{{n}} rows', { n: sample.rows.length })}
                                </span>
                              </summary>
                              <div style={{ overflowX: 'auto', marginTop: 4, border: '1px solid var(--border)', borderRadius: 4 }}>
                                <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: 'var(--fs-micro)', fontFamily: 'var(--font-mono)' }}>
                                  <thead>
                                    <tr>{sample.headers.map((h, i) => (
                                      <th key={i} style={{ textAlign: 'left', padding: '3px 8px', borderBottom: '1px solid var(--border)', color: 'var(--text-muted)', fontWeight: 600, whiteSpace: 'nowrap', position: 'sticky', top: 0, background: 'var(--surface)' }}>{h}</th>
                                    ))}</tr>
                                  </thead>
                                  <tbody>{sample.rows.slice(0, 50).map((r, ri) => (
                                    <tr key={ri}>{r.map((c, ci) => (
                                      <td key={ci} style={{ padding: '3px 8px', borderBottom: '1px solid var(--border-subtle, var(--border))', color: 'var(--text)', maxWidth: 320, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={c}>{c}</td>
                                    ))}</tr>
                                  ))}</tbody>
                                </table>
                              </div>
                              {sample.rows.length > 50 && (
                                <div style={{ fontSize: 'var(--fs-micro)', color: 'var(--text-dim)', padding: '3px 8px' }}>
                                  {tOr('panel.rows_truncated', 'Showing first 50 of {{n}} rows', { n: sample.rows.length })}
                                </div>
                              )}
                            </details>
                          )}
                          <textarea
                            className="v"
                            value={strVal}
                            placeholder={p.required ? tOr('panel.required', 'required') : ''}
                            rows={Math.min(6, Math.max(2, Math.ceil(strVal.length / 60)))}
                            spellCheck={false}
                            style={{ marginTop: 4, width: '100%', fontSize: 'var(--fs-micro)', padding: '4px 6px', background: 'var(--surface)', border: `1px solid ${borderCol}`, borderRadius: 4, color: 'var(--text)', fontFamily: 'var(--font-mono)', resize: 'vertical', lineHeight: 1.4 }}
                            onChange={e => onParamChange(p.id, e.target.value)}
                          />
                        </div>
                      );
                    }

                    // A file/input param holds a storage path or dataset key as
                    // its value — never show that to the user (incl. in the
                    // editor or on hover). Render the clean file name read-only;
                    // files are bound via attach/browse, not hand-typed here.
                    if (p.type === 'file') {
                      const shown = strVal ? (strVal.split('/').pop() || '') : '';
                      return (
                        <div key={p.id} className="param-row" data-param={p.id} data-param-kind="file" style={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: 8, alignItems: 'center' }}>
                          {label}
                          <span style={{ fontSize: 'var(--fs-micro)', color: shown ? 'var(--text)' : 'var(--text-dim)', fontFamily: 'var(--font-mono)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 160, textAlign: 'right' }}>
                            {shown || (missing ? tOr('panel.required', 'required') : tOr('panel.not_set', 'not set'))}
                          </span>
                        </div>
                      );
                    }

                    // Default inline row: label · editor.
                    return (
                      <div key={p.id} className="param-row" data-param={p.id} style={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: 8, alignItems: 'center' }}>
                        {label}
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
                            style={{ fontSize: 'var(--fs-micro)', padding: '2px 4px', background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 3, color: 'var(--text)' }}
                            onChange={e => onParamChange(p.id, e.target.value)}
                          >
                            {p.options.map((o: any) => {
                              const val = o !== null && typeof o === 'object' ? String(o.value ?? '') : String(o);
                              const lbl = o !== null && typeof o === 'object' ? String(o.label ?? o.value ?? '') : String(o);
                              return <option key={val} value={val}>{lbl}</option>;
                            })}
                          </select>
                        ) : (
                          <input
                            type={p.type === 'number' ? 'number' : 'text'}
                            className="v"
                            value={strVal}
                            placeholder={p.required ? tOr('panel.required', 'required') : ''}
                            style={{ fontSize: 'var(--fs-micro)', padding: '2px 6px', width: 140, background: 'var(--surface)', border: `1px solid ${borderCol}`, borderRadius: 3, color: 'var(--text)', fontFamily: p.type === 'file' ? 'var(--font-mono)' : undefined }}
                            onChange={e => onParamChange(p.id, e.target.value)}
                          />
                        )}
                      </div>
                    );
                  })}
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
                className={`step ${stepStatus}${steps.length === 1 ? ' solo' : ''}`}
                data-testid={`phase-card-${step.id}`}
                data-status={s}
              >
                <div className="step-head">
                  {/* One indicator per step: the status dot on the rail. The circled
                      ordinal (①) duplicated it (founder phase-view review 2026-11-11). */}
                  <div className={`name${isFailed ? ' dim' : ''}`}>
                    {tl(userFacingStepName(step.name))}
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
                        style={{ marginLeft: 6, fontSize: 'var(--fs-xs)', fontWeight: 600, padding: '1px 5px', borderRadius: 4, background: 'oklch(0.95 0.06 80)', color: 'oklch(0.45 0.15 70)' }}
                      >
                        ⚠ {head.metric}{more > 0 ? ` +${more}` : ''}
                      </span>
                    );
                  })()}
                  {isRunning && <span className="chip run" style={{marginLeft:'auto'}}><Loader2 className="h-2.5 w-2.5 animate-spin" style={{display:'inline-block'}}/>{tOr('panel.chip.running', 'RUNNING')}</span>}
                  {isDone    && <span className="chip ok"  style={{marginLeft:'auto'}}>{tOr('panel.chip.done', 'DONE')}</span>}
                  {isFailed  && <span className="chip err" style={{marginLeft:'auto'}}>{tOr('panel.chip.failed', 'FAILED')}</span>}
                  <div className="actions">
                    <button
                        className="btn ghost sm"
                        onClick={(e) => { e.stopPropagation(); onOpenFullStepView(step); }}
                        data-testid={`button-full-step-view-${step.id}`}
                        title={tOr('panel.step.details_tip', 'Open full step view — provenance, resolved parameters, rendered ⇄ raw outputs')}
                      >{tOr('panel.step.details', 'Details')}</button>
                    {(isDone || isFailed) && (
                      <button
                        className="btn ghost sm"
                        onClick={(e) => { e.stopPropagation(); onRun(step); }}
                        data-testid={`button-run-step-${step.id}`}
                      >{tOr('panel.step.rerun', 'Rerun')}</button>
                    )}
                    {/* "Params" (adjust-and-rerun) step button DISABLED 2026-11-12
                        (founder): the StepAdjustModal popup it opens is wrong — it
                        surfaces in the wrong context with the wrong params. Hidden
                        via `false &&` until that popup is redesigned. */}
                    {false && !isRunning && !isDone && step.parameters && Object.keys(step.parameters).length > 0 && (
                      <button
                        className="btn ghost sm"
                        onClick={(e) => { e.stopPropagation(); onAdjustAndRerun(step); }}
                        data-testid={`button-adjust-step-${step.id}`}
                      >{tOr('panel.step.params', 'Params')}</button>
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

                {/* Param meta (first 3 params with non-null values inline, non-running non-done) */}
                {!isRunning && !isDone && step.parameters && (() => {
                  const visible = Object.entries(step.parameters as Record<string,unknown>)
                    // Skip metadata-object placeholders ({type,label,default}) — those
                    // params render (with real values) in the phase's params section;
                    // the inline step-meta is for scalar runtime values only, so an
                    // object here would stringify to "[object Object]".
                    .filter(([,v]) => v !== null && v !== undefined && v !== '' && typeof v !== 'object')
                    // Already shown in the phase's parameter block above — repeating
                    // it on the step row was duplicate noise.
                    .filter(([k]) => !phaseRenderedParams.some((p: any) => (p.id || p.name) === k));
                  if (visible.length === 0) return null;
                  return (
                    <div className="step-meta">
                      {visible.slice(0,3).map(([k,v]) => (
                        <span key={k}><span style={{opacity:0.6}}>{k}:</span> {cleanParamValueForDisplay(v) || '—'}</span>
                      ))}
                    </div>
                  );
                })()}

                {/* Output files */}
                {hasOutputs && (
                  <div className="step-outputs">
                    {(step.outputFiles as any[]).slice(0,4).map((f: any, fi: number) => (
                      <span className="output-file" key={fi}>
                        <span className="fn" title={f.name}>{f.name}</span>
                        <span
                          className="act"
                          onClick={() => onPreviewFile(f, step)}
                          data-testid={`phase-card-preview-btn-${f.name}`}
                        >{tOr('panel.file.view', 'view')}</span>
                        {activeRunId && (
                          <a
                            className="act"
                            href={`/api/workflows/runs/${encodeURIComponent(activeRunId)}/step-file?path=${encodeURIComponent(f.path)}&download=1`}
                            data-testid={`phase-card-download-btn-${f.name}`}
                          >{tOr('panel.file.download_short', 'dl')}</a>
                        )}
                      </span>
                    ))}
                    {step.outputFiles.length > 4 && (
                      <span className="output-file">
                        <span className="fn">{tOr('panel.file.more_count', '+{{n}} more', { n: step.outputFiles.length - 4 })}</span>
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
                <span>{tOr('panel.qc_gates', 'QC Gates')}</span>
                <button
                  className="linkish"
                  style={{ fontSize: 'var(--fs-xs)' }}
                  onClick={() => setQcEditorOpen(o => !o)}
                  data-testid={`qc-edit-toggle-${group.key}`}
                >
                  {qcEditorOpen ? tOr('panel.done_action', 'done') : tOr('panel.edit_action', 'edit')}
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
                      style={{ width: 60, textAlign: 'right', fontSize: 'var(--fs-micro)',
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
                      style={{ fontSize: 'var(--fs-xs)', color: 'var(--warn)' }}
                      title={tOr('panel.reset_to_default', 'Reset to default')}
                      onClick={() => onQcChange(t.key, null)}
                    >×</button>
                  )}
                </div>
              ))}
              {/* Self-correct toggle — WORKFLOW-CONDITIONED: shown only for autoloop-ready
                  workflows (the few drug-dev profiles with a ready design→make→test loop,
                  per the QC profile's `autoloop` flag). Hidden for the many gate-only
                  workflows. Opt-in, default OFF. */}
              {!autoloopLocked && (
              <div className="qc-autoloop">
                <span
                  className={`switch${autoloopEnabled ? ' on' : ''}`}
                  onClick={onToggleAutoloop}
                  role="switch"
                  aria-checked={autoloopEnabled}
                  data-testid={`autoloop-toggle-${group.key}`}
                />
                <span
                  title={"When ON: if a quality check fails, BioMate adjusts parameters and retries the phase automatically (up to 3 times). When OFF: a review card appears so you can approve or reject the suggested fix before continuing."}
                >
                  Self-correct on QC failure <span style={{fontFamily:'var(--font-mono)', color:'var(--text-dim)'}}>(max 3×)</span>
                </span>
              </div>
              )}
            </div>
          )}

          {/* AutoLoopPanel — renders the QC gate table + remediation card when the
              auto-loop gate fires (autoloop_gate_results SSE). Re-enabled once the QC
              loop was made to fire live end-to-end (executor SSE emit + experiments/ deploy). */}
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
                {tOr('panel.stop_phase', 'Stop phase')}
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
                style={{fontSize: 'var(--fs-meta)'}}
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

function sanitizeErrorText(msg: string): string {
  if (!msg) return msg;
  // Shared with the after-run report: no storage paths, upload ids or infrastructure names.
  return userFacingErrorText(msg).replace(/\bnextflow\b/gi, 'the pipeline');
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
  wasCancelled = false,
  errorMessage,
  progress = 0,
  onParameterChange,
  sessionId,
  runId,
  targetAfterRunTab,
  autofix,
  nextflowStatus,
  executionEngine,
  onAdjustViaChat,
  onWorkflowProgress,
  executionMetrics,
  onResize,
  onClose,
  onToggleExpand,
  expanded,
  projectName,
  projectId: projectIdProp,
  onAutoReroute,
  onRerunStarted,
}: NextflowWorkflowViewerProps) {
  const [, navigate] = useLocation();
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

  // C1 — a chat answer deep-link ("Full table in Summary", "Files in Outputs")
  // sets targetAfterRunTab; jump to the After-run tab (the sub-tab is selected
  // inside AfterRunReport via its targetTab prop, below).
  useEffect(() => {
    if (!targetAfterRunTab) return;
    setActiveTab('after-run');
    setTabAutoDefault(false);
  }, [targetAfterRunTab]);

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
  // The step that owns the currently-previewed file (if known), so the inline
  // preview can offer an "open full step view" affordance for the right step.
  const [previewStep, setPreviewStep] = useState<any | null>(null);
  const [adjustStep, setAdjustStep] = useState<{ id: string; name: string; processName?: string; parameters?: Record<string, any> } | null>(null);
  // Full step view (spec-08 step-as-object surface). Holds the mapped
  // StepDetailStep for the step the user chose to open; null → dialog closed.
  const [fullViewStep, setFullViewStep] = useState<StepDetailStep | null>(null);
  // When user reruns from a step, track the new runId so the viewer polls the right run
  const [rerunRunId, setRerunRunId] = useState<string | null>(null);
  const activeRunId = rerunRunId ?? runId;
  // Guard against concurrent /rerun calls (phase Run + footer Resume can both be visible)
  const [rerunInProgress, setRerunInProgress] = useState(false);

  // QC governance settings
  const [qcSettingsOpen, setQcSettingsOpen] = useState(false);
  const [pauseAtQcFailures, setPauseAtQcFailures] = useState(true);
  const [qcProfile, setQcProfile] = useState('');
  // Output storage follows the chat's project automatically.
  const projectId = projectIdProp ?? (workflowDefinition as any)?.projectId ?? null;
  const [availableQcProfiles, setAvailableQcProfiles] = useState<Array<{ id: string; description: string; domain_hint: string; overrides: Record<string, number>; autoloop?: boolean }>>([]);
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
    if (!hasSteps && nfPath && !recordedProcessPhases(nextflowStatus?.processes).length) {
      setLazyStepsFetching(true);
      fetch(`/api/nextflow/steps?nextflow_path=${encodeURIComponent(nfPath)}`)
        .then(r => r.ok ? r.json() : null)
        .then(data => { setLazySteps(data?.steps ?? {}); })
        .catch(() => { setLazySteps({}); })
        .finally(() => setLazyStepsFetching(false));
    }
  }, [workflowDefinition, nextflowStatus?.processes]);

  // Per-phase declared-skip + DAG-dependency analysis (spec 02 §2.5.1). Feeds the
  // SkipDependency panel with real skippable/param/blocks/warn state derived from
  // the workflow's declared skip params + channel wiring. null until fetched.
  const [skipAnalysis, setSkipAnalysis] = useState<PhaseSkipInfo[] | null>(null);
  useEffect(() => {
    const nfPath = workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath;
    if (!nfPath) { setSkipAnalysis(null); return; }
    let cancelled = false;
    fetch(`/api/nextflow/skip-analysis?nextflow_path=${encodeURIComponent(nfPath)}`)
      .then(r => r.ok ? r.json() : null)
      .then(data => { if (!cancelled) setSkipAnalysis(Array.isArray(data?.phases) ? data.phases : null); })
      .catch(() => { if (!cancelled) setSkipAnalysis(null); });
    return () => { cancelled = true; };
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

  // ── Live run-progress (Gap 3/4) ──────────────────────────────────────────
  // While a run is active, poll the aggregate AI status endpoint (issues +
  // autofix state) and surface overall progress / current step / elapsed time /
  // a collapsible logs+autofix section at the top of the Phases tab.
  const runActive = status === 'running' || status === 'paused';
  const realtimeStatus = useRealtimeRunStatus(invocationId, runActive);
  const [progressDetailsOpen, setProgressDetailsOpen] = useState(false);
  // Elapsed-time clock — ticks every 1s while active; frozen otherwise.
  const runStartRef = useRef<number | null>(null);
  const [nowTick, setNowTick] = useState<number>(() => Date.now());
  useEffect(() => {
    if (!runActive) {
      runStartRef.current = null;
      return;
    }
    if (runStartRef.current == null) {
      const nfStart = typeof nextflowStatus?.started_at === 'number'
        ? nextflowStatus.started_at * 1000
        : null;
      runStartRef.current = nfStart ?? Date.now();
    }
    setNowTick(Date.now());
    const id = setInterval(() => setNowTick(Date.now()), 1000);
    return () => clearInterval(id);
  }, [runActive, nextflowStatus?.started_at]);


  const [stepExecutionById, setStepExecutionById] = useState<Record<string, StepExecutionState>>({});
  const [skippedPhaseIds, setSkippedPhaseIds] = useState<Set<string>>(new Set());
  const [confirmSkipPhaseId, setConfirmSkipPhaseId] = useState<string | null>(null);
  const stepPollersRef = React.useRef<Record<string, ReturnType<typeof setInterval>>>({});

  // QC gate inline panel state (SSE-triggered)
  const [showQcInline, setShowQcInline] = useState(false);
  const qcExecutionStatusRef = useRef(status);
  qcExecutionStatusRef.current = status;
  useEffect(() => {
    if (status !== "running" && status !== "paused") {
      setShowQcInline(false);
      setQcGateHalt(false);
      setQcGateSecondsLeft(null);
    }
  }, [status]);
  const [qcGateData, setQCGateData] = useState<QCGateData | null>(null);
  // Gap 1 (inverse) — near-threshold QC advisories keyed by process_name.
  // The narrator already emits a chat line via workflow.qc_gate_warning; here
  // we surface the same information in the panel so the user sees the
  // annotation on the step card. Backend emit site:
  // backend/lib/galaxy/jobs/qc_trace_monitor.py:5744.
  const [qcAdvisoryByStep, setQcAdvisoryByStep] = useState<Record<string, { metric?: string; value?: any; threshold?: any }[]>>({});
  const [qcGateSecondsLeft, setQcGateSecondsLeft] = useState<number | null>(null);
  // Safety HALT gate: a blocking (non-advisory) QC gate PAUSES the run and waits
  // for the user — Resume or Cancel, no 10s auto-proceed. Gated by pauseAtQcFailures.
  // Ref mirrors the state so the long-lived SSE listener sees the current value.
  const [qcGateHalt, setQcGateHalt] = useState(false);
  const pauseAtQcFailuresRef = React.useRef(pauseAtQcFailures);
  React.useEffect(() => { pauseAtQcFailuresRef.current = pauseAtQcFailures; }, [pauseAtQcFailures]);
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
    regulatoryActions: [],
    complete: null,
  });
  // Layer-2 AI diagnosis (emitted when no auto-reroute alternative is available)
  const [aiDiagnosis, setAiDiagnosis] = useState<{
    category: string; user_message: string; suggested_action: string; fix_strategy: string;
    is_transient: boolean; task_error_snippet?: string;
  } | null>(null);
  // Container pull progress: shown when backend is downloading a missing image before run.
  const [containerPullStatus, setContainerPullStatus] = useState<{
    image: string; status: 'pulling' | 'ready' | 'failed'; message: string;
  } | null>(null);
  // Auto-resume countdown state: triggered by backend `auto_resuming` SSE for infra_transient failures.
  // autoResumeDelay is set once per SSE event (triggers the useEffect); autoResumeCountdown is the
  // display value, ticked down by the interval inside the effect.
  const [autoResumeDelay, setAutoResumeDelay] = useState<number | null>(null);
  const [autoResumeCountdown, setAutoResumeCountdown] = useState<number | null>(null);
  const autoResumeCancelledRef = React.useRef(false);
  // Per-phase auto-loop toggle. An ABSENT key = follow the QC profile's own default
  // (autoloop:true profiles close the loop by default); an explicit true/false is a
  // user override that always wins. See profileAutoloopDefault below.
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
    const recorded = recordedProcessPhases(nextflowStatus?.processes);
    // Prefer stored steps; fall back to lazily-fetched steps for old sessions
    const stepsSource = (
      workflowDefinition?.steps && typeof workflowDefinition.steps === "object" && Object.keys(workflowDefinition.steps).length > 0
        ? workflowDefinition.steps
        : lazySteps ?? {}
    );
    const planned: ViewerPhase[] = Object.keys(stepsSource).length > 0
      ? Object.entries(stepsSource).map(([stepKey, rawStep], index) => {
          const step = (rawStep || {}) as Record<string, unknown>;
          return {
            id: String(step.id || stepKey || `step-${index}`),
            name: String(step.name || step.label || step.tool_id || `Step ${index + 1}`),
            status: "pending" as ViewerPhaseStatus,
            description: String(step.annotation || step.description || ""),
            toolId: typeof step.tool_id === "string" ? step.tool_id : undefined,
            parameters: step.parameters && typeof step.parameters === "object" ? (step.parameters as Record<string, unknown>) : {},
            inputs: step.inputs && typeof step.inputs === "object" ? (step.inputs as Record<string, unknown>) : {},
            summary: typeof step.summary === "string" ? step.summary : undefined,
            autoloop: typeof step.autoloop === "boolean" ? step.autoloop : undefined,
            phase_group: typeof step.phase_group === "string" && step.phase_group ? step.phase_group : undefined,
            phase_label: typeof step.phase_label === "string" && step.phase_label ? step.phase_label : undefined,
          };
        })
      : [];
    // Keep the full planned phase list visible while reflecting real runtime status
    // on the phases that ran — so a stopped/paused run no longer drops its
    // not-yet-started phases (founder: "I stopped the first phase and the rest all
    // disappeared"). Redesigned 2026-11-12 with real nf-core matching tests;
    // supersedes the 2026-11-12 revert. See mergePlannedWithRecorded.
    return mergePlannedWithRecorded(planned, recorded);
  }, [workflowDefinition, lazySteps, nextflowStatus?.processes]);

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
    if (!activeRunId || rerunInProgress) return;

    setRerunInProgress(true);
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
      // Restart parent polling — it stopped when status hit 'failed'.
      onRerunStarted?.(newRunId || activeRunId);
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
    } finally {
      setRerunInProgress(false);
    }
  }, [activeRunId, invocationId, workflowId, rerunInProgress, onRerunStarted]);

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
    const addKey = (raw: any, proc: any) => {
      if (!raw) return;
      const s = String(raw).toLowerCase();
      map[s] = proc;
      // audit S4#4: nf-core emits fully-qualified process names
      // (NFCORE_RNASEQ:RNASEQ:FASTQC) while phases are keyed by the short name (fastqc).
      // Also index the trailing segment so phase.id/phase.name lookups match — otherwise
      // procStatus is null and the live pills fall back to a workflow-%% heuristic that
      // cannot show per-phase running state. Additive + non-clobbering (exact names win).
      const tail = s.split(':').pop();
      if (tail && tail !== s && !(tail in map)) map[tail] = proc;
    };
    for (const proc of procs) {
      addKey(proc?.name, proc);
      addKey(proc?.process, proc);
      addKey(proc?.id, proc);
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
          : rawProcStatus.includes('complet') || rawProcStatus === 'succeeded' || rawProcStatus === 'ok' || rawProcStatus === 'cached'
            ? 'completed'
            : null;
    if (procStatus) {
      derivedStatus = procStatus;
    } else if (nfProcLookup) {
      // A real task record with an unreported/pending state is not evidence
      // that it completed merely because the whole run is terminal.
      derivedStatus = phase.status;
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
    const rawFiles = nfProc
      ? [...(Array.isArray(nfProc.task_files) ? nfProc.task_files : Array.isArray(nfProc.taskFiles) ? nfProc.taskFiles : []), ...(Array.isArray(nfProc.outputs) ? nfProc.outputs : [])]
      : (phase.outputFiles || []);
    const outputFiles = Array.from(new Map((Array.isArray(rawFiles) ? rawFiles : []).flatMap((file: any) => {
      const path = typeof file === 'string' ? file : typeof file?.path === 'string' ? file.path : typeof file?.s3_uri === 'string' ? file.s3_uri : null;
      if (!path) return [];
      const name = typeof file?.name === 'string' ? file.name : path.split('/').pop() || path;
      return [[path, { name, path, extension: name.split('.').pop() || '', ...(typeof file?.size === 'number' ? { size: file.size } : {}) }] as const];
    })).values());

    const stepExecution = stepExecutionById[phase.id];
    if (!stepExecution) {
      return { ...phase, ...reportedStepDetails(nfProc), status: derivedStatus, outputFiles };
    }

    return {
      ...phase,
      ...reportedStepDetails(nfProc),
      status: stepExecution.phaseStatus,
      backendState: stepExecution.backendState,
      jobId: stepExecution.jobId ?? reportedStepDetails(nfProc).jobId,
      startedAt: stepExecution.startedAt,
      lastRunAt: stepExecution.lastRunAt,
      runCount: stepExecution.runCount,
      outputsCount: stepExecution.outputsCount,
      errorMessage: stepExecution.errorMessage ?? reportedStepDetails(nfProc).errorMessage,
      isExecuting: stepExecution.isExecuting,
      outputFiles,
    };
  });

  // Group updatedPhases by their phase_group field (A/B/C/D/E for cryo-EM, etc.)
  const groupedPhases = React.useMemo<PhaseGroup[]>(
    // No steps loaded yet → [] so the empty-state message renders instead of a
    // phantom phase card with "0 steps".
    () => groupStepsIntoPhases(updatedPhases as any[], tOr('panel.phase.all_steps', 'Steps')),
    [updatedPhases],
  );

  // QC: derive display thresholds from defaults + auto-detected profile + user edits
  const activeQcProfile = React.useMemo(
    () => availableQcProfiles.find(p => p.id === qcProfile) ?? null,
    [availableQcProfiles, qcProfile]
  );
  // A QC profile that DECLARES autoloop:true is opting into auto-remediation, so
  // the closed loop runs by default for it (no hidden manual toggle). A ref mirrors
  // it so the SSE gate handler reads the default synchronously. Non-autoloop
  // profiles stay paused-for-human; an explicit user toggle always wins.
  const profileAutoloopDefault = activeQcProfile?.autoloop === true;
  const profileAutoloopDefaultRef = React.useRef(profileAutoloopDefault);
  React.useEffect(() => { profileAutoloopDefaultRef.current = profileAutoloopDefault; }, [profileAutoloopDefault]);
  const displayedQcThresholds = React.useMemo(() => {
    const merged: Record<string, { bound: number; direction: string; rationale?: string; source: 'default' | 'profile' | 'user' }> = {};
    const wfDomain = qcWorkflowDomain(workflowDefinition, activeQcProfile);
    const countMatrixOnly = isCountMatrixDeWorkflow(workflowDefinition);
    Object.entries(qcDefaults).forEach(([k, meta]) => {
      // Skip domain-specific metrics that don't apply to this workflow
      const allowedDomains = (meta as any).domains as string[] | undefined;
      if (allowedDomains && !allowedDomains.includes(wfDomain)) return;
      // Count-matrix differential-expression workflows (differentialabundance,
      // DESeq2/limma/edgeR) consume a count matrix, not raw reads — they do no
      // alignment/trimming, so the sequencing-alignment QC family doesn't apply
      // even though their transcriptomics domain aliases to rnaseq. Drop just
      // those metrics; real sequencing workflows keep them.
      if (countMatrixOnly && ALIGNMENT_QC_METRICS.has(k)) return;
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
  }, [qcDefaults, activeQcProfile, qcOverrides, workflowDefinition]);

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
    // Defense in depth — button disabled state can race the license fetch;
    // never start/restart a BYOL workflow without a resolved credential.
    if (isLicenseBlocked) {
      setActiveTab('settings');
      return;
    }
    // Seed from structured param rows so display-bound values (required_params[].value
    // shown as "mapped" in the Inputs card) cannot be missing from the execute
    // payload (2026-11-13 DE samplesheet symptom).
    const fromStructured: Record<string, any> = {};
    for (const p of [
      ...(Array.isArray(workflowDefinition?.required_params) ? workflowDefinition.required_params : []),
      ...(Array.isArray(workflowDefinition?.optional_params) ? workflowDefinition.optional_params : []),
    ]) {
      const n = p?.name;
      if (!n) continue;
      const v = p.value !== undefined && p.value !== null && p.value !== '' ? p.value : p.default;
      if (v !== undefined && v !== null && v !== '') fromStructured[n] = v;
    }
    emitUxEvent('workflow.run_clicked', { workflowId, invocationId });
    if (onExecute) {
      onExecute({
        ...fromStructured,
        ...params,
        __qcConfig: {
          pauseAtQcFailures,
          ...(qcProfile && { qcProfile }),
          ...(Object.keys(qcOverrides).length > 0 && { qcOverrides }),
        },
        ...(projectId ? { __outputLocation: { type: 'project', projectId } } : {}),
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

  // Fix B (#5): resume a FAILED run from its last cached step via the same
  // /rerun (-resume) path QC remediation uses. The backend resume is status-
  // agnostic (reconstructs -w <prev_work_dir> from the run id), so a failed
  // run reuses its cached completed steps and only re-runs the failed one.
  const _failure = (nextflowStatus as any)?.failure as
    { user_message?: string; is_transient?: boolean; suggested_action?: string;
      category?: string; task_error_snippet?: string } | undefined;
  // Resume only makes sense when at least one step actually completed — the resume
  // path reconstructs -w <prev_work_dir> and reuses cached completed steps. A LAUNCH
  // failure (bad work dir, invalid config, missing inputs — 0 steps ran) has nothing
  // to resume from, and reusing the same work dir would just fail again. In that case
  // the footer shows "Restart", not "Resume from last step".
  const anyStepCompleted = updatedPhases.some((p: any) => String(p?.status).toLowerCase() === 'completed');
  const canResumeFailed = status === 'failed' && !wasCancelled && !!activeRunId && !!_failure
    && ['resume', 'resume_more_resources', 'fix_and_resume'].includes(_failure.suggested_action || '')
    && anyStepCompleted;
  // The diagnosis card below is the ONE place a failed run's cause is stated; the
  // embedded AfterRunReport then shows only the failed steps + log tail.
  const showsFailureDiagnosis = status === 'failed' && !wasCancelled
    && !!(aiDiagnosis?.user_message || _failure?.user_message);
  const handleResumeFromFailed = async () => {
    if (!activeRunId || rerunInProgress) return;
    setRerunInProgress(true);
    // Immediately switch to phases and lock the tab — don't wait for the API.
    setActiveTab('phases');
    setTabAutoDefault(false);
    try {
      // The Node rerun contract forwards params as ResumeRunRequest.parameters.
      // Nextflow reuses task caches only when the current inputs/parameters match.
      const resp = await fetch(`/api/workflows/runs/${encodeURIComponent(activeRunId)}/rerun`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ params }),
      });
      const data = await resp.json().catch(() => ({}));
      const newRunId: string | undefined = data?.run_id ?? data?.runId;
      if (resp.ok) {
        if (newRunId) setRerunRunId(newRunId);
        // Tell the parent to restart status polling — useUnifiedExecution stops
        // polling on terminal states; loadRun (forcePolling:true) re-enables it
        // immediately without waiting for DB to flip to 'running'.
        onRerunStarted?.(newRunId || activeRunId);
      } else {
        console.warn('[NFViewer] resume-from-failed API error:', data?.error || resp.status);
        toast({ title: 'Resume failed', description: data?.error || `Server error ${resp.status}`, variant: 'destructive' });
      }
    } catch (e) {
      console.error('[NFViewer] resume-from-failed network error:', e);
      toast({ title: 'Resume failed', description: 'Network error — please try again.', variant: 'destructive' });
    } finally {
      setRerunInProgress(false);
    }
  };

  // Countdown effect: keyed on autoResumeDelay (set once per SSE event) so the interval
  // starts exactly once per auto-resuming signal, regardless of countdown tick updates.
  const handleResumeFromFailedRef = React.useRef(handleResumeFromFailed);
  handleResumeFromFailedRef.current = handleResumeFromFailed;
  React.useEffect(() => {
    if (autoResumeDelay === null) return;
    let remaining = autoResumeDelay;
    const timer = setInterval(() => {
      remaining -= 1;
      setAutoResumeCountdown(remaining);
      if (remaining <= 0) {
        clearInterval(timer);
        setAutoResumeCountdown(null);
        setAutoResumeDelay(null);
        if (!autoResumeCancelledRef.current) {
          handleResumeFromFailedRef.current();
        }
      }
    }, 1000);
    return () => clearInterval(timer);
  // autoResumeDelay is set to a fresh value each time the SSE event fires.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoResumeDelay]);

  const dismissQcGate = React.useCallback((reason: 'user' | 'timeout') => {
    if (qcGateTimerRef.current) { clearInterval(qcGateTimerRef.current); qcGateTimerRef.current = null; }
    setShowQcInline(false);
    setQCGateData(null);
    setQcGateSecondsLeft(null);
    setQcGateHalt(false);
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
    if (qcGateHalt) { setQcGateSecondsLeft(null); return; } // halt gate: no auto-proceed countdown
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
  }, [showQcInline, qcGateHalt, dismissQcGate]);

  const handleProceedAnyway = () => dismissQcGate('user');

  // Safety HALT gate: the run was paused; the user explicitly Resumes (continue
  // from cached steps via the existing /resume) or Cancels. No auto-proceed.
  const handleResumeAfterHalt = () => {
    if (activeRunId) {
      fetch(`/api/workflows/runs/${encodeURIComponent(activeRunId)}/resume`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, credentials: 'include', body: '{}',
      }).catch(err => console.error("[QC Gate NFViewer] Halt-resume failed:", err));
    }
    setShowQcInline(false);
    setQCGateData(null);
    setQcGateHalt(false);
  };

  const handleCancelWorkflow = () => {
    console.log("[QC Gate NFViewer] User cancelled workflow due to QC failures");
    setShowQcInline(false);
    setQCGateData(null);
    setQcGateHalt(false);
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
    const withHints = Object.keys(toolHintMap).length === 0 ? base : base.map((p: any) => {
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
    // §7.4 param-origin: mark user-edited params so the "Edited" badge renders. The data
    // comes from the existing userOverriddenParams ref (populated in handleParamChange on
    // every edit). params changes on each edit → this memo recomputes and reads the ref
    // fresh. Display-only + additive, so it cannot affect the edit/run flow. (Only
    // `overridden`/Edited is wired; `inherited` stays unset until the backend flags
    // project-sourced values — showing it now would be guessing.)
    return withHints.map((p: any) =>
      userOverriddenParams.current.has(p.id || p.name) ? { ...p, overridden: true } : p);
  }, [workflowDefinition, params, toolHintMap]);
  // Backend-sourced parameter / data-input labels ("Samplesheet", "Matrix") for the
  // settings-tab input rows, localized for the zh UI (cached label service).
  const tlParamLabel = useLocalizedLabels([
    ...renderedParameters.map((p: any) => String(p?.label || p?.name || '')),
    ...((Array.isArray(workflowDefinition?.data_inputs) ? workflowDefinition.data_inputs : []) as any[]).map((d: any) => String(d?.label || d?.name || '')),
  ]);

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
  // Block Run only for REQUIRED file-type params with no value and no default.
  // Blocking optional file inputs too contradicted the per-row "optional — empty"
  // label (which keys off p.required); the run gate must use the same required
  // flag so the footer and the row agree (cf. commit 5e812ef429 — a param is
  // required only when the workflow enforces it). A workflow that truly needs a
  // file it marks optional is a schema bug to fix in its definition, not here.
  const missingFileInputs = prereqChecklist?.overrideAllowed
    ? []
    : renderedParameters.filter(
        (p: any) => p.type === 'file' && p.required === true && !p.value && !p.default
      );
  // Clinic hard primary data (movies_path, samplesheet, matrix, …) even when the
  // schema left required=false / demo elvis — same classifier as the execute gate.
  const clinicHardUnbound = prereqChecklist?.overrideAllowed
    ? []
    : unboundClinicHardDataFromParams(workflowDefinition, {
        ...Object.fromEntries(
          renderedParameters.map((p: any) => [p.id || p.name, p.value]),
        ),
        ...params,
      });
  const missingClinicHard = clinicHardUnbound.map((u) => ({
    name: u.name,
    label: u.label,
    required: true,
    type: 'file' as const,
  }));
  // Perception / extension sniff vs param kind — same pure helper as the Inputs card.
  // Override-allowed (demo recovery) skips the hard block; the card still shows the warning.
  const datatypeGateBlocked = React.useMemo(() => {
    if (prereqChecklist?.overrideAllowed) return false;
    const paramDefs: any[] = [
      ...(workflowDefinition?.required_params || []),
      ...(workflowDefinition?.optional_params || []),
    ];
    const model = derivePrerunInputs(renderedParameters as any, sessionDatasets as any, paramDefs);
    return runIsBlockedByInputs(model.primary);
  }, [
    prereqChecklist?.overrideAllowed,
    workflowDefinition?.required_params,
    workflowDefinition?.optional_params,
    renderedParameters,
    sessionDatasets,
  ]);
  const isPrereqBlocked =
    (!!prereqChecklist && !prereqChecklist.canRun) ||
    hasUnfilledRequired ||
    missingFileInputs.length > 0 ||
    missingClinicHard.length > 0 ||
    datatypeGateBlocked;
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

  // D4: Auto-fetch error explanation when workflow fails
  useEffect(() => {
    let abandoned = false;
    if (wasCancelled) { setErrorExplanation(null); setErrorExplaining(false); return; }
    if (status === 'failed' && !wasCancelled && !errorExplanation && !errorExplaining) {
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
          workflow_name: workflowDefinition?.name || workflowDefinition?.chain_display_name || workflowDefinition?.workflow_name,
          error_log: rawLog,
          run_id: runId,
          failed_steps: failedSteps,
        }),
      })
        .then(r => r.json())
        .then(data => { if (!abandoned) setErrorExplanation(data); })
        .catch(() => {
          if (abandoned) return;
          // Show a minimal fallback so the user isn't left staring at "Analyzing…"
          setErrorExplanation({
            human_summary: 'Error analysis timed out. Check the log output above for details.',
            suggested_fix: 'Review the error log and retry the workflow, or contact support if the issue persists.',
            error_type: 'analysis_failed',
            chat_prompt: '',
            llm_used: false,
          });
        })
        .finally(() => { clearTimeout(explainTimeout); if (!abandoned) setErrorExplaining(false); });
      return () => { abandoned = true; abortController.abort(); clearTimeout(explainTimeout); };
    }
  }, [status, wasCancelled]);

  useEffect(() => {
    setLastUpdateAt(new Date());
  }, [status, wasCancelled, progress, errorMessage, nextflowStatus, stepExecutionById]);

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
    // Prefer the backend-classified / user-requested profile the workflow already carries
    // (workflowDefinition.qc_profile — e.g. the message's "admet_standard", set by
    // ai_assistant._infer_qc_profile). Without this, the domain fallback below picked the
    // FIRST drug_discovery profile (cipa_ind_submission) and silently ignored the request.
    const explicitProfile = (workflowDefinition as any).qc_profile as string | undefined;
    if (explicitProfile && availableQcProfiles.some(p => p.id === explicitProfile)) {
      setQcProfile(explicitProfile);
      return;
    }
    const name = (workflowDefinition.name || workflowDefinition.workflow_name || '').toLowerCase();
    const domainMap: Record<string, string[]> = {
      cryo_em: ['cryo', 'cryosparc', 'spa', 'tomography', 'helical', 'subtomogram'],
      rnaseq: ['rnaseq', 'rna-seq', 'transcriptom', 'rna_seq'],
      wgs: ['wgs', 'germline', 'gatk', 'variant_calling', 'sarek'],
      wes: ['wes', 'exome'],
      scrna_seq: ['scdownstream', 'scrna', 'single_cell', 'scrnaseq', 'cellranger', '10x'],
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
    setAutoLoopPanel({ gateResults: null, remediations: [], regulatoryActions: [], complete: null });

    // US-7.2 style reconnect: a transient SSE blip must NOT permanently close the
    // stream. This channel carries live run telemetry (step_state, workflow_state,
    // autoloop_*, qc_gate_*); closing on the first error froze the panel on
    // "Running…" forever. Reconnect with exponential backoff, capped at 5 attempts,
    // mirroring workflow-artifact.tsx. `stopped` + the cleanup below still close
    // cleanly on a real unmount so there is no leak or double-subscribe.
    let currentEs: EventSource | null = null;
    let reconnectAttempts = 0;
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null;

    const connect = () => {
      if (stopped) return;
      const es = new EventSource(`/api/workflows/${invocationId}/events`);
      currentEs = es;
      es.onopen = () => { reconnectAttempts = 0; };

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
            invocationId: typeof data.invocation_id === 'string' ? data.invocation_id : invocationId,
            eventId: typeof data.event_id === 'string' ? data.event_id
              : typeof data.eventId === 'string' ? data.eventId : event.lastEventId || undefined,
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
        // A completed-process observation is a result finding. Only an explicitly
        // confirmed orchestration boundary can authorize pause/retry controls.
        if (!canControlExecutionFromQc(data, qcExecutionStatusRef.current)) {
          const processName = data.process_name || "QC";
          setQcAdvisoryByStep(prev => ({ ...prev, [processName]: gateData.failures
            .filter((f): f is QCGateFailure => !!f && typeof f === "object")
            .map(f => ({ metric: f.metric, value: f.value, threshold: f.threshold })) }));
          return;
        }
        // Determine if auto-loop is enabled for this phase.
        // Auto-loop ON → apply suggestions automatically using Nextflow -resume, no card shown.
        // Auto-loop OFF → show confirmation card and let user decide.
        const phaseKey = data.phase_key ?? data.process_name ?? '';
        // No explicit user toggle → fall back to the profile's own autoloop
        // declaration (autoloop:true profiles close the loop by default); an
        // explicit true/false the user set always wins.
        const autoloopOn = autoloopMapRef.current[phaseKey] ?? profileAutoloopDefaultRef.current;

        // SAFETY HALT: a qc_gate_triggered event only fires when a blocking
        // (halt-threshold) failure exists — advisory-only crossings come via
        // qc_warning. So when pauseAtQcFailures is on (default) and this is a
        // blocking gate, PAUSE the run and wait for the user (Resume / Cancel) —
        // no 10s auto-proceed. We EXEMPT phases the user explicitly set to
        // auto-loop (!autoloopOn): that is a deliberate opt-in to auto-remediate.
        // Blocking = advisory !== true (mirrors the backend's blocking_failures).
        const isHaltGate = Array.isArray(gateData.failures)
          && gateData.failures.some((f: any) => f && typeof f === 'object' && f.advisory !== true);
        if (pauseAtQcFailuresRef.current && isHaltGate && activeRunId && !autoloopOn) {
          setQCGateData(gateData);
          setQcGateHalt(true);
          setShowQcInline(true);
          fetch(`/api/workflows/runs/${encodeURIComponent(activeRunId)}/pause`, { method: 'POST', credentials: 'include' })
            .catch(err => console.error("[QC Gate NFViewer] Halt-pause request failed:", err));
          const failSummary = gateData.failures
            .map((f: any) => (typeof f === 'string' ? f : `${f.metric} ${f.operator ?? ''} ${f.threshold} (got ${f.value})`))
            .join(", ");
          onWorkflowProgress?.({
            kind: 'workflow.qc_halt_paused',
            friendly_message: `Paused on a safety QC gate (${failSummary}). Review the result, then Resume or Cancel.`,
            ts: Date.now() / 1000,
            technical: { decision: 'paused on halt gate', source: 'qc_gate_halt' },
          });
          return;
        }

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
          regulatoryActions: data.regulatory_actions ?? [],
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

    // ── Failure self-healing events ───────────────────────────────────────
    es.addEventListener("auto_reroute", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        if (onAutoReroute) {
          onAutoReroute({
            fromWorkflow: data.from_workflow ?? "",
            toWorkflowName: data.to_workflow_name ?? data.to_workflow ?? "",
            reason: data.reason ?? "",
            newRunId: data.new_run_id ?? "",
            newInvocationId: data.new_invocation_id ?? "",
          });
        }
      } catch (err) {
        console.error("[auto_reroute] parse error:", err);
      }
    });

    es.addEventListener("ai_diagnosis", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        setAiDiagnosis({
          category: data.category ?? "unknown",
          user_message: data.user_message ?? "The run encountered an error.",
          suggested_action: data.suggested_action ?? "resume",
          fix_strategy: data.fix_strategy ?? "not_fixable",
          is_transient: data.is_transient ?? false,
          task_error_snippet: data.task_error_snippet ?? "",
        });
      } catch (err) {
        console.error("[ai_diagnosis] parse error:", err);
      }
    });

    es.addEventListener("auto_resuming", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        const delay = typeof data.delay_s === 'number' ? data.delay_s : 30;
        autoResumeCancelledRef.current = false;
        setAutoResumeDelay(delay);
        setAutoResumeCountdown(delay);
      } catch (err) {
        console.error("[auto_resuming] parse error:", err);
      }
    });


    es.addEventListener("container_pull_progress", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data as string);
        setContainerPullStatus({
          image: data.image ?? "",
          status: data.status ?? "pulling",
          message: data.message ?? "",
        });
        // Auto-clear once ready so the banner disappears after pull completes
        if (data.status === "ready") {
          setTimeout(() => setContainerPullStatus(null), 3000);
        }
      } catch (err) {
        console.warn("[SSE] container_pull_progress parse error:", err);
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
    // ── Post-completion chain suggestions ────────────────────────────────
    es.addEventListener("chain_suggestion", (event: MessageEvent) => {
      if (!onWorkflowProgress) return;
      try {
        const data = JSON.parse(event.data as string);
        const triggerWf = String(data.trigger_workflow || "").split("/").pop() || "your workflow";
        const suggestionLines = (data.suggestions as Array<{ display_name: string; steps: number; description: string }> ?? [])
          .map((s) => `→ **${s.display_name}** (${s.steps} steps) — ${s.description}`)
          .join("\n");
        if (!suggestionLines) return;
        onWorkflowProgress({
          kind: "chain_suggestion",
          friendly_message: `**Suggested next steps** after your ${triggerWf} run:\n\n${suggestionLines}`,
          ts: Date.now() / 1000,
          technical: { chain_suggestion: true, suggestions: data.suggestions, trigger_workflow: data.trigger_workflow },
        });
      } catch (err) {
        console.warn("[SSE] chain_suggestion parse error:", err);
      }
    });
    // ── Post-completion proactive suggestion ─────────────────────────────
    es.addEventListener("proactive_suggestion", (event: MessageEvent) => {
      if (!onWorkflowProgress) return;
      try {
        const data = JSON.parse(event.data as string);
        if (!data.message) return;
        onWorkflowProgress({
          kind: "proactive_suggestion",
          friendly_message: data.message,
          ts: Date.now() / 1000,
          technical: {
            proactive_suggestion: true,
            quick_replies: data.quick_replies || [],
          },
        });
      } catch (err) {
        console.warn("[SSE] proactive_suggestion parse error:", err);
      }
    });
    // ─────────────────────────────────────────────────────────────────────

      es.onerror = () => {
        // Close the dead handle (defeating EventSource's own retry so we control
        // the cadence), then reconnect with exponential backoff up to 5 attempts.
        // After the cap we stop: the panel keeps its last-known status instead of
        // spinning on a dead socket. A real unmount sets `stopped` first, so this
        // never fires a reconnect against a torn-down component.
        es.close();
        if (currentEs === es) currentEs = null;
        if (stopped) return;
        const attempt = reconnectAttempts;
        reconnectAttempts += 1;
        if (attempt < 5) {
          const delay = Math.min(2000 * Math.pow(2, attempt), 30000);
          reconnectTimer = setTimeout(connect, delay);
        }
      };
    };

    connect();

    return () => {
      stopped = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      currentEs?.close();
      currentEs = null;
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

  // The overall bar must never read 100% while the run is still going — 100% is
  // reserved for a terminal/completed run. The backend's progressPercent can
  // reach 100 (all Batch tasks dispatched/finished) before the run is finalised
  // (a QC gate still pending review, outputs hydrating), which otherwise renders
  // "100% · Running" next to a per-step bar at 50% — a self-contradiction the
  // screenshot committee flagged on r-fail-state. Cap at 99% until completed.
  const overallProgressDisplay =
    status === 'completed' ? effectiveProgress : Math.min(effectiveProgress, 99);

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
          title={tOr('panel.drag_to_resize', 'Drag to resize')}
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
        // Run KIND overrides "Workflow" for design / sandbox / training runs (Spec 13 §13.4).
        const runKind = deriveRunKind(workflowDefinition);
        const runKindLabel = t(`panel.run_kind.${RUN_KIND_KEY[runKind]}`).toUpperCase();
        const kickerLabel = meaningfulDomain
          ? `${tOr(`domains.${meaningfulDomain.toLowerCase()}`, meaningfulDomain.replace(/_/g, ' ')).toUpperCase()} · ${runKindLabel}`
          : runKindLabel;
        const hasRealPhases = groupedPhases.some((g: any) => g.key !== 'all');
        const phaseCount = hasRealPhases ? groupedPhases.length : groupedPhases.length > 0 ? 1 : 0;
        const stepCount = updatedPhases.length;
        const subtitleParts: string[] = [];
        if (projectName) subtitleParts.push(projectName);
        if (workflowDefinition?.version) subtitleParts.push(String(workflowDefinition.version));
        if (phaseCount > 0) subtitleParts.push(t(phaseCount === 1 ? 'panel.phase_count_one' : 'panel.phase_count_other', { n: phaseCount }));
        const panelSub = subtitleParts.length > 0
          ? subtitleParts.join(' · ')
          : ((workflowDefinition?.description || '') as string).split(/[.—]/)[0].trim().slice(0, 60);
        return (
          <div className="panel-head" data-tour="panel-header">
            <div className="top-row">
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="kicker" data-testid="panel-kicker" data-run-kind={runKind}>{kickerLabel}</div>
                <div className="panel-name">{workflowDefinition?.name || workflowDefinition?.chain_display_name || workflowDefinition?.workflow_name || t('panel.untitled')}</div>
                {panelSub && <div className="panel-sub">{panelSub}</div>}
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                {onToggleExpand && <button type="button" className="iconbtn" aria-label={expanded ? 'Restore split view' : 'Expand workflow panel'} onClick={onToggleExpand} data-testid="workflow-panel-expand">{expanded ? <Minimize2 style={{ width: 13, height: 13 }} /> : <Maximize2 style={{ width: 13, height: 13 }} />}</button>}
                {onClose && <button type="button" className="iconbtn" aria-label="Close workflow panel" data-testid="workflow-panel-close" onClick={onClose}><span aria-hidden style={{ fontSize: 'var(--fs-section)', lineHeight: 1 }}>×</span></button>}
                {projectId && (
                  <button
                    onClick={() => navigate(`/projects?project=${projectId}`)}
                    data-testid="viewer-goto-project"
                    title={t('panel.go_to_project')}
                    style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 'var(--fs-meta)',
                             padding: '2px 8px', borderRadius: 4, border: '1px solid var(--bm-border, hsl(var(--border)))',
                             background: 'transparent', cursor: 'pointer', color: 'var(--bm-text-muted)',
                             flexShrink: 0 }}
                  >
                    <FolderOpen style={{ width: 12, height: 12 }} />
                    {t('panel.project')}
                  </button>
                )}
                {workflowDefinition?.qc_profile && (
                  <span className="chip ok" style={{ fontSize: 'var(--fs-xs)' }}>
                    {tOr('panel.qc_prefix', 'QC: ')}{(workflowDefinition.qc_profile as string).replace(/_/g, ' ')}
                  </span>
                )}
                {/* Only show chip for non-idle states */}
                {status !== 'idle' && (
                  <span
                    className={`chip${wasCancelled ? '' : status === 'running' ? ' run' : status === 'completed' ? ' ok' : status === 'failed' ? ' err' : ''}`}
                    data-testid="workflow-overall-status-badge"
                    data-status={wasCancelled ? 'cancelled' : status}
                  >
                    {wasCancelled
                      ? tStatus('cancelled')
                      : (['running', 'completed', 'failed', 'queued', 'cancelled', 'pending'].includes(status)
                      ? tStatus(status)
                      : status.toUpperCase())}
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
                  <button className="iconbtn" data-testid="button-cancel-workflow-panel" onClick={onCancel} title={t('actions.cancel')} aria-label={t('actions.cancel')}>
                    <Ban style={{ width: 14, height: 14 }} />
                  </button>
                )}
              </div>
            </div>
            {(status === 'running' || status === 'completed') && effectiveProgress > 0 && (
              <div className="run-bar">
                <div className="progress">
                  <div className="fill" style={{ width: `${overallProgressDisplay}%` }} />
                </div>
                <span className="pct">{overallProgressDisplay}%</span>
                {status === 'completed' && stepCount > 0 && (
                  <span className="meta">{stepCount}/{stepCount}</span>
                )}
              </div>
            )}

          </div>
        );
      })()}

      {/* ── Top-level tabs (Step A MVP — phases tab keeps current view) ─────── */}
      {(() => {
        const hasRealPhases = groupedPhases.some((g: any) => g.key !== 'all');
        const phaseCount = hasRealPhases ? groupedPhases.length : groupedPhases.length > 0 ? 1 : 0;
        const showAfterRunDot = status === 'completed' || status === 'failed';
        // Per-tab hover hints so the user can see what each tab contains
        // without clicking.
        const tabTips: Record<'settings' | 'phases' | 'after-run', string> = {
          settings: t('panel.tab_tips.settings'),
          phases: t('panel.tab_tips.phases'),
          'after-run': t('panel.tab_tips.after_run'),
        };
        const tabBtn = (key: 'settings' | 'phases' | 'after-run', label: string, badge?: React.ReactNode): React.ReactElement => (
          <HintTip key={key} hint={tabTips[key]} side="bottom">
          <button
            type="button"
            onClick={() => { setActiveTab(key); setTabAutoDefault(false); }}
            data-testid={`panel-tab-${key}`}
            aria-selected={activeTab === key}
            style={{
              background: 'transparent',
              border: 'none',
              padding: '8px 14px',
              cursor: 'pointer',
              fontSize: 'var(--fs-meta)',
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
          </HintTip>
        );
        const countBadge = (n: number) =>
          n > 0 ? (
            <span style={{
              fontSize: 'var(--fs-micro)',
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
            background: wasCancelled ? 'oklch(0.62 0.01 260)' : status === 'failed' ? 'oklch(0.62 0.18 25)' : 'oklch(0.65 0.15 145)',
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
            {tabBtn('settings', t('panel.tabs.settings'), undefined)}
            {tabBtn('phases', t('panel.tabs.phases'), countBadge(phaseCount))}
            {tabBtn('after-run', t('panel.tabs.after_run'), showAfterRunDot ? dotBadge : null)}
          </div>
        );
      })()}

      {/* ── After-run tab content (v2 AfterRunReport, embedded inline) ──────── */}
      {activeTab === 'after-run' && (
        <div className="panel-body" data-testid="panel-after-run">
          {/* Container pull progress banner — shown when backend is downloading a missing image */}
          {containerPullStatus && (status === 'running' || containerPullStatus.status === 'pulling') && (
            <div style={{
              margin: '12px 16px 0',
              padding: '10px 14px',
              background: containerPullStatus.status === 'failed'
                ? 'oklch(0.97 0.01 40)' : 'oklch(0.96 0.02 250)',
              border: `1px solid ${containerPullStatus.status === 'failed'
                ? 'oklch(0.88 0.04 40)' : 'oklch(0.82 0.06 250)'}`,
              borderRadius: 8,
              display: 'flex',
              alignItems: 'center',
              gap: 10,
            }}>
              {containerPullStatus.status === 'pulling' && (
                <Loader2 style={{ width: 14, height: 14, flexShrink: 0 }} className="animate-spin" />
              )}
              {containerPullStatus.status === 'ready' && (
                <span style={{ fontSize: 'var(--fs-body)' }}>✓</span>
              )}
              {containerPullStatus.status === 'failed' && (
                <span style={{ fontSize: 'var(--fs-body)' }}>⚠</span>
              )}
              <div>
                <div style={{ fontSize: 'var(--fs-meta)', fontWeight: 600, color: 'var(--text)' }}>
                  {containerPullStatus.status === 'pulling' ? tOr('panel.env.preparing', 'Preparing the run environment (first run)') :
                   containerPullStatus.status === 'ready' ? tOr('panel.env.ready', 'Environment ready') : tOr('panel.env.pull_failed', 'Image download failed')}
                </div>
                <div style={{ fontSize: 'var(--fs-micro)', color: 'var(--text-muted)', marginTop: 2 }}>
                  {containerPullStatus.message}
                </div>
              </div>
            </div>
          )}

          {/* Auto-resume countdown banner — shown when backend pushes auto_resuming SSE */}
          {autoResumeCountdown !== null && (
            <div style={{
              margin: '12px 16px 0',
              padding: '10px 14px',
              background: 'oklch(0.96 0.015 230)',
              border: '1px solid oklch(0.80 0.06 230)',
              borderRadius: 8,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: 10,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 'var(--fs-body)' }}>⚡</span>
                <span style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.35 0.03 230)', fontWeight: 500 }}>
                  {tOr('panel.env.auto_resume', 'Backend restart detected — resuming automatically in {{n}}s…', { n: autoResumeCountdown ?? 0 })}
                </span>
              </div>
              <button
                onClick={() => {
                  autoResumeCancelledRef.current = true;
                  setAutoResumeCountdown(null);
                  setAutoResumeDelay(null);
                }}
                style={{
                  fontSize: 'var(--fs-meta)', padding: '3px 10px', borderRadius: 5, cursor: 'pointer',
                  background: 'transparent', border: '1px solid oklch(0.72 0.05 230)',
                  color: 'oklch(0.42 0.04 230)', whiteSpace: 'nowrap', flexShrink: 0,
                }}
              >
                {tOr('panel.env.cancel', 'Cancel')}
              </button>
            </div>
          )}


          {/* AI diagnosis card — merges real-time SSE (aiDiagnosis) with API-backed failure (survives refresh) */}
          {(() => {
            // Prefer SSE-pushed diagnosis (has task_error_snippet); fall back to API-polled failure.
            const diag = aiDiagnosis ?? (_failure?.user_message ? _failure : null);
            const snippet = (aiDiagnosis?.task_error_snippet ?? _failure?.task_error_snippet ?? "").trim();
            if (!diag?.user_message || status !== 'failed' || wasCancelled) return null;
            const isArchCompat = (diag as any).category === 'arch_compat' || _failure?.category === 'arch_compat';
            return (
              <div style={{
                margin: '12px 16px 0',
                padding: '12px 14px',
                background: isArchCompat ? 'oklch(0.97 0.01 280)' : 'oklch(0.97 0.01 40)',
                border: `1px solid ${isArchCompat ? 'oklch(0.82 0.06 280)' : 'oklch(0.88 0.04 40)'}`,
                borderRadius: 8,
                display: 'flex',
                flexDirection: 'column',
                gap: 8,
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{ fontSize: 'var(--fs-body)' }}>{isArchCompat ? '⚙️' : '🔍'}</span>
                  <span style={{ fontSize: 'var(--fs-meta)', fontWeight: 600, color: 'oklch(0.38 0.02 40)' }}>
                    {tOr('panel.diag.title', 'AI diagnosis')}
                  </span>
                </div>
                {(() => {
                  // The rule classifier names specific causes (too few rows, missing
                  // column, bad contrast, OOM …) from the task's own error text; when it
                  // recognises one, it leads. Otherwise the server's category sentence.
                  const ts = classifyRunFailure([snippet, errorMessage].filter(Boolean).join('\n'));
                  if (ts.known && ts.i18n.cause) {
                    const culprit = ts.culprit ? (ts.i18n.culprit ? tOr(ts.i18n.culprit, ts.culprit, ts.i18n.vars) : ts.culprit) : '';
                    return (
                      <div data-testid="failure-diagnosis-cause" data-failure-class={ts.klass} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                        <p style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.42 0.015 260)', margin: 0, lineHeight: 1.5 }}>
                          {tOr(ts.i18n.cause, ts.cause, ts.i18n.vars)}
                        </p>
                        {culprit && !ts.cause.includes(ts.culprit!) && (
                          <p style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.5 0.01 260)', margin: 0 }}>
                            <strong>{tOr('afterrun.at_fault', 'At fault')}:</strong> {culprit}
                          </p>
                        )}
                        <p style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.5 0.01 260)', margin: 0 }}>
                          <strong>{tOr('afterrun.next_action', 'Next')}:</strong> {tOr(ts.i18n.next, ts.nextAction, ts.i18n.vars)}
                        </p>
                      </div>
                    );
                  }
                  return (
                    <p style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.42 0.015 260)', margin: 0, lineHeight: 1.5 }}>
                      {failureDiagnosisMessage(diag.user_message, canResumeFailed, (diag as any).category, (diag as any).error_detail)}
                    </p>
                  );
                })()}
                {failureRecoveryAdvice(diag.suggested_action, canResumeFailed) && (
                  <p data-testid="failure-recovery-advice" style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.55 0.01 260)', margin: 0 }}>
                    {failureRecoveryAdvice(diag.suggested_action, canResumeFailed)}
                  </p>
                )}
                {/* Raw engine log/snippet intentionally NOT shown (founder 2026-11-11:
                    internal Nextflow DEBUG/CacheDB/plugin plumbing must never surface
                    to the user). The plain-language diagnosis above and the real error
                    message in the report below are what the user reads; full engine
                    logs stay in the dedicated job-log viewer for support. */}
                {(!snippet && diag.suggested_action === 'resume') && (
                  <p style={{ fontSize: 'var(--fs-meta)', color: 'oklch(0.55 0.01 260)', margin: 0 }}>
                    ℹ️ {tOr('panel.diag.no_log', 'No error log was captured for this run. If resuming keeps failing, report the run to BioMate.')}
                  </p>
                )}
              </div>
            );
          })()}
          <AfterRunReport
            embedded
            hideFailureDiagnosis={showsFailureDiagnosis}
            runId={runId || invocationId || ''}
            invocationId={invocationId}
            // C2: Stream 2 adds `targetTab?` to AfterRunReportProps; cast-spread
            // keeps this file's tsc green until that lands.
            {...((targetAfterRunTab ? { targetTab: targetAfterRunTab } : {}) as any)}
            workflowName={workflowDefinition?.name}
            projectId={projectId || undefined}
            parameters={params as Record<string, unknown>}
            executionStatus={
              wasCancelled ? 'cancelled'
              : status === 'completed' ? 'completed'
              : status === 'failed' ? 'failed'
              : status === 'running' ? 'running'
              : status === 'paused' ? 'paused'
              : undefined
            }
            errorMessage={errorMessage}
            failedSteps={wasCancelled ? undefined : updatedPhases.filter(phase => phase.status === 'failed').map(phase => phase.processName || phase.name)}
            logTail={Array.isArray(nextflowStatus?.log_tail) ? nextflowStatus.log_tail.filter((line: unknown) => typeof line === 'string') : undefined}
            autofix={wasCancelled ? undefined : autofix}
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
                // NAME (e.g. INVIVO_CART_ATLAS_SAFETY/) — mirrors the
                // chat-with-artifacts derivation so styling is consistent.
                // But many S3 layouts put the file under an opaque run/history
                // id (e.g. 76d11493/) rather than a process name; showing that id
                // as the "step" is meaningless to the user ("who knows the id?").
                // So accept the segment only when it reads like a process name,
                // never when it is an opaque hash / uuid / numeric id — in which
                // case we leave step blank (grouped under the neutral header).
                const parts = filePath.split('/');
                const rawStep = parts.length >= 2 ? parts[parts.length - 2] : '';
                const isOpaqueId =
                  /^[0-9a-f]{6,}$/i.test(rawStep) ||            // hex hash (76d11493)
                  /^[0-9a-f]{8}-[0-9a-f-]{8,}$/i.test(rawStep) || // uuid
                  /^\d+$/.test(rawStep);                         // pure numeric id
                const step = isOpaqueId ? '' : rawStep;
                // Thread the real byte size through (it's in the s3_output_files
                // payload) so the Outputs tab shows actual sizes, not 0 B.
                const size = (typeof f === 'object' && typeof f.size === 'number') ? f.size : undefined;
                return { step, name, path: filePath, ext, size };
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
          {/* ── Human approval gate (§7.6) ──────────────────────────────────────
              Rendered when the run is awaiting human approval. The panel
              represents that state as status === 'pending_review'. Placed at the
              top of the shared body (NOT inside the phases-tab-only wrapper) so
              it is visible on whichever tab is active — pending_review auto-
              defaults to the Settings tab. A human approval reads in the same
              measured · threshold · verdict grammar as a QC gate. Approve resumes
              the run (handleExecute), Deny cancels (onCancel), "Ask a reviewer"
              hands off to chat (onAdjustViaChat).
              NOTE: the backend does not yet emit a dedicated "awaiting approval"
              SSE trigger — this surfaces on the existing pending_review status;
              wiring a first-class approval trigger is a documented follow-up. */}
          {status === 'pending_review' && (() => {
            const approvalData: ApprovalGateData = {
              what: tOr('panel.approval.what', 'Run "{{name}}"', { name: workflowDefinition?.name || workflowDefinition?.workflowName || tOr('panel.approval.this_workflow', 'this workflow') }),
              why: tOr('panel.approval.why', 'This run is paused for human review before it starts consuming compute.'),
              cost: tOr('panel.approval.cost', 'Approving starts the workflow on the configured infrastructure.'),
              measured: [
                {
                  key: tOr('panel.approval.review_state', 'Review state'),
                  measured: tOr('panel.approval.awaiting', 'awaiting approval'),
                  threshold: tOr('panel.approval.signoff_required', 'human sign-off required before run'),
                  verdict: 'needs approval',
                },
              ],
              who: projectId
                ? tOr('panel.approval.who_project', 'You can approve this — you own this run in the project.')
                : tOr('panel.approval.who_run', 'You can approve this — this is your run.'),
              policy: tOr('panel.approval.policy', 'Governed by the workflow approval policy.'),
            };
            return (
              <div style={{ margin: '0 18px 10px' }}>
                <ApprovalGate
                  data={approvalData}
                  onResolve={(record) => {
                    if (record.decision === 'approve') {
                      handleExecute();
                    } else if (record.decision === 'deny') {
                      onCancel?.();
                    } else {
                      onAdjustViaChat?.(
                        tOr('panel.approval.request_review_msg', 'I\'d like a reviewer to sign off on running "{{name}}" before it starts.', { name: workflowDefinition?.name || tOr('panel.approval.this_workflow', 'this workflow') }),
                      );
                    }
                  }}
                />
              </div>
            );
          })()}
          {/* ── Phases-tab-only runtime section ─────────────────────────────── */}
          <div style={{ display: activeTab === 'phases' ? 'contents' : 'none' }}>
          {/* Container pull progress banner — shown on phases tab while backend downloads a missing image.
              This runs BEFORE Nextflow starts, so no phase cards exist yet; the banner is the only feedback. */}
          {containerPullStatus && (status === 'running' || containerPullStatus.status === 'pulling') && (
            <div style={{
              margin: '12px 16px 4px',
              padding: '10px 14px',
              background: containerPullStatus.status === 'failed'
                ? 'oklch(0.97 0.01 40)' : 'oklch(0.95 0.025 250)',
              border: `1px solid ${containerPullStatus.status === 'failed'
                ? 'oklch(0.88 0.04 40)' : 'oklch(0.80 0.08 250)'}`,
              borderRadius: 8,
              display: 'flex',
              alignItems: 'center',
              gap: 10,
            }}>
              {containerPullStatus.status === 'pulling' && (
                <Loader2 style={{ width: 16, height: 16, flexShrink: 0 }} className="animate-spin" />
              )}
              {containerPullStatus.status === 'ready' && (
                <span style={{ fontSize: 'var(--fs-body)' }}>✓</span>
              )}
              {containerPullStatus.status === 'failed' && (
                <span style={{ fontSize: 'var(--fs-body)' }}>⚠</span>
              )}
              <div>
                <div style={{ fontSize: 'var(--fs-meta)', fontWeight: 600, color: 'var(--text)' }}>
                  {containerPullStatus.status === 'pulling' ? tOr('panel.env.preparing', 'Preparing the run environment (first run)') :
                   containerPullStatus.status === 'ready' ? tOr('panel.env.ready_starting', 'Environment ready, starting…') : tOr('panel.env.pull_failed', 'Image download failed')}
                </div>
                <div style={{ fontSize: 'var(--fs-micro)', color: 'var(--text-muted)', marginTop: 2 }}>
                  {containerPullStatus.message}
                </div>
              </div>
            </div>
          )}
          {/* The pre-launch "click a phase to expand…" paragraph was removed (founder
              phase-view review 2026-11-11): the chevrons already afford expansion and
              per-phase run controls now only appear once a run exists. */}
          {/* QC Gate Inline Review Panel — appears when backend fires a qc_gate_triggered SSE event */}
          {showQcInline && qcGateData && (status === "running" || status === "paused") && (
            <div className="alert warn" data-testid="qc-gate-inline" style={{ marginBottom: 10 }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6 }}>
                <AlertTriangle className="h-3.5 w-3.5" style={{ flexShrink: 0, marginTop: 1 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontWeight: 600, marginBottom: 2 }}>
                    {tOr('panel.qc_gate_prefix', 'QC Gate — ')}{qcGateData.processName.includes(":")
                      ? qcGateData.processName.split(":").pop()?.replace(/_/g, " ")
                      : qcGateData.processName.replace(/_/g, " ")}{qcGateHalt
                        ? tOr('panel.qc_gate_paused_suffix', ' — run paused · action required')
                        : tOr('panel.qc_gate_review_suffix', ' — Review Required')}
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
                            <span style={{ flex: 1, fontSize: 'var(--fs-meta)', color: 'var(--text-2)' }}>{fail.metric}</span>
                            <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 700, color: 'var(--err)', fontSize: 'var(--fs-meta)' }} data-testid="qc-gate-measured">
                              {typeof fail.value === 'number' ? fail.value.toFixed(fail.value < 10 ? 2 : 0) : fail.value}
                            </span>
                            <span style={{ color: 'var(--text-dim)', fontSize: 'var(--fs-micro)' }}>{fail.operator}</span>
                            <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 600, color: 'var(--ok)', fontSize: 'var(--fs-meta)' }} data-testid="qc-gate-threshold">
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
                    <div style={{ marginTop: 6, fontSize: 'var(--fs-micro)', color: 'var(--text-dim)' }} data-testid="qc-gate-countdown">
                      {tOr('panel.qc_gate_countdown', 'Pipeline continues in {{time}} unless you act', { time: `${Math.floor(qcGateSecondsLeft / 60)}:${String(qcGateSecondsLeft % 60).padStart(2, '0')}` })}
                    </div>
                  )}
                  <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
                    {qcGateHalt ? (
                      <>
                        <button className="btn sm" data-testid="qc-gate-resume" onClick={handleResumeAfterHalt}>{tOr('panel.qc_resume', 'Resume')}</button>
                        <button className="btn ghost sm danger" data-testid="qc-gate-cancel-run" onClick={handleCancelWorkflow}>{tOr('panel.cancel_run', 'Cancel run')}</button>
                      </>
                    ) : (
                      <>
                        {qcGateData.suggestions.length > 0 && (
                          <button className="btn sm" data-testid="qc-gate-apply" onClick={() => { void handleRetryWithSuggestions(); }} disabled={isApplyingSuggestions}>
                            {isApplyingSuggestions ? tOr('panel.qc_applying', 'Applying…') : tOr('panel.qc_apply_suggestions', 'Apply suggestions')}
                          </button>
                        )}
                        <button className="btn ghost sm" data-testid="qc-gate-keep" onClick={handleProceedAnyway}>{tOr('panel.qc_keep_current', 'Keep current')}</button>
                        <button className="btn ghost sm danger" data-testid="qc-gate-cancel-run" onClick={handleCancelWorkflow}>{tOr('panel.cancel_run', 'Cancel run')}</button>
                      </>
                    )}
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Completion banner — shown when workflow reaches terminal success state */}
          {status === 'completed' && (
            <div className="alert ok" data-testid="workflow-completion-banner" style={{ marginBottom: 10 }}>
              <CheckCircle2 className="h-3.5 w-3.5" style={{ flexShrink: 0 }} />
              <span>{tOr('panel.completed_banner', 'Workflow completed. View Results and Download All are available.')}</span>
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
                <div style={{ fontSize: 'var(--fs-micro)', fontWeight: 700, letterSpacing: '0.06em', color: 'var(--text-dim)', marginBottom: 6, textTransform: 'uppercase' }}>
                  {tOr('panel.qc_results', 'QC Results')}
                </div>
                {allMetrics.map((m: any, i: number) => (
                  <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center', fontSize: 'var(--fs-meta)', padding: '3px 0', borderBottom: i < allMetrics.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
                    <span style={{ flex: 1, color: 'var(--text-2)' }}>{m.name}</span>
                    <span style={{ fontVariantNumeric: 'tabular-nums', color: m.pass ? 'var(--ok)' : 'var(--err)', fontWeight: 600 }}>
                      {typeof m.measured === 'number' ? m.measured.toFixed(m.measured < 10 ? 2 : 0) : m.measured}
                      {m.unit ? ` ${m.unit}` : ''}
                    </span>
                    <span style={{ color: 'var(--text-dim)', fontSize: 'var(--fs-micro)' }}>
                      {m.pass ? '✓' : '✗'} {tOr('panel.threshold_short', 'thresh')} {m.threshold}
                    </span>
                  </div>
                ))}
              </div>
            );
          })()}


          </div>{/* end Phases-tab-only runtime section (re-opens after settings strip) */}

          {/* ── Settings-tab-only: the existing Workflow-settings strip ─────── */}
          <div style={{ display: activeTab === 'settings' ? 'contents' : 'none' }}>
          {/* ── Inputs mapped — restate resolved inputs + compatibility BEFORE run ─ */}
          {/* L3 (one-object-everywhere): before anything runs, BioMate restates    */}
          {/* which dataset is bound to each input and flags anything that isn't    */}
          {/* safely resolved, so the user confirms the mapping — not a raw form.   */}
          {(() => {
            const paramDefs: any[] = [
              ...(workflowDefinition?.required_params || []),
              ...(workflowDefinition?.optional_params || []),
            ];
            // Pure derivation (input-mapping-status.ts, unit-tested): the user's
            // DATA inputs — required ones first, even when the schema types them as
            // plain strings (nf-core/rnaseq `input` samplesheet) — versus optional
            // file overrides still on their genome/pipeline default. Overrides are
            // not "mapped inputs", so they render collapsed and never inflate the
            // header count. Same classifier as the chat reply state.
            // Executor-owned required data inputs (nf-core `input`): described by the backend,
            // never editable params — the executor builds them from attached files or an accession.
            const executorInputs: any[] = (Array.isArray(workflowDefinition?.data_inputs) ? workflowDefinition.data_inputs : [])
              .filter((d: any) => d?.name && d?.required)
              .map((d: any) => ({
                id: `__data_input__${d.name}`, name: d.name, label: d.label || d.name, type: 'file', required: true,
                data_input: true, executor_bound: true,
                value: d.bound ? (d.bound_value || tOr('panel.provided_in_chat', 'provided in chat')) : '',
              }));
            const model = derivePrerunInputs([...executorInputs, ...renderedParameters] as any, sessionDatasets as any, [...executorInputs, ...paramDefs]);
            if (model.primary.length === 0 && model.overrides.length === 0) {
            // Style-A workflows declare their input via a `// Input:` code header,
            // which surfaces as ordinary OPTIONAL STRING params ("Input Csv", "Dataset Id",
            // "S3 Uri", "File Name", …) rather than type:'file' — so the schema
            // classifier finds no data input and the panel would wrongly say "no data
            // inputs to bind". Detect them so the user knows the workflow DOES take data and
            // how to supply it: attach via the composer (📎) — the uploaded file's
            // s3 URI is wired into the param, which the executor reads. (We do NOT
            // re-type them as 'file' — that would change the working bind path.)
            const INPUT_LIKE_RE = /(^|[_\s])(input|csv|tsv|dataset|data.?id|s3.?uri|file.?name|samplesheet|matrix|contrasts|counts|clinical|expression)([_\s]|$)/i;
            const styleAInputs = renderedParameters.filter((p: any) =>
                  (p.type === 'string' || p.type === 'text' || p.type === undefined)
                  && INPUT_LIKE_RE.test(`${p.name || ''} ${p.label || ''}`)
                  && !/output|outdir|out_dir|publish/i.test(String(p.name || '')));
            if (styleAInputs.length === 0) {
              return (
                <div data-testid="prerun-inputs-mapped" className="card2" style={{ marginBottom: 12, padding: '10px 12px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 'var(--fs-meta)', fontWeight: 600 }}>
                    <Database className="h-3.5 w-3.5" /> {tOr('panel.inputs_title', 'Inputs')}
                  </div>
                  <div style={{ fontSize: 'var(--fs-meta)', color: 'var(--text-dim)', marginTop: 4 }}>
                    {tOr('panel.params_only_no_inputs', 'This workflow takes parameters only — no data inputs to bind.')}
                  </div>
                  {/* The user uploaded data but this workflow reads none of it —
                      say so here instead of leaving them to infer it from an
                      empty Inputs card (founder report: 5 files attached, panel
                      said "parameters only"). */}
                  {/* Only files attached in THIS chat that the workflow does not read — the login-session
                      upload list covered every chat since login, so the line showed with nothing
                      uploaded here (founder 2026-11-12). */}
                  {((workflowDefinition as any)?.attachment_binding?.unbound?.length ?? 0) > 0 && (
                    <div
                      data-testid="prerun-attachments-unused"
                      style={{ fontSize: 'var(--fs-micro)', color: 'var(--warn, #b45309)', marginTop: 6 }}
                    >
                      {tOr(
                        'panel.attachments_not_used',
                        'Files you uploaded in this session are not used by this workflow. Ask in the chat for a workflow that reads them.',
                      )}
                    </div>
                  )}
                </div>
              );
            }
              return (
                <div data-testid="prerun-inputs-mapped" className="card2" style={{ marginBottom: 12, padding: '10px 12px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 'var(--fs-meta)', fontWeight: 600 }}>
                    <Database className="h-3.5 w-3.5" /> {tOr('panel.inputs_title', 'Inputs')}
                  </div>
                  <div style={{ fontSize: 'var(--fs-meta)', color: 'var(--text-dim)', marginTop: 4 }}>
                    {!styleAInputs.some((p: any) => p.value != null && String(p.value).trim() !== '')
                      ? tOr('panel.styleA_attach_hint', 'This workflow needs a data file. Attach it with the paperclip (📎) in the message box below — BioMate wires your uploaded file into the workflow automatically.')
                      : tOr('panel.inputs_linked_review', 'Input references are set. Review the mapping below.')}
                  </div>
                  <div style={{ marginTop: 6, display: 'flex', flexDirection: 'column', gap: 4 }}>
                    {styleAInputs.map((p: any, i: number) => {
                      const bound = p.value != null && String(p.value).trim() !== '';
                      return (
                        <div key={p.id || p.name || i} data-testid="prerun-input-row" style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 'var(--fs-meta)', flexWrap: 'wrap' }}>
                          <span style={{ fontWeight: 500 }}>{p.label || p.name}</span>
                          <span style={{ color: 'var(--text-dim)' }}>→</span>
                          <span style={{ color: bound ? 'var(--text)' : 'var(--text-dim)' }}>
                            {bound ? String(p.value).split('/').pop() : tOr('panel.not_set', 'not set')}
                          </span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            }
            const blocking = blockingInputRows([...model.primary, ...model.overrides]);
            const basename = (v: any) => String(v).split('/').pop() || String(v);
            // Public-accession guidance only where an accession can actually supply
            // the data (sequencing / omics domains), never for e.g. a compound CSV.
            const acceptsAccession = /rnaseq|scrna|wgs|transcript|genom|epigen|single.?cell|variant|metagen|chip|atac|proteom/.test(
              `${qcWorkflowDomain(workflowDefinition)} ${String(workflowDefinition?.domain || '')}`.toLowerCase());
            const renderRow = (r: InputMappingRow, isOverride: boolean, i: number) => {
              const p: any = r.param;
              return (
                <div key={p.id || p.name || i} data-testid={isOverride ? 'prerun-override-row' : 'prerun-input-row'} data-status={r.status} style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: 'var(--fs-meta)', flexWrap: 'wrap' }}>
                  <span style={{ minWidth: 0, fontWeight: isOverride ? 400 : 500 }}>{tlParamLabel(String(p.label || p.name || ''))}</span>
                  <span style={{ color: 'var(--text-dim)' }}>→</span>
                  <span style={{ minWidth: 0, flex: 1 }}>
                    {r.empty ? (
                      <span style={{ color: 'var(--text-dim)' }}>
                        {isOverride ? tOr('panel.not_set_default_used', 'not set — default used') : tOr('panel.not_set', 'not set')}
                      </span>
                    ) : (
                      // Show the clean name only. Never reveal the storage URI or
                      // dataset id — not inline and not on hover (founder: no
                      // internal path/key/id in the UI, including tooltips). The hover
                      // title uses cleanParamValueForDisplay, which strips s3://gs://
                      // URIs + bare UUIDs + id= patterns (basename alone would leak
                      // those in the no-dataset-name edge case — audit finding).
                      <span title={r.dataset?.name || cleanParamValueForDisplay(r.value) || tOr('panel.staged_file', 'staged file')}>
                        {r.dataset?.name || cleanParamValueForDisplay(r.value) || tOr('panel.staged_file', 'staged file')}
                      </span>
                    )}
                  </span>
                  {isOverride && r.status === 'resolved' && (
                    <span className="chip" style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px' }}>{tOr('panel.uses_default', 'default')}</span>
                  )}
                  {!isOverride && r.status === 'resolved' && (
                    <span
                      className="chip ok"
                      style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px' }}
                      data-format-checked={r.formatChecked ? 'true' : 'false'}
                      title={r.formatChecked
                        ? tOr('panel.resolved_format_ok_tip', 'Bound to this dataset. File kind matches this input’s expected type.')
                        : tOr('panel.resolved_tip', 'Bound to this dataset. Schema/units compatibility is not automatically checked for this input type.')}
                    >
                      {r.formatChecked
                        ? tOr('panel.resolved_format_ok', 'resolved · format ok')
                        : tOr('panel.resolved_format_unchecked', 'resolved · format not checked')}
                    </span>
                  )}
                  {r.status === 'unresolved' && (
                    <span className="chip err" style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px' }}>{tOr('panel.required_not_set', 'required — not set')}</span>
                  )}
                  {r.status === 'needs-mapping' && (
                    <span className="chip err" style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px' }}>{tOr('panel.needs_mapping', 'needs mapping')}</span>
                  )}
                  {!isOverride && r.status === 'optional-empty' && (
                    <span className="chip" style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px' }}>{tOr('panel.optional_empty', 'optional — empty')}</span>
                  )}
                  {(r.status === 'unresolved' || r.status === 'needs-mapping') && !p.executor_bound && (
                    <button
                      type="button"
                      className="btn sm ghost"
                      style={{ fontSize: 'var(--fs-xs)', padding: '1px 6px' }}
                      onClick={() => setBrowsingForParam({ id: p.id, label: p.label || p.name || p.id })}
                    >
                      {tOr('panel.choose_file', 'Choose file')}
                    </button>
                  )}
                  {r.mismatch && (
                    <div className="hint" style={{ flexBasis: '100%', color: 'var(--warn, #b45309)', fontSize: 'var(--fs-micro)' }}>⚠️ {r.mismatch}</div>
                  )}
                </div>
              );
            };
            return (
              <div data-testid="prerun-inputs-mapped" className="card2" style={{ marginBottom: 12, padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 8 }}>
                <div data-testid="prerun-inputs-header" style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 'var(--fs-meta)', fontWeight: 600, flexWrap: 'wrap' }}>
                  <Database className="h-3.5 w-3.5" /> {tOr('panel.inputs_title', 'Inputs')}
                  <span style={{ color: 'var(--text-dim)', fontWeight: 400 }}>·</span>
                  {model.requiredUnset > 0 ? (
                    <span className="chip err" data-testid="prerun-inputs-summary" style={{ fontSize: 'var(--fs-xs)', padding: '1px 5px', fontWeight: 500 }}>
                      {tOr('panel.inputs_required_unset', '{{n}} required, not set', { n: model.requiredUnset })}
                    </span>
                  ) : model.boundCount > 0 ? (
                    <span className="hint" data-testid="prerun-inputs-summary" style={{ fontWeight: 400, fontSize: 'var(--fs-micro)' }}>
                      {tOr('panel.inputs_mapped_count', '{{n}} mapped', { n: model.boundCount })}
                    </span>
                  ) : (
                    <span className="hint" data-testid="prerun-inputs-summary" style={{ fontWeight: 400, fontSize: 'var(--fs-micro)' }}>
                      {tOr('panel.inputs_none_required', 'no required data inputs')}
                    </span>
                  )}
                </div>
                {model.primary.length > 0 ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    {model.primary.map((r, i) => renderRow(r, false, i))}
                  </div>
                ) : (
                  <div style={{ fontSize: 'var(--fs-meta)', color: 'var(--text-dim)' }}>
                    {tOr('panel.only_optional_overrides', 'No data upload needed — the files below are optional overrides.')}
                  </div>
                )}
                {model.requiredUnset > 0 && (
                  <div data-testid="prerun-inputs-how-to-provide" style={{ fontSize: 'var(--fs-micro)', color: 'var(--text-2)' }}>
                    {acceptsAccession
                      ? tOr('panel.inputs_attach_or_accession', 'Attach your files with the paperclip (📎) in the message box below, or reply in the chat with a public accession (e.g. SRR…, GSE…).')
                      : tOr('panel.inputs_attach_hint', 'Attach your file with the paperclip (📎) in the message box below — BioMate wires it into the workflow.')}
                  </div>
                )}
                {model.overrides.length > 0 && (
                  <details data-testid="prerun-input-overrides" style={{ fontSize: 'var(--fs-meta)' }}>
                    <summary style={{ cursor: 'pointer', color: 'var(--text-2)' }}>
                      {tOr('panel.reference_overrides', 'Reference overrides')} ({model.overrides.length})
                      <span className="hint" style={{ marginLeft: 6, fontSize: 'var(--fs-micro)' }}>
                        {tOr('panel.reference_overrides_hint', 'optional — defaults come from the selected genome or pipeline')}
                      </span>
                    </summary>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 6 }}>
                      {model.overrides.map((r, i) => renderRow(r, true, i))}
                    </div>
                  </details>
                )}
                {/* The how-to line above already covers "required, not set"; the
                    blocking line is only needed when a bound input needs re-mapping. */}
                {blocking.some(r => r.status === 'needs-mapping') ? (
                  <div style={{ fontSize: 'var(--fs-micro)', color: 'var(--warn, #b45309)' }}>
                    {tOr('panel.inputs_blocking', 'Nothing will run until {{n}} input{{verb}} resolved — pick the file or fix the mapping above.', { n: blocking.length, verb: blocking.length !== 1 ? 's are' : ' is' })}
                  </div>
                ) : model.boundCount > 0 ? (
                  <div style={{ fontSize: 'var(--fs-micro)', color: 'var(--text-dim)' }}>
                    {tOr('panel.inputs_all_bound', 'These inputs will be used exactly as bound. Reopen a dataset from its chip to check its provenance.')}
                  </div>
                ) : null}
              </div>
            );
          })()}
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

            if (globalParams.length === 0 && !mismatch) return (
              <div style={{ minHeight: 100, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '32px 24px', textAlign: 'center', color: 'var(--text-dim)', fontSize: 'var(--fs-meta)' }}>
                {/* Don't claim "no parameters" when params exist but are pinned to
                    individual phases — point the user to the Phases tab instead. */}
                <div style={{ marginBottom: 6 }}>{allPhaseParamNames.size > 0
                  ? tOr('panel.params_in_phases', 'Parameters are configured per phase — open the Phases tab to adjust them.')
                  : tOr('panel.no_configurable_params', 'This workflow has no configurable parameters.')}</div>
                <div style={{ fontSize: 'var(--fs-meta)', opacity: 0.75 }}>{tOr('panel.confirm_to_start', 'Click "{{button}}" below to start it.', { button: t('workflow.actions.confirm_and_run') })}</div>
              </div>
            );
            return (
              <div>
                  <div className="strip-body">
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                      {mismatch && (
                        <div className="alert warn" data-testid="format-mismatch-warning">
                          <span>⚠️</span><span>{mismatch.format_mismatch_warning}</span>
                        </div>
                      )}
                      {requiredParams.length > 0 && (
                        <ParameterGroup
                          id="params-required"
                          title={tOr('panel.required_parameters', 'Required parameters')}
                          description={`${requiredUnfilled.length > 0 ? tOr('panel.still_needed', '{{n}} still needed · ', { n: requiredUnfilled.length }) : ''}${tOr('panel.param_count', '{{n}} param{{s}}', { n: requiredParams.length, s: requiredParams.length !== 1 ? 's' : '' })}`}
                          parameters={requiredParams}
                          onChange={handleParamChange}
                          onBrowseDataset={(paramId, paramLabel) => setBrowsingForParam({ id: paramId, label: paramLabel })}
                          defaultOpen={true}
                        />
                      )}
                      {optionalParams.length > 0 && (
                        <ParameterGroup
                          id="params-optional"
                          title={tOr('panel.optional_parameters', 'Optional parameters')}
                          description={`${tOr('panel.param_count', '{{n}} param{{s}}', { n: optionalParams.length, s: optionalParams.length !== 1 ? 's' : '' })} — ${tOr('panel.collapsed_by_default', 'collapsed by default')}`}
                          parameters={optionalParams}
                          onChange={handleParamChange}
                          onBrowseDataset={(paramId, paramLabel) => setBrowsingForParam({ id: paramId, label: paramLabel })}
                          defaultOpen={false}
                        />
                      )}
                      {requiredParams.length === 0 && optionalParams.length === 0 && (
                        <ParameterGroup
                          id="params-global"
                          title={tOr('panel.workflow_parameters', 'Workflow parameters')}
                          description={tOr('panel.param_count', '{{n}} param{{s}}', { n: globalParams.length, s: globalParams.length !== 1 ? 's' : '' })}
                          parameters={globalParams}
                          onChange={handleParamChange}
                          onBrowseDataset={(paramId, paramLabel) => setBrowsingForParam({ id: paramId, label: paramLabel })}
                          defaultOpen={true}
                        />
                      )}

                      {/* Output-location controls hidden at user request.
                          Project runs use the project folder; standalone runs use managed storage. */}

                    </div>
                  </div>
              </div>
            );
          })()}

          <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
            </div>

          {/* Permissions and verification summaries hidden at user request.
          {(() => {
            const scope = projectId ? tOr('panel.scope_project', 'This project') : tOr('panel.scope_run', 'This run');
            const rolesData: RolesData = {
              you: tOr('panel.owner', 'Owner'),
              project: scope,
              caps: [
                { capability: tOr('panel.run_this_workflow', 'Run this workflow'), needs: tOr('panel.owner', 'Owner'), allowed: true },
                { capability: tOr('panel.change_params_qc', 'Change parameters & QC thresholds'), needs: tOr('panel.owner', 'Owner'), allowed: true },
                { capability: tOr('panel.cap_cancel_job', 'Cancel a running job'), needs: tOr('panel.owner', 'Owner'), allowed: true },
                { capability: tOr('panel.cap_register_model', 'Register a model from this run'), needs: tOr('panel.owner', 'Owner'), allowed: true },
                { capability: tOr('panel.cap_invite_reviewer', 'Invite a reviewer'), needs: tOr('panel.owner', 'Owner'), allowed: true },
              ],
            };
            const verifyKinds: VerifyKind[] = [
              { kind: tOr('panel.verify.qc_kind', 'Workflow QC gate'), measuredBy: tOr('panel.verify.qc_by', 'a measurement on your data'), stops: tOr('panel.verify.qc_stops', 'halts the run'), where: 'Spec 07' },
              { kind: tOr('panel.verify.approval_kind', 'Human approval'), measuredBy: tOr('panel.verify.approval_by', 'a person'), stops: tOr('panel.verify.approval_stops', 'holds the run until sign-off'), where: 'Spec 7.6' },
              { kind: tOr('panel.verify.license_kind', 'License gate'), measuredBy: tOr('panel.verify.license_by', 'the workflow license terms'), stops: tOr('panel.verify.license_stops', 'blocks the run'), where: 'Spec 07' },
            ];
            return (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '10px 18px 4px' }}>
                <RolesCard data={rolesData} />
                <VerifyPattern kinds={verifyKinds} />
              </div>
            );
          })()}
          */}

            {/* License gate lives in Workflow settings (footer copy points here).
                Mount for any status where Confirm / Restart / Run again can fire —
                not only idle — so a failed CryoSPARC run cannot Restart without a
                user license. Path also covers workflow_type=cryosparc with no
                nextflow_path. */}
            {(() => {
              const licensePath = licenseGatePathForWorkflow(workflowDefinition);
              if (!licensePath) return null;
              if (status === 'running' || status === 'paused' || status === 'queued') return null;
              return (
                <div style={{ padding: '8px 18px 12px' }} data-testid="license-gate-settings">
                  <LicenseGate
                    nextflowPath={licensePath}
                    onBlockedChange={setIsLicenseBlocked}
                  />
                </div>
              );
            })()}
          </div>{/* end settings-tab-only section */}

          {/* ── Phases-tab-only — phase cards + everything below ──────────── */}
          <div style={{ display: activeTab === 'phases' ? 'contents' : 'none' }}>
            {/* ── Phase section label ──────────────────────────────────────────── */}
            {groupedPhases.length > 0 && (() => {
              const hasRealPhases = groupedPhases.some((g: any) => g.key !== 'all');
              // The phases tab badge already shows the phase count; repeating it here
              // ("阶段 · 4") was the third copy on screen. Only the flat-steps case,
              // which has no badge of its own, keeps a label.
              if (hasRealPhases) return null;
              const label = tOr('panel.steps_label', 'STEPS · {{n}}', { n: updatedPhases.length });
              return (
                <div style={{ fontSize: 'var(--fs-xs)', fontWeight: 700, letterSpacing: '0.08em', color: 'var(--text-dim)', padding: '10px 18px 4px', textTransform: 'uppercase' }}>
                  {label}
                </div>
              );
            })()}

            {/* ── Live run progress (Gap 3/4) — overall %, current step, elapsed,
                   collapsible recent logs + AI autofix state. Active runs only;
                   polling stops on terminal status (runActive flips false). ── */}
            {runActive && groupedPhases.length > 0 && (() => {
              const totalSteps = updatedPhases.length;
              const completedSteps = updatedPhases.filter((p: any) => p.status === 'completed').length;
              const runningStep = updatedPhases.find((p: any) => p.status === 'running');
              const pct = totalSteps > 0
                ? Math.round((completedSteps / totalSteps) * 100)
                : (Number.isFinite(effectiveProgress) ? Math.max(0, Math.min(100, effectiveProgress)) : 0);
              const elapsedMs = runStartRef.current != null ? nowTick - runStartRef.current : 0;
              const af = realtimeStatus?.autofix ?? null;
              const issues = realtimeStatus?.issues ?? [];
              const fixesApplied = af?.fixes_applied ?? 0;
              const afBusy = !!af && (af.active || fixesApplied > 0);
              const restartInv = realtimeStatus?.restart_info?.new_invocation_id;
              // Prefer backend-tailed logs when present; else the SSE log_tail we already hold.
              const recentLogs = (realtimeStatus?.recent_logs && realtimeStatus.recent_logs.length > 0)
                ? realtimeStatus.recent_logs
                : logs;
              const currentLabel = runningStep?.name
                || (status === 'paused' ? tOr('workflow.status.paused', 'Paused') : t('workflow.status.running'));
              const sevColor = (sev?: string) =>
                sev === 'high' || sev === 'critical' ? 'var(--err)'
                : sev === 'low' ? 'var(--text-muted)'
                : 'var(--warn)';
              return (
                <div
                  className="live-progress"
                  data-testid="live-run-progress"
                  data-status={status}
                  data-progress-pct={pct}
                >
                  <div className="run-bar" style={{ marginTop: 0 }}>
                    <Activity
                      style={{ width: 13, height: 13, color: 'var(--run)', flexShrink: 0,
                               animation: status === 'running' ? 'spin 1.4s linear infinite' : 'none' }}
                    />
                    <div className="progress" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
                      <div className="fill" style={{ width: `${pct}%` }} />
                    </div>
                    <span className="pct" data-testid="live-progress-pct">{pct}%</span>
                    {totalSteps > 0 && (
                      <span className="meta" data-testid="live-progress-steps">{completedSteps}/{totalSteps}</span>
                    )}
                  </div>
                  <div className="live-progress-meta">
                    <span className="current" data-testid="live-progress-current" title={currentLabel}>
                      {currentLabel}
                    </span>
                    <span className="elapsed" data-testid="live-progress-elapsed">
                      <Clock style={{ width: 11, height: 11, verticalAlign: '-1px', marginRight: 3 }} />
                      {formatDuration(elapsedMs)}
                    </span>
                  </div>
                  {(afBusy || issues.length > 0 || restartInv) && (
                    <div className="live-progress-badges">
                      {afBusy && (
                        <span className="chip warn" data-testid="live-progress-autofix-chip" style={{ fontSize: 'var(--fs-xs)' }}>
                          <ShieldCheck style={{ width: 11, height: 11, verticalAlign: '-1px', marginRight: 3 }} />
                          {fixesApplied > 0
                            ? t('panel.live.autofix_applied', { n: fixesApplied })
                            : t('panel.live.autofix_active')}
                        </span>
                      )}
                      {issues.length > 0 && (
                        <span className="chip" data-testid="live-progress-issues-chip"
                              style={{ fontSize: 'var(--fs-xs)', background: 'var(--warn-soft)', color: 'var(--warn)' }}>
                          <AlertTriangle style={{ width: 11, height: 11, verticalAlign: '-1px', marginRight: 3 }} />
                          {t('panel.live.issues_detected', { n: issues.length })}
                        </span>
                      )}
                      {restartInv && (
                        <span className="chip" data-testid="live-progress-restart-chip"
                              style={{ fontSize: 'var(--fs-xs)', background: 'var(--run-soft)', color: 'var(--run)' }}>
                          <RotateCcw style={{ width: 11, height: 11, verticalAlign: '-1px', marginRight: 3 }} />
                          {t('panel.live.restarted')}
                        </span>
                      )}
                    </div>
                  )}
                  <button
                    type="button"
                    className="live-progress-toggle"
                    data-testid="live-progress-details-toggle"
                    aria-expanded={progressDetailsOpen}
                    onClick={() => setProgressDetailsOpen(o => !o)}
                  >
                    <ChevronRight
                      style={{ width: 12, height: 12, transition: 'transform 0.15s',
                               transform: progressDetailsOpen ? 'rotate(90deg)' : 'none' }}
                    />
                    {progressDetailsOpen ? t('panel.live.hide_details') : t('panel.live.show_details')}
                  </button>
                  {progressDetailsOpen && (
                    <div className="live-progress-details" data-testid="live-progress-details">
                      {/* AI-detected issues + autofix detail (from /realtime/status) */}
                      {issues.length > 0 && (
                        <div className="live-progress-issues">
                          {issues.map((iss, i) => (
                            <div key={i} className="live-progress-issue">
                              <span className="sev" style={{ color: sevColor(iss.severity) }}>
                                {(iss.severity || tOr('panel.live.severity_info', 'info')).toUpperCase()}
                              </span>
                              <span className="msg">
                                {iss.message || iss.type || t('panel.live.issue_fallback')}
                                {iss.auto_fixable && (
                                  <span className="autofixable"> · {t('panel.live.auto_fixable')}</span>
                                )}
                              </span>
                            </div>
                          ))}
                        </div>
                      )}
                      {/* Recent log lines */}
                      {recentLogs.length > 0 ? (
                        <pre className="live-progress-log" data-testid="live-progress-log">
                          {recentLogs.slice(-40).join('\n')}
                        </pre>
                      ) : (
                        <div className="live-progress-log-empty">{t('panel.live.no_logs_yet')}</div>
                      )}
                    </div>
                  )}
                </div>
              );
            })()}

            {/* ── Loading state when steps are being lazily fetched ────────── */}
            {groupedPhases.length === 0 && lazyStepsFetching && (workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath) && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '16px 18px', color: 'var(--text-dim)', fontSize: 'var(--fs-meta)' }}>
                <span style={{ display: 'inline-block', width: 14, height: 14, borderRadius: '50%', border: '2px solid currentColor', borderTopColor: 'transparent', animation: 'spin 0.8s linear infinite' }} />
                {tOr('panel.loading_steps', 'Loading workflow steps…')}
              </div>
            )}
            {/* ── No steps found after fetch completed ─────────────────────── */}
            {groupedPhases.length === 0 && !lazyStepsFetching && lazySteps !== null && (workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath) && (
              <div style={{ minHeight: 100, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px 18px', color: 'var(--text-dim)', fontSize: 'var(--fs-meta)', textAlign: 'center' }}>
                {wasCancelled
                  ? tOr('panel.run_cancelled_no_phases', 'Run was cancelled before any phases completed.')
                  : status === 'failed'
                  ? tOr('panel.run_failed_no_phases', 'Run failed before any phases started. Check the error details above.')
                  : tOr('panel.phases_appear', 'Execution phases will appear here once the workflow starts.')}
              </div>
            )}
            {/* ── Idle / no nextflow_path — personal workflow not yet run ─── */}
            {groupedPhases.length === 0 && !lazyStepsFetching && lazySteps === null && status === 'idle' && (
              <div style={{ minHeight: 100, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '32px 24px', textAlign: 'center', color: 'var(--text-dim)', fontSize: 'var(--fs-meta)' }}>
                <div style={{ marginBottom: 6 }}>{tOr('panel.no_phases', 'No phases defined yet.')}</div>
                <div style={{ fontSize: 'var(--fs-meta)', opacity: 0.75 }}>{tOr('panel.phases_appear', 'Execution phases will appear here once the workflow starts.')}</div>
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
                    onPreviewFile={(file, step) => { setPreviewFile(file); setPreviewStep(step ?? null); }}
                    onOpenFullStepView={(step) => setFullViewStep(buildStepDetailStep(step))}
                    qcThresholds={idx === 0 ? displayedQcThresholds : []}
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
                      canControlExecutionFromQc(autoLoopPanel.gateResults, status) &&
                      autoLoopPanel.gateResults &&
                      autoloopPhaseMatches(group.key, autoLoopPanel.gateResults.phase)
                        ? autoLoopPanel
                        : undefined
                    }
                    autoloopEnabled={autoloopMap[group.key] ?? profileAutoloopDefault}
                    autoloopLocked={activeQcProfile?.autoloop !== true}
                    onToggleAutoloop={() => {
                      // Workflow-conditioned: only autoloop-ready profiles (the few
                      // drug-dev workflows with a ready design→make→test loop) expose
                      // this. For those, it DEFAULTS ON (the profile opted into the
                      // closed loop); the user can still switch it off. No-op for
                      // non-autoloop workflows.
                      if (activeQcProfile?.autoloop !== true) return;
                      setAutoloopMap(prev => {
                        const cur = prev[group.key] ?? profileAutoloopDefault;
                        const next = { ...prev, [group.key]: !cur };
                        autoloopMapRef.current = next;
                        return next;
                      });
                    }}
                    onDismissAutoloop={() =>
                      setAutoLoopPanel({ gateResults: null, remediations: [], regulatoryActions: [], complete: null })
                    }
                    onAcceptAutoloop={(paramChanges) => {
                      setParams(prev => ({ ...prev, ...paramChanges }));
                      setAutoLoopPanel({ gateResults: null, remediations: [], regulatoryActions: [], complete: null });
                      handleExecute();
                    }}
                    qcAdvisoryByStep={qcAdvisoryByStep}
                  />
                ))}
                {/* "Suggest a new step via chat" removed — step authoring is not a
                    supported action here; it only produced a free-text chat nudge. */}
              </div>
            )}

            {/* ── Skip dependency map (§7.5 / §2.5.1) ────────────────────────────
                Per-phase skippable state, DAG-aware. Skip is a declared workflow
                capability — a phase is only skippable if the workflow declares a
                skip parameter for it. Data comes from GET /api/nextflow/skip-analysis
                (backend derives skippable/param/blocks/warn from the workflow's
                declared skip params + DAG channel wiring). When the analysis hasn't
                loaded (or the workflow has no nextflow_path), fall back to the honest
                "not declared skippable" state per visible phase group. Read-only —
                no onToggle handler yet (skipping is not wired into execution).
                Shown pre-run only. */}
            {groupedPhases.some((g: any) => g.key !== 'all') && (status === 'idle' || status === 'pending_review') && (() => {
              const realGroups = groupedPhases.filter((g: any) => g.key !== 'all');
              if (realGroups.length === 0) return null;
              // Index the backend analysis by phase id so we can align it to the
              // phase groups the viewer is actually rendering.
              const byId: Record<string, PhaseSkipInfo> =
                (skipAnalysis || []).reduce((acc: Record<string, PhaseSkipInfo>, p) => {
                  acc[p.id] = p; return acc;
                }, {});
              const skipPhases: PhaseSkipInfo[] = realGroups.map((g: any) => {
                const real = byId[g.key];
                const phaseLabel = g.label || tOr('panel.skip.phase_named', 'Phase {{id}}', { id: g.key });
                // The backend sends `why` as free-form English prose. It's built from
                // a fixed set of templates keyed on the same structured fields the
                // viewer already has (skippable / blocks / warn / param), so we
                // regenerate it localized here instead of rendering the raw English
                // next to the Chinese chrome. Covers every case, not just the simple
                // "not declared" one.
                const localizeWhy = (info: PhaseSkipInfo): string => {
                  if (info.skippable) {
                    const param = info.param || '';
                    return (info.warn && info.warn.length)
                      ? tOr('panel.skip.why_skippable_reduced', '{{phase}} — the workflow declares `{{param}}`, so this phase can be skipped. Downstream phases still run but with reduced input.', { phase: phaseLabel, param })
                      : tOr('panel.skip.why_skippable', '{{phase}} — the workflow declares `{{param}}`, so this phase can be skipped without affecting downstream phases.', { phase: phaseLabel, param });
                  }
                  return (info.blocks && info.blocks.length)
                    ? tOr('panel.skip.why_blocked', '{{phase}} — this workflow does not declare a skip parameter for this phase, and its output feeds downstream phases, so it always runs.', { phase: phaseLabel })
                    : tOr('panel.skip.why_not_declared', '{{phase}} — this workflow does not declare a skip parameter for this phase, so it always runs.', { phase: phaseLabel });
                };
                if (real) {
                  return { ...real, why: localizeWhy(real) };
                }
                return { id: g.key, skippable: false, why: localizeWhy({ id: g.key, skippable: false, why: '' }) };
              });
              // Only surface the skip UI when at least one phase is actually
              // skippable. When nothing is skippable the section is pure noise
              // (four disabled rows + "cannot skip" warnings), so hide it.
              if (!skipPhases.some((p) => p.skippable)) return null;
              return (
                <div style={{ padding: '4px 18px 10px' }}>
                  <SkipDependency phases={skipPhases} />
                </div>
              );
            })()}

          </div>{/* end flex-column wrapper */}

              {/* Global QC settings removed — QC gates are now shown per-phase inside each phase card */}

              {isAutofixActive && (
                <div className="alert info" data-testid="autofix-active-banner" style={{ marginBottom: 8 }}>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" style={{ flexShrink: 0 }} />
                  <span>{tOr('panel.autofix_in_progress', 'Auto-fix in progress ({{state}}) — manual retry disabled to prevent duplicate runs.', { state: autofix?.state || tOr('panel.autofix_fixing', 'fixing') })}</span>
                </div>
              )}
              {/* Execution checklist — only shown when hard blockers exist (e.g. domain guard, license gate) */}
              {prereqChecklist && !prereqChecklist.canRun && prereqChecklist.items.some(i => i.status === 'missing' && i.id !== 'input_data' && i.id !== 'required_parameters') && (
                <div className="alert err" data-testid="workflow-prereq-checklist" style={{ flexDirection: 'column', alignItems: 'flex-start', gap: 6, marginBottom: 8 }}>
                  <div style={{ fontWeight: 600 }}>{tOr('panel.cannot_run_prereqs', 'Cannot run — missing prerequisites:')}</div>
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
                            {tOr('panel.continue_in_chat', 'Continue in chat →')}
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {/* ── Post-run links row ─────────────────────────────────────────── */}
              {status === 'completed' && activeTab === 'after-run' && (
                <div className="results-links">
                  <button
                    className="linkish"
                    onClick={() => handleToggleShowResults((prev) => !prev)}
                    disabled={!invocationId}
                    data-testid="button-view-results-link"
                  >
                    {showResults ? tOr('panel.hide_results', 'Hide results') : tOr('panel.view_results', 'View results')}
                  </button>
                  <span className="sep">·</span>
                  <button
                    className="linkish"
                    onClick={() => {
                      if (!invocationId) return;
                      emitUxEvent('output.download_clicked', { invocationId, scope: 'all' });
                      window.open(`/api/invocations/${invocationId}/download-all`, '_blank');
                      setDownloadAllPromptOpen(true);
                    }}
                    disabled={!invocationId}
                    data-testid="button-download-all-workflow-panel"
                  >
                    {tOr('panel.download_all', 'Download all')}
                  </button>
                  <span className="sep">·</span>
                  <button
                    className="linkish"
                    style={{ display: 'inline-flex', alignItems: 'center', gap: 3 }}
                    disabled={!runId || analysisState === 'loading'}
                    onClick={handleAnalyzeResults}
                    data-testid="button-analyze-results"
                  >
                    {analysisState === 'loading' && <Loader2 className="h-2.5 w-2.5 animate-spin" />}
                    {analysisState === 'loading' ? tOr('panel.analyzing', 'Analyzing…') : tOr('panel.ai_analysis', 'AI analysis')}
                  </button>
                  <span className="sep">·</span>
                  <button
                    className="linkish"
                    disabled={!invocationId}
                    onClick={() => {
                      if (!invocationId) return;
                      window.open(`/api/invocations/${invocationId}/methods-report`, '_blank');
                    }}
                    data-testid="button-download-methods-report"
                    data-invocation-id={invocationId || ''}
                  >
                    {tOr('panel.report', 'Report')}
                  </button>
                  {(availableQcProfiles.length > 0 || qcGateData !== null) && (
                    <>
                      <span className="sep">·</span>
                      <button
                        className="linkish"
                        disabled={!invocationId}
                        onClick={() => {
                          if (!invocationId) return;
                          window.open(`/api/invocations/${invocationId}/qc-audit-download`, '_blank');
                        }}
                        data-testid="button-download-qc-audit"
                      >
                        {tOr('panel.qc_audit_log', 'QC audit log')}
                      </button>
                    </>
                  )}
                </div>
              )}

            {/* ── Run metrics strip ─────────────────────────────────────────── */}
              {activeTab === 'phases' && (nextflowStatus?.duration_s != null || nextflowStatus?.started_at != null) && (
                <div className="metrics-strip" data-testid="run-metrics-strip">
                  {nextflowStatus?.duration_s != null && (
                    <div className="cell" data-testid="run-metric-duration">
                      <div className="lbl">{tOr('panel.wall_time', 'Wall time')}</div>
                      <div className="val" data-testid="run-metric-duration-value">
                        {nextflowStatus.duration_s < 60
                          ? `${nextflowStatus.duration_s}s`
                          : `${Math.floor(nextflowStatus.duration_s / 60)}m ${nextflowStatus.duration_s % 60}s`}
                      </div>
                    </div>
                  )}
                  {nextflowStatus?.started_at != null && (
                    <div className="cell" data-testid="run-metric-started-at">
                      <div className="lbl">{tOr('panel.started', 'Started')}</div>
                      <div className="val">{new Date(nextflowStatus.started_at * 1000).toLocaleTimeString()}</div>
                    </div>
                  )}
                  {nextflowStatus?.completed_at != null && (
                    <div className="cell" data-testid="run-metric-completed-at">
                      <div className="lbl">{tOr('panel.ended', 'Ended')}</div>
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
                  onClose={() => { setPreviewFile(null); setPreviewStep(null); }}
                  projectId={projectId}
                  // Offer the "open full step view" affordance only when we know
                  // which step owns this file — otherwise there is no real step
                  // object to map, and we refuse to fabricate one.
                  onOpenFullStepView={previewStep
                    ? () => setFullViewStep(buildStepDetailStep(previewStep))
                    : undefined}
                />
              )}
              {/* StepAdjustModal ("调整并重新运行" adjust-params-and-rerun popup) DISABLED
                  2026-11-12 (founder): the popup itself is wrong — it surfaces in the
                  wrong context with the wrong/confusing params; fixing its content is
                  beside the point. Gated with `false &&` (every affordance that opened
                  it is also hidden). Re-enable when the popup is redesigned.
              {false && adjustStep && activeRunId && (
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
              )} */}

              {/* ── Full step view (spec-08 step-as-object surface) ─────────────
                  Opened from a step's "Details" button or the inline preview's
                  "Full step view" affordance. StepDetail receives ONLY the real
                  mapped step data (see buildStepDetailStep) plus the workflow
                  definition (for param defaults/origins) — nothing fabricated. */}
              {fullViewStep && (
                /* Full step view is a PANEL WITHIN the workflow-view artifact (not a
                   screen-level Dialog overlay): an absolutely-positioned sub-panel
                   covering the workflow panel's content (the .wf-panel root is
                   position:relative). StepDetail provides its own header + back/close. */
                <div
                  className="absolute inset-0 z-30 flex flex-col bg-background overflow-hidden"
                  data-testid="full-step-view-panel"
                  role="region"
                  aria-label={tOr('panel.full_step_view_title', 'Full step view: {{name}}', { name: fullViewStep.name })}
                >
                    {(() => {
                      // Flat ordered step list (across phases) with phase letters —
                      // drives the .deephd position + .deepfoot prev/next traversal
                      // (spec 08 §8.2/§8.3).
                      const flat: Array<{ raw: any; letter: string }> = groupedPhases.flatMap(
                        (g: any) => (Array.isArray(g.steps) ? g.steps.map((s: any) => ({ raw: s, letter: g.letter })) : []),
                      );
                      const idx = flat.findIndex(
                        (e) => String(e.raw?.id ?? e.raw?.name ?? '') === String(fullViewStep.id),
                      );
                      const pos = idx >= 0
                        ? {
                            // Only a REAL phase letter (A/B/…); for unphased workflows
                            // groupStepsIntoPhases returns a numeric step-count "letter",
                            // which must NOT render as a phase badge (audit finding A2).
                            phaseLetter: /^[A-Za-z]/.test(flat[idx].letter || "") ? flat[idx].letter : undefined,
                            stepNumber: idx + 1,
                            totalSteps: flat.length,
                          }
                        : {};
                      const openAt = (i: number) => { if (flat[i]) setFullViewStep(buildStepDetailStep(flat[i].raw)); };
                      return (
                    <StepDetail
                      runId={activeRunId || ""}
                      step={{ ...fullViewStep, ...pos }}
                      workflowDefinition={workflowDefinition}
                      projectId={projectId}
                      onClose={() => setFullViewStep(null)}
                      onPrev={idx > 0 ? () => openAt(idx - 1) : undefined}
                      onNext={idx >= 0 && idx < flat.length - 1 ? () => openAt(idx + 1) : undefined}
                      // Footer "Re-run from here" is intentionally NOT wired: it would
                      // open the StepAdjustModal popup, which is disabled (wrong popup,
                      // founder 2026-11-12). undefined → StepDetail hides the footer
                      // re-run button entirely. Re-wire when that popup is redesigned.
                      onAdjustAndRerun={undefined}
                      onApplyAndRerun={(edited) => {
                        // Apply the in-place-edited params to the form and re-run
                        // with the merged set (pass merged directly — setParams is
                        // async, so handleExecute would otherwise see stale params).
                        setParams(prev => ({ ...prev, ...edited }));
                        setFullViewStep(null);
                        if (onExecute) onExecute({
                          ...params,
                          ...edited,
                          __qcConfig: {
                            pauseAtQcFailures,
                            ...(qcProfile && { qcProfile }),
                            ...(Object.keys(qcOverrides).length > 0 && { qcOverrides }),
                          },
                          ...(projectId ? { __outputLocation: { type: 'project', projectId } } : {}),
                        });
                      }}
                    />
                      );
                    })()}
                </div>
              )}

          {/* ── Error recovery card ───────────────────────────────────────────── */}
          {status === 'failed' && !wasCancelled && (
            <div className="alert err" data-testid="execution-triage-panel" style={{ flexDirection: 'column', alignItems: 'flex-start', gap: 8, margin: '8px 18px' }}>
              <div style={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: 6 }}>
                <XCircle className="h-3.5 w-3.5" style={{ flexShrink: 0 }} />
                {tOr('panel.workflow_failed', 'Workflow Failed')}
                {errorExplaining && <span style={{ fontWeight: 400, fontSize: 'var(--fs-micro)', opacity: 0.7 }}>{tOr('panel.analyzing_error', 'Analyzing error…')}</span>}
              </div>
              {errorExplanation ? (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, width: '100%' }}>
                  <div><span style={{ fontWeight: 600 }}>{tOr('panel.what_went_wrong', 'What went wrong: ')}</span>{sanitizeErrorText(errorExplanation.human_summary)}</div>
                  <div><span style={{ fontWeight: 600 }}>{tOr('panel.suggested_fix', 'Suggested fix: ')}</span>{sanitizeErrorText(errorExplanation.suggested_fix)}</div>
                </div>
              ) : errorExplaining ? (
                <span>{tOr('panel.analyzing_error_log', 'Analyzing error log…')}</span>
              ) : errorMessage ? (
                <span>{sanitizeErrorText(errorMessage)}</span>
              ) : null}
            </div>
          )}

          {activeTab === 'after-run' && (invocationId || runId) && showResults && (
            <div style={{ padding: '8px 0 0' }}>
              <div style={{ padding: '0 18px 6px', fontSize: 'var(--fs-micro)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.06em', color: 'var(--text-dim)' }}>{tOr('panel.output_results', 'Output Results')}</div>
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
                  executionStatus={status}
                />
              )}
            </div>
          )}

          {/* ── AI Analysis Panel ───────────────────────────────────────── */}
          {(analysisState === 'loading' || analysisState === 'done' || analysisState === 'error') && (
            <div className="findings-card" data-testid="ai-analysis-panel">
              <div className="f-h">
                <Activity className="h-3.5 w-3.5" style={{ flexShrink: 0 }} />
                {tOr('panel.ai_findings_analysis', 'Findings analysis')}
                {analysisState === 'done' && <span style={{ fontWeight: 400, marginLeft: 'auto', fontSize: 'var(--fs-xs)' }}>claude-sonnet-4-6</span>}
              </div>

              {analysisState === 'loading' && (
                <div className="f-body" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" style={{ flexShrink: 0 }} />
                  {tOr('panel.analyzing_output_files', 'Analyzing output files…')}
                </div>
              )}

              {analysisState === 'error' && (
                <div className="alert err" style={{ margin: '8px 14px' }}>
                  {analysisError || tOr('panel.analysis_failed', 'Analysis failed. Try again.')}
                </div>
              )}

              {analysisState === 'done' && analysisResult && (
                <>
                  {analysisResult.summary && (
                    <div className="f-body">{analysisResult.summary}</div>
                  )}

                  {analysisResult.key_findings?.length > 0 && (
                    <div className="f-section">
                      <div className="f-section-lbl">{tOr('panel.key_findings', 'Key Findings')}</div>
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
                      <div className="f-section-lbl">{tOr('panel.quality_assessment', 'Quality Assessment')}</div>
                      <div style={{ fontSize: 'var(--fs-meta)', color: 'var(--text-muted)', lineHeight: 1.5 }}>{analysisResult.quality_assessment}</div>
                    </div>
                  )}

                  {analysisResult.next_steps?.length > 0 && (
                    <div className="f-section">
                      <div className="f-section-lbl">{tOr('panel.recommended_next_steps', 'Recommended Next Steps')}</div>
                      {analysisResult.next_steps.map((step: string, i: number) => (
                        <div key={i} className="f-row">{i + 1}. {step}</div>
                      ))}
                    </div>
                  )}

                  {analysisResult.citations?.length > 0 && (
                    <div className="f-section">
                      <div className="f-section-lbl">{tOr('panel.supporting_references', 'Supporting References')}</div>
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
                        <span><b>{tOr('panel.limitations', 'Limitations: ')}</b>{analysisResult.limitations}</span>
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          )}
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
        // Terminal state (completed/failed) is handled by panel-foot below — don't render an empty dark bar here
        if (!isRunning && !isPaused) return null;
        void isTerminal;

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
          fontSize: 'var(--fs-body)',
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
                  title={tOr('panel.pause_execution', 'Pause execution')}
                ><span>⏸</span><span>{tOr('panel.pause', 'Pause')}</span></button>
                <button
                  type="button"
                  data-testid="panel-action-stop"
                  onClick={onCancel}
                  disabled={!onCancel}
                  style={btnBase}
                  title={tOr('panel.stop_execution', 'Stop execution')}
                ><span>⏹</span><span>{tOr('panel.stop', 'Stop')}</span></button>
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
                  title={tOr('panel.resume_execution', 'Resume execution')}
                ><span>▶</span><span>{tOr('panel.resume', 'Resume')}</span></button>
                <button
                  type="button"
                  data-testid="panel-action-stop"
                  onClick={onCancel}
                  disabled={!onCancel}
                  style={btnBase}
                  title={tOr('panel.stop_execution', 'Stop execution')}
                ><span>⏹</span><span>{tOr('panel.stop', 'Stop')}</span></button>
              </>
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
              <strong>{tOr('panel.execution_blocked', 'Execution blocked')}</strong> — {executionBlockedReason}
              {lowConfSecondsLeft !== null && (
                <div data-testid="low-confidence-countdown" style={{ marginTop: 4, fontSize: 'var(--fs-micro)', color: 'var(--text-dim)' }}>
                  {tOr('panel.auto_confirming', 'Auto-confirming in {{n}}s unless you act.', { n: lowConfSecondsLeft })}
                </div>
              )}
              <div className="act">
                <button
                  className="btn sm"
                  onClick={() => {
                    if (lowConfTimerRef.current) { clearInterval(lowConfTimerRef.current); lowConfTimerRef.current = null; }
                    setLowConfSecondsLeft(null);
                    setActiveTab('settings');
                    setTabAutoDefault(false);
                  }}
                >
                  {tOr('panel.fix_now', 'Fix now')}
                </button>
                <button
                  className="btn ghost sm"
                  data-testid="button-confirm-low-confidence-run"
                  disabled={status === 'running' || status === 'completed' || (isPrereqBlocked && !prereqChecklist?.overrideAllowed) || isAutofixActive || isLicenseBlocked}
                  onClick={() => fireLowConfidenceConfirm('user')}
                >
                  {tOr('panel.confirm_anyway', 'Confirm anyway')}
                </button>
              </div>
            </div>
          </div>
        )}
        <div className="run-primary">
          {!executionBlockedReason && status !== 'running' && status !== 'paused' && (
            <button
              className="btn primary"
              data-testid={status === 'completed' ? 'panel-run-again-cta' : 'button-run-workflow-panel'}
              onClick={() => { if (status === 'completed' || status === 'failed') analytics.track('run_again_clicked', { source: 'panel' }); if (canResumeFailed) { void handleResumeFromFailed(); } else { handleExecute(); } }}
              disabled={
                rerunInProgress ||
                // When resuming a failed run, skip prereq/param checks — the run
                // already passed them when it started; only block on autofix/license.
                (canResumeFailed
                  ? (isAutofixActive || isLicenseBlocked)
                  : ((isPrereqBlocked && status !== 'completed')
                      || isAutofixActive
                      || isLicenseBlocked
                      || ((status === 'idle' || status === 'pending_review')
                          && globalRequiredUnfilledCount > 0)))
              }
              title={
                (status === 'idle' || status === 'pending_review') && globalRequiredUnfilledCount > 0
                  ? tOr('panel.fill_required_tip', 'Fill in {{n}} required parameter{{s}} above before running', { n: globalRequiredUnfilledCount, s: globalRequiredUnfilledCount > 1 ? 's' : '' })
                  : undefined
              }
              data-required-unfilled={
                (status === 'idle' || status === 'pending_review')
                  ? globalRequiredUnfilledCount
                  : undefined
              }
            >
              {wasCancelled ? (
                t('panel.footer.run_again')
              ) : status === 'failed' ? (
                canResumeFailed
                  ? (_failure?.suggested_action === 'fix_and_resume' ? t('panel.footer.fix_and_resume') : t('panel.footer.resume_from_last'))
                  : t('panel.footer.restart')
              ) : status === 'completed' ? (
                t('panel.footer.run_again')
              ) : (
                t('workflow.actions.confirm_and_run')
              )}
            </button>
          )}
          {/* Inline reason why the button is disabled — visible without hovering.
              License block also shown for failed/completed so Restart can't look "ready". */}
          {!executionBlockedReason && isLicenseBlocked && (status === 'idle' || status === 'pending_review' || status === 'failed' || status === 'completed') && (
            <div style={{ fontSize: 'var(--fs-micro)', color: 'oklch(0.50 0.16 40)', marginTop: 4, display: 'flex', alignItems: 'center', gap: 5 }} data-testid="license-blocked-hint">
              <span>⚠</span>
              <span dangerouslySetInnerHTML={{ __html: tOr('panel.footer.license_required', 'License required — see <strong>Tool Credentials</strong> in Workflow settings') }} />
            </div>
          )}
          {!executionBlockedReason && !isLicenseBlocked && (status === 'idle' || status === 'pending_review') && (
            globalRequiredUnfilledCount > 0 ? (
              <div style={{ fontSize: 'var(--fs-micro)', color: 'oklch(0.50 0.01 260)', marginTop: 4 }}>
                {tOr('panel.footer.fill_required_params', 'Fill in {{n}} required parameter{{s}} above before running', { n: globalRequiredUnfilledCount, s: globalRequiredUnfilledCount > 1 ? 's' : '' })}
              </div>
            ) : ((missingFileInputs.length > 0) || (missingClinicHard.length > 0)) ? (
              <div style={{ fontSize: 'var(--fs-micro)', color: 'oklch(0.50 0.16 40)', marginTop: 4, display: 'flex', alignItems: 'flex-start', gap: 5 }}>
                <span>⚠</span>
                <span>
                  {tOr('panel.footer.input_files_required_prefix', 'Input files required:')}{' '}
                  <strong>{[...missingFileInputs, ...missingClinicHard].map((p: any) => p.label || p.name).join(', ')}</strong>
                  {' '}{tOr('panel.footer.input_files_required_suffix', '— attach them with the file button in chat')}
                </span>
              </div>
            ) : (isPrereqBlocked && !prereqChecklist?.overrideAllowed) ? (
              <div style={{ fontSize: 'var(--fs-micro)', color: 'oklch(0.50 0.16 40)', marginTop: 4, display: 'flex', alignItems: 'center', gap: 5 }}>
                <span>⚠</span>
                <span>{tOr('panel.footer.prereqs_not_met', 'Prerequisites not met — see checklist above')}</span>
              </div>
            ) : null
          )}
          {canResumeFailed && (
            <button
              type="button"
              data-testid="button-start-over-failed"
              disabled={isLicenseBlocked || isAutofixActive}
              onClick={() => { analytics.track('run_again_clicked', { source: 'panel' }); handleExecute(); }}
              title={t('panel.footer.start_over_tip')}
              style={{ marginLeft: 8, fontSize: 'var(--fs-micro)', color: 'var(--bm-text-dim, oklch(0.55 0.01 260))', background: 'transparent', border: 'none', cursor: isLicenseBlocked ? 'not-allowed' : 'pointer', textDecoration: 'underline', opacity: isLicenseBlocked ? 0.5 : 1 }}
            >
              {t('panel.footer.start_over')}
            </button>
          )}
          {showingSubmittedParams && (status === 'completed' || status === 'failed') && (
            <button type="button" data-testid="button-reset-params-to-defaults" onClick={() => { analytics.track('reset_to_defaults_clicked'); resetToDefaults(); }} title={t('panel.footer.reset_defaults_tip')} style={{ marginLeft: 8, fontSize: 'var(--fs-micro)', color: 'var(--bm-text-dim, oklch(0.55 0.01 260))', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}>{t('panel.footer.reset_defaults')}</button>
          )}
        </div>
        <div className="run-foot-meta">
          {status === 'paused' && onResume && (
            <button className="linkish" data-testid="button-resume-workflow-panel" onClick={onResume}>
              {tOr('panel.resume', 'Resume')}
            </button>
          )}
          {usageMeter && usageMeter.used > 0 && (status === 'idle' || status === 'pending_review') && (
            <span data-testid="usage-meter" style={{ fontSize: 'var(--fs-micro)' }}>
              {tOr('panel.vcpu_hrs', '{{used}} / {{limit}} vCPU-hrs', { used: usageMeter.used.toFixed(1), limit: usageMeter.limit })}
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
          toast({ title: tOr('panel.toast_selected', '"{{name}}" selected', { name }), description: tOr('panel.toast_assigned', 'Assigned to {{label}}.', { label: browsingForParam.label }) });
          setBrowsingForParam(null);
        }}
      />
    </div>
  );
}
