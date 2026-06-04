import React, { useState } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Loader2 } from "lucide-react";

function prettifyLabel(raw: string): string {
  return raw
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/\b\w/g, c => c.toUpperCase());
}

interface StepAdjustModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  runId: string;
  step: {
    id: string;
    name: string;
    processName?: string;
    parameters?: Record<string, any>;
  };
  workflowDefinition?: any;
  onRerunSubmitted: (newRunId: string) => void;
}

export function StepAdjustModal({
  open,
  onOpenChange,
  runId,
  step,
  workflowDefinition,
  onRerunSubmitted,
}: StepAdjustModalProps) {
  const [paramOverrides, setParamOverrides] = useState<Record<string, any>>(
    () => ({ ...(step.parameters || {}) })
  );
  const [submitting, setSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Merge in relevant params from workflowDefinition that appear in step.parameters
  const stepParamKeys = new Set(Object.keys(step.parameters || {}));
  const defParams: Array<{ name: string; default?: any; type?: string }> = [
    ...(workflowDefinition?.required_params || []),
    ...(workflowDefinition?.optional_params || []),
  ].filter((p: any) => stepParamKeys.has(p.name));

  // Build the final param map: keys from step.parameters, with defParam metadata as context
  const allParamKeys = Array.from(stepParamKeys);

  function getParamType(key: string): 'boolean' | 'number' | 'string' {
    const val = paramOverrides[key];
    if (typeof val === 'boolean') return 'boolean';
    if (typeof val === 'number') return 'number';
    const defParam = defParams.find(p => p.name === key);
    if (defParam?.type === 'boolean') return 'boolean';
    if (defParam?.type === 'number' || defParam?.type === 'integer' || defParam?.type === 'float') return 'number';
    return 'string';
  }

  function updateParam(key: string, value: any) {
    setParamOverrides(prev => ({ ...prev, [key]: value }));
  }

  async function handleRerun() {
    setSubmitting(true);
    setErrorMsg(null);
    try {
      const response = await fetch(`/api/workflows/runs/${runId}/rerun-from-step`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          step_name: step.processName || step.name,
          param_overrides: paramOverrides,
        }),
      });
      if (!response.ok) {
        const errData = await response.json().catch(() => ({ error: response.statusText }));
        setErrorMsg(errData.error || response.statusText);
        return;
      }
      const data = await response.json();
      onRerunSubmitted(data.new_run_id);
      onOpenChange(false);
    } catch (err: any) {
      setErrorMsg(err.message || 'Unknown error');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent data-testid="step-adjust-modal" className="max-w-lg max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Adjust &amp; Rerun: {step.processName || step.name}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {allParamKeys.length === 0 && (
            <p className="text-sm text-muted-foreground">No parameters available for this step.</p>
          )}
          {allParamKeys.map(key => {
            const paramType = getParamType(key);
            const val = paramOverrides[key];
            return (
              <div key={key} className="flex items-center justify-between gap-3">
                <Label htmlFor={`param-${key}`} className="text-sm min-w-0 flex-1">
                  {prettifyLabel(key)}
                </Label>
                {paramType === 'boolean' ? (
                  <Switch
                    id={`param-${key}`}
                    checked={Boolean(val)}
                    onCheckedChange={checked => updateParam(key, checked)}
                  />
                ) : paramType === 'number' ? (
                  <Input
                    id={`param-${key}`}
                    type="number"
                    value={val ?? ''}
                    onChange={e => updateParam(key, e.target.valueAsNumber)}
                    className="w-40 text-sm"
                  />
                ) : (
                  <Input
                    id={`param-${key}`}
                    type="text"
                    value={val != null ? String(val) : ''}
                    onChange={e => updateParam(key, e.target.value)}
                    className="w-40 text-sm"
                  />
                )}
              </div>
            );
          })}

          <p className="text-xs text-muted-foreground pt-1">
            Only changed parameters will be applied. The workflow resumes from this step.
          </p>

          {errorMsg && (
            <div className="rounded-md bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700 dark:bg-red-900/30 dark:border-red-800 dark:text-red-300">
              {errorMsg}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={handleRerun} disabled={submitting}>
            {submitting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin mr-2" />
                Submitting…
              </>
            ) : (
              'Rerun from this step'
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
