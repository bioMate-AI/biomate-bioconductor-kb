import { describe, expect, it } from "vitest";
import { isOrphanInterrupt } from "./nextflow-run-status";

describe("isOrphanInterrupt — stuck-'running' finalization", () => {
  it("finalizes a LOCAL interrupted run that is still 'running' (the stuck-run case)", () => {
    expect(isOrphanInterrupt("interrupted", "running", false)).toBe(true);
    expect(isOrphanInterrupt("interrupted", "configuring", false)).toBe(true);
  });

  it("does NOT flip a deliberately PAUSED run (QC gate / cancel keeps it resumable)", () => {
    expect(isOrphanInterrupt("interrupted", "paused", false)).toBe(false);
    expect(isOrphanInterrupt("interrupted", "cancelled", false)).toBe(false);
  });

  it("does NOT flip a BATCH run (left to the completion poller's describe_jobs)", () => {
    expect(isOrphanInterrupt("interrupted", "running", true)).toBe(false);
    // Unknown/undefined is_batch is treated conservatively as not-finalizable.
    expect(isOrphanInterrupt("interrupted", "running", undefined)).toBe(false);
  });

  it("ignores non-interrupted states (those are handled by the existing branches)", () => {
    expect(isOrphanInterrupt("running", "running", false)).toBe(false);
    expect(isOrphanInterrupt("succeeded", "running", false)).toBe(false);
    expect(isOrphanInterrupt("failed", "running", false)).toBe(false);
  });

  it("does not re-finalize an already-terminal run", () => {
    expect(isOrphanInterrupt("interrupted", "completed", false)).toBe(false);
    expect(isOrphanInterrupt("interrupted", "failed", false)).toBe(false);
  });
});
