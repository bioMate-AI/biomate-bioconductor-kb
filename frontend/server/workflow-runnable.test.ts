import { describe, it, expect } from "vitest";
import { isRunnableWorkflow } from "./workflow-runnable";

describe("isRunnableWorkflow", () => {
  it("accepts a Galaxy/Nextflow workflow (workflow_ga)", () => {
    expect(isRunnableWorkflow({ success: true, workflow_ga: { name: "x" } })).toBe(true);
  });

  it("accepts an explicit nextflow_path", () => {
    expect(isRunnableWorkflow({ success: true, nextflow_path: "nf-core/rnaseq/main.nf" })).toBe(true);
  });

  it("accepts a chain by workflow_type or chain_name", () => {
    expect(isRunnableWorkflow({ success: true, workflow_type: "chain", chain_steps: [] })).toBe(true);
    expect(isRunnableWorkflow({ success: true, chain_name: "bulk_rnaseq_de_analysis" })).toBe(true);
  });

  it("accepts a cryosparc workflow", () => {
    expect(isRunnableWorkflow({ success: true, workflow_type: "cryosparc" })).toBe(true);
  });

  it("accepts a pipeline card with a NON-EMPTY pipeline_steps (the fix)", () => {
    expect(
      isRunnableWorkflow({
        success: true,
        workflow_type: "pipeline",
        pipeline_steps: [{ workflow_name: "QC" }, { workflow_name: "Align" }],
        step_count: 2,
      }),
    ).toBe(true);
  });

  it("REJECTS a pipeline card with empty or missing pipeline_steps", () => {
    expect(isRunnableWorkflow({ success: true, workflow_type: "pipeline", pipeline_steps: [] })).toBe(false);
    expect(isRunnableWorkflow({ success: true, workflow_type: "pipeline" })).toBe(false);
    expect(isRunnableWorkflow({ success: true, workflow_type: "pipeline", pipeline_steps: "nope" as any })).toBe(false);
  });

  it("REJECTS when success is falsy even for an otherwise-runnable shape", () => {
    expect(isRunnableWorkflow({ success: false, workflow_ga: { name: "x" } })).toBe(false);
    expect(isRunnableWorkflow({ workflow_type: "pipeline", pipeline_steps: [{}] })).toBe(false); // no success
  });

  it("REJECTS when an error is present", () => {
    expect(isRunnableWorkflow({ success: true, error: "db_unavailable", workflow_ga: { name: "x" } })).toBe(false);
    expect(
      isRunnableWorkflow({ success: true, error: "boom", workflow_type: "pipeline", pipeline_steps: [{}] }),
    ).toBe(false);
  });

  it("REJECTS a clarification / non-runnable payload", () => {
    expect(isRunnableWorkflow({ success: false, workflow_type: "clarification" })).toBe(false);
    expect(isRunnableWorkflow({ success: true })).toBe(false); // success but no runnable shape
  });

  it("REJECTS null / undefined / empty", () => {
    expect(isRunnableWorkflow(null)).toBe(false);
    expect(isRunnableWorkflow(undefined)).toBe(false);
    expect(isRunnableWorkflow({})).toBe(false);
  });
});
