// Unit tests for the two 2026-11-04 run-record population fixes:
//   Fix #6  — deriveRunMetricsPatch: metrics.outputs.{fileCount,totalSizeBytes,byType,
//             bySize} + runtime.totalSeconds from a completed run's data (was all-zero).
//   Fix #5b — resolveInlineFindings: inline_findings mirrors findings_data.json.
// No mocks — the findings test reads a REAL sidecar file written to the same /tmp path
// the server reads from.
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { mkdir, writeFile, rm } from "fs/promises";
import { deriveRunMetricsPatch, resolveInlineFindings, finalizeRunSteps } from "./run-record-metrics";

describe("Fix #6 — deriveRunMetricsPatch populates metrics from completed-run data", () => {
  it("derives outputs.fileCount / totalSizeBytes / byType / bySize from an output_files list", () => {
    const nextflowStatus = {
      s3_output_files: [
        { filename: "sample.vcf", size: 1000, s3_uri: "s3://b/sample.vcf" },
        { filename: "report.html", size: 2500 },
        { name: "qc/results.csv", size: 500 },
        { filename: "plot.png", size: 4000 },
      ],
    };
    const patch = deriveRunMetricsPatch({ execution: {}, metrics: {} } as any, nextflowStatus);
    expect(patch).not.toBeNull();
    expect(patch!.outputs!.fileCount).toBe(4);
    expect(patch!.outputs!.totalSizeBytes).toBe(1000 + 2500 + 500 + 4000);
    expect(patch!.outputs!.byType).toEqual({ vcf: 1, html: 1, csv: 1, png: 1 });
    expect(patch!.outputs!.bySize).toEqual({ vcf: 1000, html: 2500, csv: 500, png: 4000 });
  });

  it("must never report zero outputs for a run that has output files", () => {
    const patch = deriveRunMetricsPatch(
      { execution: {}, metrics: {} } as any,
      { s3_output_files: [{ filename: "a.txt", size: 10 }] },
    );
    expect(patch!.outputs!.fileCount).toBeGreaterThan(0);
    expect(patch!.outputs!.totalSizeBytes).toBeGreaterThan(0);
  });

  it("prefers s3_output_files, falls back to output_files, groups same ext", () => {
    const fallback = deriveRunMetricsPatch(
      { execution: {}, metrics: {} } as any,
      { output_files: [{ name: "a.txt", size: 5 }, { name: "b.txt", size: 7 }] },
    );
    expect(fallback!.outputs!.fileCount).toBe(2);
    expect(fallback!.outputs!.byType).toEqual({ txt: 2 });
    expect(fallback!.outputs!.bySize).toEqual({ txt: 12 });
  });

  it("derives runtime.totalSeconds from execution.startedAt / completedAt", () => {
    const patch = deriveRunMetricsPatch(
      {
        execution: {
          startedAt: new Date("2026-11-04T10:00:00.000Z"),
          completedAt: new Date("2026-11-04T10:02:30.000Z"), // 150s later
        },
        metrics: {},
      } as any,
      {},
    );
    expect(patch).not.toBeNull();
    expect(patch!.runtime!.totalSeconds).toBe(150);
  });

  it("prefers Nextflow's own duration_s over the wall-clock delta", () => {
    const patch = deriveRunMetricsPatch(
      {
        execution: {
          startedAt: new Date("2026-11-04T10:00:00.000Z"),
          completedAt: new Date("2026-11-04T10:02:30.000Z"), // 150s wall-clock
        },
        metrics: {},
      } as any,
      { duration_s: 123 },
    );
    expect(patch!.runtime!.totalSeconds).toBe(123);
  });

  it("does NOT fabricate resources.* (left for storage zero-init; no trace Node-side)", () => {
    const patch = deriveRunMetricsPatch(
      { execution: {}, metrics: {} } as any,
      { s3_output_files: [{ filename: "a.txt", size: 10 }], duration_s: 60 },
    );
    expect(patch!.resources).toBeUndefined();
  });

  it("returns null when nothing is derivable (no files, no runtime)", () => {
    expect(deriveRunMetricsPatch({ execution: {}, metrics: {} } as any, {})).toBeNull();
    expect(deriveRunMetricsPatch({ execution: {}, metrics: {} } as any, null)).toBeNull();
  });
});

