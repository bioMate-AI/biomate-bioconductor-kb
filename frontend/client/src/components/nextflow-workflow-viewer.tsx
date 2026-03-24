import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { emitUxEvent } from "@/lib/ux-telemetry";
import { Badge } from "@/components/ui/badge";
import { PhaseCard } from "./phase-card";
import { ParameterGroup } from "./parameter-group";
import { Button } from "@/components/ui/button";
import { Loader2, CheckCircle2, XCircle, AlertTriangle, FlaskConical, Lightbulb, Download, Eye, Pause, Play, RotateCcw, Square, ChevronDown, ChevronRight, Settings2, ShieldCheck } from "lucide-react";
import { ReportConfusionButton } from "./feedback/report-confusion-button";
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { ChatOutputAttachments } from "./chat-output-attachments";
import type { PrereqChecklist } from "@/lib/prereq-normalizer";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

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
  onRequestPrereqRecovery?: () => void;
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

function inferParamType(value: any): ViewerParameter['type'] {
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

function DownloadCommandsPanel({ runId }: { runId: string }) {
  const [data, setData] = useState<any>(null);

  useEffect(() => {
    fetch(`/api/workflows/runs/${runId}/download_commands`)
      .then(r => r.json())
      .then(d => setData(d))
      .catch(() => {});
  }, [runId]);

  if (!data?.download_commands) return null;

  const allOutputs: string = data.download_commands.all_outputs ?? '';
  if (!allOutputs) return null;

  return (
    <div data-testid="download-commands-panel" className="rounded-md border border-muted p-4 space-y-3">
      <h4 className="text-sm font-semibold flex items-center gap-2">
        <Download className="h-4 w-4" />
        Download Outputs
      </h4>
      <div className="space-y-1">
        <p className="text-xs text-muted-foreground">All outputs:</p>
        <code className="block text-xs font-mono bg-muted p-2 rounded break-all">{allOutputs}</code>
      </div>
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
  onExecute,
  onPause,
  onResume,
  onCancel,
  status = 'idle',
  errorMessage,
  progress = 0,
  onParameterChange,
  onRequestPrereqRecovery,
  sessionId,
  runId,
  autofix,
  nextflowStatus,
  executionEngine,
}: NextflowWorkflowViewerProps) {
  const [params, setParams] = useState<Record<string, any>>(
    initialParams || workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {}
  );
  const [logs, setLogs] = useState<string[]>([]);
  const [lastUpdateAt, setLastUpdateAt] = useState<Date>(new Date());

  // QC governance settings
  const [qcSettingsOpen, setQcSettingsOpen] = useState(false);
  const [pauseAtQcFailures, setPauseAtQcFailures] = useState(true);
  const [qcProfile, setQcProfile] = useState('');
  const [availableQcProfiles, setAvailableQcProfiles] = useState<Array<{ id: string; description: string; domain_hint: string }>>([]);
  const [qcOverrides, setQcOverrides] = useState<Record<string, number>>({});
  const [qcOverrideKey, setQcOverrideKey] = useState('');
  const [qcOverrideValue, setQcOverrideValue] = useState('');

  // C3: validate environment state
  const [validateStatus, setValidateStatus] = useState<'idle' | 'running' | 'pass' | 'fail' | 'timeout' | 'skipped'>('idle');
  const [validateLog, setValidateLog] = useState<string[]>([]);
  const [validateLogOpen, setValidateLogOpen] = useState(false);

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
  const stepPollersRef = React.useRef<Record<string, ReturnType<typeof setInterval>>>({});

  // QC gate inline panel state (SSE-triggered)
  const [showQcInline, setShowQcInline] = useState(false);
  const [qcGateData, setQCGateData] = useState<QCGateData | null>(null);
  const [isApplyingSuggestions, setIsApplyingSuggestions] = useState(false);;

  const phases = React.useMemo<ViewerPhase[]>(() => {
    if (workflowDefinition?.steps && typeof workflowDefinition.steps === "object") {
      return Object.entries(workflowDefinition.steps).map(([stepKey, rawStep], index) => {
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
    return [
      { id: "setup", name: "Setup & Input", status: "completed" },
      { id: "process", name: "Data Processing", status: "running" },
      { id: "analysis", name: "Statistical Analysis", status: "pending" },
      { id: "report", name: "Report Generation", status: "pending" },
    ];
  }, [workflowDefinition]);

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
    if (!phase.toolId) {
      setStepExecutionById((prev) => ({
        ...prev,
        [phase.id]: {
          ...(prev[phase.id] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
          phaseStatus: "failed",
          isExecuting: false,
          errorMessage: "Step is missing tool_id and cannot run individually.",
          runCount: prev[phase.id]?.runCount ?? 0,
        },
      }));
      return;
    }

    const startedAt = new Date().toISOString();
    emitUxEvent("workflow.run_clicked", {
      workflowId,
      stepId: phase.id,
      toolId: phase.toolId,
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
      const response = await fetch("/api/workflow/step/execute", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          step_id: phase.id,
          tool_id: phase.toolId,
          parameters: phase.parameters || {},
          inputs: phase.inputs || {},
        }),
      });
      if (!response.ok) {
        const message = await readApiErrorMessage(response);
        throw new Error(message);
      }

      const payload = await response.json();
      const backendState = normalizeBackendState(payload?.state || "queued");
      setStepExecutionById((prev) => ({
        ...prev,
        [phase.id]: {
          ...(prev[phase.id] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
          backendState,
          phaseStatus: mapBackendToPhaseStatus(backendState),
          jobId: payload?.job_id || prev[phase.id]?.jobId,
          isExecuting: !isTerminalBackendState(backendState),
        },
      }));
      beginStepStatusPolling(phase.id);
    } catch (error: any) {
      setStepExecutionById((prev) => ({
        ...prev,
        [phase.id]: {
          ...(prev[phase.id] || { runCount: 0, phaseStatus: "pending", isExecuting: false }),
          phaseStatus: "failed",
          backendState: "error",
          isExecuting: false,
          errorMessage: error?.message || "Step execution failed.",
        },
      }));
      clearStepPoller(phase.id);
    }
  }, [beginStepStatusPolling, clearStepPoller, invocationId, workflowId]);

  const updatedPhases = phases.map((phase, index) => {
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

    const stepExecution = stepExecutionById[phase.id];
    if (!stepExecution) {
      return { ...phase, status: derivedStatus };
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
    };
  });

  const handleParamChange = (id: string, value: any) => {
    setParams((prev: any) => ({ ...prev, [id]: value }));
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
      return { ...p, rationale: `${hint.toolName.toUpperCase()} recommendations — ${hint.rationale}`, autoFilled: false };
    });
  }, [workflowDefinition, params, toolHintMap]);

  const [showResults, setShowResults] = useState(status === 'completed');
  const [downloadAllPromptOpen, setDownloadAllPromptOpen] = useState(false);
  const isPrereqBlocked = !!prereqChecklist && !prereqChecklist.canRun;
  const isGlobalExecutionActive = status === "running" || status === "paused";
  const isAutofixActive =
    autofix?.active === true ||
    ["analyzing", "fixing", "restarting"].includes(autofix?.state || "");

  useEffect(() => {
    if (status === 'completed') {
      setShowResults(true);
    }
  }, [status]);

  useEffect(() => {
    setLastUpdateAt(new Date());
  }, [status, progress, errorMessage, nextflowStatus, stepExecutionById]);

  useEffect(() => {
    setParams(initialParams || workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {});
  }, [initialParams, workflowDefinition]);

  useEffect(() => {
    fetch('/api/qc/profiles')
      .then(r => r.ok ? r.json() : null)
      .then(data => { if (data?.profiles) setAvailableQcProfiles(data.profiles); })
      .catch(() => {});
  }, []);

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
      ? `Nextflow status: ${String(nextflowStatus.status)}`
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
            <span>Nextflow Workflow: {workflowDefinition?.name || 'Untitled'}</span>
            <div className="flex items-center gap-2">
                {workflowDefinition?.qc_profile && (
                  <Badge variant="outline" className="text-xs font-normal text-emerald-700 border-emerald-400/50 bg-emerald-50/40 dark:bg-emerald-950/20">
                    QC: {workflowDefinition.qc_profile.replace(/_/g, '\u00A0')}
                  </Badge>
                )}
                {effectiveProgress > 0 && <span className="text-sm text-muted-foreground">{effectiveProgress}%</span>}
                <Badge variant={status === 'running' ? 'secondary' : 'outline'}>
                {status.toUpperCase()}
                </Badge>
            </div>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {/* Scientific Rationale Panel — shown when Bioconductor KB has data */}
          {rationale && rationale.tools_used?.length > 0 && (
            <div className="mb-5 space-y-3">
              {/* When to use / Do not use */}
              {(rationale.when_to_use?.length > 0 || rationale.do_not_use_when?.length > 0) && (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  {rationale.when_to_use?.length > 0 && (
                    <Alert className="border-green-500/40 bg-green-50/40 dark:bg-green-950/10 py-2">
                      <CheckCircle2 className="h-3.5 w-3.5 text-green-600 mt-0.5" />
                      <AlertDescription className="text-xs">
                        <span className="font-semibold text-green-800 dark:text-green-300">When to use</span>
                        <ul className="mt-1 space-y-0.5 text-green-700 dark:text-green-400">
                          {rationale.when_to_use.map((uc: string, i: number) => (
                            <li key={i} className="leading-snug">• {uc}</li>
                          ))}
                        </ul>
                      </AlertDescription>
                    </Alert>
                  )}
                  {rationale.do_not_use_when?.length > 0 && (
                    <Alert className="border-red-400/40 bg-red-50/40 dark:bg-red-950/10 py-2">
                      <XCircle className="h-3.5 w-3.5 text-red-500 mt-0.5" />
                      <AlertDescription className="text-xs">
                        <span className="font-semibold text-red-700 dark:text-red-300">Do NOT use when</span>
                        <ul className="mt-1 space-y-0.5 text-red-600 dark:text-red-400">
                          {rationale.do_not_use_when.map((lim: string, i: number) => (
                            <li key={i} className="leading-snug">• {lim}</li>
                          ))}
                        </ul>
                      </AlertDescription>
                    </Alert>
                  )}
                </div>
              )}

              {/* Data requirements */}
              {rationale.data_requirements && Object.keys(rationale.data_requirements).length > 0 && (
                <Alert className="border-blue-400/40 bg-blue-50/40 dark:bg-blue-950/10 py-2">
                  <FlaskConical className="h-3.5 w-3.5 text-blue-600 mt-0.5" />
                  <AlertDescription className="text-xs">
                    <span className="font-semibold text-blue-800 dark:text-blue-300">Data requirements</span>
                    <ul className="mt-1 space-y-0.5 text-blue-700 dark:text-blue-400">
                      {Object.entries(rationale.data_requirements).slice(0, 3).map(([k, v]: [string, any]) => (
                        <li key={k} className="leading-snug">
                          <span className="font-medium">{k.replace(/_/g, ' ')}:</span> {String(v)}
                        </li>
                      ))}
                    </ul>
                  </AlertDescription>
                </Alert>
              )}

              {/* Common pitfalls */}
              {rationale.common_pitfalls?.length > 0 && (
                <Alert className="border-amber-400/40 bg-amber-50/40 dark:bg-amber-950/10 py-2">
                  <AlertTriangle className="h-3.5 w-3.5 text-amber-600 mt-0.5" />
                  <AlertDescription className="text-xs">
                    <span className="font-semibold text-amber-800 dark:text-amber-300">Common pitfalls</span>
                    <ul className="mt-1 space-y-1 text-amber-700 dark:text-amber-400">
                      {rationale.common_pitfalls.map((p: any, i: number) => (
                        <li key={i} className="leading-snug">
                          <span className="font-medium">{p.cause || p.error}</span>
                          {p.fix && <span className="text-amber-600 dark:text-amber-500"> → {p.fix}</span>}
                        </li>
                      ))}
                    </ul>
                  </AlertDescription>
                </Alert>
              )}

              {/* Parameter hints */}
              {rationale.parameter_hints?.length > 0 && (
                <Alert className="border-purple-400/40 bg-purple-50/40 dark:bg-purple-950/10 py-2">
                  <Lightbulb className="h-3.5 w-3.5 text-purple-600 mt-0.5" />
                  <AlertDescription className="text-xs">
                    <span className="font-semibold text-purple-800 dark:text-purple-300">Recommended parameters</span>
                    <ul className="mt-1 space-y-0.5 text-purple-700 dark:text-purple-400">
                      {rationale.parameter_hints.slice(0, 5).map((h: any, i: number) => (
                        <li key={i} className="leading-snug">
                          <span className="font-medium">{h.param}</span>
                          {' = '}
                          <span className="font-mono text-purple-600 dark:text-purple-300">{h.recommended}</span>
                          {h.rationale && <span className="text-muted-foreground"> — {h.rationale}</span>}
                        </li>
                      ))}
                    </ul>
                  </AlertDescription>
                </Alert>
              )}
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="md:col-span-1 space-y-4">
              <h3 className="text-lg font-semibold">Parameters</h3>
              <ParameterGroup
                id="main-params"
                title="Workflow Parameters"
                description={renderedParameters.length === 0 ? "No editable parameters detected for this workflow." : undefined}
                parameters={renderedParameters}
                onChange={handleParamChange}
              />
              <div className="space-y-2" data-testid="workflow-run-controls">
                {/* C3: Validate environment button — only show for Nextflow workflows */}
                {(workflowDefinition?.nextflow_path || workflowDefinition?.nextflowPath) && status === 'pending' && (
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
                  {status === 'running' ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : 'Run Workflow'}
                </Button>
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

              {/* QC Settings collapsible */}
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
                        {Object.keys(qcOverrides).length}
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
                        Pause at QC failures
                      </Label>
                      <Switch
                        id="pause-qc-switch"
                        checked={pauseAtQcFailures}
                        onCheckedChange={setPauseAtQcFailures}
                        aria-label="Pause at QC failures"
                      />
                    </div>
                    <p className="text-xs text-muted-foreground -mt-2">
                      {pauseAtQcFailures
                        ? 'Workflow pauses when a gate fires'
                        : 'Gates are logged but workflow continues'}
                    </p>

                    {/* QC Profile picker */}
                    {availableQcProfiles.length > 0 && (
                      <div className="space-y-1.5">
                        <Label className="text-xs text-muted-foreground">Named QC Profile</Label>
                        <Select value={qcProfile || 'none'} onValueChange={v => setQcProfile(v === 'none' ? '' : v)}>
                          <SelectTrigger className="h-7 text-xs">
                            <SelectValue placeholder="Platform defaults" />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="none" className="text-xs">Platform defaults (no profile)</SelectItem>
                            {availableQcProfiles.map(p => (
                              <SelectItem key={p.id} value={p.id} className="text-xs">
                                {p.id.replace(/_/g, '\u00A0')}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    )}

                    {/* Threshold overrides */}
                    <div className="space-y-1.5">
                      <Label className="text-xs text-muted-foreground">Threshold Overrides</Label>
                      <div className="flex gap-1">
                        <Input
                          className="h-7 text-xs flex-1"
                          placeholder="metric_key"
                          value={qcOverrideKey}
                          onChange={e => setQcOverrideKey(e.target.value)}
                        />
                        <Input
                          className="h-7 text-xs w-20"
                          placeholder="value"
                          type="number"
                          value={qcOverrideValue}
                          onChange={e => setQcOverrideValue(e.target.value)}
                        />
                        <Button
                          variant="outline"
                          size="sm"
                          className="h-7 text-xs px-2"
                          onClick={() => {
                            const v = parseFloat(qcOverrideValue);
                            if (qcOverrideKey && !isNaN(v)) {
                              setQcOverrides(prev => ({ ...prev, [qcOverrideKey]: v }));
                              setQcOverrideKey('');
                              setQcOverrideValue('');
                            }
                          }}
                        >
                          Add
                        </Button>
                      </div>
                      {Object.entries(qcOverrides).map(([key, val]) => (
                        <div key={key} className="flex items-center justify-between text-xs bg-muted/40 rounded px-2 py-1">
                          <span>{key}: {val}</span>
                          <button
                            type="button"
                            className="text-muted-foreground hover:text-destructive ml-2"
                            onClick={() => setQcOverrides(prev => { const n = {...prev}; delete n[key]; return n; })}
                          >
                            ×
                          </button>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>

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
              {prereqChecklist && prereqChecklist.items.length > 0 && (
                <div
                  className="space-y-2 rounded-md border border-muted bg-muted/30 p-3"
                  data-testid="workflow-prereq-checklist"
                >
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      Execution checklist
                    </p>
                    <Badge variant={prereqChecklist.canRun ? "outline" : "secondary"}>
                      {prereqChecklist.canRun ? "Ready" : "Action required"}
                    </Badge>
                  </div>
                  <div className="space-y-1.5">
                    {prereqChecklist.items.map((item) => (
                      <div
                        key={item.id}
                        className="rounded border border-border/70 bg-background/70 px-2 py-1.5"
                        data-testid={`workflow-prereq-item-${item.id}`}
                      >
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-xs font-medium">{item.label}</span>
                          <Badge
                            variant={
                              item.status === "ok"
                                ? "outline"
                                : item.status === "warning"
                                ? "secondary"
                                : "destructive"
                            }
                            className="text-[10px] uppercase"
                          >
                            {item.status}
                          </Badge>
                        </div>
                        {item.reason && <p className="mt-1 text-xs text-muted-foreground">{item.reason}</p>}
                        {item.actionHint && <p className="mt-1 text-xs">{item.actionHint}</p>}
                      </div>
                    ))}
                  </div>
                  {isPrereqBlocked && (
                    <Button
                      variant="outline"
                      size="sm"
                      className="w-full"
                      data-testid="button-prereq-recovery"
                      onClick={onRequestPrereqRecovery}
                    >
                      Ask BioMate to prepare runnable demo inputs
                    </Button>
                  )}
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
                  disabled={!invocationId}
                  title={invocationId ? "View output results" : "Run workflow to view results"}
                >
                  <Eye className="mr-2 h-4 w-4" />
                  {showResults ? 'Hide Results' : 'View Results'}
                </Button>
                <Button
                  variant="outline"
                  className="w-full"
                  data-testid="button-download-all-workflow-panel"
                  disabled={!invocationId}
                  title={invocationId ? "Download all outputs" : "Run workflow to enable download"}
                  onClick={() => {
                    if (!invocationId) return;
                    emitUxEvent('output.download_clicked', { invocationId, scope: 'all' });
                    window.open(`/api/invocations/${invocationId}/download-all`, '_blank');
                    setDownloadAllPromptOpen(true);
                  }}
                >
                  <Download className="mr-2 h-4 w-4" />
                  Download All
                </Button>
              </div>
            </div>

            <div className="md:col-span-2 space-y-4">
              <h3 className="text-lg font-semibold">Execution Progress</h3>
              <p className="text-xs text-muted-foreground" data-testid="workflow-last-update">
                Last update: {lastUpdateAt.toLocaleTimeString()}
              </p>
              <div
                className="rounded-md border border-muted bg-muted/30 p-3"
                data-testid="run-context-chip"
              >
                <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                  Run context
                </div>
                <div className="mt-2 grid grid-cols-1 gap-1 text-xs sm:grid-cols-3 sm:gap-2">
                  <div>
                    <span className="text-muted-foreground">Run ID:</span>{" "}
                    <span className="font-mono">{formatContextValue(runId)}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Invocation ID:</span>{" "}
                    <span className="font-mono">{formatContextValue(invocationId)}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Nextflow run ID:</span>{" "}
                    <span className="font-mono">{formatContextValue(nextflowRunId)}</span>
                  </div>
                </div>
              </div>
              <div className="rounded-md border border-muted p-3 text-xs space-y-1" data-testid="workflow-execution-evidence">
                <div className="font-medium">Execution evidence</div>
                <div>Run ID: {runId || "n/a"}</div>
                <div>Invocation ID: {invocationId || "n/a"}</div>
                <div>Runtime status: {nextflowStatus?.status || status}</div>
                {nextflowStatus?.run_id && <div>Nextflow run ID: {String(nextflowStatus.run_id)}</div>}
              </div>
              <div className="rounded-md border border-muted p-3 text-xs space-y-2" data-testid="execution-triage-summary">
                <div className="font-medium">Execution triage</div>
                <div data-testid="execution-triage-status">
                  <span className="text-muted-foreground">Status:</span> {triageStatus}
                </div>
                <div data-testid="execution-triage-next-action">
                  <span className="text-muted-foreground">Next action:</span> {triageNextAction}
                </div>
                <div data-testid="execution-triage-logs">
                  <span className="text-muted-foreground">Logs:</span> {triageLogsHint}
                </div>
                <div data-testid="execution-triage-outputs">
                  <span className="text-muted-foreground">Outputs:</span> {triageOutputsHint}
                </div>
              </div>
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
                      !phase.toolId ||
                      phase.isExecuting === true ||
                      !!executionBlockedReason ||
                      isPrereqBlocked ||
                      isAutofixActive ||
                      isGlobalExecutionActive
                    }
                    runLoading={phase.isExecuting === true}
                    runButtonTestId={`button-run-step-${phase.id}`}
                  />
                ))}
              </div>
              
              <div className="mt-4 bg-muted p-4 rounded-md h-48 overflow-y-auto font-mono text-xs">
                {logs.length === 0 ? <span className="text-muted-foreground">No logs available.</span> : logs.map((log, i) => (
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

          {runId && (status === 'completed' || status === 'failed') && (
            <div className="mt-4">
              <DownloadCommandsPanel runId={runId} />
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
                    If the output cards are still empty, Galaxy output hydration may still be in progress.
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
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
