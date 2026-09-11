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
      missingInputStepIds: ["0", "1"],
      invalidInputCount: 0,
      inputsRequired: true,
      inputsInvalid: false,
      inputsUnsupportedForNextflow: false,
    });
  });

  it("does not mistake UI inputData-shaped state for the documented inputs contract", () => {
    expect(validateWorkflowInputs(workflowWithInputs, { datasets: ["dataset-1"] })).toEqual({
      inputStepsCount: 2,
      missingInputStepIds: ["0", "1"],
      invalidInputCount: 0,
      inputsRequired: true,
      inputsInvalid: false,
      inputsUnsupportedForNextflow: false,
    });
  });

  it("requires a well-formed dataset binding for every data input step", () => {
    expect(validateWorkflowInputs(workflowWithInputs, [
      { id: "dataset-1", src: "hda", step_id: 0 },
      { id: "dataset-2", src: "hdca", stepId: "1" },
    ], "galaxy")).toEqual({
      inputStepsCount: 2,
      missingInputStepIds: [],
      invalidInputCount: 0,
      inputsRequired: false,
      inputsInvalid: false,
      inputsUnsupportedForNextflow: false,
    });
    expect(validateWorkflowInputs({ steps: { 0: { type: "tool" } } }, [], "galaxy")).toEqual({
      inputStepsCount: 0,
      missingInputStepIds: [],
      invalidInputCount: 0,
      inputsRequired: false,
      inputsInvalid: false,
      inputsUnsupportedForNextflow: false,
    });
  });

  it("rejects malformed, unbound, and incomplete inputs instead of launching with dropped data", () => {
    expect(validateWorkflowInputs(workflowWithInputs, [{ id: "dataset-1", src: "hda" }], "galaxy"))
      .toMatchObject({ inputsInvalid: true, inputsRequired: true, invalidInputCount: 1, missingInputStepIds: ["0", "1"] });
    expect(validateWorkflowInputs(workflowWithInputs, [
      { id: "dataset-1", src: "hda", step_id: 0 },
    ], "galaxy"))
      .toMatchObject({ inputsInvalid: false, inputsRequired: true, missingInputStepIds: ["1"] });
  });

  it("reads Galaxy definitions wrapped in workflow_ga", () => {
    expect(validateWorkflowInputs({ steps: {}, workflow_ga: workflowWithInputs }, [
      { id: "dataset-1", src: "hda", step_id: 0 },
      { id: "dataset-2", src: "hda", step_id: 1 },
    ], "galaxy")).toMatchObject({ inputStepsCount: 2, inputsRequired: false, inputsInvalid: false });
  });

  it("blocks the default Nextflow execution engine rather than silently dropping accepted datasets", () => {
    expect(validateWorkflowInputs(workflowWithInputs, [
      { id: "dataset-1", src: "hda", step_id: 0 },
      { id: "dataset-2", src: "hda", step_id: 1 },
    ], "nextflow"))
      .toMatchObject({ inputsRequired: false, inputsInvalid: false, inputsUnsupportedForNextflow: true });
  });
});
