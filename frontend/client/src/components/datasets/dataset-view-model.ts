/**
 * The dataset object's per-kind view model — ONE pure function decides, for a file's data
 * kind, which preview views exist, which stats the QC card shows and which actions apply
 * (Edit, Plot, Columns, Run full QC, Open in Jupyter). The panel renders whatever this says;
 * no per-format special cases live in JSX.
 *
 * The kind is content-first: the profiler's `viewKind` (it read the bytes) wins. Profiles from
 * older backends carry no `viewKind`, so the kind is then derived from the file extension.
 */
import type { DataProfile, PerceptionFinding, PerceptionQuality } from "@/components/data-perception"

export const VIEW_KINDS = [
  "table", "records", "json", "sequences", "reads", "variants", "intervals", "annotation",
  "alignment", "anndata", "loom", "matrix", "molecules", "structure", "image", "document",
  "archive", "binary", "unknown",
] as const
export type ViewKind = (typeof VIEW_KINDS)[number]

/** A preview view. `table`/`columns`/`plot`/`edit` are the tabular views; every other kind has
 *  exactly one content view (`content`), rendered by the kind's own viewer. */
export type PreviewView = "table" | "columns" | "plot" | "edit" | "content"

/** How the single `content` view of a kind is drawn. */
export type ContentRenderer =
  | "rows"        // the full-rows table (rows endpoint), falling back to the file's own viewer
  | "viewer"      // the file's own in-browser viewer (JSON tree, image, 3D, sequences, VCF, markdown, PDF…)
  | "anndata"     // AnnData / Loom summary built from the profile
  | "summary"     // a stats + findings summary built from the profile (BAM, Matrix Market, spreadsheets)
  | "download"    // honest "cannot be shown here" + Download

/** Stat codes the QC card can show (`perception.stat.<code>`). */
export type StatCode =
  | "rows" | "columns" | "cells" | "genes" | "sequences" | "bases" | "reads" | "read_length"
  | "variants" | "samples" | "regions" | "features" | "molecules" | "chains" | "sheets"
  | "references" | "entries" | "records" | "tables"
export interface StatItem { code: StatCode | string; value: number | string }

export interface DatasetViewModel {
  kind: ViewKind
  /** Preview views offered, in order; the first is the default. One view → no toggle bar. */
  views: PreviewView[]
  content: ContentRenderer
  /** Ask the paged rows endpoint for this file. */
  useRows: boolean
  /** Rows / columns belong in the stat grid (only for tables). */
  tableShape: boolean
  canEdit: boolean
  canRunQC: boolean
  canOpenIn: boolean
}

// ── kind from the file extension (older profiles without viewKind) ───────────
const EXT_KIND: Record<string, ViewKind> = {}
const add = (kind: ViewKind, exts: string) => exts.split(" ").forEach((e) => { EXT_KIND[e] = kind })
add("table", "csv tsv tab tabular txt xlsx xls")
add("records", "jsonl ndjson")
add("json", "json yaml yml")
add("sequences", "fasta fa fna faa ffn fas")
add("reads", "fastq fq")
add("variants", "vcf bcf")
add("intervals", "bed narrowpeak broadpeak bedgraph bedpe")
add("annotation", "gtf gff gff3")
add("alignment", "bam sam cram")
add("anndata", "h5ad")
add("loom", "loom")
add("matrix", "mtx")
add("molecules", "smi smiles sdf mol mol2")
add("structure", "pdb cif mmcif ent mrc mrcs map rec")
add("image", "png jpg jpeg gif webp svg tif tiff bmp")
add("document", "pdf md markdown log html htm rtf")
add("archive", "zip tar tgz 7z rar")
add("binary", "h5 hdf5 rds rdata rda pod5 fast5 cs csg bin")

const COMPRESSION = /\.(gz|bgz|bz2|zst|xz)$/i

/** Lower-case extension, looking through one compression suffix (`x.fastq.gz` → `fastq`). */
export function fileExt(name: string): string {
  const base = name.replace(COMPRESSION, "")
  const dot = base.lastIndexOf(".")
  return dot < 0 ? "" : base.slice(dot + 1).toLowerCase()
}

