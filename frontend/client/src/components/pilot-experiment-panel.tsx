/**
 * PilotExperimentPanel — Track 2C: Experiment Test Harness UX
 *
 * Allows researchers to run A/B comparisons on workflows:
 *   1. Specify hypothesis + control/experimental parameter sets
 *   2. BioMate fires both runs in parallel
 *   3. Shows side-by-side comparison + automated narrative when done
 *   4. History of past experiments in left sidebar panel
 *
 * Referenced from nextflow-workflow-viewer.tsx as a tab.
 */

import React, { useState, useEffect, useCallback, useRef } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Separator } from "@/components/ui/separator";
import { useToast } from "@/hooks/use-toast";
import {
  FlaskConical,
  Play,
  RefreshCw,
  Clock,
  CheckCircle,
  XCircle,
  ChevronRight,
  Info,
} from "lucide-react";

// ─── Types ──────────────────────────────────────────────────────────────────

interface ExperimentListItem {
  id: string;
  hypothesis: string;
  workflowId: string;
  workflowName: string | null;
  controlLabel: string | null;
  experimentalLabel: string | null;
  status: string;
  controlRunId: string | null;
  experimentalRunId: string | null;
  hasResults: boolean;
  createdAt: string;
}

interface ExperimentResult {
  id: string;
  status: string;
  hypothesis: string;
  controlLabel: string | null;
  experimentalLabel: string | null;
  controlRun?: { runId: string; status: string };
  experimentalRun?: { runId: string; status: string };
  comparison?: {
    runtimeDelta?: number;
    memoryDelta?: number;
    qualityDelta?: Record<string, number>;
    parameterDifferences?: Array<{ param: string; run1Value: unknown; run2Value: unknown }>;
    preferredRun?: string;
    reason?: string;
  };
  narrative?: string;
}

interface PilotExperimentPanelProps {
  workflowId: string;
  workflowName?: string;
  workflowDefinition?: any;
  currentParams?: Record<string, any>;
  /** Called when the panel needs to execute a workflow run with specific params */
  onExecuteRun: (params: Record<string, any>, label: string) => Promise<string | null>;
}

// ─── Status helpers ──────────────────────────────────────────────────────────

function StatusIcon({ status }: { status: string }) {
  if (status === "completed") return <CheckCircle className="h-4 w-4 text-green-500" />;
  if (status === "failed" || status === "error") return <XCircle className="h-4 w-4 text-red-500" />;
  if (status === "running") return <RefreshCw className="h-4 w-4 text-blue-500 animate-spin" />;
  return <Clock className="h-4 w-4 text-muted-foreground" />;
}

function statusBadgeVariant(status: string): "default" | "secondary" | "destructive" | "outline" {
  if (status === "completed") return "default";
  if (status === "failed" || status === "error") return "destructive";
  if (status === "running") return "secondary";
  return "outline";
}

// ─── New experiment form ──────────────────────────────────────────────────────

