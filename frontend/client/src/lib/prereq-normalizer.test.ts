/**
 * normalizePrereqChecklist — pure-function tests for every branch.
 *
 * This helper converts the backend's PrerequisitesValidator payload into
 * the {items, canRun, overrideAllowed} shape consumed by the workflow
 * viewer's prerequisites checklist UI. It has 6 distinct branches per
 * field (input_data, required_parameters) plus the canRun gate logic,
 * and zero existing test coverage.
 */
import { describe, it, expect } from "vitest";
import { normalizePrereqChecklist } from "./prereq-normalizer";

describe("normalizePrereqChecklist", () => {
  it("returns undefined when no validator payload is provided", () => {
    expect(normalizePrereqChecklist(null)).toBeUndefined();
    expect(normalizePrereqChecklist(undefined)).toBeUndefined();
  });

  it("flags input_data as warning when required inputs are missing", () => {
    const out = normalizePrereqChecklist({
      analysis: { missingInputs: [{ inputName: "reads" }, { inputName: "ref" }], missingParameters: [], inputMappings: [] },
    });
    const input = out!.items.find(i => i.id === "input_data")!;
    expect(input.status).toBe("warning");
    expect(input.reason).toContain("2 required input");
    expect(input.actionHint).toMatch(/Upload or select/i);
    expect(input.chatPrompt).toBeTruthy();
  });

  it("flags input_data as ok when inputMappings are present", () => {
    const out = normalizePrereqChecklist({
      analysis: { missingInputs: [], missingParameters: [], inputMappings: [{ inputName: "reads", datasetId: "ds1" }] },
    });
    expect(out!.items.find(i => i.id === "input_data")!.status).toBe("ok");
  });

  it("flags input_data as ok with the 'inline data' reason when hasInlineData=true", () => {
    const out = normalizePrereqChecklist(
      { analysis: { missingInputs: [], missingParameters: [], inputMappings: [] } },
      { hasInlineData: true }
    );
    const input = out!.items.find(i => i.id === "input_data")!;
    expect(input.status).toBe("ok");
    expect(input.reason).toMatch(/inline data/i);
  });

  it("flags input_data as warning ('no input detected') when neither mappings nor inline data exist", () => {
    const out = normalizePrereqChecklist({
      analysis: { missingInputs: [], missingParameters: [], inputMappings: [] },
    });
    const input = out!.items.find(i => i.id === "input_data")!;
    expect(input.status).toBe("warning");
    expect(input.reason).toMatch(/No input data detected/i);
  });

  it("marks canRun=false when a required parameter has no default", () => {
    const out = normalizePrereqChecklist({
      analysis: {
        missingInputs: [],
        missingParameters: [{ stepId: "s1", paramName: "genome" }],
        inputMappings: [{ inputName: "reads", datasetId: "ds1" }],
      },
      requirements: {
        parameters: [{ stepId: "s1", paramName: "genome", optional: false, defaultValue: null }],
      },
    });
    const params = out!.items.find(i => i.id === "required_parameters")!;
    expect(params.status).toBe("missing");
    expect(out!.canRun).toBe(false);
  });

  it("marks canRun=true (warning only) when required params have defaults", () => {
    const out = normalizePrereqChecklist({
      analysis: {
        missingInputs: [],
        missingParameters: [{ stepId: "s1", paramName: "threads" }],
        inputMappings: [{ inputName: "reads", datasetId: "ds1" }],
      },
      requirements: {
        parameters: [{ stepId: "s1", paramName: "threads", optional: false, defaultValue: 4 }],
      },
    });
    const params = out!.items.find(i => i.id === "required_parameters")!;
    expect(params.status).toBe("warning");
    expect(params.reason).toMatch(/will use defaults/);
    expect(out!.canRun).toBe(true);
  });

  it("includes optional/suggested params in the warning, not as a hard block", () => {
    const out = normalizePrereqChecklist({
      analysis: {
        missingInputs: [],
        missingParameters: [
          { stepId: "s1", paramName: "min_length", suggestedOptions: [{ value: 30 }, { value: 50 }] },
        ],
        inputMappings: [{ inputName: "reads", datasetId: "ds1" }],
      },
      requirements: { parameters: [] },
    });
    const params = out!.items.find(i => i.id === "required_parameters")!;
    expect(params.status).toBe("warning");
    expect(out!.canRun).toBe(true);
  });

  it("marks required_parameters as ok when nothing is missing", () => {
    const out = normalizePrereqChecklist({
      analysis: { missingInputs: [], missingParameters: [], inputMappings: [{ inputName: "reads", datasetId: "ds1" }] },
      requirements: { parameters: [] },
    });
    expect(out!.items.find(i => i.id === "required_parameters")!.status).toBe("ok");
    expect(out!.canRun).toBe(true);
  });

  it("propagates allowLowConfidenceOverride into overrideAllowed", () => {
    const out1 = normalizePrereqChecklist(
      { analysis: { missingInputs: [], missingParameters: [], inputMappings: [] } },
      { allowLowConfidenceOverride: true }
    );
    const out2 = normalizePrereqChecklist(
      { analysis: { missingInputs: [], missingParameters: [], inputMappings: [] } },
      { allowLowConfidenceOverride: false }
    );
    expect(out1!.overrideAllowed).toBe(true);
    expect(out2!.overrideAllowed).toBe(false);
  });

  it("does not count an optional missing param as a hard blocker even without suggestedOptions", () => {
    const out = normalizePrereqChecklist({
      analysis: {
        missingInputs: [],
        missingParameters: [{ stepId: "s1", paramName: "trailing_q" }],
        inputMappings: [{ inputName: "reads", datasetId: "ds1" }],
      },
      requirements: {
        parameters: [{ stepId: "s1", paramName: "trailing_q", optional: true }],
      },
    });
    expect(out!.canRun).toBe(true);
  });
});
