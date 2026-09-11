import { describe, expect, it } from "vitest";
import { presentWorkflowExecutionError } from "./workflow-execution-error";
import { toWorkflowExecutionErrorDetails } from "@/hooks/useUnifiedExecution";

describe("presentWorkflowExecutionError", () => {
  it("preserves execute API code and structured missing fields", () => {
    expect(toWorkflowExecutionErrorDetails({
      error: "missing_required_params",
      message: "missing values",
      missing: [{ name: "smiles", label: "SMILES" }],
      guidance: "fill it",
    }, "fallback")).toMatchObject({
      code: "missing_required_params",
      message: "missing values",
      missing: [{ name: "smiles", label: "SMILES" }],
      guidance: "fill it",
    });
  });

  it("lists actual missing parameters and confirms no compute was launched", () => {
    const result = presentWorkflowExecutionError({ code: "missing_required_params", message: "Workflow needs parameters", missing: [{ name: "smiles", label: "Compound SMILES" }, { name: "dose" }] });
    expect(result.title).toBe("Complete required parameters");
    expect(result.missingLabels).toEqual(["Compound SMILES", "dose"]);
    expect(result.detail).toMatch(/no compute was used/i);
  });

  it("turns an input gate into an attach-data action", () => {
    expect(presentWorkflowExecutionError({ code: "inputs_required", message: "inputs missing", inputStepsCount: 2 })).toMatchObject({ title: "Attach input data before running", detail: "This workflow needs data for 2 input steps." });
  });

  it("does not tell users to retry an unsupported Nextflow input binding", () => {
    const result = presentWorkflowExecutionError({ code: "nextflow_inputs_not_supported", message: "not supported" });
    expect(result.title).toMatch(/not supported yet/i);
    expect(result.detail).toMatch(/No compute was started/i);
    expect(result.action).not.toMatch(/^Try again$/i);
  });
});
