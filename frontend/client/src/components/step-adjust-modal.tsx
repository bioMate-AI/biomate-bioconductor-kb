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
import { tOr } from "@/lib/i18n";
import { cleanParamValueForDisplay } from "@/lib/user-facing-text";

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
  // Param values can arrive as structured objects ({value|default|val, type, origin,…}).
  // Pull out the scalar they carry so the field shows the real value — not "[object
  // Object]" (string inputs) or an empty box (number inputs coercing an object to NaN).
  const coerceParamValue = (v: any, depth = 0): any => {
    if (v != null && typeof v === "object" && !Array.isArray(v) && depth < 5) {
      // Use `!== undefined` (not `in`) so an explicit `value: undefined` falls
      // through to default/val instead of erasing the param (code-review #6).
      // Recurse (bounded) so a nested wrapper {value:{value:"foo"}} still unwraps
      // to the scalar rather than rendering [object Object] (multi-LLM review).
      // null / 0 / false / "" are legitimate scalar values and are returned as-is.
      if (v.value !== undefined) return coerceParamValue(v.value, depth + 1);
      if (v.default !== undefined) return coerceParamValue(v.default, depth + 1);
      if (v.val !== undefined) return coerceParamValue(v.val, depth + 1);
      return JSON.stringify(v); // last resort — readable, never "[object Object]"
    }
    return v;
  };
  const [paramOverrides, setParamOverrides] = useState<Record<string, any>>(
    () => Object.fromEntries(
      Object.entries(step.parameters || {}).map(([k, v]) => [k, coerceParamValue(v)]),
    )
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
      setErrorMsg(err.message || tOr('common.unknown_error', 'Unknown error'));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent data-testid="step-adjust-modal" className="max-w-lg max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{tOr('step_adjust.title', 'Adjust & rerun: {{name}}', { name: step.name || step.processName || '' })}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {allParamKeys.length === 0 && (
            <p className="text-sm text-muted-foreground">{tOr('step_adjust.no_params', 'No parameters available for this step.')}</p>
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
                ) : typeof val === 'string' && /^(?:s3|gs|file):\/\//i.test(val.trim()) ? (
                  // A stored file is shown by its name, read-only — the storage path is
                  // never user-facing (founder no-S3 rule, 2026-11-11).
                  <span id={`param-${key}`} data-testid={`step-adjust-file-${key}`} title={cleanParamValueForDisplay(val)}
                    className="w-40 truncate rounded border bg-muted/40 px-2 py-1 font-mono text-xs">
                    {cleanParamValueForDisplay(val) || tOr('panel.staged_file', 'staged file')}
                  </span>
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
            {tOr('step_adjust.hint', 'Only changed parameters will be applied. The workflow resumes from this step.')}
          </p>

          {errorMsg && (
            <div className="rounded-md bg-red-50 border border-red-200 px-3 py-2 text-sm text-red-700 dark:bg-red-900/30 dark:border-red-800 dark:text-red-300">
              {errorMsg}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={submitting}>
            {tOr('common.cancel', 'Cancel')}
          </Button>
          <Button onClick={handleRerun} disabled={submitting}>
            {submitting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin mr-2" />
                {tOr('step_adjust.submitting', 'Submitting…')}
              </>
            ) : (
              tOr('step_adjust.rerun', 'Rerun from this step')
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
