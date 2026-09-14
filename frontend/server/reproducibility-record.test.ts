import { describe, it, expect } from "vitest";
import { assembleReproducibilityRecord } from "./reproducibility-record";

describe("assembleReproducibilityRecord", () => {
  const run = {
    id: "run-1",
    workflowName: "bulk RNA-seq DE",
    status: "ok",
    createdAt: new Date("2026-09-14T00:00:00Z"),
    completedAt: new Date("2026-09-14T00:10:00Z"),
    parameters: { fdr: 0.05, contrast: "treated_vs_control" },
    inputBindings: [{ stepId: "0", datasetId: "ds-a", s3Uri: "s3://b/a.csv" }],
  };
  const outputs = [
    { id: "o1", name: "results.csv", fileType: "csv", fileSize: 2048, sha256: "abc" },
    { id: "o2", name: "plot.png", metadata: { datatype: "png", size: 90000 } },
  ];

  it("assembles identity, parameters, input bindings and outputs", () => {
    const r = assembleReproducibilityRecord(run, outputs);
    expect(r.recordVersion).toBe("1.0");
    expect(r.runId).toBe("run-1");
    expect(r.workflowName).toBe("bulk RNA-seq DE");
    expect(r.status).toBe("ok");
    expect(r.createdAt).toBe("2026-09-14T00:00:00.000Z");
    expect(r.completedAt).toBe("2026-09-14T00:10:00.000Z");
    expect(r.parameters).toEqual({ fdr: 0.05, contrast: "treated_vs_control" });
    expect(r.inputBindings).toHaveLength(1);
    expect(r.outputCount).toBe(2);
  });

  it("maps outputs from either flat fields or metadata, carrying sha256/null", () => {
    const r = assembleReproducibilityRecord(run, outputs);
    expect(r.outputs[0]).toEqual({ id: "o1", name: "results.csv", fileType: "csv", sizeBytes: 2048, sha256: "abc" });
    expect(r.outputs[1]).toEqual({ id: "o2", name: "plot.png", fileType: "png", sizeBytes: 90000, sha256: null });
  });

  it("never exposes raw s3 uris anywhere in the record (inputs + outputs opaque)", () => {
    const r = assembleReproducibilityRecord(
      { ...run, inputBindings: [{ stepId: "0", datasetId: "ds-a", name: "counts.csv", projectFileId: "pf-1", s3Uri: "s3://in/a.csv" }] },
      [{ id: "o", name: "x", s3Uri: "s3://secret/x" }],
    );
    // Whole-record check — not just outputs.
    expect(JSON.stringify(r)).not.toContain("s3://");
    // But the identifiers needed to reproduce the input are retained.
    expect(r.inputBindings[0]).toEqual({ stepId: "0", datasetId: "ds-a", name: "counts.csv", projectFileId: "pf-1" });
  });

  it("degrades gracefully on a sparse/partial run", () => {
    const r = assembleReproducibilityRecord({ id: "r2" }, []);
    expect(r.runId).toBe("r2");
    expect(r.workflowName).toBe("Untitled Workflow");
    expect(r.status).toBe("unknown");
    expect(r.createdAt).toBeNull();
    expect(r.parameters).toEqual({});
    expect(r.inputBindings).toEqual([]);
    expect(r.outputs).toEqual([]);
    expect(r.outputCount).toBe(0);
  });

  it("reads status from execution sub-object when top-level is absent", () => {
    const r = assembleReproducibilityRecord({ id: "r3", execution: { status: "running" } }, []);
    expect(r.status).toBe("running");
  });
});
