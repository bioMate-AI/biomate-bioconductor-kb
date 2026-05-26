/**
 * Gap 2 — Rule-based extractor (v1).
 *
 * Frontend-side natural-language → WorkflowEdit[] extractor for the simplest
 * deterministic cases. Deliberately conservative: returns [] when intent is
 * ambiguous so we never apply something the user didn't ask for.
 *
 * The production path is a backend Haiku structured-output extractor with
 * full schema validation against galaxy_ai_tools.db (see Gap 2 doc). Until
 * that lands, this rule layer handles the 80% case (parameter edits in
 * imperative English) without any network round-trip or LLM cost.
 *
 * Patterns recognised (case-insensitive):
 *   "set <param> to <value>"
 *   "change <param> to <value>"
 *   "<param> = <value>"
 *   "<param>: <value>"
 *
 * Plus the trailing "on step <stepId>" / "for step <stepId>" / "in <stepId>"
 * qualifier to disambiguate which step to target in a chain. Without the
 * qualifier we target the first step that already declares the named param,
 * which is unambiguous for most pipelines.
 *
 * See: docs/20260521_GAP2_CHAT_DRIVEN_EDITS.md
 */

import type { WorkflowEdit, WorkflowArtifact, WorkflowStep } from './workflow-edits';

const SET_PATTERNS: RegExp[] = [
  /\b(?:set|change|update)\s+(?:the\s+)?([a-z_][a-z0-9_.-]*)\s+(?:to|=)\s+(.+?)(?:\s+(?:on|for|in)\s+(?:step\s+)?([a-z0-9_.-]+))?\s*[.!]?\s*$/i,
  /\b([a-z_][a-z0-9_.-]*)\s*=\s*(.+?)(?:\s+(?:on|for|in)\s+(?:step\s+)?([a-z0-9_.-]+))?\s*[.!]?\s*$/i,
  /\b([a-z_][a-z0-9_.-]*)\s*:\s*(.+?)(?:\s+(?:on|for|in)\s+(?:step\s+)?([a-z0-9_.-]+))?\s*[.!]?\s*$/i,
];

function coerceValue(raw: string): unknown {
  const trimmed = raw.trim().replace(/^["']|["']$/g, '');
  if (trimmed === '') return '';
  if (/^(true|yes|on)$/i.test(trimmed)) return true;
  if (/^(false|no|off)$/i.test(trimmed)) return false;
  // Integer
  if (/^-?\d+$/.test(trimmed)) return parseInt(trimmed, 10);
  // Float
  if (/^-?\d*\.\d+([eE][+-]?\d+)?$/.test(trimmed)) return parseFloat(trimmed);
  return trimmed;
}

function getSteps(wf: WorkflowArtifact): WorkflowStep[] | null {
  if (Array.isArray(wf.pipeline_steps)) return wf.pipeline_steps;
  if (Array.isArray(wf.chain_steps)) return wf.chain_steps;
  return null;
}

function findStepIdByName(steps: WorkflowStep[], needle: string): string | null {
  const n = needle.toLowerCase();
  // Direct id match
  const byId = steps.find((s) => s.id?.toLowerCase() === n);
  if (byId) return byId.id;
  // Workflow path / name match (suffix of path)
  const byName = steps.find((s) => {
    const path = String(s.workflow_path || s.nextflow_path || '').toLowerCase();
    const name = String(s.workflow_name || '').toLowerCase();
    return path.includes(n) || name.includes(n);
  });
  return byName ? byName.id : null;
}

function findStepIdByParam(steps: WorkflowStep[], paramName: string): string | null {
  const found = steps.find((s) => {
    const params = (s.params || s.parameters) as Record<string, unknown> | undefined;
    return params && Object.prototype.hasOwnProperty.call(params, paramName);
  });
  return found ? found.id : null;
}

/**
 * Extract zero or more WorkflowEdits from a user message + the currently
 * open workflow artifact. Returns [] when nothing clear was matched.
 */
export function extractWorkflowEdits(
  message: string,
  workflow: WorkflowArtifact,
): WorkflowEdit[] {
  if (!message || !workflow) return [];
  const steps = getSteps(workflow);

  for (const re of SET_PATTERNS) {
    const m = message.match(re);
    if (!m) continue;
    const paramName = m[1];
    const rawValue = m[2];
    const stepHint = m[3];
    if (!paramName || rawValue == null) continue;
    const value = coerceValue(rawValue);

    // Resolve target step.
    let stepId: string;
    if (steps) {
      if (stepHint) {
        const resolved = findStepIdByName(steps, stepHint);
        if (!resolved) return []; // user named a step that doesn't exist — abstain
        stepId = resolved;
      } else {
        // Pick the first step that already declares this param. Abstain if no
        // step has it AND there are multiple steps — too ambiguous.
        const fromParam = findStepIdByParam(steps, paramName);
        if (fromParam) {
          stepId = fromParam;
        } else if (steps.length === 1) {
          stepId = steps[0].id;
        } else {
          return [];
        }
      }
    } else {
      // Single-workflow artifact: stepId is unused by the reducer's single
      // path but we still need a value.
      stepId = 'single';
    }

    return [{ op: 'set_param', stepId, paramName, value }];
  }

  return [];
}