function NewExperimentForm({
  workflowId,
  workflowName,
  currentParams,
  onSubmit,
}: {
  workflowId: string;
  workflowName?: string;
  currentParams?: Record<string, any>;
  onSubmit: (data: {
    hypothesis: string;
    controlLabel: string;
    experimentalLabel: string;
    controlParams: Record<string, any>;
    experimentalParams: Record<string, any>;
    metrics: string[];
  }) => void;
}) {
  const [hypothesis, setHypothesis] = useState("");
  const [controlLabel, setControlLabel] = useState("Control");
  const [experimentalLabel, setExperimentalLabel] = useState("Experimental");
  const [controlParamsText, setControlParamsText] = useState(
    JSON.stringify(currentParams ?? {}, null, 2)
  );
  const [experimentalParamsText, setExperimentalParamsText] = useState(
    JSON.stringify(currentParams ?? {}, null, 2)
  );
  const [metrics, setMetrics] = useState("runtime,output_count,quality");
  const [jsonError, setJsonError] = useState<{ control?: string; experimental?: string }>({});

  const validateJson = (text: string, field: "control" | "experimental") => {
    try {
      JSON.parse(text);
      setJsonError(e => ({ ...e, [field]: undefined }));
      return true;
    } catch {
      setJsonError(e => ({ ...e, [field]: "Invalid JSON" }));
      return false;
    }
  };

  const handleSubmit = () => {
    if (!hypothesis.trim()) return;
    const cOk = validateJson(controlParamsText, "control");
    const eOk = validateJson(experimentalParamsText, "experimental");
    if (!cOk || !eOk) return;
    onSubmit({
      hypothesis: hypothesis.trim(),
      controlLabel,
      experimentalLabel,
      controlParams: JSON.parse(controlParamsText),
      experimentalParams: JSON.parse(experimentalParamsText),
      metrics: metrics.split(",").map(m => m.trim()).filter(Boolean),
    });
  };

  return (
    <div className="space-y-4">
      <div>
        <label className="text-xs font-medium text-muted-foreground mb-1 block">
          Hypothesis <span className="text-destructive">*</span>
        </label>
        <textarea
          className="w-full min-h-[60px] text-sm rounded-md border border-input bg-background px-3 py-2 resize-none focus:outline-none focus:ring-1 focus:ring-ring"
          placeholder="e.g. Increasing min_map_quality from 20 to 30 will reduce false-positive variants without significantly increasing runtime."
          value={hypothesis}
          onChange={e => setHypothesis(e.target.value)}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="text-xs font-medium text-muted-foreground mb-1 block">Control label</label>
          <input
            className="w-full text-sm rounded-md border border-input bg-background px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-ring"
            value={controlLabel}
            onChange={e => setControlLabel(e.target.value)}
          />
        </div>
        <div>
          <label className="text-xs font-medium text-muted-foreground mb-1 block">Experimental label</label>
          <input
            className="w-full text-sm rounded-md border border-input bg-background px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-ring"
            value={experimentalLabel}
            onChange={e => setExperimentalLabel(e.target.value)}
          />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="text-xs font-medium text-muted-foreground mb-1 block">
            {controlLabel} parameters (JSON)
          </label>
          <textarea
            className={`w-full min-h-[120px] font-mono text-xs rounded-md border px-3 py-2 resize-y focus:outline-none focus:ring-1 focus:ring-ring ${jsonError.control ? "border-destructive" : "border-input"} bg-background`}
            value={controlParamsText}
            onChange={e => { setControlParamsText(e.target.value); validateJson(e.target.value, "control"); }}
          />
          {jsonError.control && <p className="text-xs text-destructive mt-0.5">{jsonError.control}</p>}
        </div>
        <div>
          <label className="text-xs font-medium text-muted-foreground mb-1 block">
            {experimentalLabel} parameters (JSON)
          </label>
          <textarea
            className={`w-full min-h-[120px] font-mono text-xs rounded-md border px-3 py-2 resize-y focus:outline-none focus:ring-1 focus:ring-ring ${jsonError.experimental ? "border-destructive" : "border-input"} bg-background`}
            value={experimentalParamsText}
            onChange={e => { setExperimentalParamsText(e.target.value); validateJson(e.target.value, "experimental"); }}
          />
          {jsonError.experimental && <p className="text-xs text-destructive mt-0.5">{jsonError.experimental}</p>}
        </div>
      </div>

      <div>
        <label className="text-xs font-medium text-muted-foreground mb-1 block">
          Metrics to compare (comma-separated)
        </label>
        <input
          className="w-full text-sm rounded-md border border-input bg-background px-3 py-1.5 focus:outline-none focus:ring-1 focus:ring-ring"
          value={metrics}
          onChange={e => setMetrics(e.target.value)}
          placeholder="runtime, output_count, quality"
        />
      </div>

      <Button
        size="sm"
        onClick={handleSubmit}
        disabled={!hypothesis.trim()}
        className="w-full"
      >
        <Play className="h-3.5 w-3.5 mr-1.5" />
        Launch Experiment
      </Button>
    </div>
  );
}

// ─── Comparison view ──────────────────────────────────────────────────────────