export function kindFromName(name: string): ViewKind {
  const ext = fileExt(name)
  if (EXT_KIND[ext]) return EXT_KIND[ext]
  // A bare archive (`.tar.gz`, `.gz` of nothing we know) is an archive.
  if (/\.(tar\.gz|tgz|gz|bz2|zst|xz)$/i.test(name) && !ext) return "archive"
  return "unknown"
}

/** Content-first: the profiler's `viewKind`, else the file extension. */
export function datasetKind(name: string, profile?: Pick<DataProfile, "viewKind"> | null): ViewKind {
  const vk = profile?.viewKind
  if (vk && (VIEW_KINDS as readonly string[]).includes(vk)) return vk as ViewKind
  return kindFromName(name)
}

const EDITABLE_EXT = new Set(["csv", "tsv", "tab", "txt"])
const R_OBJECT_EXT = new Set(["rds", "rdata", "rda"])

const QC_KINDS = new Set<ViewKind>(["table", "records", "sequences", "reads", "alignment", "variants", "anndata", "loom", "matrix"])
const OPEN_IN_KINDS = new Set<ViewKind>([
  "table", "records", "json", "sequences", "reads", "variants", "intervals", "annotation",
  "alignment", "anndata", "loom", "matrix", "molecules", "structure",
])
const CONTENT: Record<ViewKind, ContentRenderer> = {
  table: "rows", records: "rows", intervals: "rows", annotation: "rows", molecules: "rows",
  json: "viewer", sequences: "viewer", reads: "viewer", variants: "viewer", structure: "viewer",
  image: "viewer", document: "viewer",
  anndata: "anndata", loom: "anndata",
  alignment: "summary", matrix: "summary",
  archive: "download", binary: "download", unknown: "download",
}

/**
 * The view model for one file.
 *  - `hasColumns`: the rows endpoint or the profile produced column names (a table we can show).
 *  - `columnsPending`: still waiting for them (keep the table views while loading).
 *  - `versionable`: a user file in a project (edits write a new version).
 */
export function datasetViewModel(
  kind: ViewKind,
  opts: { name: string; hasColumns?: boolean; columnsPending?: boolean; versionable?: boolean; projectFile?: boolean } = { name: "" },
): DatasetViewModel {
  const ext = fileExt(opts.name)
  const tabular = kind === "table" || kind === "records"
  // A table we cannot read here (e.g. a spreadsheet the rows endpoint does not parse) has no
  // Columns / Plot / Edit to offer — its single view is the profile summary.
  const tableAvailable = tabular && (Boolean(opts.hasColumns) || Boolean(opts.columnsPending))
  const canEdit = kind === "table" && Boolean(opts.versionable) && Boolean(opts.hasColumns) && EDITABLE_EXT.has(ext)
    && !COMPRESSION.test(opts.name)
  const views: PreviewView[] = tableAvailable
    ? ["table", "columns", "plot", ...(canEdit ? (["edit"] as const) : [])]
    : ["content"]
  const content: ContentRenderer = tabular && !tableAvailable ? "summary" : CONTENT[kind]
  return {
    kind,
    views,
    content,
    useRows: CONTENT[kind] === "rows",
    tableShape: tabular,
    canEdit,
    canRunQC: QC_KINDS.has(kind),
    canOpenIn: Boolean(opts.projectFile) && (OPEN_IN_KINDS.has(kind) || R_OBJECT_EXT.has(ext)),
  }
}

// ── stats per kind ───────────────────────────────────────────────────────────

