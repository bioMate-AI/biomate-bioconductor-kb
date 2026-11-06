import { describe, it, expect } from "vitest";
import {
  toManifestEntry,
  entryToCanonical,
  readManifest,
  buildManifest,
  isTerminalStatus,
} from "./runs-outputs-manifest";
import type { CanonicalOutput } from "./runs-outputs-service";

const out: CanonicalOutput = {
  id: "run-1:a/b/results.csv",
  name: "results.csv",
  extension: "csv",
  size: 2048,
  fileType: "table",
  downloadUrl: "https://s3.example/presigned-EXPIRES",
  s3Uri: "s3://bucket/a/b/results.csv",
  s3Bucket: "bucket",
  s3Key: "a/b/results.csv",
  step: "02_deseq2",
  previewable: true,
  metadata: { s3Uri: "s3://bucket/a/b/results.csv" },
};

describe("output manifest round-trip (L1a)", () => {
  it("persists only stable fields — NOT the ephemeral presigned url / id / metadata", () => {
    const e = toManifestEntry(out);
    expect(e).toEqual({
      name: "results.csv",
      extension: "csv",
      size: 2048,
      fileType: "table",
      s3Uri: "s3://bucket/a/b/results.csv",
      s3Bucket: "bucket",
      s3Key: "a/b/results.csv",
      step: "02_deseq2",
      previewable: true,
    });
    expect(e).not.toHaveProperty("downloadUrl");
    expect(e).not.toHaveProperty("id");
    expect(e).not.toHaveProperty("metadata");
  });

  it("rebuilds a CanonicalOutput: id from runId, FRESH downloadUrl, metadata mirrors s3Uri", () => {
    const e = toManifestEntry(out);
    const rebuilt = entryToCanonical(e, "run-1", "https://s3.example/FRESH");
    // Stable fields preserved…
    expect(rebuilt.name).toBe(out.name);
    expect(rebuilt.s3Uri).toBe(out.s3Uri);
    expect(rebuilt.s3Key).toBe(out.s3Key);
    expect(rebuilt.fileType).toBe(out.fileType);
    expect(rebuilt.step).toBe(out.step);
    // …ephemeral fields re-derived, never the stale presigned url.
    expect(rebuilt.id).toBe("run-1:a/b/results.csv");
    expect(rebuilt.downloadUrl).toBe("https://s3.example/FRESH");
    expect(rebuilt.downloadUrl).not.toContain("EXPIRES");
    expect(rebuilt.metadata).toEqual({ s3Uri: out.s3Uri });
  });

  it("id is re-derived from the CURRENT runId, so a galaxy-id read still yields a run-keyed id", () => {
    const e = toManifestEntry(out);
    expect(entryToCanonical(e, "run-99", "u").id).toBe("run-99:a/b/results.csv");
  });

  it("buildManifest + readManifest survive a JSON persist/reload cycle", () => {
    const m = buildManifest([out], "2026-09-16T00:00:00.000Z");
    const persisted = JSON.parse(JSON.stringify({ outputManifest: m }));
    const read = readManifest(persisted);
    expect(read?.entries).toHaveLength(1);
    expect(read?.entries[0].s3Key).toBe("a/b/results.csv");
    expect(read?.registeredAt).toBe("2026-09-16T00:00:00.000Z");
  });

  it("readManifest returns null for missing/empty manifests (so list() falls back to S3)", () => {
    expect(readManifest(undefined)).toBeNull();
    expect(readManifest({})).toBeNull();
    expect(readManifest({ outputManifest: { entries: [] } })).toBeNull();
    expect(readManifest({ outputManifest: { entries: "nope" } })).toBeNull();
  });

  it("only terminal statuses may register a manifest (never a running run)", () => {
    expect(isTerminalStatus("completed")).toBe(true);
    expect(isTerminalStatus("OK")).toBe(true);
    expect(isTerminalStatus("failed")).toBe(true);
    expect(isTerminalStatus("running")).toBe(false);
    expect(isTerminalStatus("pending")).toBe(false);
    expect(isTerminalStatus(null)).toBe(false);
  });
});