function ComparisonView({ result }: { result: ExperimentResult }) {
  const ctrlLabel = result.controlLabel || "Control";
  const expLabel = result.experimentalLabel || "Experimental";

  const { comparison } = result;

  return (
    <div className="space-y-4">
      {/* Run status row */}
      <div className="grid grid-cols-2 gap-3">
        {[
          { label: ctrlLabel, run: result.controlRun },
          { label: expLabel, run: result.experimentalRun },
        ].map(({ label, run }) => (
          <Card key={label} className="p-3">
            <div className="flex items-center gap-2 mb-1">
              <StatusIcon status={run?.status ?? "pending"} />
              <span className="text-sm font-medium">{label}</span>
              <Badge variant={statusBadgeVariant(run?.status ?? "pending")} className="ml-auto text-xs">
                {run?.status ?? "pending"}
              </Badge>
            </div>
            {run?.runId && (
              <p className="text-xs text-muted-foreground font-mono truncate">{run.runId}</p>
            )}
          </Card>
        ))}
      </div>

      {/* Metrics table */}
      {comparison && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Metrics Comparison</CardTitle>
          </CardHeader>
          <CardContent className="pt-0">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b">
                  <th className="text-left py-1.5 text-muted-foreground font-medium">Metric</th>
                  <th className="text-right py-1.5 text-muted-foreground font-medium">{ctrlLabel}</th>
                  <th className="text-right py-1.5 text-muted-foreground font-medium">{expLabel}</th>
                  <th className="text-right py-1.5 text-muted-foreground font-medium">Δ</th>
                </tr>
              </thead>
              <tbody>
                {comparison.runtimeDelta !== undefined && (
                  <tr className="border-b border-border/50">
                    <td className="py-1.5">Runtime</td>
                    <td className="text-right py-1.5 text-muted-foreground">—</td>
                    <td className="text-right py-1.5 text-muted-foreground">—</td>
                    <td className={`text-right py-1.5 font-medium ${comparison.runtimeDelta > 0 ? "text-orange-500" : "text-green-500"}`}>
                      {comparison.runtimeDelta > 0 ? "+" : ""}{comparison.runtimeDelta.toFixed(1)}%
                    </td>
                  </tr>
                )}
                {comparison.memoryDelta !== undefined && (
                  <tr className="border-b border-border/50">
                    <td className="py-1.5">Peak Memory</td>
                    <td className="text-right py-1.5 text-muted-foreground">—</td>
                    <td className="text-right py-1.5 text-muted-foreground">—</td>
                    <td className={`text-right py-1.5 font-medium ${comparison.memoryDelta > 0 ? "text-orange-500" : "text-green-500"}`}>
                      {comparison.memoryDelta > 0 ? "+" : ""}{comparison.memoryDelta.toFixed(1)}%
                    </td>
                  </tr>
                )}
                {Object.entries(comparison.qualityDelta ?? {}).map(([key, delta]) => (
                  <tr key={key} className="border-b border-border/50">
                    <td className="py-1.5">{key}</td>
                    <td className="text-right py-1.5 text-muted-foreground">—</td>
                    <td className="text-right py-1.5 text-muted-foreground">—</td>
                    <td className={`text-right py-1.5 font-medium ${(delta as number) >= 0 ? "text-green-500" : "text-red-500"}`}>
                      {(delta as number) >= 0 ? "+" : ""}{(delta as number).toFixed(3)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            {/* Parameter differences */}
            {(comparison.parameterDifferences ?? []).length > 0 && (
              <div className="mt-3 pt-3 border-t">
                <p className="text-xs font-medium text-muted-foreground mb-2">
                  Parameter differences ({comparison.parameterDifferences!.length})
                </p>
                <div className="space-y-1">
                  {comparison.parameterDifferences!.slice(0, 6).map(diff => (
                    <div key={diff.param} className="flex items-start gap-2 text-xs">
                      <code className="text-blue-600 dark:text-blue-400 shrink-0">{diff.param}</code>
                      <span className="text-muted-foreground shrink-0">
                        {JSON.stringify(diff.run1Value)}
                      </span>
                      <ChevronRight className="h-3 w-3 text-muted-foreground shrink-0 mt-px" />
                      <span className="font-medium">
                        {JSON.stringify(diff.run2Value)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Recommendation */}
            {comparison.preferredRun && comparison.reason && (
              <div className="mt-3 pt-3 border-t flex items-start gap-2">
                <Info className="h-3.5 w-3.5 text-blue-500 mt-0.5 shrink-0" />
                <p className="text-xs text-muted-foreground">
                  <span className="font-medium text-foreground">Recommendation:</span>{" "}
                  {comparison.reason}
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Narrative */}
      {result.narrative && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Analysis</CardTitle>
          </CardHeader>
          <CardContent className="pt-0">
            <div className="text-xs text-muted-foreground whitespace-pre-wrap leading-relaxed">
              {result.narrative}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

// ─── Main panel ──────────────────────────────────────────────────────────────

export function PilotExperimentPanel({
  workflowId,
  workflowName,
  workflowDefinition,
  currentParams,
  onExecuteRun,
}: PilotExperimentPanelProps) {
  const { toast } = useToast();
  const [view, setView] = useState<"new" | "history">("new");
  const [experiments, setExperiments] = useState<ExperimentListItem[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedResult, setSelectedResult] = useState<ExperimentResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [launching, setLaunching] = useState(false);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // App uses httpOnly cookie auth — credentials: 'include' is sufficient
  const fetchOpts: RequestInit = { credentials: 'include' };

  // ── Fetch experiment list ─────────────────────────────────────────────────

  const fetchList = useCallback(async () => {
    try {
      const r = await fetch("/api/experiments", fetchOpts);
      if (!r.ok) return;
      const data = await r.json();
      setExperiments(data.experiments ?? []);
    } catch {}
  }, []);

  useEffect(() => { fetchList(); }, [fetchList]);

  // ── Poll selected experiment ──────────────────────────────────────────────

  const fetchResult = useCallback(async (id: string) => {
    try {
      const r = await fetch(`/api/experiments/${id}/results`, fetchOpts);
      if (!r.ok) return;
      const data: ExperimentResult = await r.json();
      setSelectedResult(data);
      if (data.status === "completed" || data.status === "failed") {
        if (pollRef.current) { clearInterval(pollRef.current); pollRef.current = null; }
        fetchList();
      }
    } catch {}
  }, [fetchList]);

  useEffect(() => {
    if (!selectedId) return;
    fetchResult(selectedId);
    pollRef.current = setInterval(() => fetchResult(selectedId), 8000);
    return () => { if (pollRef.current) clearInterval(pollRef.current); };
  }, [selectedId, fetchResult]);

  // ── Launch experiment ─────────────────────────────────────────────────────

  const handleLaunch = async (formData: {
    hypothesis: string;
    controlLabel: string;
    experimentalLabel: string;
    controlParams: Record<string, any>;
    experimentalParams: Record<string, any>;
    metrics: string[];
  }) => {
    setLaunching(true);
    try {
      // 1. Create experiment record
      const createRes = await fetch("/api/experiments", {
        method: "POST",
        credentials: 'include',
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          hypothesis: formData.hypothesis,
          workflowId,
          workflowName: workflowName || workflowId,
          controlLabel: formData.controlLabel,
          experimentalLabel: formData.experimentalLabel,
          controlParams: formData.controlParams,
          experimentalParams: formData.experimentalParams,
          metrics: formData.metrics,
        }),
      });
      if (!createRes.ok) throw new Error("Failed to create experiment");
      const { id: expId } = await createRes.json();

      // 2. Fire both runs in parallel
      const [controlRunId, experimentalRunId] = await Promise.all([
        onExecuteRun(formData.controlParams, formData.controlLabel),
        onExecuteRun(formData.experimentalParams, formData.experimentalLabel),
      ]);

      if (!controlRunId || !experimentalRunId) {
        throw new Error("One or both runs failed to start");
      }

      // 3. Link run IDs to experiment
      await fetch(`/api/experiments/${expId}`, {
        method: "PATCH",
        credentials: 'include',
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ controlRunId, experimentalRunId }),
      });

      toast({ title: "Experiment launched", description: `Both runs started. Polling for results...` });
      setSelectedId(expId);
      setView("history");
      await fetchList();
    } catch (err: any) {
      toast({ title: "Launch failed", description: err.message, variant: "destructive" });
    } finally {
      setLaunching(false);
    }
  };

  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <FlaskConical className="h-4 w-4 text-primary" />
        <span className="text-sm font-semibold">Pilot Experiments</span>
        <Badge variant="outline" className="text-xs ml-auto">
          {experiments.length} experiment{experiments.length !== 1 ? "s" : ""}
        </Badge>
      </div>

      <Tabs value={view} onValueChange={v => setView(v as "new" | "history")}>
        <TabsList className="w-full">
          <TabsTrigger value="new" className="flex-1 text-xs">New Experiment</TabsTrigger>
          <TabsTrigger value="history" className="flex-1 text-xs">
            History {experiments.length > 0 ? `(${experiments.length})` : ""}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="new" className="mt-4">
          <NewExperimentForm
            workflowId={workflowId}
            workflowName={workflowName}
            currentParams={currentParams}
            onSubmit={handleLaunch}
          />
          {launching && (
            <div className="flex items-center gap-2 mt-3 text-xs text-muted-foreground">
              <RefreshCw className="h-3.5 w-3.5 animate-spin" />
              Launching both runs…
            </div>
          )}
        </TabsContent>

        <TabsContent value="history" className="mt-4">
          {experiments.length === 0 ? (
            <p className="text-xs text-muted-foreground text-center py-6">
              No experiments yet. Create one using the "New Experiment" tab.
            </p>
          ) : (
            <div className="space-y-2">
              {experiments.map(exp => (
                <button
                  key={exp.id}
                  onClick={() => { setSelectedId(exp.id); fetchResult(exp.id); }}
                  className={`w-full text-left rounded-md border p-3 hover:bg-accent/50 transition-colors ${selectedId === exp.id ? "border-primary bg-accent/30" : "border-border"}`}
                >
                  <div className="flex items-center gap-2 mb-1">
                    <StatusIcon status={exp.status} />
                    <span className="text-xs font-medium truncate flex-1">{exp.hypothesis}</span>
                    <Badge variant={statusBadgeVariant(exp.status)} className="text-xs shrink-0">
                      {exp.status}
                    </Badge>
                  </div>
                  <p className="text-xs text-muted-foreground truncate">
                    {exp.workflowName || exp.workflowId} ·{" "}
                    {new Date(exp.createdAt).toLocaleDateString()}
                  </p>
                </button>
              ))}
            </div>
          )}

          {selectedId && selectedResult && (
            <>
              <Separator className="my-4" />
              <ComparisonView result={selectedResult} />
            </>
          )}

          {selectedId && !selectedResult && (
            <div className="flex items-center gap-2 text-xs text-muted-foreground mt-4">
              <RefreshCw className="h-3.5 w-3.5 animate-spin" />
              Loading results…
            </div>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}
