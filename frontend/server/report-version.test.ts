import { describe, it, expect } from "vitest";
import { makeRunOriginal, appendReportVersion, currentReportVersion } from "./report-version";
import { sha256Hex } from "./reproducibility-record";

describe("report-version model (L5 — report is a versioned object, run link never severed)", () => {
  it("run original is version 0, immutable, hashed, and bound to its run", () => {
    const o = makeRunOriginal("run-1", "Results: FDR<0.05, 128 DE genes.", new Date("2026-09-15T00:00:00Z"));
    expect(o.version).toBe(0);
    expect(o.immutable).toBe(true);
    expect(o.runId).toBe("run-1");
    expect(o.editedFromVersion).toBeNull();
    expect(o.sha256).toBe(sha256Hex("Results: FDR<0.05, 128 DE genes."));
    expect(o.createdAt).toBe("2026-09-15T00:00:00.000Z");
  });

  it("requires a runId — a report must belong to a run", () => {
    expect(() => makeRunOriginal("", "x")).toThrow(/runId/);
  });

  it("append forks a new version that KEEPS the runId and records what it edited from", () => {
    const o = makeRunOriginal("run-1", "original");
    const v1 = appendReportVersion([o], "edited body", { note: "tightened abstract" });
    expect(v1.version).toBe(1);
    expect(v1.immutable).toBe(false);
    expect(v1.runId).toBe("run-1");              // back-link never dropped on edit
    expect(v1.editedFromVersion).toBe(0);
    expect(v1.note).toBe("tightened abstract");
    expect(v1.sha256).toBe(sha256Hex("edited body"));
    expect(v1.sha256).not.toBe(o.sha256);
  });

  it("is append-only and does NOT mutate history; the run original stays intact", () => {
    const o = makeRunOriginal("run-1", "original");
    const history = [o];
    const v1 = appendReportVersion(history, "v1 body");
    const v2 = appendReportVersion([...history, v1], "v2 body");
    expect(v2.version).toBe(2);
    expect(v2.editedFromVersion).toBe(1);
    expect(v2.runId).toBe("run-1");
    // history untouched by the pure append
    expect(history).toHaveLength(1);
    expect(history[0]).toBe(o);
    expect(o.immutable).toBe(true);
  });

  it("carries the runId even when the caller passes a history out of order", () => {
    const o = makeRunOriginal("run-9", "orig");
    const v1 = appendReportVersion([o], "a");
    const v2 = appendReportVersion([v1, o], "b"); // order shuffled
    expect(v2.version).toBe(2);
    expect(v2.runId).toBe("run-9");
  });

  it("refuses to append onto an empty or original-less history (never orphan a report)", () => {
    expect(() => appendReportVersion([], "x")).toThrow(/run original/);
    const fake = { version: 3, runId: "r", createdAt: null, sha256: "", editedFromVersion: 2, immutable: false };
    expect(() => appendReportVersion([fake], "x")).toThrow(/run original/);
  });

  it("currentReportVersion returns the latest by version number", () => {
    const o = makeRunOriginal("run-1", "orig");
    const v1 = appendReportVersion([o], "a");
    expect(currentReportVersion([o, v1])?.version).toBe(1);
    expect(currentReportVersion([])).toBeNull();
  });
});
