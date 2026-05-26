/**
 * Gap 3 — Run Again Param Carryover hook.
 *
 * When a workflow run reaches a terminal status (completed/failed), pre-fills
 * the panel's params state with the params actually submitted to that run so
 * "Run again" doesn't quietly reset to workflowDefinition defaults.
 *
 * Companion to nextflow-workflow-viewer.tsx. Designed as an external hook so
 * the wire-up is a single line inside the viewer and the logic lives in a
 * file that other tooling (formatters, IDE buffers) is unlikely to touch.
 *
 * Doc: docs/20260521_GAP3_RUN_AGAIN_PARAM_CARRYOVER.md
 *
 * Usage inside the viewer:
 *
 *   const { showingSubmittedParams, resetToDefaults } = useRunAgainParamCarryover({
 *     status,
 *     runId,
 *     lastSubmittedParams,   // flat {paramName: value} from currentRun
 *     userOverriddenParams,  // existing ref<Set<string>>
 *     setParams,             // existing setState
 *     defaults: initialParams || workflowDefinition?.parameters || workflowDefinition?.inline_parameters || {},
 *   });
 */

import { useCallback, useEffect, useRef, useState } from 'react';

export interface UseRunAgainParamCarryoverArgs {
  /** Viewer status — only acts on 'completed' | 'failed'. */
  status?: string;
  /** Disambiguates one terminal transition from another (e.g. rerun N → N+1). */
  runId?: string;
  /** Flat map of params submitted to the prior run. Skipped if empty/undefined. */
  lastSubmittedParams?: Record<string, any>;
  /** Ref of param keys the user has actively edited; we won't clobber those. */
  userOverriddenParams: React.MutableRefObject<Set<string>>;
  /** Viewer's setState for the local params record. */
  setParams: React.Dispatch<React.SetStateAction<Record<string, any>>>;
  /** Defaults to fall back to when user clicks "Reset to defaults". */
  defaults: Record<string, any>;
}

export interface UseRunAgainParamCarryoverResult {
  /** True while the panel is showing pre-filled-from-prior-run values. */
  showingSubmittedParams: boolean;
  /** Re-applies workflow defaults, clears the override set, hides the Reset link. */
  resetToDefaults: () => void;
}

export function useRunAgainParamCarryover(
  args: UseRunAgainParamCarryoverArgs,
): UseRunAgainParamCarryoverResult {
  const { status, runId, lastSubmittedParams, userOverriddenParams, setParams, defaults } = args;

  // One-shot per (status, runId): ref guard prevents re-clobber if the user
  // edits a field after the pre-fill. A new terminal transition (different
  // runId or status change) re-arms the guard.
  const appliedKey = useRef<string | null>(null);
  const [showingSubmittedParams, setShowingSubmittedParams] = useState(false);

  useEffect(() => {
    if (status !== 'completed' && status !== 'failed') return;
    if (!lastSubmittedParams || Object.keys(lastSubmittedParams).length === 0) return;
    const guardKey = `${status}:${runId ?? ''}`;
    if (appliedKey.current === guardKey) return;
    setParams((prev) => {
      const next = { ...prev };
      for (const [k, v] of Object.entries(lastSubmittedParams)) {
        if (!userOverriddenParams.current.has(k)) next[k] = v;
      }
      return next;
    });
    appliedKey.current = guardKey;
    setShowingSubmittedParams(true);
  }, [status, runId, lastSubmittedParams, setParams, userOverriddenParams]);

  const resetToDefaults = useCallback(() => {
    setParams(defaults || {});
    userOverriddenParams.current.clear();
    setShowingSubmittedParams(false);
  }, [defaults, setParams, userOverriddenParams]);

  return { showingSubmittedParams, resetToDefaults };
}

/**
 * Pure helper: flatten ExecutionRun.parameters.toolParameters or
 * workflowDefinition.parameters into a single flat {paramName: value} map.
 *
 * Recipe mirrors backend/frontend/server/routes.ts:4264-4269 so the panel
 * and the reproducibility export share the same notion of "submitted params".
 *
 * Pass `currentRun` from useUnifiedExecution into this and feed the result
 * into useRunAgainParamCarryover's `lastSubmittedParams`.
 */
export function extractSubmittedParams(currentRun: any): Record<string, any> {
  const nfParams: Record<string, any> = currentRun?.workflowDefinition?.parameters || {};
  if (Object.keys(nfParams).length > 0) return nfParams;
  const toolParameters: Record<string, Record<string, any>> = currentRun?.parameters?.toolParameters || {};
  return Object.values(toolParameters).reduce(
    (acc, paramMap) => Object.assign(acc, paramMap),
    {} as Record<string, any>,
  );
}
