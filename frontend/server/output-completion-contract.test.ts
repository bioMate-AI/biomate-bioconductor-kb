import { describe, expect, it } from "vitest";
import { assessOutputCompletion } from "./output-completion-contract";

describe("output completion contract", () => {
  it("does not treat a completed generic workflow with no registered outputs as result-ready", () => {
    expect(assessOutputCompletion({ metadata: { domain: "transcriptomics" } }, 0)).toEqual({
      mode: "artifacts_required",
      state: "artifact_unavailable",
      registeredOutputCount: 0,
      meetsContract: false,
    });
  });

  it("accepts a registered output for the default contract", () => {
    expect(assessOutputCompletion({ metadata: { domain: "genomics" } }, 2)).toMatchObject({
      mode: "artifacts_required",
      state: "ready",
      registeredOutputCount: 2,
      meetsContract: true,
    });
  });

  it("allows outputless completion only for an explicit stdout_only declaration", () => {
    expect(assessOutputCompletion({ metadata: { output_contract: "stdout_only" } }, 0)).toEqual({
      mode: "stdout_only",
      state: "stdout_only",
      registeredOutputCount: 0,
      meetsContract: true,
    });
  });

  it("does not accept a loose stdout_only boolean flag", () => {
    expect(assessOutputCompletion({ metadata: { stdout_only: true } }, 0)).toMatchObject({
      mode: "artifacts_required",
      state: "artifact_unavailable",
      meetsContract: false,
    });
  });
});
