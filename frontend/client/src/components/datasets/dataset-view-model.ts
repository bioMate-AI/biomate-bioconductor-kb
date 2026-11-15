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
  | "empty"       // the file has no content (0 bytes / only blank lines): say so

/** Stat codes the QC card can show (`perception.stat.<code>`). */
export type StatCode =
  | "rows" | "columns" | "cells" | "genes" | "sequences" | "bases" | "reads" | "read_length"
  | "variants" | "samples" | "regions" | "features" | "molecules" | "chains" | "sheets"
  | "references" | "entries" | "records" | "tables"
export interface StatItem {
  code: StatCode | string
  value: number | string
  /** A sampled / capped count: the true value is at least this ("at least N"). */
  atLeast?: boolean
}

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
  /** The kind can be opened in Jupyter / RStudio (a project file of a kind those tools read). */
  openInSupported: boolean
  /** Open-in is OFFERED: supported AND the launch path is available (OPEN_IN_AVAILABLE). Every
   *  panel element that points to Open-in (the button, notes that say "open it in Jupyter")
   *  follows this — never the kind alone. */
  canOpenIn: boolean
}

/** Whether the Open-in (Jupyter / RStudio) launch from the dataset panel is available. Off since
 *  2026-11-11 (founder): the interactive-tool launch path is not working yet. One switch, so the
 *  button and the copy that mentions it can never disagree. */
export const OPEN_IN_AVAILABLE = false

// ── kind from the file extension (older profiles without viewKind) ───────────
const EXT_KIND: Record<string, ViewKind> = {}
const add = (kind: ViewKind, exts: string) => exts.split(" ").forEach((e) => { EXT_KIND[e] = kind })
// The same vocabulary and the same decisions as the profiler's decide() (data_perception.py:
// _KIND_VIEW / _GALAXY_VIEW / _BINARY_NAME_FORMATS), so an old profile without viewKind and a new
// one agree: .smi is a table (with a molecules stat), spreadsheets and Office files are
// documents, MRC maps are images, POD5 / FAST5 / HDF5 are binary.
add("table", "csv tsv tab tabular txt smi smiles")
add("records", "jsonl ndjson")
add("json", "json yaml yml")
add("sequences", "fasta fa fna faa ffn fas genbank gb gbk")
add("reads", "fastq fq")
add("variants", "vcf bcf")
add("intervals", "bed narrowpeak broadpeak bedgraph bedpe")
add("annotation", "gtf gff gff3")
add("alignment", "bam sam cram")
add("anndata", "h5ad")
add("loom", "loom")
add("matrix", "mtx")
add("molecules", "sdf mol mol2 inchi")
add("structure", "pdb cif mmcif ent pqr gro")
// `.map` / `.rec` are not images by name (a PLINK .map is a text table): only the profiler, which
// reads the header, calls such a file an MRC map.
add("image", "png jpg jpeg gif webp svg tif tiff bmp mrc mrcs")
add("document", "pdf md markdown log html htm rtf xlsx xls docx pptx")
add("archive", "zip tar tgz 7z rar")
add("binary", "h5 hdf5 rds rdata rda pod5 fast5 bigwig bw bigbed bb npy parquet sqlite db cs csg bin")

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

/** Finding codes that mean the file has no content. */
export const EMPTY_FILE_CODES = new Set(["empty_file", "blank_content"])
/** The "no content" code from the profile's findings, else null. */
export function profileEmptyCode(profile?: Pick<DataProfile, "findings"> | null): "empty_file" | "blank_content" | null {
  const f = profile?.findings?.find((x) => EMPTY_FILE_CODES.has(x.code))
  return f ? (f.code as "empty_file" | "blank_content") : null
}

/** Content-first: the profiler's `viewKind`, else the file extension. */
export function datasetKind(name: string, profile?: Pick<DataProfile, "viewKind"> | null): ViewKind {
  const vk = profile?.viewKind
  if (vk && (VIEW_KINDS as readonly string[]).includes(vk)) return vk as ViewKind
  return kindFromName(name)
}

const EDITABLE_EXT = new Set(["csv", "tsv", "tab", "txt"])
/** Documents a browser cannot draw (spreadsheets, Office files): their view is the profile
 *  summary (sheets, what was read), never an empty "preview unsupported". */
const SUMMARY_DOCUMENT_EXT = new Set(["xlsx", "xls", "docx", "pptx"])
const R_OBJECT_EXT = new Set(["rds", "rdata", "rda"])

