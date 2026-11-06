/**
 * Numeric-param guardrail (coerceNumericParams).
 *
 * Regression: the WGS capstone (SRR1518169, "subsample: max_spots=500000)")
 * failed because the LLM extractor captured max_spots="500000)" (trailing paren
 * from the prose). The workflow's `params.max_spots as int` then threw a Groovy
 * NumberFormatException and failed the run in ~14s. The guardrail strips the
 * prose punctuation back to a clean numeric token for "number"-typed params
 * while leaving clean values and non-numeric sentinels untouched.
 */
import { describe, it, expect } from "vitest";
import { coerceNumericParams } from "./lib/paramRules.js";
import type { WorkflowSchema } from "./lib/paramSchema.js";

function schema(params: WorkflowSchema["params"]): WorkflowSchema {
  return { workflowName: "test-wf", params, source: "workflow_ga" } as WorkflowSchema;
}

const numParam = (name: string, required = false) =>
  ({ name, type: "number", required } as WorkflowSchema["params"][number]);

describe("coerceNumericParams", () => {
  it("strips a trailing paren from a numeric value (the WGS max_spots bug)", () => {
    const params: Record<string, string | string[]> = { max_spots: "500000)" };
    const notes = coerceNumericParams(params, schema([numParam("max_spots")]));
    expect(params.max_spots).toBe("500000");
    expect(notes).toEqual([{ key: "max_spots", from: "500000)", to: "500000" }]);
  });

  it("strips thousands separators", () => {
    const params: Record<string, string | string[]> = { max_spots: "500,000" };
    coerceNumericParams(params, schema([numParam("max_spots")]));
    expect(params.max_spots).toBe("500000");
  });

  it("extracts a number embedded in prose", () => {
    const params: Record<string, string | string[]> = { n_reads: "about 1000 reads" };
    coerceNumericParams(params, schema([numParam("n_reads")]));
    expect(params.n_reads).toBe("1000");
  });

  it("preserves floats and scientific notation", () => {
    const params: Record<string, string | string[]> = { thr: "0.05).", exp: "5e5 spots" };
    coerceNumericParams(
      params,
      schema([numParam("thr"), numParam("exp")]),
    );
    expect(params.thr).toBe("0.05");
    expect(params.exp).toBe("5e5");
  });

  it("leaves already-clean numbers untouched (no note)", () => {
    const params: Record<string, string | string[]> = { max_spots: "500000", f: "-1.5" };
    const notes = coerceNumericParams(
      params,
      schema([numParam("max_spots"), numParam("f")]),
    );
    expect(params.max_spots).toBe("500000");
    expect(params.f).toBe("-1.5");
    expect(notes).toHaveLength(0);
  });

  it("leaves non-numeric sentinels (null/auto) untouched so optional params survive", () => {
    const params: Record<string, string | string[]> = { auc_observed: "null", mode: "auto" };
    const notes = coerceNumericParams(
      params,
      schema([numParam("auc_observed"), numParam("mode")]),
    );
    expect(params.auc_observed).toBe("null");
    expect(params.mode).toBe("auto");
    expect(notes).toHaveLength(0);
  });

  it("does not touch non-number-typed params", () => {
    const params: Record<string, string | string[]> = { genome: "hg38)" };
    const notes = coerceNumericParams(
      params,
      schema([{ name: "genome", type: "string", required: false } as WorkflowSchema["params"][number]]),
    );
    expect(params.genome).toBe("hg38)");
    expect(notes).toHaveLength(0);
  });
});
