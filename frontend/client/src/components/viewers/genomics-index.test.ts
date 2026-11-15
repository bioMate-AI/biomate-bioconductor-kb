import { describe, expect, it } from "vitest";
import {
  genomicsTrackKind,
  siblingIndexPathCandidates,
  stepFileUrl,
} from "./genomics-index";
import { resolveViewer, resolveViewerFromName } from "./inline-content-viewers";

describe("genomics index helpers", () => {
  it("detects bam and vcf.gz", () => {
    expect(genomicsTrackKind("sample.bam")).toBe("bam");
    expect(genomicsTrackKind("dir/x.VCF.GZ")).toBe("vcf_gz");
    expect(genomicsTrackKind("plain.vcf")).toBeNull();
  });

  it("lists sibling index candidates", () => {
    expect(siblingIndexPathCandidates("out/aln.bam", "bam")).toEqual([
      "out/aln.bam.bai",
      "out/aln.bai",
    ]);
    expect(siblingIndexPathCandidates("calls.vcf.gz", "vcf_gz")[0]).toBe("calls.vcf.gz.tbi");
  });

  it("builds step-file URLs", () => {
    const u = stepFileUrl("run-1", "outs/a.bam", "a.bam");
    expect(u).toContain("/api/workflows/runs/run-1/step-file?");
    expect(u).toContain("path=outs%2Fa.bam");
  });
});

describe("resolveViewer igv routing", () => {
  it("routes bam and vcf.gz to igv; plain vcf stays table viewer", () => {
    expect(resolveViewerFromName("x.bam")).toBe("igv");
    expect(resolveViewerFromName("x.vcf.gz")).toBe("igv");
    expect(resolveViewer("bam")).toBe("igv");
    expect(resolveViewer("vcf")).toBe("vcf");
    expect(resolveViewer("gz", "sample.vcf.gz")).toBe("igv");
  });

  it("keeps igv in SELF_FETCHING via resolveViewer name", () => {
    expect(resolveViewer("bam", "reads.bam")).toBe("igv");
  });
});
