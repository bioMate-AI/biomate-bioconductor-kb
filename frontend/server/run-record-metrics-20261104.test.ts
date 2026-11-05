// Unit tests for the two 2026-11-04 run-record population fixes:
//   Fix #6  — deriveRunMetricsPatch: metrics.outputs.{fileCount,totalSizeBytes,byType,
//             bySize} + runtime.totalSeconds from a completed run's data (was all-zero).
//   Fix #5b — resolveInlineFindings: inline_findings mirrors findings_data.json.
// No mocks — the findings test reads a REAL sidecar file written to the same /tmp path
// the server reads from.
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { mkdir, writeFile, rm } from "fs/promises";
import { deriveRunMetricsPatch, resolveInlineFindings } from "./run-record-metrics";

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
