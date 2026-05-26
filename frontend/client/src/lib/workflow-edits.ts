/**
 * Gap 2 — Chat-driven workflow edits.
 *
 * Discriminated-union schema for edit ops the assistant may emit alongside
 * its text reply, plus a pure reducer that applies them to a workflow
 * artifact. Both pieces are pure and testable; integration (where the ops
 * arrive on the wire, where the reducer is called, where the UI confirms
 * structural ops) belongs in chat-with-artifacts.tsx and ai_assistant.py.
 *
 * See: docs/20260521_GAP2_CHAT_DRIVEN_EDITS.md
 *
 * v1 supports four ops:
 *   - set_param: change a parameter value on an existing step
 *   - add_step: splice a new step into a chain after an existing step
 *   - remove_step: drop a step from a chain
 *   - reorder: move a step to a new position (linear DAG only)
 *
 * Compound DAG edits, multi-step transformations, and undo/redo are out of
 * scope for v1.
 */

export type WorkflowEdit =
  | { op: 'set_param'; stepId: string; paramName: string; value: unknown }
  | { op: 'add_step'; afterStepId: string | null; workflowPath: string; params?: Record<string, unknown> }
  | { op: 'remove_step'; stepId: string }
  | { op: 'reorder'; stepId: string; beforeStepId: string };

export interface WorkflowStep {
  id: string;
  workflow_path?: string;
  nextflow_path?: string;
  workflow_name?: string;
  params?: Record<string, unknown>;
  parameters?: Record<string, unknown>;
  [key: string]: unknown;
}

export interface WorkflowArtifact {
  pipeline_steps?: WorkflowStep[];
  chain_steps?: WorkflowStep[];
  inline_parameters?: Record<string, unknown>;
  parameters?: Record<string, unknown>;
  [key: string]: unknown;
}

export interface ApplyResult {
  next: WorkflowArtifact;
  applied: WorkflowEdit[];
  rejected: Array<{ edit: WorkflowEdit; reason: string }>;
}

/**
 * Pure reducer. Returns a new artifact, never mutates the input.
 *
 * Steps live under `pipeline_steps` for AI-generated chains and `chain_steps`
 * for curated chains. We touch whichever array is present; if neither, the
 * artifact is treated as a single-workflow case where `set_param` writes to
 * `inline_parameters`/`parameters` directly.
 */
export function applyWorkflowEdits(
  workflow: WorkflowArtifact,
  edits: ReadonlyArray<WorkflowEdit>,
): ApplyResult {
  const applied: WorkflowEdit[] = [];
  const rejected: Array<{ edit: WorkflowEdit; reason: string }> = [];

  // Clone the artifact once at the top so each op sees the cumulative result.
  let next: WorkflowArtifact = deepClone(workflow);

  for (const edit of edits) {
    try {
      switch (edit.op) {
        case 'set_param':
          next = applySetParam(next, edit, rejected);
          break;
        case 'add_step':
          next = applyAddStep(next, edit, rejected);
          break;
        case 'remove_step':
          next = applyRemoveStep(next, edit, rejected);
          break;
        case 'reorder':
          next = applyReorder(next, edit, rejected);
          break;
        default: {
          const _exhaustive: never = edit;
          rejected.push({ edit: edit as WorkflowEdit, reason: `unknown op` });
          break;
        }
      }
      if (rejected.length === 0 || rejected[rejected.length - 1].edit !== edit) {
        applied.push(edit);
      }
    } catch (e: any) {
      rejected.push({ edit, reason: e?.message || 'apply threw' });
    }
  }

  return { next, applied, rejected };
}

function applySetParam(
  wf: WorkflowArtifact,
  edit: Extract<WorkflowEdit, { op: 'set_param' }>,
  rejected: ApplyResult['rejected'],
): WorkflowArtifact {
  const steps = getStepsArray(wf);
  if (steps) {
    const step = steps.find((s) => s.id === edit.stepId);
    if (!step) {
      rejected.push({ edit, reason: `step '${edit.stepId}' not found` });
      return wf;
    }
    // Prefer .params; fall back to .parameters; create .params if neither.
    if (step.parameters && !step.params) {
      step.parameters[edit.paramName] = edit.value;
    } else {
      step.params = { ...(step.params || {}), [edit.paramName]: edit.value };
    }
    return wf;
  }
  // Single-workflow case: write to top-level inline_parameters/parameters.
  if (wf.inline_parameters) {
    wf.inline_parameters[edit.paramName] = edit.value;
  } else if (wf.parameters) {
    (wf.parameters as Record<string, unknown>)[edit.paramName] = edit.value;
  } else {
    wf.inline_parameters = { [edit.paramName]: edit.value };
  }
  return wf;
}

