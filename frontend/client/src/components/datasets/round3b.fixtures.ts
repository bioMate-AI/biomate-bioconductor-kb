/** A round-3 folder profile (folder_profile.py @ f74176aac8): the project's input root with paired
 *  FASTQs in two naming styles, an orphan (→ single-end sheet), a TSV, a featureCounts table and a
 *  10x matrix at the root (`dir: null`). Shared by the en and zh round-3b tests. */
export const MIXED_FOLDER = {
  path: "", kind: "mixed", fileCount: 9,
  rollup: [
    { format: "fastq", label: "FASTQ", count: 5, pairs: 2, viewKind: "reads" },
    { format: "tsv", label: "TSV", count: 1, viewKind: "table" },
    { format: "tsv", label: "featureCounts counts", count: 1, viewKind: "table" },
    { format: "mtx", label: "Matrix Market", count: 1, viewKind: "matrix" },
    { format: "tsv", label: "TSV", count: 1 },
  ],
  findings: [
    { code: "folder_fastq_pairs", level: "info", params: { pairs: 2, pattern: "_R1/_R2 and _1/_2", patterns: ["_R1/_R2", "_1/_2"] } },
    { code: "folder_samplesheet", level: "info", params: { rows: 2, layout: "paired", path_base: "project inputs" } },
    { code: "folder_samplesheet_single_end", level: "info", params: { rows: 1, filename: "samplesheet_single_end.csv", names: ["S3_R1.fastq.gz"] } },
    { code: "folder_tenx_recognised", level: "info", params: { cells: 5, genes: 7, nnz: 9, version: "v3", dir: null } },
  ],
  fastq: {
    verdict: "mixed", pattern: "Rs", patterns: ["Rs", "illumina"], engine: "galaxy", pairs: 2,
    samples: [
      { sample: "S1", forward: "S1_R1.fastq.gz", reverse: "S1_R2.fastq.gz", status: "paired" },
      { sample: "WT_1", forward: "WT_1_1.fq.gz", reverse: "WT_1_2.fq.gz", status: "paired" },
      { sample: "S3", forward: "S3_R1.fastq.gz", reverse: null, status: "orphan", role: "forward" },
    ],
    orphans: ["S3_R1.fastq.gz"], singles: [],
  },
  samplesheet: {
    columns: ["sample", "fastq_1", "fastq_2"], filename: "samplesheet.csv", layout: "paired", pathBase: "project inputs",
    rows: [["S1", "S1_R1.fastq.gz", "S1_R2.fastq.gz"], ["WT_1", "WT_1_1.fq.gz", "WT_1_2.fq.gz"]],
    csv: "sample,fastq_1,fastq_2\nS1,S1_R1.fastq.gz,S1_R2.fastq.gz\nWT_1,WT_1_1.fq.gz,WT_1_2.fq.gz\n",
    single: {
      columns: ["sample", "fastq_1", "fastq_2"], filename: "samplesheet_single_end.csv", layout: "single_end", pathBase: "project inputs",
      rows: [["S3", "S3_R1.fastq.gz", ""]], csv: "sample,fastq_1,fastq_2\nS3,S3_R1.fastq.gz,\n",
    },
    excluded: ["S3_R1.fastq.gz"],
  },
  tenx: { sets: [{ dir: "", prefix: "", matrix: "matrix.mtx", barcodes: "barcodes.tsv", features: "features.tsv",
    version: "v3", complete: true, missing: [], genes: 7, cells: 5, nnz: 9 }] },
}
