/**
 * Ground chat prose to the engine-bound payload (2026-11-13 Admet Pred / fake-chain).
 *
 * When the engine returns a single workflow_ga (not workflow_type chain/pipeline),
 * the assistant must not narrate a multi-step "composite pipeline" as if it were
 * an executable chain. Full integrator/chain composition remains deferred.
 */

export type GroundableWorkflowPayload = {
  workflow_type?: string | null;
  workflow_ga?: { name?: string | null } | null;
  nextflow_path?: string | null;
  chain_name?: string | null;
  chain_steps?: unknown;
  pipeline_steps?: unknown;
  success?: boolean;
  error?: unknown;
};

/** True when the payload is a single bound workflow card, not a chain/pipeline DAG. */
export function isSingleBoundWorkflow(payload: GroundableWorkflowPayload | null | undefined): boolean {
  if (!payload || payload.error) return false;
  const wt = String(payload.workflow_type || '').toLowerCase();
  if (wt === 'chain' || wt === 'pipeline' || wt === 'cryosparc') return false;
  if (payload.chain_name || (Array.isArray(payload.chain_steps) && payload.chain_steps.length > 0)) {
    return false;
  }
  if (Array.isArray(payload.pipeline_steps) && payload.pipeline_steps.length > 0) return false;
  return !!(payload.workflow_ga || payload.nextflow_path);
}

/**
 * System/user prompt directive that constrains the reply to the single bound
 * workflow. Empty string when the payload is a real chain/pipeline (or unbound).
 */
export function singleWorkflowGroundingDirective(
  payload: GroundableWorkflowPayload | null | undefined,
  displayName?: string,
): string {
  if (!isSingleBoundWorkflow(payload)) return '';
  const name =
    (displayName && displayName.trim()) ||
    String(payload?.workflow_ga?.name || '').trim() ||
    'the bound workflow';
  return [
    `ENGINE-BOUND SINGLE WORKFLOW: The panel is bound to exactly one workflow: "${name}".`,
    'Describe ONLY this workflow (its inputs, key steps, expected outputs).',
    'Do NOT narrate a multi-step composite pipeline, chain, or numbered "(1) docking (2) ADMET (3) pharmacophore (4) ranking" plan as if it were the executable payload.',
    'Do NOT invent sibling phases that are not this workflow.',
    'If the user asked for a multi-criteria triage/chain and this single workflow cannot cover every step, say so in one plain sentence after describing what THIS workflow does — do not fake a chain in prose.',
  ].join(' ');
}