function applyAddStep(
  wf: WorkflowArtifact,
  edit: Extract<WorkflowEdit, { op: 'add_step' }>,
  rejected: ApplyResult['rejected'],
): WorkflowArtifact {
  const steps = getStepsArray(wf);
  if (!steps) {
    rejected.push({ edit, reason: 'workflow is not a chain (no pipeline_steps/chain_steps)' });
    return wf;
  }
  const newStep: WorkflowStep = {
    id: makeStepId(steps),
    workflow_path: edit.workflowPath,
    nextflow_path: edit.workflowPath,
    workflow_name: deriveWorkflowName(edit.workflowPath),
    params: edit.params || {},
  };
  if (edit.afterStepId === null) {
    steps.unshift(newStep);
  } else {
    const idx = steps.findIndex((s) => s.id === edit.afterStepId);
    if (idx === -1) {
      rejected.push({ edit, reason: `afterStepId '${edit.afterStepId}' not found` });
      return wf;
    }
    steps.splice(idx + 1, 0, newStep);
  }
  return wf;
}

function applyRemoveStep(
  wf: WorkflowArtifact,
  edit: Extract<WorkflowEdit, { op: 'remove_step' }>,
  rejected: ApplyResult['rejected'],
): WorkflowArtifact {
  const steps = getStepsArray(wf);
  if (!steps) {
    rejected.push({ edit, reason: 'workflow is not a chain' });
    return wf;
  }
  const idx = steps.findIndex((s) => s.id === edit.stepId);
  if (idx === -1) {
    rejected.push({ edit, reason: `step '${edit.stepId}' not found` });
    return wf;
  }
  steps.splice(idx, 1);
  return wf;
}

function applyReorder(
  wf: WorkflowArtifact,
  edit: Extract<WorkflowEdit, { op: 'reorder' }>,
  rejected: ApplyResult['rejected'],
): WorkflowArtifact {
  const steps = getStepsArray(wf);
  if (!steps) {
    rejected.push({ edit, reason: 'workflow is not a chain' });
    return wf;
  }
  const srcIdx = steps.findIndex((s) => s.id === edit.stepId);
  const dstIdx = steps.findIndex((s) => s.id === edit.beforeStepId);
  if (srcIdx === -1) {
    rejected.push({ edit, reason: `stepId '${edit.stepId}' not found` });
    return wf;
  }
  if (dstIdx === -1) {
    rejected.push({ edit, reason: `beforeStepId '${edit.beforeStepId}' not found` });
    return wf;
  }
  if (srcIdx === dstIdx) return wf;
  const [moved] = steps.splice(srcIdx, 1);
  const newDstIdx = srcIdx < dstIdx ? dstIdx - 1 : dstIdx;
  steps.splice(newDstIdx, 0, moved);
  return wf;
}

// ────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────

function getStepsArray(wf: WorkflowArtifact): WorkflowStep[] | null {
  if (Array.isArray(wf.pipeline_steps)) return wf.pipeline_steps;
  if (Array.isArray(wf.chain_steps)) return wf.chain_steps;
  return null;
}

function makeStepId(existing: WorkflowStep[]): string {
  const used = new Set(existing.map((s) => s.id));
  for (let i = 1; ; i++) {
    const candidate = `step-${existing.length + i}`;
    if (!used.has(candidate)) return candidate;
  }
}

function deriveWorkflowName(workflowPath: string): string {
  // For nf-core-style paths like `docking/vina_dock/main.nf` the meaningful
  // name is the parent directory of main.nf, not the filename. Fall back to
  // the last non-"main" segment.
  const parts = workflowPath.split('/').filter(Boolean);
  for (let i = parts.length - 1; i >= 0; i--) {
    const stripped = parts[i].replace(/\.(nf|ga)$/i, '');
    if (stripped && stripped.toLowerCase() !== 'main') return stripped;
  }
  return workflowPath;
}

function deepClone<T>(x: T): T {
  // Structured clone would be ideal but we can't rely on it everywhere;
  // workflow artifacts are JSON-shaped so this is safe.
  return JSON.parse(JSON.stringify(x)) as T;
}
