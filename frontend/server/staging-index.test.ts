import { describe, it, expect, vi } from "vitest";
import {
  detectIndexableKind,
  expectedIndexPath,
  ensureGenomicIndexesForParams,
  StagingIndexError,
} from "./staging-index";

describe("detectIndexableKind / expectedIndexPath", () => {
  it("detects bam and vcf.gz only", () => {
    expect(detectIndexableKind("x.bam")).toBe("bam");
    expect(detectIndexableKind("x.BAM")).toBe("bam");
    expect(detectIndexableKind("x.vcf.gz")).toBe("vcf_gz");
    expect(detectIndexableKind("x.vcf")).toBeNull();
    expect(detectIndexableKind("x.fastq.gz")).toBeNull();
  });
  it("maps to sibling index paths", () => {
    expect(expectedIndexPath("/tmp/a.bam", "bam")).toBe("/tmp/a.bam.bai");
    expect(expectedIndexPath("/tmp/a.vcf.gz", "vcf_gz")).toBe("/tmp/a.vcf.gz.tbi");
  });
});

describe("ensureGenomicIndexesForParams", () => {
  it("no-ops when index already exists", async () => {
    const exists = vi.fn(async (p: string) => true);
    const which = vi.fn(async () => "/usr/bin/samtools");
    const execFile = vi.fn();
    const out = await ensureGenomicIndexesForParams(
      { bam: "/data/sample.bam", reads: "/data/a.fastq.gz" },
      { exists, which, execFile: execFile as any },
    );
    expect(out).toEqual([
      {
        param: "bam",
        kind: "bam",
        dataPath: "/data/sample.bam",
        indexPath: "/data/sample.bam.bai",
        created: false,
      },
    ]);
    expect(execFile).not.toHaveBeenCalled();
  });

  it("creates .bai via samtools when missing", async () => {
    const exists = vi.fn(async (p: string) => {
      if (p.endsWith(".bai")) return false;
      return p === "/data/sample.bam";
    });
    // After index: pretend bai appears
    let created = false;
    const exists2 = vi.fn(async (p: string) => {
      if (p === "/data/sample.bam") return true;
      if (p === "/data/sample.bam.bai") return created;
      return false;
    });
    const which = vi.fn(async () => "/usr/bin/samtools");
    const execFile = vi.fn(async () => {
      created = true;
      return { stdout: "", stderr: "" };
    });
    const out = await ensureGenomicIndexesForParams(
      { bam: "/data/sample.bam" },
      { exists: exists2, which, execFile: execFile as any },
    );
    expect(execFile).toHaveBeenCalledWith(
      "/usr/bin/samtools",
      ["index", "/data/sample.bam"],
      expect.any(Object),
    );
    expect(out[0]?.created).toBe(true);
    expect(exists).toBeDefined();
  });

  it("fail-closed when samtools missing", async () => {
    const exists = vi.fn(async (p: string) => p === "/data/sample.bam");
    const which = vi.fn(async () => null);
    await expect(
      ensureGenomicIndexesForParams(
        { bam: "/data/sample.bam" },
        { exists, which, execFile: vi.fn() as any },
      ),
    ).rejects.toBeInstanceOf(StagingIndexError);
  });

  it("creates .tbi via tabix for vcf.gz", async () => {
    let hasTbi = false;
    const exists = vi.fn(async (p: string) => {
      if (p === "/data/x.vcf.gz") return true;
      if (p === "/data/x.vcf.gz.tbi") return hasTbi;
      return false;
    });
    const which = vi.fn(async (b: string) => (b === "tabix" ? "/usr/bin/tabix" : null));
    const execFile = vi.fn(async () => {
      hasTbi = true;
      return { stdout: "", stderr: "" };
    });
    const out = await ensureGenomicIndexesForParams(
      { vcf: "/data/x.vcf.gz" },
      { exists, which, execFile: execFile as any },
    );
    expect(execFile).toHaveBeenCalledWith(
      "/usr/bin/tabix",
      ["-p", "vcf", "/data/x.vcf.gz"],
      expect.any(Object),
    );
    expect(out[0]?.created).toBe(true);
  });
});
