/** Typed response state shared by chat cards and panel auto-opening.
 * Never infer permission to execute from the assistant's prose.
 */
export function awaitsWorkflowInput(workflow: any, metadata: any = {}): boolean {
  const hasProposal = !!(workflow?.nextflow_path || workflow?.steps || workflow?.workflow_ga?.steps);
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
    || (Array.isArray(metadata?.intentClarification?.candidates) && metadata.intentClarification.candidates.length > 0)
    || (Array.isArray(metadata?.paramClarifications) && metadata.paramClarifications.length > 0)
    || (workflow?.needs_user_feedback === true && Array.isArray(workflow?.candidate_workflows) && workflow.candidate_workflows.length > 0);
}