describe("Fix #5b — resolveInlineFindings populates inline_findings", () => {
  const runId = `test-run-5b-${process.pid}-${Date.now()}`;
  const dir = `/tmp/nextflow_runs/${runId}/output`;
  const sidecar = `${dir}/findings_data.json`;
  const KEY_RESULTS = [
    { metric: "hERG IC50", value: "3.2 uM", interpretation: "Elevated liability", source_file: "admet.csv" },
    { metric: "Oral bioavailability", value: "0.62", interpretation: "Acceptable", source_file: "admet.csv" },
  ];

  beforeAll(async () => {
    await mkdir(dir, { recursive: true });
    await writeFile(sidecar, JSON.stringify({ summary: "ADMET screen complete", key_results: KEY_RESULTS }), "utf8");
  });
  afterAll(async () => {
    await rm(`/tmp/nextflow_runs/${runId}`, { recursive: true, force: true });
  });

  it("reads key_results from the local findings_data.json sidecar", async () => {
    const findings = await resolveInlineFindings({ id: runId, execution: { nextflowRunId: runId } } as any, {});
    expect(findings).toEqual(KEY_RESULTS);
  });

  it("falls back to [] when no sidecar, no cache, no embedded findings", async () => {
    const findings = await resolveInlineFindings(
      { id: "nonexistent-run-xyz", execution: {} } as any,
      {},
    );
    expect(findings).toEqual([]);
  });

  it("uses the in-memory findings cache when present (AWS-run parity)", async () => {
    const cache = new Map<string, Record<string, any>>([
      ["aws-run-1", { key_results: KEY_RESULTS }],
    ]);
    const findings = await resolveInlineFindings(
      { id: "aws-run-1", execution: {} } as any,
      {},
      (id) => cache.get(id),
    );
    expect(findings).toEqual(KEY_RESULTS);
  });

  it("ignores a still-generating cache entry and falls through to []", async () => {
    const cache = new Map<string, Record<string, any>>([["gen-run", { _generating: true }]]);
    const findings = await resolveInlineFindings(
      { id: "gen-run", execution: {} } as any,
      {},
      (id) => cache.get(id),
    );
    expect(findings).toEqual([]);
  });

  it("honors nextflowStatus-embedded key_results as the first source", async () => {
    const findings = await resolveInlineFindings(
      { id: "embedded-run", execution: {} } as any,
      { key_results: KEY_RESULTS },
    );
    expect(findings).toEqual(KEY_RESULTS);
  });
});

