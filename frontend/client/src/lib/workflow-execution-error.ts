import type { WorkflowExecutionErrorDetails } from "@/hooks/useUnifiedExecution";

export interface WorkflowExecutionErrorPresentation {
  title: string;
  detail: string;
  action: string;
  missingLabels: string[];
}

/** Translate stable execute-API errors into a user action, without exposing infrastructure. */
export function presentWorkflowExecutionError(error: WorkflowExecutionErrorDetails): WorkflowExecutionErrorPresentation {
  const missingLabels = (error.missing || []).map((item) => item.label || item.name);
  switch (error.code) {
    case "missing_required_params":
      return { title: "Complete required parameters", detail: "This workflow was not started, so no compute was used.", action: error.guidance || "Open the workflow parameters, fill the listed values, then run again.", missingLabels };
    case "inputs_required":
      return { title: "Attach input data before running", detail: error.inputStepsCount ? `This workflow needs data for ${error.inputStepsCount} input step${error.inputStepsCount === 1 ? "" : "s"}.` : "This workflow needs input data.", action: "Attach or select the required dataset, then run again.", missingLabels: [] };
    case "nextflow_inputs_not_supported":
      return { title: "This workflow's input binding is not supported yet", detail: "No compute was started and your datasets were not changed.", action: "Choose a workflow that accepts parameterized dataset paths, or ask BioMate to prepare a compatible workflow.", missingLabels: [] };
    default:
      return { title: "Execution failed", detail: error.message || "The workflow could not be started.", action: error.guidance || "Review inputs and parameters, then try again.", missingLabels };
  }
}
