import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { emitUxEvent } from "@/lib/ux-telemetry";
import { Badge } from "@/components/ui/badge";
import { PhaseCard } from "./phase-card";
import { ParameterGroup } from "./parameter-group";
import { Button } from "@/components/ui/button";
import { Loader2, CheckCircle2, XCircle, AlertTriangle, FlaskConical, Lightbulb, Download, Eye } from "lucide-react";
import { ReportConfusionButton } from "./feedback/report-confusion-button";
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { ChatOutputAttachments } from "./chat-output-attachments";
import type { PrereqChecklist } from "@/lib/prereq-normalizer";

interface NextflowWorkflowViewerProps {
  workflowId?: string;
  invocationId?: string;
  executionBlockedReason?: string;
  prereqChecklist?: PrereqChecklist;
  workflowDefinition?: any; // Nextflow definition
  initialParams?: any;
  onExecute?: (params: any) => void;
  status?: 'idle' | 'running' | 'completed' | 'failed';
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
}

export function NextflowWorkflowViewer({ 
  workflowId, 
  invocationId,
  executionBlockedReason,
  prereqChecklist,
  workflowDefinition, 
  initialParams, 
  onExecute,
  status = 'idle',
  errorMessage,
  progress = 0,
  onParameterChange,
  onRequestPrereqRecovery,
  sessionId,
  runId,
  autofix,
  nextflowStatus,
}: NextflowWorkflowViewerProps) {
  const [params, setParams] = useState(initialParams || {});
  const [logs, setLogs] = useState<string[]>([]);
  const [lastUpdateAt, setLastUpdateAt] = useState<Date>(new Date());

  // Prefer real Nextflow trace processes over simulated workflow steps.
  // nextflowStatus.processes is populated by _parse_trace_progress() on the backend
  // with actual task names, statuses, work_dir paths, and task_files per process.
  const traceProcesses: any[] =
    Array.isArray(nextflowStatus?.processes) && nextflowStatus.processes.length > 0
      ? nextflowStatus.processes
      : [];

  // Fallback: derive phases from the workflow definition (used before execution starts)
  const definitionPhases = workflowDefinition?.steps
    ? Object.values(workflowDefinition.steps).map((step: any, index: number) => ({
        id: step.id || `step-${index}`,
        name: step.name || step.label || step.tool_id || `Step ${index + 1}`,
        status: 'pending' as const,
        description: step.annotation || step.description,
      }))
    : [
        { id: 'setup',    name: 'Setup & Input',        status: 'pending' as const },
        { id: 'process',  name: 'Data Processing',      status: 'pending' as const },
        { id: 'analysis', name: 'Statistical Analysis', status: 'pending' as const },
        { id: 'report',   name: 'Report Generation',    status: 'pending' as const },
      ];

  // Build the phase list shown in the UI
  const updatedPhases: any[] = traceProcesses.length > 0
    // Real path: one card per Nextflow process from the trace
    ? traceProcesses.map((proc: any, idx2: number) => ({
        id: proc.id || `proc-${idx2}`,
        name: proc.name,
        processName: proc.name,
        status: proc.status,       // raw Nextflow status — PhaseCard maps it
        taskFiles: proc.task_files ?? [],
        workDir: proc.work_dir ?? '',
      }))
    // Fallback: definition steps with simulated status from overall progress
    : definitionPhases.map((phase: any, index: number) => {
        if (status === 'completed') return { ...phase, status: 'completed' };
        if (status === 'running') {
          const total = definitionPhases.length;
          const cur   = Math.floor((effectiveProgress / 100) * total);
          return {
            ...phase,
            status: index < cur ? 'completed' : index === cur ? 'running' : 'pending',
          };
        }
        return phase;
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
      onExecute(params);
    }
  };

  const rationale = workflowDefinition?.scientific_rationale;
  const [showResults, setShowResults] = useState(status === 'completed');
  const [downloadAllPromptOpen, setDownloadAllPromptOpen] = useState(false);
  const isPrereqBlocked = !!prereqChecklist && !prereqChecklist.canRun;

  // Derive required/optional params from the workflow definition (populated by backend)
  const requiredParams: Array<{name: string; label: string; description: string; default: string | null}> =
    workflowDefinition?.required_params ?? [];
  const optionalParams: Array<{name: string; label: string; description: string; default: string | null}> =
    workflowDefinition?.optional_params ?? [];
  const allWorkflowParams = [...requiredParams, ...optionalParams];

  // Block run if any required param is still empty
  const hasUnfilledRequired = requiredParams.some(
    (p) => !params[p.name] || String(params[p.name]).trim() === ""
  );

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
  }, [status, progress, errorMessage, nextflowStatus]);

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
    <div className="space-y-6 p-4">
      <DownloadOutcomePrompt
        open={downloadAllPromptOpen}
        onOpenChange={setDownloadAllPromptOpen}
        invocationId={invocationId}
        sessionId={sessionId}
        runId={runId}
        isDownloadAll={true}
      />
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>Nextflow Workflow: {workflowDefinition?.name || 'Untitled'}</span>
            <div className="flex items-center gap-2">
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
              {allWorkflowParams.length > 0 ? (
                <>
                  <ParameterGroup
                    id="nextflow-params"
                    title="Workflow Parameters"
                    parameters={allWorkflowParams.map((p) => ({
                      id: p.name,
                      name: p.name,
                      label: p.label + (p.default === null ? ' *' : ''),
                      type: 'string' as const,
                      required: p.default === null,
                      defaultValue: p.default ?? undefined,
                      description: p.description,
                      value: params[p.name] ?? p.default ?? '',
                    }))}
                    onChange={handleParamChange}
                  />
                  {hasUnfilledRequired && (
                    <p className="text-xs text-destructive mt-1">
                      Fill in all required parameters (*) before running.
                    </p>
                  )}
                </>
              ) : (
                <ParameterGroup
                  id="main-params"
                  title="Workflow Parameters"
                  parameters={[
                    { id: 'input', name: 'input', label: 'Input File', type: 'string' as const, required: true },
                    { id: 'output', name: 'output', label: 'Output Directory', type: 'string' as const, required: true },
                    { id: 'threads', name: 'threads', label: 'Threads', type: 'number' as const, defaultValue: 4 }
                  ]}
                  onChange={handleParamChange}
                />
              )}
              <Button
                className="w-full"
                data-testid="button-run-workflow-panel"
                onClick={handleExecute}
                disabled={
                  status === 'running' ||
                  status === 'completed' ||
                  !!executionBlockedReason ||
                  isPrereqBlocked ||
                  isAutofixActive ||
                  hasUnfilledRequired
                }
              >
                {status === 'running' ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : status === 'completed' ? 'Completed' : 'Run Workflow'}
              </Button>
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
                      isPrereqBlocked ||
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
                {updatedPhases.map((phase: any, index: number) => (
                  <PhaseCard
                    key={phase.id}
                    phase={phase}
                    onExecute={() => console.log(`Execute phase ${phase.name}`)}
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
