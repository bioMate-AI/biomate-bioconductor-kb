import { describe, it, expect } from "vitest";
import {
  normalizeHonestEstimate,
  UNAVAILABLE_ESTIMATE,
  historicalFromRuns,
  actualVcpuHoursFromRun,
  compareRow,
} from "./admin-cost-estimate";

describe("normalizeHonestEstimate", () => {
  it("passes through honest prior shape", () => {
    const n = normalizeHonestEstimate({
      confidence: "prior",
      basis: "domain prior (rnaseq)",
      assumptions: ["a"],
      nextflow_path: "nf-core/rnaseq",
      domain: "rnaseq",
      range: { min_vcpu_hrs: 8, max_vcpu_hrs: 32 },
      usd_range: { min_usd: 1, max_usd: 5, label: "rough" },
    });
    expect(n.confidence).toBe("prior");
    expect(n.range.max_vcpu_hrs).toBe(32);
    expect(n.usd_range?.max_usd).toBe(5);
  });
  it("legacy fake dollars → unavailable (no invent)", () => {
    const n = normalizeHonestEstimate({ min_usd: 0.5, max_usd: 5.0, assumptions: ["default"] });
    expect(n.confidence).toBe("unavailable");
  });
  it("empty → unavailable", () => {
    expect(normalizeHonestEstimate(null).confidence).toBe("unavailable");
    expect(UNAVAILABLE_ESTIMATE("x").range.min_vcpu_hrs).toBe(0);
  });
});

describe("historicalFromRuns", () => {
  it("needs ≥2 completed samples", () => {
    expect(
      historicalFromRuns(
        [{ id: "1", status: "completed", nextflowPath: "nf-core/rnaseq", vcpuHours: 10 }],
        "nf-core/rnaseq",
      ),
    ).toBeNull();
  });
  it("builds median band from matching completed runs", () => {
    const h = historicalFromRuns(
      [
        { id: "1", status: "completed", nextflowPath: "nf-core/rnaseq", vcpuHours: 8, usd: 2 },
        { id: "2", status: "completed", nextflowPath: "nf-core/rnaseq", vcpuHours: 12, usd: 4 },
        { id: "3", status: "failed", nextflowPath: "nf-core/rnaseq", vcpuHours: 99 },
      ],
      "nf-core/rnaseq",
    );
    expect(h?.confidence).toBe("historical");
    expect(h!.range.min_vcpu_hrs).toBeLessThanOrEqual(h!.range.max_vcpu_hrs);
    expect(h!.usd_range).toBeTruthy();
  });
});

describe("actualVcpuHoursFromRun / compareRow", () => {
  it("derives from totalSeconds × vcpus", () => {
    expect(
      actualVcpuHoursFromRun({
        metrics: { runtime: { totalSeconds: 3600 }, resources: { vcpus: 8 } },
      }),
    ).toBe(8);
  });
  it("compare uses snapshot mid vs actual", () => {
    const row = compareRow({
      id: "r1",
      workflowName: "rnaseq",
      execution: {
        status: "completed",
        costEstimateSnapshot: {
          confidence: "prior",
          basis: "x",
          assumptions: [],
          range: { min_vcpu_hrs: 8, max_vcpu_hrs: 12 },
        },
      },
      metrics: { runtime: { totalSeconds: 3600 }, resources: { vcpus: 10 } },
    });
    expect(row.estimated_vcpu_hrs).toBe(10);
    expect(row.actual_vcpu_hrs).toBe(10);
    expect(row.delta_pct).toBe(0);
  });
});
