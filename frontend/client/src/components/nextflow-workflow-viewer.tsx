import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { PhaseCard } from "./phase-card";
import { ParameterGroup } from "./parameter-group";
import { Button } from "@/components/ui/button";
import { Loader2, CheckCircle2, XCircle, AlertTriangle, FlaskConical, Lightbulb } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { useUnifiedExecution } from "@/hooks/useUnifiedExecution";

interface NextflowWorkflowViewerProps {
  workflowId?: string;
  workflowDefinition?: any; // Nextflow definition
  initialParams?: any;
  onExecute?: (params: any) => void;
  status?: 'idle' | 'running' | 'completed' | 'failed';
  progress?: number;
  onParameterChange?: (id: string, value: any) => void;
}

export function NextflowWorkflowViewer({ 
  workflowId, 
  workflowDefinition, 
  initialParams, 
  onExecute,
  status = 'idle',
  progress = 0,
  onParameterChange
}: NextflowWorkflowViewerProps) {
  const [params, setParams] = useState(initialParams || {});
  const [logs, setLogs] = useState<string[]>([]);

  // Derive phases from workflow steps if available
  const phases = workflowDefinition?.steps ? Object.values(workflowDefinition.steps).map((step: any, index: number) => ({
    id: step.id || `step-${index}`,
    name: step.name || step.label || step.tool_id || `Step ${index + 1}`,
    status: 'pending', // Default status, should be updated based on execution state
    description: step.annotation || step.description
  })) : [
    { id: 'setup', name: 'Setup & Input', status: 'completed' },
    { id: 'process', name: 'Data Processing', status: 'running' },
    { id: 'analysis', name: 'Statistical Analysis', status: 'pending' },
    { id: 'report', name: 'Report Generation', status: 'pending' }
  ];

  // Update phase status based on global status (simple simulation for now)
  // In a real implementation, we would map individual step statuses from the backend
  const updatedPhases = phases.map((phase: any, index: number) => {
    if (status === 'completed') return { ...phase, status: 'completed' };
    if (status === 'running') {
        // Simple progress simulation mapping
        const totalPhases = phases.length;
        const currentPhaseIndex = Math.floor((progress / 100) * totalPhases);
        if (index < currentPhaseIndex) return { ...phase, status: 'completed' };
        if (index === currentPhaseIndex) return { ...phase, status: 'running' };
        return { ...phase, status: 'pending' };
    }
    return phase;
  });

  const handleParamChange = (id: string, value: any) => {
    setParams((prev: any) => ({ ...prev, [id]: value }));
    onParameterChange?.(id, value);
  };

  const handleExecute = () => {
    if (onExecute) {
      onExecute(params);
    }
  };

  const rationale = workflowDefinition?.scientific_rationale;

  return (
    <div className="space-y-6 p-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>Nextflow Workflow: {workflowDefinition?.name || 'Untitled'}</span>
            <div className="flex items-center gap-2">
                {progress > 0 && <span className="text-sm text-muted-foreground">{progress}%</span>}
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
                parameters={[
                  { id: 'input', name: 'input', label: 'Input File', type: 'string', required: true },
                  { id: 'output', name: 'output', label: 'Output Directory', type: 'string', required: true },
                  { id: 'threads', name: 'threads', label: 'Threads', type: 'number', defaultValue: 4 }
                ]}
                onChange={handleParamChange}
              />
              <Button 
                className="w-full" 
                onClick={handleExecute} 
                disabled={status === 'running'}
              >
                {status === 'running' ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : 'Run Workflow'}
              </Button>
            </div>

            <div className="md:col-span-2 space-y-4">
              <h3 className="text-lg font-semibold">Execution Progress</h3>
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
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
