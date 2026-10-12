/**
 * isRunnableWorkflow — decide whether a generated workflow payload represents a
 * RUNNABLE workflow (i.e. the chat should report responseState = "workflow_ready"
 * and surface a Confirm & Run affordance), as opposed to a failed/empty generation.
 *
 * Extracted from server/routes.ts (/api/chat/stream handler) so the allowlist is
 * unit-testable in isolation — it is security/UX-relevant (a wrong answer mislabels
 * a valid draft as workflow_failed, or vice-versa). Keep this the single source of
 * truth: routes.ts imports it; the test pins every accepted shape.
 *
 * Runnable shapes:
 *   - a Galaxy/Nextflow workflow object (workflow_ga) or an explicit nextflow_path
 *   - a chain (workflow_type === 'chain' or a chain_name)
 *   - a CryoSPARC workflow (workflow_type === 'cryosparc')
 *   - a sequential/DAG pipeline card (workflow_type === 'pipeline' with a NON-EMPTY
 *     pipeline_steps array) — the galaxy-assistant.ts processSequentialPipeline shape,
 *     which has no workflow_ga/nextflow_path but IS runnable via whole-plan Confirm & Run.
 * In all cases the payload must have success === true and no error.
 */
export function isRunnableWorkflow(workflowPayload: any): boolean {
  return !!(
    workflowPayload?.success &&
    !workflowPayload?.error &&
    (workflowPayload?.workflow_ga ||
      workflowPayload?.nextflow_path ||
      workflowPayload?.workflow_type === "chain" ||
      workflowPayload?.chain_name ||
      workflowPayload?.workflow_type === "cryosparc" ||
      (workflowPayload?.workflow_type === "pipeline" &&
        Array.isArray(workflowPayload?.pipeline_steps) &&
        workflowPayload.pipeline_steps.length > 0))
  );
}
