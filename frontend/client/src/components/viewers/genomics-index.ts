/**
 * Sibling index URL helpers for BAM/VCF tracks (IGV.js needs an index).
 * Convention: file.bam → file.bam.bai | file.bai; file.vcf.gz → file.vcf.gz.tbi | .csi
 */

export type GenomicsTrackKind = "bam" | "vcf_gz";

export function genomicsTrackKind(nameOrPath: string): GenomicsTrackKind | null {
  const n = nameOrPath.toLowerCase().split("?")[0];
  if (/\.bam$/i.test(n)) return "bam";
  if (/\.vcf\.gz$/i.test(n) || /\.vcf\.bgz$/i.test(n)) return "vcf_gz";
  return null;
}

/** Candidate relative paths (same directory) for the index, most specific first. */
export function siblingIndexPathCandidates(filePath: string, kind: GenomicsTrackKind): string[] {
  const slash = filePath.lastIndexOf("/");
  const dir = slash >= 0 ? filePath.slice(0, slash + 1) : "";
  const base = slash >= 0 ? filePath.slice(slash + 1) : filePath;
  if (kind === "bam") {
    return [
      `${dir}${base}.bai`,
      `${dir}${base.replace(/\.bam$/i, ".bai")}`,
    ];
  }
  return [
    `${dir}${base}.tbi`,
    `${dir}${base}.csi`,
    `${dir}${base.replace(/\.gz$/i, ".gz.tbi")}`,
  ];
}

/** Build a step-file URL for a sibling path under the same run. */
export function stepFileUrl(runId: string, path: string, name?: string): string {
  const leaf = name || path.split("/").pop() || path;
  return `/api/workflows/runs/${encodeURIComponent(runId)}/step-file?path=${encodeURIComponent(path)}&name=${encodeURIComponent(leaf)}`;
}
