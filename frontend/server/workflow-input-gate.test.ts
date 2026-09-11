import { describe, expect, it } from "vitest";
import { validateWorkflowInputs } from "./workflow-input-gate";

const workflowWithInputs = {
  steps: {
    0: { type: "data_input" },
    1: { type: "data_collection_input" },
    2: { type: "tool" },
  },
};

describe("workflow execution input gate", () => {
  it("rejects a workflow with input steps before a launcher can be reached", () => {
    expect(validateWorkflowInputs(workflowWithInputs, undefined)).toEqual({
      inputStepsCount: 2,
      inputsRequired: true,
    });
  });

  it("does not mistake UI inputData-shaped state for the documented inputs contract", () => {
    expect(validateWorkflowInputs(workflowWithInputs, { datasets: ["dataset-1"] })).toEqual({
      inputStepsCount: 2,
      inputsRequired: true,
    });
  });

  it("accepts a non-empty documented inputs array and ignores ordinary tool steps", () => {
    expect(validateWorkflowInputs(workflowWithInputs, [{ id: "dataset-1" }])).toEqual({
      inputStepsCount: 2,
      inputsRequired: false,
    });
    expect(validateWorkflowInputs({ steps: { 0: { type: "tool" } } }, [])).toEqual({
      inputStepsCount: 0,
      inputsRequired: false,
    });
  });
});