const QC_KINDS = new Set<ViewKind>(["table", "records", "sequences", "reads", "alignment", "variants", "anndata", "loom", "matrix"])
const OPEN_IN_KINDS = new Set<ViewKind>([
  "table", "records", "json", "sequences", "reads", "variants", "intervals", "annotation",
  "alignment", "anndata", "loom", "matrix", "molecules", "structure",
])
// `rows` exactly for the kinds the backend's read_rows pages (tabular = table / records /
// intervals / annotation); molecules (SDF, MOL2) are read by their own viewer.
const CONTENT: Record<ViewKind, ContentRenderer> = {
  table: "rows", records: "rows", intervals: "rows", annotation: "rows",
  molecules: "viewer", json: "viewer", sequences: "viewer", reads: "viewer", variants: "viewer", structure: "viewer",
  image: "viewer", document: "viewer",
  anndata: "anndata", loom: "anndata",
  // BAM/CRAM: in-product IGV.js slot (dataset-file-preview); not Interactive Tools.
  alignment: "viewer", matrix: "summary",
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
  opts: { name: string; hasColumns?: boolean; columnsPending?: boolean; versionable?: boolean; projectFile?: boolean; empty?: boolean
    /** A table with a header and no data rows: nothing to edit, nothing for a QC workflow to check. */
    noDataRows?: boolean } = { name: "" },
): DatasetViewModel {
  const ext = fileExt(opts.name)
  // No content at all: one honest "empty" view whatever the kind — no table tools, no edit, no
  // "not shown cell by cell" summary, no "cannot be shown here".
  if (opts.empty) {
    return {
      kind, views: ["content"], content: "empty", useRows: CONTENT[kind] === "rows", tableShape: false,
      canEdit: false, canRunQC: false, openInSupported: false, canOpenIn: false,
    }
  }
  const tabular = kind === "table" || kind === "records"
  // A table we cannot read here (e.g. a spreadsheet the rows endpoint does not parse) has no
  // Columns / Plot / Edit to offer — its single view is the profile summary.
  const tableAvailable = tabular && (Boolean(opts.hasColumns) || Boolean(opts.columnsPending))
  const canEdit = kind === "table" && Boolean(opts.versionable) && Boolean(opts.hasColumns) && EDITABLE_EXT.has(ext)
    && !COMPRESSION.test(opts.name) && !opts.noDataRows
  const views: PreviewView[] = tableAvailable
    ? ["table", "columns", "plot", ...(canEdit ? (["edit"] as const) : [])]
    : ["content"]
  const content: ContentRenderer = tabular && !tableAvailable ? "summary"
    : kind === "document" && SUMMARY_DOCUMENT_EXT.has(ext) ? "summary"
    : CONTENT[kind]
  const openInSupported = Boolean(opts.projectFile) && (OPEN_IN_KINDS.has(kind) || R_OBJECT_EXT.has(ext))
  return {
    kind,
    views,
    content,
    useRows: CONTENT[kind] === "rows",
    tableShape: tabular,
    canEdit,
    canRunQC: QC_KINDS.has(kind) && !(tabular && opts.noDataRows),
    openInSupported,
    canOpenIn: OPEN_IN_AVAILABLE && openInSupported,
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
    return profile.stats
      .filter((s) => s && typeof s.code === "string" && s.value !== null && s.value !== undefined)
      .map((s) => (s.atLeast ? { code: s.code, value: s.value, atLeast: true } : { code: s.code, value: s.value }))
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

/**
 * Findings whose whole content is the kind's headline numbers ("Variant records: 30; samples: 1.",
 * "Rows: 6 · columns: 5.", "Reads scanned: 10,000; mean read length 151 bp."): each param and the stat code(s) that
 * show the same number. A finding with any other param says something more and is never listed here.
 */
const NUMBERS_ONLY_FINDINGS: Record<string, Record<string, readonly string[]>> = {
  vcf_records: { variants: ["variants"], samples: ["samples"] },
  vcf_summary: { variants: ["variants"], samples: ["samples"] },
  vcf_sized: { variants: ["variants"], samples: ["samples"] },
  // (anndata_shape / loom_shape state the matrix ORIENTATION since round 5, not the numbers: kept.)
  table_summary: { rows: ["rows", "records"], cols: ["columns"] },
  molecules_count: { molecules: ["molecules"] },
  fastq_reads: { reads: ["reads"], mean_len: ["read_length"] },
}

const sameNumber = (a: unknown, b: unknown) =>
  a != null && b != null && (a === b || (Number.isFinite(Number(a)) && Number(a) === Number(b)))

/**
 * True when `f` only restates numbers the host's stat grid shows with the same values — decided by
 * the finding's code and params (NUMBERS_ONLY_FINDINGS), never by matching its text. A finding with
 * an `at_least` qualifier is a lower bound and repeats an "at least" stat only.
 */
export function findingRepeatsStats(f: PerceptionFinding, stats: ReadonlyArray<Pick<StatItem, "code" | "value">>): boolean {
  const spec = NUMBERS_ONLY_FINDINGS[f.code]
  if (!spec || !f.params) return false
  const params = Object.entries(f.params).filter(([k]) => k !== "at_least")
  if (params.length === 0) return false
  return params.every(([k, v]) => {
    const codes = spec[k]
    return Boolean(codes) && stats.some((s) => codes.includes(s.code) && sameNumber(s.value, v))
  })
}

/** The count a finding's `at_least` param qualifies (backend _AT_LEAST_PARAMS). */
export const AT_LEAST_STAT: Record<string, string> = { fastq_reads: "reads", fasta_sequences: "sequences" }

function statsFromFindings(findings: PerceptionFinding[] | undefined): StatItem[] {
  const out: StatItem[] = []
  for (const f of findings ?? []) {
    const spec = FINDING_STATS[f.code]
    if (!spec) continue
    for (const [code, param] of spec) {
      const v = f.params?.[param]
      if ((typeof v === "number" || typeof v === "string") && !out.some((s) => s.code === code)) {
        // The finding's `at_least` marks its headline count (reads / sequences) as a lower bound.
        out.push(f.params?.at_least && code === AT_LEAST_STAT[f.code] ? { code, value: v, atLeast: true } : { code, value: v })
      }
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
  constant_columns: "columns",
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
    // Only a finding at watch / blocked level flags a column: an info-level statement (a
    // near-constant column that is expected with few rows, or per-record metadata) is a note.
    if (!param || f.section === "plan" || f.level === "info") continue
    const v = f.params?.[param]
    const names = Array.isArray(v) ? v.map(String) : typeof v === "string" ? [v] : []
    for (const n of names) out.set(n, [...(out.get(n) ?? []), f])
  }
  return out
}

// ── facts shown once ─────────────────────────────────────────────────────────

/** AnnData / Loom findings that the summary view draws as content (obs / var columns, embeddings,
 *  layers, the file's stored parts). */
const ANNDATA_CONTENT_CODES = [
  "anndata_obs", "anndata_var", "anndata_embeddings", "anndata_layers", "anndata_no_layers",
  "anndata_components", "hdf5_groups", "loom_col_attrs", "loom_row_attrs", "loom_layers",
]

/** The spreadsheet sheet the profiler read (its first rows), when the profile carries one. */
export function previewedSheet(profile?: Pick<DataProfile, "previewSheet" | "columns" | "sampleRows"> | null):
  { name: string; columns: string[]; rows: string[][] } | null {
  return profile && typeof profile.previewSheet === "string" && profile.columns?.length && profile.sampleRows?.length
    ? { name: profile.previewSheet, columns: profile.columns, rows: profile.sampleRows } : null
}

/**
 * Finding codes the Preview already shows as content, so the QC card does not list them again:
 * each fact once — the stat grid for numbers, the QC card for findings, the preview for content.
 *  - the AnnData / Loom summary draws the obs / var columns, embeddings, layers and stored parts;
 *  - a spreadsheet whose first rows are previewed: "preview of sheet X" repeats the caption, and
 *    "Sheets (1): X" repeats the caption + the SHEETS stat when X is the only sheet.
 */
export function findingsShownAsContent(content: ContentRenderer, profile?: DataProfile | null): ReadonlySet<string> {
  if (!profile) return new Set()
  if (content === "anndata") return new Set(ANNDATA_CONTENT_CODES)
  // ("metadata was read; values not analysed" is not emitted by the profiler when it read the
  // preview rows — round-4 backend — so only the caption's twin is left to drop here.)
  const sheet = previewedSheet(profile)
  if (content === "summary" && sheet) {
    // "Sheets (1): Data." when "Data" is the ONLY sheet: the caption names it and the stat grid counts
    // it. Decided by the finding's params, never its text; a workbook with more sheets keeps the list.
    const sheets = (profile.findings ?? []).find((f) => f.code === "spreadsheet_sheets")?.params?.sheets
    const onlyPreviewed = Array.isArray(sheets) && sheets.length === 1 && String(sheets[0]) === sheet.name
    return new Set(onlyPreviewed ? ["spreadsheet_preview", "spreadsheet_sheets"] : ["spreadsheet_preview"])
  }
  return new Set()
}
