/**
 * Input gate for workflow execution requests.
 *
 * Keep this independent of Express and the workflow launcher: a rejected
 * request must be identified before any run or external invocation exists.
 */
export function requiredWorkflowInputCount(workflowDefinition: unknown): number {
  if (!workflowDefinition || typeof workflowDefinition !== "object") return 0;
  const steps = (workflowDefinition as { steps?: unknown }).steps;
  if (!steps || typeof steps !== "object") return 0;

  return Object.values(steps).filter((step) => {
    const type = step && typeof step === "object" ? (step as { type?: unknown }).type : undefined;
    return type === "data_input" || type === "data_collection_input";
  }).length;
}

export function validateWorkflowInputs(
  workflowDefinition: unknown,
  inputs: unknown,
): { inputStepsCount: number; inputsRequired: boolean; inputsUnsupportedForNextflow: boolean } {
  const inputStepsCount = requiredWorkflowInputCount(workflowDefinition);
  const definition = workflowDefinition && typeof workflowDefinition === "object"
    ? workflowDefinition as { workflow_type?: unknown; nextflow_path?: unknown }
    : {};
  const hasInputs = Array.isArray(inputs) && inputs.length > 0;
  const isNextflowDirect = definition.workflow_type === "nextflow" || typeof definition.nextflow_path === "string";
  return {
    inputStepsCount,
    // Deliberately accept only the documented `inputs` array. `inputData` is
    // presentation state, not an execution input contract.
    inputsRequired: inputStepsCount > 0 && !hasInputs,
    // Nextflow direct execution currently has no step-id → parameter binding.
    // Rejecting is safer than accepting a dataset and silently dropping it.
    inputsUnsupportedForNextflow: inputStepsCount > 0 && hasInputs && isNextflowDirect,
  };
}