/** Which finding carries a kind's headline numbers when the profile has no `stats` (older backends). */
const FINDING_STATS: Record<string, Array<[StatCode, string]>> = {
  fastq_reads: [["reads", "reads"], ["read_length", "mean_len"]],
  fasta_sequences: [["sequences", "sequences"], ["bases", "total"]],
  vcf_records: [["variants", "variants"], ["samples", "samples"]],
  anndata_shape: [["cells", "cells"], ["genes", "genes"]],
  loom_shape: [["cells", "cells"], ["genes", "genes"]],
  mtx_dimensions: [["rows", "rows"], ["columns", "cols"]],
  mtx_dense: [["rows", "rows"], ["columns", "cols"]],
  intervals_summary: [["regions", "regions"]],
  annotation_features: [["features", "features"]],
  molecules_count: [["molecules", "molecules"]],
  structure_chains: [["chains", "count"]],
  spreadsheet_sheets: [["sheets", "count"]],
  alignment_references: [["references", "references"]],
}

/**
 * The QC card's headline numbers for this file. `profile.stats` when the backend sends them;
 * otherwise rows × columns for tables only, and the kind's own measures read from its findings.
 * Never rows × columns for a non-table (a PNG is not "0 rows, 0 columns").
 */
export function profileStats(profile: DataProfile, kind: ViewKind): StatItem[] {
  if (Array.isArray(profile.stats) && profile.stats.length) {
    return profile.stats.filter((s) => s && typeof s.code === "string" && s.value !== null && s.value !== undefined)
  }
  if (kind === "table" || kind === "records") {
    // A profile that could not read the table (e.g. a spreadsheet) has no honest shape.
    if (!profile.shape || (!profile.shape.cols && !profile.columns?.length)) {
      return statsFromFindings(profile.findings)
    }
    return [{ code: "rows", value: profile.shape.rows }, { code: "columns", value: profile.shape.cols || profile.columns?.length || 0 }]
  }
  return statsFromFindings(profile.findings)
}

function statsFromFindings(findings: PerceptionFinding[] | undefined): StatItem[] {
  const out: StatItem[] = []
  for (const f of findings ?? []) {
    const spec = FINDING_STATS[f.code]
    if (!spec) continue
    for (const [code, param] of spec) {
      const v = f.params?.[param]
      if ((typeof v === "number" || typeof v === "string") && !out.some((s) => s.code === code)) out.push({ code, value: v })
    }
  }
  return out
}

// ── quality ──────────────────────────────────────────────────────────────────
export type EffectiveQuality = PerceptionQuality

/** Findings that only say "identified, contents not analysed". */
const NOT_ANALYSED = new Set(["format_identified", "format_metadata_only", "format_metadata_skipped", "unprofilable"])

/**
 * The verdict to show. The backend says "unassessed" when it identified a file without
 * analysing its content; an older backend said "watch" for that, with only not-analysed
 * findings as its reasons — those are shown as "Not checked" too, never as a warning.
 */
export function effectiveQuality(profile: Pick<DataProfile, "quality" | "findings">): EffectiveQuality {
  if (profile.quality !== "watch" || !Array.isArray(profile.findings)) return profile.quality
  const reasons = profile.findings.filter((f) => f.level === "watch" && f.section !== "plan")
  return reasons.length > 0 && reasons.every((f) => NOT_ANALYSED.has(f.code)) ? "unassessed" : profile.quality
}

// ── column problems (structured, never substring-matched) ────────────────────

/** Finding codes that name a column as a problem, and the param(s) holding the column name(s). */
const COLUMN_PROBLEM_PARAMS: Record<string, string> = {
  near_constant: "columns",
  high_missing: "columns",
  label_free_text: "column",
  leaked_id: "column",
  leaked_feature: "column",
  batch_confound: "column",
  nested_blank_cells: "column",
  nested_row_cap: "column",
}

/** column name → the findings that name it as a problem. */
export function columnProblems(findings: PerceptionFinding[] | undefined): Map<string, PerceptionFinding[]> {
  const out = new Map<string, PerceptionFinding[]>()
  for (const f of findings ?? []) {
    const param = COLUMN_PROBLEM_PARAMS[f.code]
    if (!param || f.section === "plan") continue
    const v = f.params?.[param]
    const names = Array.isArray(v) ? v.map(String) : typeof v === "string" ? [v] : []
    for (const n of names) out.set(n, [...(out.get(n) ?? []), f])
  }
  return out
}
