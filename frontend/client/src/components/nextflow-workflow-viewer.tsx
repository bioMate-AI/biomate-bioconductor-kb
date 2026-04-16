import React, { useState, useEffect, useRef } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { emitUxEvent } from "@/lib/ux-telemetry";
import { Badge } from "@/components/ui/badge";
import { PhaseCard } from "./phase-card";
import { ParameterGroup } from "./parameter-group";
import { StepOutputPreview } from "./step-output-preview";
import { StepAdjustModal } from "./step-adjust-modal";
import { Button } from "@/components/ui/button";
import { Loader2, CheckCircle2, XCircle, AlertTriangle, FlaskConical, Download, Eye, Pause, Play, RotateCcw, Square, ChevronDown, ChevronRight, Settings2, ShieldCheck, Activity, Clock } from "lucide-react";
import { ReportConfusionButton } from "./feedback/report-confusion-button";
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { ChatOutputAttachments } from "./chat-output-attachments";
import { FindingsCard } from "./findings-card";
import type { PrereqChecklist } from "@/lib/prereq-normalizer";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { GalaxyDatasetBrowser } from "./galaxy-dataset-browser";
import { useToast } from "@/hooks/use-toast";

interface NextflowWorkflowViewerProps {
  workflowId?: string;
  invocationId?: string;
  executionBlockedReason?: string;
  prereqChecklist?: PrereqChecklist;
  workflowDefinition?: any; // Nextflow definition
  initialParams?: any;
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
  executionEngine?: string;
  /** Execution metrics from status API (includes perStepLlmCost). */
  executionMetrics?: {
    runtime?: { totalSeconds?: number; perStepSeconds?: Record<string, number> };
    perStepLlmCost?: Record<string, number | null>;
    [key: string]: any;
  };
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
    <div data-testid="download-commands-panel" className="rounded-md border border-muted p-4 space-y-3">
      <h4 className="text-sm font-semibold flex items-center gap-2">
        <Download className="h-4 w-4" />
        Output Files
      </h4>
      <div className="space-y-1">
        {downloadableFiles.map((f) => (
          <a
            key={f.name}
            href={f.download_url!}
            download={f.name}
            className="flex items-center justify-between gap-2 text-xs bg-muted rounded px-2 py-1 hover:bg-muted/80 group"
          >
            <span className="font-mono truncate max-w-[260px]">{f.name}</span>
            <span className="text-muted-foreground shrink-0 flex items-center gap-1">
              {formatFileSize(f.size)}
              <Download className="h-3 w-3 opacity-0 group-hover:opacity-100 transition-opacity" />
            </span>
          </a>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Track 3C: Reproducibility export button
// ---------------------------------------------------------------------------
function ReproducibilityExportButton({ runId }: { runId: string }) {
  const [loading, setLoading] = React.useState(false);
  const [exported, setExported] = React.useState(false);

  const handleExport = async () => {
    setLoading(true);
    try {
      const resp = await fetch(`/api/workflows/runs/${runId}/reproducibility`);
      if (!resp.ok) {
        console.error('[Reproducibility] fetch failed:', resp.status);
        return;
      }
      const data = await resp.json();

      // Concatenate all files into a single downloadable text bundle
      const bundle = Object.entries(data.files as Record<string, string>)
        .map(([name, content]) => `${'='.repeat(60)}\n${name}\n${'='.repeat(60)}\n${content}\n`)
        .join('\n');

      const blob = new Blob([bundle], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `biomate_reproducibility_${runId.slice(-8)}.txt`;
      a.click();
      URL.revokeObjectURL(url);
      setExported(true);
    } catch (err) {
      console.error('[Reproducibility]', err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <button
      onClick={handleExport}
      disabled={loading}
      data-testid="reproducibility-export-button"
      className="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1 mt-2 underline-offset-2 hover:underline"
    >
      {loading ? (
        <span className="h-3 w-3 animate-spin rounded-full border border-current border-t-transparent inline-block" />
      ) : exported ? (
        <span>&#10003;</span>
      ) : (
        <span>&#8595;</span>
      )}
      {exported ? 'Downloaded' : 'Export for reproducibility'}
    </button>
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

export function NextflowWorkflowViewer({
  workflowId,
  invocationId,
  executionBlockedReason,
  prereqChecklist,
  workflowDefinition, 
  initialParams, 
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
  executionMetrics,
}: NextflowWorkflowViewerProps) {
  const { toast } = useToast();
  const [params, setParams] = useState<Record<string, any>>(
    initialParams || workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {}
  );
  // Tracks param keys the user has explicitly overridden via EditableParamRow.
  // Stored as a ref (not state) so the useEffect sees the live value without needing
  // it in the dependency array, and without triggering extra re-renders.
  const userOverriddenParams = useRef<Set<string>>(new Set());
  const [logs, setLogs] = useState<string[]>([]);
  const [lastUpdateAt, setLastUpdateAt] = useState<Date>(new Date());
  const [previewFile, setPreviewFile] = useState<{ name: string; path: string; extension: string } | null>(null);
  const [adjustStep, setAdjustStep] = useState<{ id: string; name: string; processName?: string; parameters?: Record<string, any> } | null>(null);
  // When user reruns from a step, track the new runId so the viewer polls the right run
  const [rerunRunId, setRerunRunId] = useState<string | null>(null);
  const activeRunId = rerunRunId ?? runId;

  // QC governance settings
  const [qcSettingsOpen, setQcSettingsOpen] = useState(false);
  const [pauseAtQcFailures, setPauseAtQcFailures] = useState(true);
  const [qcProfile, setQcProfile] = useState('');
  const [availableQcProfiles, setAvailableQcProfiles] = useState<Array<{ id: string; description: string; domain_hint: string; overrides: Record<string, number> }>>([]);
  const [qcDefaults, setQcDefaults] = useState<Record<string, { bound: number; direction: string; rationale?: string }>>({});
  const [qcOverrides, setQcOverrides] = useState<Record<string, number>>({});

  // C3: validate environment state
  const [validateStatus, setValidateStatus] = useState<'idle' | 'running' | 'pass' | 'fail' | 'timeout' | 'skipped'>('idle');
  const [validateLog, setValidateLog] = useState<string[]>([]);
  const [validateLogOpen, setValidateLogOpen] = useState(false);

  const [browsingForParam, setBrowsingForParam] = useState<{ id: string; label: string } | null>(null);
  const [sessionDatasets, setSessionDatasets] = useState<Array<{ id: string; name: string; file_type?: string; file_path?: string | null; source_url?: string | null; galaxy_dataset_id?: string }>>([]);

  // Lazy-load workflow phase steps when workflowDefinition has a nextflow_path
  // but steps is empty (e.g. sessions created before steps parsing was deployed).
  const [lazySteps, setLazySteps] = useState<Record<string, any> | null>(null);
  useEffect(() => {
    const nfPath = workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath;
    const existingSteps = workflowDefinition?.steps;
    const hasSteps = existingSteps && typeof existingSteps === 'object' && Object.keys(existingSteps).length > 0;
    if (!hasSteps && nfPath) {
      fetch(`/api/nextflow/steps?nextflow_path=${encodeURIComponent(nfPath)}`)
        .then(r => r.ok ? r.json() : null)
        .then(data => { if (data?.steps && Object.keys(data.steps).length > 0) setLazySteps(data.steps); })
        .catch(() => {});
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

  // Input data analysis state
  type InputRecommendation = {
    parameter: string;
    fix_type: string;
    current_value: any;
    recommended_value: any;
    reason: string;
    risk_level: 'low' | 'medium' | 'high';
    auto_apply: boolean;
  };
  const [inputAnalysis, setInputAnalysis] = useState<{
    recommendations: InputRecommendation[];
    critical_count: number;
    auto_apply_count: number;
  } | null>(null);
  const [inputAnalysisLoading, setInputAnalysisLoading] = useState(false);
  const [inputAnalysisOpen, setInputAnalysisOpen] = useState(false);

  const handleAnalyzeInputs = async () => {
    setInputAnalysisLoading(true);
    setInputAnalysisOpen(true);
    try {
      const resp = await fetch('/api/workflows/analyze-inputs', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          workflow_id: workflowId,
          workflow_name: workflowDefinition?.name || workflowDefinition?.workflow_name,
          parameters: params,
        }),
      });
      const data = await resp.json();
      setInputAnalysis(data);
      // Auto-apply low-risk recommendations silently
      if (data.recommendations) {
        for (const rec of data.recommendations as InputRecommendation[]) {
          if (rec.auto_apply && rec.risk_level === 'low' && rec.recommended_value != null) {
            setParams((prev: any) => ({ ...prev, [rec.parameter]: rec.recommended_value }));
          }
        }
      }
    } catch {
      setInputAnalysis({ recommendations: [], critical_count: 0, auto_apply_count: 0 });
    } finally {
      setInputAnalysisLoading(false);
    }
  };

  const handleValidateEnvironment = async () => {
    const nfPath = workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath || '';
    if (!nfPath) return;
    setValidateStatus('running');
    setValidateLog([]);
    setValidateLogOpen(false);
    try {
      const resp = await fetch('/api/workflows/validate_profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nextflow_path: nfPath, profile: 'test', timeout_seconds: 120 }),
      });
      const data = await resp.json();
      setValidateStatus(data.status ?? 'fail');
      setValidateLog(data.log_tail ?? []);
      if (data.status === 'fail' || data.status === 'timeout') setValidateLogOpen(true);
    } catch {
      setValidateStatus('fail');
      setValidateLog(['Network error — could not reach backend']);
      setValidateLogOpen(true);
    }
  };

  const [stepExecutionById, setStepExecutionById] = useState<Record<string, StepExecutionState>>({});
  const [skippedPhaseIds, setSkippedPhaseIds] = useState<Set<string>>(new Set());
  const stepPollersRef = React.useRef<Record<string, ReturnType<typeof setInterval>>>({});

  // QC gate inline panel state (SSE-triggered)
  const [showQcInline, setShowQcInline] = useState(false);
  const [qcGateData, setQCGateData] = useState<QCGateData | null>(null);
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
    if (status === "completed") {
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
      });
    }
  };

  const handleRetryWithSuggestions = async () => {
    if (!qcGateData) return;
    setIsApplyingSuggestions(true);
    try {
      for (const suggestion of qcGateData.suggestions) {
        if (onParameterChange) {
          onParameterChange(suggestion.parameter, suggestion.suggestedValue);
        }
        setParams((prev: Record<string, any>) => ({ ...prev, [suggestion.parameter]: suggestion.suggestedValue }));
      }
      setShowQcInline(false);
      setQCGateData(null);
      if (onExecute) onExecute(params);
    } catch (err) {
      console.error('[QC Gate NFViewer] Failed to apply suggestions:', err);
    } finally {
      setIsApplyingSuggestions(false);
    }
  };

  const handleProceedAnyway = () => {
    console.log("[QC Gate NFViewer] User chose to proceed despite QC failures");
    setShowQcInline(false);
    setQCGateData(null);
  };

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

  const [showResults, setShowResults] = useState(status === 'completed');
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
  const isGlobalExecutionActive = status === "running" || status === "paused";
  const isAutofixActive =
    autofix?.active === true ||
    ["analyzing", "fixing", "restarting"].includes(autofix?.state || "");

  useEffect(() => {
    if (status === 'completed') {
      setShowResults(true);
    }
  }, [status]);

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

    const es = new EventSource(`/api/workflows/${invocationId}/events`);

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
        setQCGateData(gateData);
        setShowQcInline(true);
      } catch (err) {
        console.error("[QC Gate NFViewer] Failed to parse event:", err);
      }
    });

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
    <div className="space-y-6 p-4" data-testid="workflow-artifact-panel">
      <DownloadOutcomePrompt
        open={downloadAllPromptOpen}
        onOpenChange={setDownloadAllPromptOpen}
        invocationId={invocationId}
        sessionId={sessionId}
        runId={runId}
        isDownloadAll={true}
      />

      {/* QC Gate Inline Review Panel — appears when backend fires a qc_gate_triggered SSE event */}
      {showQcInline && qcGateData && (
        <div
          data-testid="qc-gate-inline"
          className="rounded-lg border border-amber-200 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/30 p-3"
        >
          <div className="flex items-start gap-2 mb-2">
            <AlertTriangle className="h-4 w-4 text-amber-600 dark:text-amber-400 mt-0.5 shrink-0" />
            <div>
              <p className="font-semibold text-sm text-amber-800 dark:text-amber-300">
                QC Gate — {
                  qcGateData.processName.includes(":")
                    ? qcGateData.processName.split(":").pop()?.replace(/_/g, " ")
                    : qcGateData.processName.replace(/_/g, " ")
                } — Review Required
              </p>
              {qcGateData.failures.length > 0 && (
                <p className="text-xs text-amber-700 dark:text-amber-400 mt-0.5">
                  {typeof qcGateData.failures[0] === 'string'
                    ? qcGateData.failures[0]
                    : (qcGateData.failures[0] as QCGateFailure).message}
                </p>
              )}
            </div>
          </div>
          {qcGateData.suggestions.length > 0 && (
            <div className="mb-2 space-y-1">
              {qcGateData.suggestions.map((s, i) => (
                <div key={i} className="text-xs text-amber-700 dark:text-amber-400 flex items-center gap-1">
                  <span>•</span>
                  <span>{s.parameter}: {JSON.stringify(s.currentValue)} → {JSON.stringify(s.suggestedValue)}</span>
                </div>
              ))}
            </div>
          )}
          <div className="flex gap-2 flex-wrap">
            {qcGateData.suggestions.length > 0 && (
              <button
                data-testid="qc-gate-apply"
                className="rounded bg-amber-600 text-white px-3 py-1.5 text-xs hover:bg-amber-700 disabled:opacity-50"
                onClick={() => { void handleRetryWithSuggestions(); }}
                disabled={isApplyingSuggestions}
              >
                {isApplyingSuggestions ? "Applying…" : "Apply suggestions"}
              </button>
            )}
            <button
              data-testid="qc-gate-keep"
              className="rounded border border-amber-300 dark:border-amber-700 px-3 py-1.5 text-xs hover:bg-amber-100 dark:hover:bg-amber-900/30"
              onClick={handleProceedAnyway}
            >
              Keep current
            </button>
            <button
              data-testid="qc-gate-cancel-run"
              className="rounded border border-red-300 dark:border-red-700 text-red-600 dark:text-red-400 px-3 py-1.5 text-xs hover:bg-red-50 dark:hover:bg-red-950/30"
              onClick={handleCancelWorkflow}
            >
              Cancel run
            </button>
          </div>
        </div>
      )}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>{workflowDefinition?.name || 'Untitled'}</span>
            <div className="flex items-center gap-2">
                {workflowDefinition?.qc_profile && (
                  <Badge variant="outline" className="text-xs font-normal text-emerald-700 border-emerald-400/50 bg-emerald-50/40 dark:bg-emerald-950/20">
                    QC: {workflowDefinition.qc_profile.replace(/_/g, '\u00A0')}
                  </Badge>
                )}
                {effectiveProgress > 0 && <span className="text-sm text-muted-foreground">{effectiveProgress}%</span>}
                <Badge variant={status === 'running' ? 'secondary' : 'outline'} data-testid="workflow-overall-status-badge" data-status={status}>
                {status.toUpperCase()}
                </Badge>
            </div>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {/* Completion banner — shown when workflow reaches terminal success state */}
          {status === 'completed' && (
            <div
              data-testid="workflow-completion-banner"
              className="mb-4 flex items-center gap-2 rounded-md border border-green-400/50 bg-green-50/60 px-3 py-2 text-sm text-green-800 dark:border-green-700/50 dark:bg-green-950/30 dark:text-green-300"
            >
              <CheckCircle2 className="h-4 w-4 shrink-0 text-green-600 dark:text-green-400" />
              <span>Workflow completed successfully. View Results and Download All are now available.</span>
            </div>
          )}


          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="md:col-span-1 space-y-4">
              <h3 className="text-lg font-semibold">Parameters</h3>
              {/* Format mismatch warning — shown when uploaded file type doesn't match workflow input */}
              {(() => {
                const allParams: any[] = [
                  ...(workflowDefinition?.required_params || []),
                  ...(workflowDefinition?.optional_params || []),
                ];
                const mismatch = allParams.find((p: any) => p?.format_mismatch_warning);
                if (!mismatch) return null;
                return (
                  <div className="flex items-start gap-2 rounded-md border border-amber-300 bg-amber-50 dark:bg-amber-950/20 p-2.5 text-xs text-amber-800 dark:text-amber-300" data-testid="format-mismatch-warning">
                    <span className="mt-0.5">⚠️</span>
                    <span>{mismatch.format_mismatch_warning}</span>
                  </div>
                );
              })()}
              {renderedParameters.length === 0 ? (
                <p className="text-xs text-muted-foreground px-1">No editable parameters detected for this workflow.</p>
              ) : (() => {
                // Group params by their schema group label; fall back to a single group.
                const groups = new Map<string, typeof renderedParameters>();
                for (const p of renderedParameters) {
                  const g = p.group || 'Parameters';
                  if (!groups.has(g)) groups.set(g, []);
                  groups.get(g)!.push(p);
                }
                // Within each group: required first, then has-default, then optional
                const sortGroup = (ps: typeof renderedParameters) => [
                  ...ps.filter(p => p.required && (p.value === '' || p.value == null)),
                  ...ps.filter(p => p.required && p.value !== '' && p.value != null),
                  ...ps.filter(p => !p.required && p.defaultValue != null),
                  ...ps.filter(p => !p.required && p.defaultValue == null),
                ];
                // Always open the first group; collapse the rest by default
                let firstGroup = true;
                return Array.from(groups.entries()).map(([groupTitle, groupParams]) => {
                  const open = firstGroup;
                  firstGroup = false;
                  const sorted = sortGroup(groupParams);
                  const requiredCount = sorted.filter(p => p.required).length;
                  const desc = requiredCount > 0
                    ? `${requiredCount} required · ${sorted.length - requiredCount} optional`
                    : `${sorted.length} parameter${sorted.length !== 1 ? 's' : ''}`;
                  return (
                    <ParameterGroup
                      key={groupTitle}
                      id={`params-${groupTitle}`}
                      title={groupTitle}
                      description={desc}
                      parameters={sorted}
                      onChange={handleParamChange}
                      onBrowseDataset={(paramId, paramLabel) => setBrowsingForParam({ id: paramId, label: paramLabel })}
                      defaultOpen={open}
                    />
                  );
                });
              })()}
              {hasUnfilledRequired && (
                <p className="text-xs text-amber-700 dark:text-amber-400">
                  Fill in all required fields (*) before running.
                </p>
              )}

              {/* Input Data Analysis panel */}
              {(status === 'idle' || status === 'pending_review') && renderedParameters.length > 0 && (
                <div className="rounded-md border border-border" data-testid="input-analysis-section">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between p-3 text-sm font-medium"
                    onClick={() => {
                      if (!inputAnalysis && !inputAnalysisLoading) {
                        handleAnalyzeInputs();
                      } else {
                        setInputAnalysisOpen(prev => !prev);
                      }
                    }}
                    aria-expanded={inputAnalysisOpen}
                    data-testid="button-analyze-inputs"
                  >
                    <span className="flex items-center gap-1.5 text-xs">
                      {inputAnalysisLoading ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      ) : inputAnalysis ? (
                        inputAnalysis.recommendations.length === 0 ? (
                          <CheckCircle2 className="h-3.5 w-3.5 text-green-600" />
                        ) : (
                          <AlertTriangle className="h-3.5 w-3.5 text-amber-600" />
                        )
                      ) : (
                        <Activity className="h-3.5 w-3.5" />
                      )}
                      {inputAnalysisLoading
                        ? 'Analyzing inputs…'
                        : inputAnalysis
                        ? inputAnalysis.recommendations.length === 0
                          ? 'All inputs look good'
                          : `Input analysis — ${inputAnalysis.recommendations.length} suggestion${inputAnalysis.recommendations.length !== 1 ? 's' : ''}`
                        : 'Analyze inputs'}
                    </span>
                    {inputAnalysis && (
                      inputAnalysisOpen
                        ? <ChevronDown className="h-3.5 w-3.5" />
                        : <ChevronRight className="h-3.5 w-3.5" />
                    )}
                  </button>

                  {inputAnalysisOpen && inputAnalysis && inputAnalysis.recommendations.length > 0 && (
                    <div className="border-t border-border p-3 space-y-2">
                      {inputAnalysis.recommendations.map((rec, idx) => {
                        const riskColor =
                          rec.risk_level === 'high'
                            ? 'text-destructive'
                            : rec.risk_level === 'medium'
                            ? 'text-amber-600'
                            : 'text-green-700 dark:text-green-400';
                        const applied = rec.auto_apply && rec.risk_level === 'low';
                        return (
                          <div
                            key={idx}
                            className="flex flex-col gap-1 rounded border border-border/60 bg-muted/30 p-2 text-xs"
                            data-testid={`input-analysis-rec-${idx}`}
                          >
                            <div className="flex items-center justify-between gap-2">
                              <span className="font-mono font-medium truncate">{rec.parameter}</span>
                              <span className={`shrink-0 text-[10px] font-semibold uppercase ${riskColor}`}>
                                {rec.risk_level}
                              </span>
                            </div>
                            <p className="text-muted-foreground">{rec.reason}</p>
                            {rec.recommended_value != null && (
                              <div className="flex items-center justify-between gap-2 mt-0.5">
                                <span className="text-muted-foreground truncate">
                                  Recommended: <span className="font-mono text-foreground">{String(rec.recommended_value)}</span>
                                </span>
                                {!applied && (
                                  <button
                                    type="button"
                                    className="shrink-0 rounded border border-primary/40 px-2 py-0.5 text-[10px] text-primary hover:bg-primary/10"
                                    onClick={() => {
                                      setParams((prev: any) => ({ ...prev, [rec.parameter]: rec.recommended_value }));
                                    }}
                                  >
                                    Apply
                                  </button>
                                )}
                                {applied && (
                                  <span className="shrink-0 text-[10px] text-green-600">auto-applied</span>
                                )}
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}

              {/* Uploaded dataset selection — shown when session has files */}
              {sessionDatasets.length > 0 && (
                <div className="rounded-md border border-border p-3 space-y-2" data-testid="session-dataset-panel">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Uploaded files</p>
                  {sessionDatasets.map(ds => {
                    // Find the first file-type param that has no value yet
                    const fileParam = renderedParameters.find(p =>
                      (p.type === 'file' || p.type === 'text') && (!p.value || p.value === '')
                    );
                    return (
                      <div key={ds.id} className="flex items-center justify-between gap-2 text-xs">
                        <span className="truncate text-foreground/80" title={ds.name}>{ds.name}</span>
                        <Button
                          variant="outline"
                          size="sm"
                          className="h-6 text-[10px] px-2 shrink-0"
                          onClick={() => {
                            const path = ds.file_path || ds.source_url || ds.id;
                            if (fileParam) {
                              handleParamChange(fileParam.id, path);
                            } else if (renderedParameters.length > 0) {
                              handleParamChange(renderedParameters[0].id, path);
                            }
                          }}
                        >
                          Use
                        </Button>
                      </div>
                    );
                  })}
                  <button
                    type="button"
                    className="text-xs text-primary hover:underline"
                    onClick={() => {
                      const fileParam = renderedParameters.find(p => p.type === 'file' || p.type === 'text');
                      if (fileParam) setBrowsingForParam({ id: fileParam.id, label: fileParam.label });
                    }}
                  >
                    Browse all datasets…
                  </button>
                </div>
              )}

              <div className="space-y-2" data-testid="workflow-run-controls">
                {/* C3: Validate environment button — only show for Nextflow workflows */}
                {(workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath) && (status === 'idle' || status === 'pending_review') && (
                  <div className="space-y-1">
                    <Button
                      variant="outline"
                      size="sm"
                      className="w-full text-xs"
                      data-testid="button-validate-environment"
                      onClick={handleValidateEnvironment}
                      disabled={validateStatus === 'running'}
                    >
                      {validateStatus === 'running' ? (
                        <><Loader2 className="mr-1.5 h-3 w-3 animate-spin" />Validating environment…</>
                      ) : validateStatus === 'pass' ? (
                        <><CheckCircle2 className="mr-1.5 h-3 w-3 text-green-600" />Environment validated</>
                      ) : validateStatus === 'fail' ? (
                        <><XCircle className="mr-1.5 h-3 w-3 text-destructive" />Validation failed — see log</>
                      ) : validateStatus === 'timeout' ? (
                        <><AlertTriangle className="mr-1.5 h-3 w-3 text-amber-500" />Validation timed out</>
                      ) : (
                        <><ShieldCheck className="mr-1.5 h-3 w-3" />Validate Environment</>
                      )}
                    </Button>
                    {validateLog.length > 0 && (
                      <div>
                        <button
                          type="button"
                          onClick={() => setValidateLogOpen(v => !v)}
                          className="text-xs text-muted-foreground underline underline-offset-2"
                        >
                          {validateLogOpen ? 'Hide' : 'Show'} log ({validateLog.length} lines)
                        </button>
                        {validateLogOpen && (
                          <pre className="mt-1 max-h-32 overflow-auto rounded bg-muted/50 p-2 text-[10px] leading-snug text-foreground/80">
                            {validateLog.join('\n')}
                          </pre>
                        )}
                      </div>
                    )}
                  </div>
                )}
                <Button
                  className="w-full"
                  data-testid="button-run-workflow-panel"
                  onClick={handleExecute}
                  disabled={status === 'running' || !!executionBlockedReason || isPrereqBlocked || isAutofixActive}
                >
                  {status === 'running' ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : 'Confirm and Run Workflow'}
                </Button>

                {/* Cost estimate badge commented out — not accurate enough to show users yet.
                    Actual cost goes on the per-user billing page.
                {workflowDefinition?.nextflow_path && (status === 'idle' || status === 'failed') && (
                  <CostEstimateBadge
                    nextflowPath={workflowDefinition.nextflow_path}
                  />
                )} */}
                {usageMeter && usageMeter.used > 0 && (status === 'idle' || status === 'pending_review') && (
                  <span data-testid="usage-meter" className="text-xs text-muted-foreground">
                    {usageMeter.used.toFixed(1)} / {usageMeter.limit} vCPU-hrs
                  </span>
                )}
                <div className="grid grid-cols-2 gap-2">
                  <Button
                    variant="outline"
                    data-testid="button-pause-workflow-panel"
                    onClick={onPause}
                    disabled={status !== 'running' || !onPause}
                  >
                    <Pause className="mr-2 h-4 w-4" />
                    {executionEngine === 'nextflow' ? 'Detach' : 'Pause'}
                  </Button>
                  <Button
                    variant="outline"
                    data-testid="button-resume-workflow-panel"
                    onClick={onResume}
                    disabled={status !== 'paused' || !onResume}
                  >
                    <Play className="mr-2 h-4 w-4" />
                    {executionEngine === 'nextflow' ? 'Reconnect' : 'Resume'}
                  </Button>
                </div>
                {executionEngine === 'nextflow' && (status === 'running' || status === 'paused') && (
                  <p className="text-xs text-muted-foreground">Batch job continues running after detach.</p>
                )}
                <div className="grid grid-cols-2 gap-2">
                  <Button
                    variant="outline"
                    data-testid="button-restart-workflow-panel"
                    onClick={() => onExecute?.(params)}
                    disabled={status !== 'completed' && status !== 'failed'}
                  >
                    <RotateCcw className="mr-2 h-4 w-4" />
                    Restart
                  </Button>
                  <Button
                    variant="destructive"
                    data-testid="button-cancel-workflow-panel"
                    onClick={onCancel}
                    disabled={status !== 'running' && status !== 'paused'}
                  >
                    <Square className="mr-2 h-4 w-4" />
                    Cancel
                  </Button>
                </div>
              </div>

              {/* QC Settings — only shown when QC profiles are available or a QC gate event fired */}
              {(availableQcProfiles.length > 0 || qcGateData !== null) && (
                <div className="rounded-md border border-border" data-testid="qc-settings-section">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between p-3 text-sm font-medium"
                    onClick={() => setQcSettingsOpen(prev => !prev)}
                    aria-expanded={qcSettingsOpen}
                  >
                    <span className="flex items-center gap-1.5">
                      <Settings2 className="h-3.5 w-3.5" />
                      QC Settings
                      {Object.keys(qcOverrides).length > 0 && (
                        <Badge variant="secondary" className="ml-1 text-xs px-1 py-0">
                          {Object.keys(qcOverrides).length} edited
                        </Badge>
                      )}
                    </span>
                    {qcSettingsOpen ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                  </button>
                  {qcSettingsOpen && (
                    <div className="border-t border-border p-3 space-y-4 text-sm">
                      {/* Pause toggle */}
                      <div className="flex items-center justify-between">
                        <Label htmlFor="pause-qc-switch" className="text-xs">
                          Pause workflow when a QC gate fails
                        </Label>
                        <Switch
                          id="pause-qc-switch"
                          checked={pauseAtQcFailures}
                          onCheckedChange={setPauseAtQcFailures}
                          aria-label="Pause at QC failures"
                        />
                      </div>

                      {/* Threshold parameters — labeled, editable */}
                      {displayedQcThresholds.length > 0 && (
                        <div className="space-y-2">
                          <div className="flex items-center justify-between">
                            <Label className="text-xs text-muted-foreground">
                              Quality thresholds
                              {activeQcProfile && (
                                <span className="ml-1.5 text-[10px] bg-muted px-1.5 py-0.5 rounded font-normal">
                                  {activeQcProfile.id.replace(/_/g, ' ')}
                                </span>
                              )}
                            </Label>
                            {Object.keys(qcOverrides).length > 0 && (
                              <button
                                type="button"
                                className="text-[10px] text-muted-foreground hover:text-foreground"
                                onClick={() => setQcOverrides({})}
                              >
                                Reset all
                              </button>
                            )}
                          </div>
                          <div className="space-y-1.5">
                            {displayedQcThresholds.map(t => (
                              <div key={t.key} className="flex flex-col gap-0.5">
                                <div className="flex items-center gap-2">
                                  <span className="flex-1 text-xs truncate">
                                    {t.label}
                                    <span className="ml-1 text-[10px] text-muted-foreground">
                                      ({t.direction === 'min' ? '≥' : '≤'}{t.unit})
                                    </span>
                                  </span>
                                  <Input
                                    type="number"
                                    className={`h-6 w-20 text-xs px-1.5 py-0 text-right ${t.modified ? 'border-blue-400 bg-blue-50/30 dark:bg-blue-950/10' : ''}`}
                                    value={t.value}
                                    step="any"
                                    onChange={e => {
                                      const v = parseFloat(e.target.value);
                                      if (!isNaN(v)) setQcOverrides(prev => ({ ...prev, [t.key]: v }));
                                    }}
                                    onBlur={e => {
                                      const v = parseFloat(e.target.value);
                                      if (isNaN(v)) {
                                        setQcOverrides(prev => { const n = { ...prev }; delete n[t.key]; return n; });
                                      }
                                    }}
                                  />
                                  {t.modified && (
                                    <button
                                      type="button"
                                      className="text-[10px] text-muted-foreground hover:text-destructive shrink-0"
                                      title="Reset to default"
                                      onClick={() => setQcOverrides(prev => { const n = { ...prev }; delete n[t.key]; return n; })}
                                    >
                                      ×
                                    </button>
                                  )}
                                </div>
                                {t.rationale && (
                                  <p className="text-[10px] text-muted-foreground leading-snug pl-0.5 pr-20">
                                    {t.rationale}
                                  </p>
                                )}
                              </div>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )}

              {autofix && (
                <div
                  className="rounded-md border border-blue-300/50 bg-blue-50/40 p-3 text-xs dark:border-blue-900/60 dark:bg-blue-950/20"
                  data-testid="autofix-status-panel"
                >
                  <p className="font-semibold text-blue-800 dark:text-blue-200">Auto-fix status</p>
                  <p className="mt-1">
                    State: <span className="font-medium">{autofix.state || "unknown"}</span>
                  </p>
                  {autofix.totalAttempts !== undefined && (
                    <p>Attempts: {autofix.totalAttempts}</p>
                  )}
                  {autofix.source && <p>Source: {autofix.source}</p>}
                  {autofix.message && (
                    <p className="mt-1 text-blue-700 dark:text-blue-300">{autofix.message}</p>
                  )}
                </div>
              )}
              {isAutofixActive && (
                <Alert className="border-blue-400/40 bg-blue-50/40 dark:bg-blue-950/20" data-testid="autofix-active-banner">
                  <Loader2 className="h-4 w-4 animate-spin text-blue-600" />
                  <AlertDescription className="text-xs">
                    Auto-fix is in progress ({autofix?.state || "fixing"}). Manual retry is temporarily disabled to avoid duplicate reruns.
                  </AlertDescription>
                </Alert>
              )}
              {/* Execution checklist — only shown when hard blockers exist (e.g. domain guard, license gate) */}
              {prereqChecklist && !prereqChecklist.canRun && prereqChecklist.items.some(i => i.status === 'missing' && i.id !== 'input_data' && i.id !== 'required_parameters') && (
                <div
                  className="space-y-2 rounded-md border border-destructive/40 bg-destructive/5 p-3"
                  data-testid="workflow-prereq-checklist"
                >
                  <p className="text-xs font-semibold text-destructive">
                    Cannot run — missing prerequisites:
                  </p>
                  <div className="space-y-1.5">
                    {prereqChecklist.items.filter(i => i.status === 'missing' && i.id !== 'input_data' && i.id !== 'required_parameters').map((item) => (
                      <div
                        key={item.id}
                        className="rounded border border-border/70 bg-background/70 px-2 py-1.5"
                        data-testid={`workflow-prereq-item-${item.id}`}
                      >
                        <span className="text-xs font-medium">{item.label}</span>
                        {item.reason && <p className="mt-1 text-xs text-muted-foreground">{item.reason}</p>}
                        {item.chatPrompt && onAdjustViaChat && (
                          <button
                            type="button"
                            data-testid={`prereq-chat-link-${item.id}`}
                            className="mt-1.5 text-xs text-primary hover:underline"
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
              {executionBlockedReason && (
                <div className="space-y-2">
                  <Alert className="border-amber-400/40 bg-amber-50/50 dark:bg-amber-950/20">
                    <AlertTriangle className="h-4 w-4 text-amber-600" />
                    <AlertDescription className="text-xs">
                      {executionBlockedReason}
                    </AlertDescription>
                  </Alert>
                  <Button
                    variant="outline"
                    className="w-full"
                    data-testid="button-confirm-low-confidence-run"
                    onClick={() => {
                      emitUxEvent('workflow.low_confidence_override_clicked', {
                        workflowId,
                        invocationId,
                        runId,
                      });
                      onExecute?.({
                        ...params,
                        __executionOverrides: {
                          allowLowConfidence: true,
                          overrideReason: executionBlockedReason,
                        },
                      });
                    }}
                    disabled={
                      status === 'running' ||
                      status === 'completed' ||
                      (isPrereqBlocked && !prereqChecklist?.overrideAllowed) ||
                      isAutofixActive
                    }
                  >
                    Confirm and Run Anyway
                  </Button>
                </div>
              )}
              <div className="space-y-2">
                <Button
                  variant="outline"
                  className="w-full"
                  onClick={() => setShowResults((prev) => !prev)}
                  disabled={!invocationId || status === 'failed'}
                  title={!invocationId ? "Run workflow to view results" : status === 'failed' ? "No results — workflow failed" : "View output results"}
                >
                  <Eye className="mr-2 h-4 w-4" />
                  {showResults ? 'Hide Results' : 'View Results'}
                </Button>
                {/* AI Analysis button — enabled only on completed runs with a runId */}
                <Button
                  variant="outline"
                  className="w-full"
                  data-testid="button-analyze-results"
                  disabled={status !== 'completed' || !runId || analysisState === 'loading'}
                  title={status !== 'completed' ? "Available after workflow completes" : "AI analysis of findings with citations"}
                  onClick={handleAnalyzeResults}
                >
                  {analysisState === 'loading' ? (
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  ) : (
                    <Activity className="mr-2 h-4 w-4" />
                  )}
                  {analysisState === 'loading' ? 'Analyzing…' : analysisState === 'done' ? 'Re-analyze Results' : 'Analyze Results'}
                </Button>
                <Button
                  variant="outline"
                  className="w-full"
                  data-testid="button-download-all-workflow-panel"
                  disabled={!invocationId || status === 'failed'}
                  title={!invocationId ? "Run workflow to enable download" : status === 'failed' ? "No outputs — workflow failed" : "Download all outputs"}
                  onClick={() => {
                    if (!invocationId || status === 'failed') return;
                    emitUxEvent('output.download_clicked', { invocationId, scope: 'all' });
                    window.open(`/api/invocations/${invocationId}/download-all`, '_blank');
                    setDownloadAllPromptOpen(true);
                  }}
                >
                  <Download className="mr-2 h-4 w-4" />
                  Download All
                </Button>
                {/* Download QC Audit Log — only shown when QC profiles are available or a QC gate fired */}
                {(availableQcProfiles.length > 0 || qcGateData !== null) && (
                  <Button
                    variant="outline"
                    className="w-full"
                    data-testid="button-download-qc-audit"
                    disabled={!invocationId || status === 'failed'}
                    title={!invocationId ? "Run workflow to enable" : status === 'failed' ? "No QC data — workflow failed" : "Download QC audit log"}
                    onClick={() => {
                      if (!invocationId || status === 'failed') return;
                      window.open(`/api/invocations/${invocationId}/qc-audit-download`, '_blank');
                    }}
                  >
                    <ShieldCheck className="mr-2 h-4 w-4" />
                    Download QC Audit Log
                  </Button>
                )}
                <Button
                  variant="outline"
                  className="w-full"
                  data-testid="button-download-methods-report"
                  data-invocation-id={invocationId || ''}
                  disabled={!invocationId || status === 'failed'}
                  title={!invocationId ? "Run workflow to enable" : status === 'failed' ? "No report — workflow failed" : "Download methods report"}
                  onClick={() => {
                    if (!invocationId || status === 'failed') return;
                    window.open(`/api/invocations/${invocationId}/methods-report`, '_blank');
                  }}
                >
                  <FlaskConical className="mr-2 h-4 w-4" />
                  Download Methods Report
                </Button>
              </div>
            </div>

            <div className="md:col-span-2 space-y-4">
              <h3 className="text-lg font-semibold">Execution Progress</h3>
              <p className="text-xs text-muted-foreground" data-testid="workflow-last-update">
                Last update: {lastUpdateAt.toLocaleTimeString()}
              </p>
              {/* Run context and Execution evidence — internal debugging info, hidden from users */}
              {/* <div className="rounded-md border border-muted bg-muted/30 p-3" data-testid="run-context-chip">...</div> */}
              {/* <div className="rounded-md border border-muted p-3 text-xs space-y-1" data-testid="workflow-execution-evidence">...</div> */}
              {/* Run metrics strip — execution time and cost */}
              {(nextflowStatus?.duration_s != null || nextflowStatus?.started_at != null) && (
                <div
                  className="rounded-md border border-muted p-3 text-xs space-y-1"
                  data-testid="run-metrics-strip"
                >
                  <div className="font-medium text-muted-foreground uppercase tracking-wide text-[10px]">Run metrics</div>
                  {nextflowStatus?.duration_s != null && (
                    <div data-testid="run-metric-duration">
                      <span className="text-muted-foreground">Wall time:</span>{" "}
                      <span className="font-mono" data-testid="run-metric-duration-value">
                        {nextflowStatus.duration_s < 60
                          ? `${nextflowStatus.duration_s}s`
                          : `${Math.floor(nextflowStatus.duration_s / 60)}m ${nextflowStatus.duration_s % 60}s`}
                      </span>
                    </div>
                  )}
                  {nextflowStatus?.started_at != null && (
                    <div data-testid="run-metric-started-at">
                      <span className="text-muted-foreground">Started:</span>{" "}
                      <span className="font-mono">
                        {new Date(nextflowStatus.started_at * 1000).toLocaleTimeString()}
                      </span>
                    </div>
                  )}
                  {nextflowStatus?.completed_at != null && (
                    <div data-testid="run-metric-completed-at">
                      <span className="text-muted-foreground">Ended:</span>{" "}
                      <span className="font-mono">
                        {new Date(nextflowStatus.completed_at * 1000).toLocaleTimeString()}
                      </span>
                    </div>
                  )}
                  {executionMetrics?.perStepLlmCost != null && (
                    <div data-testid="run-metric-per-step-costs">
                      <span className="text-muted-foreground">Step LLM costs:</span>{" "}
                      <span className="font-mono">
                        {Object.values(executionMetrics.perStepLlmCost).every(v => v === null)
                          ? "none"
                          : `$${Object.values(executionMetrics.perStepLlmCost)
                              .filter((v): v is number => v !== null)
                              .reduce((a, b) => a + b, 0)
                              .toFixed(4)}`}
                      </span>
                    </div>
                  )}
                </div>
              )}
              {/* Execution triage — internal debugging panel, hidden from users */}
              {/* <div className="rounded-md border border-muted p-3 text-xs space-y-2" data-testid="execution-triage-summary">...</div> */}
              {/* Live Nextflow process status — shown when trace data is available */}
              {Array.isArray(nextflowStatus?.processes) && nextflowStatus.processes.length > 0 && (
                <div className="mb-3 rounded-md border border-muted bg-muted/30 p-3" data-testid="nf-process-list">
                  <div className="flex items-center gap-1.5 mb-2">
                    <Activity className="h-3.5 w-3.5 text-muted-foreground" />
                    <span className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
                      Pipeline steps
                    </span>
                    <span className="ml-auto text-xs text-muted-foreground">
                      {nextflowStatus.processes.filter((p: any) => p.status === 'COMPLETED').length}
                      /{nextflowStatus.processes.length} completed
                    </span>
                  </div>
                  <div className="space-y-1">
                    {nextflowStatus.processes.map((proc: any, i: number) => {
                      const procStatus = String(proc.status || '').toUpperCase();
                      const label = String(proc.name || proc.process || proc.id || `Step ${i + 1}`)
                        .replace(/.*:/, '').replace(/\s*\(.*\)/, '').replace(/_/g, ' ');
                      return (
                        <div key={proc.id || i} className="flex items-center gap-2 text-xs">
                          {procStatus === 'COMPLETED' && <CheckCircle2 className="h-3 w-3 text-green-500 shrink-0" />}
                          {procStatus === 'RUNNING' && <Loader2 className="h-3 w-3 text-blue-500 animate-spin shrink-0" />}
                          {procStatus === 'FAILED' && <XCircle className="h-3 w-3 text-red-500 shrink-0" />}
                          {(procStatus === 'SUBMITTED' || procStatus === 'CACHED') && <Clock className="h-3 w-3 text-amber-500 shrink-0" />}
                          {!['COMPLETED','RUNNING','FAILED','SUBMITTED','CACHED'].includes(procStatus) && (
                            <div className="h-3 w-3 rounded-full border border-muted-foreground/40 shrink-0" />
                          )}
                          <span className={procStatus === 'RUNNING' ? 'text-foreground font-medium' : 'text-muted-foreground'}>
                            {label}
                          </span>
                          {procStatus === 'CACHED' && (
                            <span className="text-[10px] text-amber-600 bg-amber-50 dark:bg-amber-950/30 px-1 rounded">cached</span>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              <p className="text-xs text-muted-foreground mb-3 px-1" data-testid="workflow-capability-hint">
                You can{" "}
                <button className="underline hover:text-foreground" onClick={() => {}}>edit parameters</button>
                {" · "}
                <button className="underline hover:text-foreground" onClick={() => {}}>adjust QC thresholds</button>
                {" · "}
                <span>skip steps</span>
                {" · "}
                <span>preview outputs</span>
                {" · "}
                <span>continue in chat →</span>
              </p>

              <div className="space-y-2">
                <p className="text-xs text-muted-foreground" data-testid="workflow-step-controls-hint">
                  Run single steps for targeted checks. Finished or errored steps can be rerun repeatedly.
                </p>
                {updatedPhases.map((phase: any) => (
                  <PhaseCard
                    key={phase.id}
                    phase={phase}
                    onRun={() => handleRunStep(phase)}
                    runLabel={(phase.runCount ?? 0) > 0 ? "Rerun Step" : "Run Step"}
                    runDisabled={
                      !activeRunId ||
                      phase.isExecuting === true ||
                      !!executionBlockedReason ||
                      isPrereqBlocked ||
                      isAutofixActive ||
                      isGlobalExecutionActive
                    }
                    runLoading={phase.isExecuting === true}
                    runButtonTestId={`button-run-step-${phase.id}`}
                    outputFiles={phase.outputFiles}
                    onPreviewFile={(file) => setPreviewFile(file)}
                    onAdjustAndRerun={() => setAdjustStep({
                      id: phase.id,
                      name: phase.name,
                      processName: phase.processName,
                      parameters: phase.parameters as Record<string, any> | undefined,
                    })}
                    onSkip={() => handleSkipPhase(phase.id)}
                    runId={activeRunId || undefined}
                  />
                ))}
                <button
                  className="mt-3 w-full text-sm text-muted-foreground border border-dashed rounded-md py-2 hover:text-foreground hover:border-foreground transition-colors"
                  data-testid="button-suggest-step"
                  onClick={() => {
                    const lastStep = updatedPhases[updatedPhases.length - 1]?.name || "last step";
                    onAdjustViaChat?.(`Add a step after "${lastStep}" that `);
                  }}
                >
                  + Suggest step
                </button>
              </div>
              
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
<div className="mt-4 bg-muted p-4 rounded-md h-48 overflow-y-auto font-mono text-xs">
                {logs.length === 0 ? (
                  status === 'running'
                    ? <span className="text-muted-foreground flex items-center gap-1.5"><Loader2 className="h-3 w-3 animate-spin" />Waiting for logs...</span>
                    : <span className="text-muted-foreground">No logs available.</span>
                ) : logs.map((log, i) => (
                  <div key={i}>{log}</div>
                ))}
              </div>
              {status === 'running' && logs.length === 0 && (
                <p className="text-xs text-blue-700 dark:text-blue-300" data-testid="workflow-running-hint">
                  Workflow is running. Logs can take a short time to appear.
                </p>
              )}
              <div className="mt-2 flex justify-end">
                <ReportConfusionButton
                  runId={runId}
                  sessionId={sessionId}
                  workflowId={workflowId}
                  invocationId={invocationId}
                  context={{
                    executionStatus: status,
                    errorMessage,
                    workflowName: workflowDefinition?.name,
                    progress,
                    showResults,
                  }}
                  variant="ghost"
                  size="sm"
                />
              </div>
            </div>
          </div>

          {runId && (status === 'completed' || status === 'failed' || status === 'running') && (
            <div className="mt-4">
              <DownloadCommandsPanel runId={runId} />
              <ReproducibilityExportButton runId={runId} />
            </div>
          )}

          {/* D4: Error recovery card — shown when workflow has failed */}
          {status === 'failed' && (
            <div className="mt-4 rounded-lg border border-destructive/40 bg-destructive/5 p-4 space-y-3">
              <div className="flex items-center gap-2 text-destructive font-semibold text-sm">
                <span>⚠ Workflow Failed</span>
                {errorExplaining && <span className="text-muted-foreground font-normal text-xs">Analyzing error…</span>}
              </div>
              {errorExplanation ? (
                <>
                  <div className="space-y-1">
                    <p className="text-sm font-medium">What went wrong</p>
                    <p className="text-sm text-muted-foreground">{errorExplanation.human_summary}</p>
                  </div>
                  <div className="space-y-1">
                    <p className="text-sm font-medium">Suggested fix</p>
                    <p className="text-sm text-muted-foreground">{errorExplanation.suggested_fix}</p>
                  </div>
                  {errorExplanation.chat_prompt && (
                    <button
                      className="inline-flex items-center gap-2 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90 transition-colors"
                      onClick={() => {
                        setErrorExplanation(null);
                        onAdjustViaChat?.(errorExplanation.chat_prompt);
                      }}
                      data-testid="button-error-fix-chat"
                    >
                      Fix &amp; Retry via Chat
                    </button>
                  )}
                  <p className="text-[10px] text-muted-foreground/60">
                    Error type: {errorExplanation.error_type}
                    {errorExplanation.llm_used ? ' · AI-analyzed' : ' · pattern-matched'}
                  </p>
                </>
              ) : errorExplaining ? (
                <p className="text-xs text-muted-foreground">Analyzing error log…</p>
              ) : errorMessage ? (
                <p className="text-sm text-muted-foreground">{errorMessage}</p>
              ) : null}
            </div>
          )}

          {invocationId && showResults && (
            <div className="mt-6">
              <h3 className="text-lg font-semibold mb-3">Output Results</h3>
              {runtimeArtifacts.length > 0 && (
                <div
                  className="mb-3 rounded-md border border-blue-200/70 bg-blue-50/40 p-3 text-xs text-blue-900 dark:border-blue-900/60 dark:bg-blue-950/20 dark:text-blue-200"
                  data-testid="nextflow-runtime-artifacts"
                >
                  <div className="font-medium mb-1">
                    Runtime artifacts detected ({runtimeArtifacts.length})
                  </div>
                  <div className="space-y-0.5">
                    {runtimeArtifacts.slice(0, 6).map((artifactPath, idx) => (
                      <div key={`${artifactPath}-${idx}`} className="truncate font-mono">
                        {artifactPath}
                      </div>
                    ))}
                  </div>
                  <div className="mt-2 text-[11px] text-blue-700 dark:text-blue-300">
                    If the output cards are still empty, output processing may still be in progress.
                  </div>
                </div>
              )}
              <ChatOutputAttachments
                invocationId={invocationId}
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
            <div className="mt-6" data-testid="ai-analysis-panel">
              <h3 className="text-lg font-semibold mb-3 flex items-center gap-2">
                <Activity className="h-4 w-4 text-blue-600" />
                AI Findings Analysis
                {analysisState === 'done' && (
                  <span className="text-xs font-normal text-muted-foreground ml-1">· claude-sonnet-4-6</span>
                )}
              </h3>

              {analysisState === 'loading' && (
                <div className="flex items-center gap-2 text-sm text-muted-foreground py-4">
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Analyzing output files…
                </div>
              )}

              {analysisState === 'error' && (
                <div className="rounded-md border border-red-200 bg-red-50 dark:bg-red-950/20 p-3 text-sm text-red-800 dark:text-red-300">
                  {analysisError || 'Analysis failed. Try again.'}
                </div>
              )}

              {analysisState === 'done' && analysisResult && (
                <div className="space-y-4 text-sm">
                  {/* Summary */}
                  {analysisResult.summary && (
                    <div className="rounded-md border border-border bg-muted/30 p-3">
                      <p className="font-medium text-xs uppercase tracking-wide text-muted-foreground mb-1">Summary</p>
                      <p>{analysisResult.summary}</p>
                    </div>
                  )}

                  {/* Key Findings */}
                  {analysisResult.key_findings?.length > 0 && (
                    <div>
                      <p className="font-medium text-xs uppercase tracking-wide text-muted-foreground mb-2">Key Findings</p>
                      <div className="space-y-2">
                        {analysisResult.key_findings.map((f, i) => (
                          <div key={i} className="rounded-md border border-blue-200/60 bg-blue-50/30 dark:border-blue-900/40 dark:bg-blue-950/10 p-2.5">
                            <p className="font-medium text-blue-900 dark:text-blue-200">{f.finding}</p>
                            {f.significance && (
                              <p className="text-xs text-muted-foreground mt-0.5">{f.significance}</p>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Quality */}
                  {analysisResult.quality_assessment && (
                    <div>
                      <p className="font-medium text-xs uppercase tracking-wide text-muted-foreground mb-1">Quality Assessment</p>
                      <p className="text-muted-foreground">{analysisResult.quality_assessment}</p>
                    </div>
                  )}

                  {/* Next Steps */}
                  {analysisResult.next_steps?.length > 0 && (
                    <div>
                      <p className="font-medium text-xs uppercase tracking-wide text-muted-foreground mb-1">Recommended Next Steps</p>
                      <ol className="list-decimal list-inside space-y-1 text-muted-foreground">
                        {analysisResult.next_steps.map((step, i) => (
                          <li key={i}>{step}</li>
                        ))}
                      </ol>
                    </div>
                  )}

                  {/* Citations */}
                  {analysisResult.citations?.length > 0 && (
                    <div>
                      <p className="font-medium text-xs uppercase tracking-wide text-muted-foreground mb-2">Supporting References</p>
                      <div className="space-y-1.5">
                        {analysisResult.citations.map((c, i) => (
                          <div key={i} className="flex gap-2 text-xs">
                            <span className="shrink-0 font-medium text-foreground">{c.tool_or_resource}:</span>
                            <span className="text-muted-foreground">
                              {c.reference}
                              {c.relevance && <span className="ml-1 italic">— {c.relevance}</span>}
                            </span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Limitations */}
                  {analysisResult.limitations && (
                    <div className="rounded-md border border-amber-200/60 bg-amber-50/30 dark:border-amber-900/40 dark:bg-amber-950/10 p-2.5 text-xs text-amber-800 dark:text-amber-300">
                      <span className="font-medium">Limitations: </span>
                      {analysisResult.limitations}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>
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
