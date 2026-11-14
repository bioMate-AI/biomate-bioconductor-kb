import { describe, expect, it, vi } from "vitest";
import {
  collectCandidateDatasetIds,
  ensureDeferredDatasetsMaterialized,
  looksLikeDatasetId,
} from "./deferred-materialize";

describe("looksLikeDatasetId", () => {
  it("accepts UUIDs and Galaxy hex ids", () => {
    expect(looksLikeDatasetId("3dc106f5-f555-47ac-bc51-75b0b5e106f5")).toBe(true);
    expect(looksLikeDatasetId("f2db41e1fa331b3e")).toBe(true);
  });
  it("rejects paths and URLs", () => {
    expect(looksLikeDatasetId("s3://bucket/key")).toBe(false);
    expect(looksLikeDatasetId("/tmp/file.fastq")).toBe(false);
    expect(looksLikeDatasetId("https://example.com/a.bam")).toBe(false);
  });
});

describe("collectCandidateDatasetIds", () => {
  it("pulls from params, inputs, and deferred session hints", () => {
    const ids = collectCandidateDatasetIds(
      { reads: "aaaaaaaaaaaaaaaa", other: "s3://x/y", n: 1 },
      [{ id: "bbbbbbbbbbbbbbbb" }, { id: "" }],
      [
        { deferred: true, galaxy_dataset_id: "cccccccccccccccc", dataset_id: "cccccccccccccccc" },
        { deferred: false, galaxy_dataset_id: "dddddddddddddddd" },
      ],
    );
    expect(ids.sort()).toEqual(
      ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb", "cccccccccccccccc"].sort(),
    );
  });
});

describe("ensureDeferredDatasetsMaterialized", () => {
  it("materializes deferred HDAs, waits for ok, downloads locally", async () => {
    let clock = 0;
    const states = new Map<string, string>([["def1", "deferred"]]);
    const materialize = vi.fn(async (id: string) => {
      states.set(id, "running");
      return { id, state: "running" };
    });
    const getMetadata = vi.fn(async (id: string) => ({
      id,
      state: states.get(id) || "ok",
      deferred: states.get(id) === "deferred",
      name: "big.bam",
      extension: "bam",
    }));
    // After first poll post-materialize, flip to ok
    getMetadata.mockImplementation(async (id: string) => {
      const st = states.get(id) || "ok";
      if (st === "running") states.set(id, "ok");
      return {
        id,
        state: states.get(id) || "ok",
        deferred: (states.get(id) || "") === "deferred",
        name: "big.bam",
        extension: "bam",
      };
    });
    const downloadToFile = vi.fn(async () => undefined);

    const result = await ensureDeferredDatasetsMaterialized(
      ["def1", "already"],
      {
        getMetadata,
        materialize,
        downloadToFile,
        now: () => clock,
        sleep: async (ms) => {
          clock += ms;
        },
      },
      {
        uploadDir: "/tmp/uploads",
        alreadyResolved: ["already"],
        timeoutMs: 10_000,
        intervalMs: 100,
      },
    );

    expect(materialize).toHaveBeenCalledWith("def1");
    expect(downloadToFile).toHaveBeenCalledWith("def1", "/tmp/uploads/def1.bam");
    expect(result.materializedIds).toEqual(["def1"]);
    expect(result.skippedIds).toContain("already");
    expect(result.filePaths.def1).toEqual({
      filePath: "/tmp/uploads/def1.bam",
      name: "big.bam",
    });
    expect(result.failures).toEqual([]);
  });

  it("records failure when materialize never reaches ok", async () => {
    let clock = 0;
    const result = await ensureDeferredDatasetsMaterialized(
      ["stuck"],
      {
        getMetadata: async () => ({ id: "stuck", state: "deferred", deferred: true }),
        materialize: async () => ({ id: "stuck", state: "deferred" }),
        downloadToFile: async () => {
          throw new Error("should not download");
        },
        now: () => clock,
        sleep: async (ms) => {
          clock += ms;
        },
      },
      { uploadDir: "/tmp/uploads", timeoutMs: 500, intervalMs: 100 },
    );
    expect(result.materializedIds).toEqual([]);
    expect(result.failures[0]?.id).toBe("stuck");
    expect(result.failures[0]?.reason).toBe("materialize_timeout");
  });

  it("skips non-Galaxy / non-deferred ids without failing", async () => {
    const result = await ensureDeferredDatasetsMaterialized(
      ["proj-file-uuid-not-galaxy"],
      {
        getMetadata: async () => {
          throw new Error("404");
        },
        materialize: async () => ({ id: "x", state: "ok" }),
        downloadToFile: async () => undefined,
      },
      { uploadDir: "/tmp/uploads" },
    );
    expect(result.skippedIds).toEqual(["proj-file-uuid-not-galaxy"]);
    expect(result.failures).toEqual([]);
  });
});
