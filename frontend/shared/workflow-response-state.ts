/** Typed response state shared by chat cards and panel auto-opening.
 * Never infer permission to execute from the assistant's prose.
 */
export function awaitsWorkflowInput(workflow: any, metadata: any = {}): boolean {
  // A multi-step chain / pipeline IS a concrete proposal (its steps are the chain_steps /
  // pipeline_steps array, not `steps`/`nextflow_path`). Without this, a `workflow_type:'chain'`
  // turn is classified as "awaiting input" → metadata.type !== 'workflow' → the right-hand panel
  // never rebinds and silently keeps the previous single workflow (2026-11-12 panel-stale bug).
  const hasProposal = !!(
    workflow?.nextflow_path || workflow?.steps || workflow?.workflow_ga?.steps
    || workflow?.workflow_type === 'chain' || workflow?.workflow_type === 'pipeline'
    || (Array.isArray(workflow?.chain_steps) && workflow.chain_steps.length > 0)
    || (Array.isArray(workflow?.pipeline_steps) && workflow.pipeline_steps.length > 0)
  );
  return hasPendingWorkflowClarification(workflow, metadata)
    || (!hasProposal && (workflow?.needs_user_feedback === true || metadata?.needsUserFeedback === true));
}

export function hasGeneratedWorkflow(workflow: any, metadata: any = {}): boolean {
  return !!workflow && workflow.success !== false && !workflow.error
    && !awaitsWorkflowInput(workflow, metadata);
}

/** Blocking clarification is distinct from a proposal asking for ordinary review.
 * The execution route still validates required values and scientific confidence.
 */
export function hasPendingWorkflowClarification(workflow: any, metadata: any = {}): boolean {
  return workflow?.workflow_type === 'disambiguation'
    || workflow?.workflow_type === 'credential_required'
    || (Array.isArray(metadata?.intentClarification?.candidates) && metadata.intentClarification.candidates.length > 0)
    || (Array.isArray(metadata?.paramClarifications) && metadata.paramClarifications.length > 0)
    || (workflow?.needs_user_feedback === true && Array.isArray(workflow?.candidate_workflows) && workflow.candidate_workflows.length > 0);
}

/**
 * Which reply format the chat must use for a workflow turn. Selected in code
 * from real signals, never left to the model:
 *  - `generated_needs_input` — a workflow was identified and generated (the card
 *    and panel show it) but a REQUIRED data input is still unbound and the
 *    message carries no data. The reply names the workflow and asks for that
 *    input; it must never say the workflow "could not be generated".
 *  - `generated_ready` — runnable and its required data inputs are bound.
 *  - `clarification_needed` / `technical_failure` — generation actually failed
 *    (without / with inline data in the message).
 *  - `other` — not a workflow-generation turn, or no workflow object to judge.
 */
export type WorkflowReplyState =
  | 'other'
  | 'generated_ready'
  | 'generated_needs_input'
  | 'clarification_needed'
  | 'technical_failure';

export interface WorkflowReplySignals {
  isWorkflowTurn: boolean;
  runnableWorkflow: boolean;
  generationFailed: boolean;
  /** Inline data detected in the message (SMILES, accession, fixture, …). */
  hasInlineData: boolean;
  /** The message itself carries data for the run (uploaded datasets, accession, attached files). */
  messageCarriesData: boolean;
  /** Required data inputs of the generated workflow that are still unbound. */
  unboundRequiredInputs: readonly unknown[];
}

export function decideWorkflowReplyState(s: WorkflowReplySignals): WorkflowReplyState {
  if (s.runnableWorkflow) {
    return s.unboundRequiredInputs.length > 0 && !s.messageCarriesData
      ? 'generated_needs_input'
      : 'generated_ready';
  }
  if (s.isWorkflowTurn && s.generationFailed) return s.hasInlineData ? 'technical_failure' : 'clarification_needed';
  return 'other';
}