describe("Fix #8 — finalizeRunSteps finalizes a terminal run's per-step records", () => {
  // Steps as storage.ts seeds them: status 'pending', outputs [].
  const seededSteps = () => [
    { stepId: "fastqc", stepIndex: 0, stepName: "FastQC", toolId: "fastqc", toolName: "FastQC", status: "pending", outputs: [] },
    { stepId: "star_align", stepIndex: 1, stepName: "STAR alignment", toolId: "star", toolName: "STAR", status: "running", outputs: [] },
    { stepId: "salmon_quant", stepIndex: 2, stepName: "Salmon quant", toolId: "salmon", toolName: "salmon", status: "pending", outputs: [] },
  ];

  it("on a COMPLETED run, moves every non-terminal step away from 'pending' → 'completed'", () => {
    const next = finalizeRunSteps(
      { execution: { status: "completed" }, steps: seededSteps() } as any,
      {},
    );
    expect(next).not.toBeNull();
    expect(next!.map((s) => s.status)).toEqual(["completed", "completed", "completed"]);
    // No step should still read 'pending' on a finished run.
    expect(next!.some((s) => s.status === "pending")).toBe(false);
  });

  it("attaches outputs to their producing step via f.step_name / f.process_name", () => {
    const next = finalizeRunSteps(
      { execution: { status: "completed" }, steps: seededSteps() } as any,
      {
        s3_output_files: [
          { filename: "sample_fastqc.html", size: 2048, s3_uri: "s3://b/qc/sample_fastqc.html", step_name: "FastQC" },
          { filename: "Aligned.sortedByCoord.out.bam", size: 500000, s3_uri: "s3://b/star/Aligned.bam", process_name: "STAR" },
          { filename: "quant.sf", size: 1024, s3_uri: "s3://b/salmon/quant.sf", step_name: "salmon" },
        ],
      },
    );
    expect(next).not.toBeNull();
    const byId = Object.fromEntries(next!.map((s) => [s.stepId, s]));
    expect(byId["fastqc"].outputs.map((o) => o.name)).toEqual(["sample_fastqc.html"]);
    expect(byId["fastqc"].outputs[0].extension).toBe("html");
    expect(byId["fastqc"].outputs[0].isVisualizable).toBe(true);
    expect(byId["fastqc"].outputs[0].sizeBytes).toBe(2048);
    expect(byId["star_align"].outputs.map((o) => o.name)).toEqual(["Aligned.sortedByCoord.out.bam"]);
    expect(byId["salmon_quant"].outputs.map((o) => o.name)).toEqual(["quant.sf"]);
  });

  it("attaches outputs via the S3 NN_<process>/ path when step_name/process_name are null (live /output_files shape)", () => {
    const next = finalizeRunSteps(
      { execution: { status: "completed" }, steps: seededSteps() } as any,
      {
        // No step_name/process_name — exactly what the live /output_files listing returns.
        s3_output_files: [
          { name: "sample_fastqc.html", size: 2048, s3_uri: "s3://b/outputs/run/01_fastqc/sample_fastqc.html" },
          { name: "Aligned.bam", size: 500000, s3_uri: "s3://b/outputs/run/02_star/Aligned.bam" },
          { name: "quant.sf", size: 1024, s3_uri: "s3://b/outputs/run/03_salmon/quant.sf" },
          // aggregate output/ dir is not a process → must stay unattributed
          { name: "findings_data.json", size: 10, s3_uri: "s3://b/outputs/run/output/findings_data.json" },
        ],
      },
    );
    expect(next).not.toBeNull();
    const byId = Object.fromEntries(next!.map((s) => [s.stepId, s]));
    expect(byId["fastqc"].outputs.map((o) => o.name)).toEqual(["sample_fastqc.html"]);
    expect(byId["star_align"].outputs.map((o) => o.name)).toEqual(["Aligned.bam"]);
    expect(byId["salmon_quant"].outputs.map((o) => o.name)).toEqual(["quant.sf"]);
    // the output/ aggregate file is attributed to no step
    expect(next!.every((s) => !s.outputs.some((o) => o.name === "findings_data.json"))).toBe(true);
  });

  it("drives per-step status from nextflowStatus.processes when present (failed process → failed)", () => {
    const next = finalizeRunSteps(
      { execution: { status: "failed" }, steps: seededSteps() } as any,
      {
        processes: [
          { name: "FastQC", status: "completed" },
          { name: "STAR", state: "failed" },
        ],
        s3_output_files: [
          { filename: "sample_fastqc.html", size: 10, s3_uri: "s3://b/sample_fastqc.html", step_name: "FastQC" },
        ],
      },
    );
    expect(next).not.toBeNull();
    const byId = Object.fromEntries(next!.map((s) => [s.stepId, s]));
    expect(byId["fastqc"].status).toBe("completed");
    expect(byId["star_align"].status).toBe("failed");
    // No process info + no outputs on a failed run → honest: left as seeded.
    expect(byId["salmon_quant"].status).toBe("pending");
  });

  it("on a FAILED run with no per-process state, marks only output-producing steps completed (no fabricated failure)", () => {
    const next = finalizeRunSteps(
      { execution: { status: "failed" }, steps: seededSteps() } as any,
      { s3_output_files: [{ filename: "a.html", size: 5, s3_uri: "s3://b/a.html", step_name: "FastQC" }] },
    );
    const byId = Object.fromEntries(next!.map((s) => [s.stepId, s]));
    expect(byId["fastqc"].status).toBe("completed"); // produced output → ran
    expect(byId["star_align"].status).toBe("running"); // unknown — left as-is, not guessed 'failed'
    expect(byId["salmon_quant"].status).toBe("pending");
    expect(next!.some((s) => s.status === "failed")).toBe(false);
  });

  it("never clobbers an already-populated step's outputs (Galaxy-path record)", () => {
    const steps = [
      { stepId: "s1", stepIndex: 0, stepName: "Step One", toolId: "t1", toolName: "T1", status: "completed",
        outputs: [{ datasetId: "existing", name: "existing.txt", extension: "txt", sizeBytes: 9, isVisualizable: true }] },
    ];
    const next = finalizeRunSteps(
      { execution: { status: "completed" }, steps } as any,
      { s3_output_files: [{ filename: "new.txt", size: 1, s3_uri: "s3://b/new.txt", step_name: "Step One" }] },
    );
    // Nothing changed — already completed and already has outputs → null.
    expect(next).toBeNull();
  });

  it("returns null for a non-terminal (still running) run — never finalizes a live run", () => {
    expect(finalizeRunSteps({ execution: { status: "running" }, steps: seededSteps() } as any, {})).toBeNull();
    expect(finalizeRunSteps({ execution: { status: "paused" }, steps: seededSteps() } as any, {})).toBeNull();
  });

  it("returns null when there are no steps to finalize", () => {
    expect(finalizeRunSteps({ execution: { status: "completed" }, steps: [] } as any, {})).toBeNull();
  });

  it("does not attribute an output file that carries no producing-step tag", () => {
    const next = finalizeRunSteps(
      { execution: { status: "completed" }, steps: seededSteps() } as any,
      { s3_output_files: [{ filename: "orphan.txt", size: 3, s3_uri: "s3://b/orphan.txt" }] },
    );
    // Status still finalized (completed), but no step gets the untagged file.
    expect(next).not.toBeNull();
    expect(next!.every((s) => s.outputs.length === 0)).toBe(true);
  });
});
