/**
 * Data-fetching hooks for the Datasets surface (Tier-1 data-centric).
 *
 * Backend endpoints (all proxied to Galaxy by the shared `_dlProxyHandler` in
 * server/routes.ts, same pattern as /api/models):
 *
 *   POST /api/perception/profile        { datasetRef } -> DataProfile (+ planImpact)
 *   GET  /api/datasets/:ref/lineage     -> producing run/workflow/step
 *   GET  /api/datasets/:ref/consumers   -> runs that read it as input
 *   GET  /api/datasets/:ref/versions    -> version history (honest v1 · current)
 *   POST /api/datasets/:ref/versions    -> append a version-log entry { note }
 *   GET  /api/datasets/:ref/ro-crate    -> RO-Crate metadata (download)
 *   GET  /api/projects/:id/files/:fileId/rows -> one page of FULL rows (useDatasetRows)
 *
 * Lineage / consumers / versions are derived from run-output provenance and the
 * input params BioMate already tracks (backend datasets_object.py). Each
 * degrades to an honest empty result where a source genuinely has nothing — the
 * DatasetObject renders "not available yet" rather than fabricating a value.
 *
 * Uses the app's react-query conventions (see lib/queryClient.ts).
 */

import {
  useMutation,
  useQuery,
  useQueryClient,
  type UseMutationResult,
  type UseQueryResult,
} from "@tanstack/react-query"
import { useCallback, useEffect, useRef, useState } from "react"
import type { DataProfile } from "@/components/data-perception"

/**
 * The profile shape the backend returns is the frontend `DataProfile` with an
 * extra `planImpact` list living alongside it (see data_perception.py
 * `to_dict()`), so we widen the type here.
 */
export interface PerceptionResponse extends DataProfile {
  planImpact?: { observed: string; effect: string }[]
}

/**
 * Profile a dataset by reference (an S3 key or a local path). Enabled only when
 * a ref is supplied. Errors surface via `isError` so the caller can render an
 * honest "quality not available" state.
 */
export function usePerceptionProfile(
  datasetRef: string | null,
  name?: string,
): UseQueryResult<PerceptionResponse> {
  return useQuery<PerceptionResponse>({
    queryKey: ["/api/perception/profile", datasetRef],
    enabled: !!datasetRef,
    // Profiling is deterministic; don't refetch aggressively.
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: async () => {
      const res = await fetch("/api/perception/profile", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ datasetRef, name }),
      })
      if (!res.ok) throw new Error(`${res.status}: failed to profile dataset`)
      return (await res.json()) as PerceptionResponse
    },
  })
}

// ── Lineage / Consumers / Versions ───────────────────────────────────────────
// A run descriptor, as returned by the datasets_object backend. Every field is
// nullable because the backend only fills what it actually tracks.
export interface RunLabel {
  runId: string
  workflow?: string | null
  workflowPath?: string | null
  status?: string | null
  createdAt?: string | number | null
}

export interface LineageResponse {
  ref: string
  /** false when the dataset has no upstream run (uploaded input). */
  available: boolean
  /** "run_output" | "output_prefix" | null */
  source?: string | null
  /** The run/workflow that produced this dataset, or null. */
  producedBy?: RunLabel | null
}

export interface ConsumersResponse {
  ref: string
  /** Runs recorded as reading this dataset — empty (honest) when none. */
  consumers: RunLabel[]
}

export interface DatasetVersion {
  version: string
  label: string
  current: boolean
  ref: string
  createdAt?: string | number | null
  producedByRunId?: string | null
  /** Operator note for a logged version (null for the implicit v1). */
  note?: string | null
  /** Author label recorded on the entry, when supplied. */
  author?: string | null
}

export interface VersionsResponse {
  ref: string
  versions: DatasetVersion[]
}

export interface AppendVersionResponse extends VersionsResponse {
  /** The entry just written (present only on success). */
  appended?: { note: string; author?: string | null; createdAt?: string | null }
  /** Present when the append was rejected (e.g. empty note). */
  error?: string
}

/** Encode a datasetRef (S3 key / path, may contain "/") for a path segment. */
function encodeRef(ref: string): string {
  return encodeURIComponent(ref)
}

async function _getJson<T>(url: string): Promise<T> {
  const res = await fetch(url, { credentials: "include" })
  if (!res.ok) throw new Error(`${res.status}: ${url}`)
  return (await res.json()) as T
}

/** Lineage — which run/workflow produced this dataset. Enabled when ref set. */
export function useDatasetLineage(
  ref: string | null,
): UseQueryResult<LineageResponse> {
  return useQuery<LineageResponse>({
    queryKey: ["/api/datasets/lineage", ref],
    enabled: !!ref,
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: () => _getJson<LineageResponse>(`/api/datasets/${encodeRef(ref!)}/lineage`),
  })
}

/** Consumers — which runs read this dataset as an input. */
export function useDatasetConsumers(
  ref: string | null,
): UseQueryResult<ConsumersResponse> {
  return useQuery<ConsumersResponse>({
    queryKey: ["/api/datasets/consumers", ref],
    enabled: !!ref,
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: () => _getJson<ConsumersResponse>(`/api/datasets/${encodeRef(ref!)}/consumers`),
  })
}

/** Versions — version history (v1 · current + the append-only log). */
export function useDatasetVersions(
  ref: string | null,
): UseQueryResult<VersionsResponse> {
  return useQuery<VersionsResponse>({
    queryKey: ["/api/datasets/versions", ref],
    enabled: !!ref,
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: () => _getJson<VersionsResponse>(`/api/datasets/${encodeRef(ref!)}/versions`),
  })
}

/**
 * Append a version-log entry (append-only; the backend never rewrites a prior
 * entry). On success it invalidates the versions query so the tab re-renders
 * with the new entry. The backend also returns the fresh list on the mutation
 * response, which we seed into the cache to avoid a redundant refetch.
 */
export function useAppendDatasetVersion(
  ref: string | null,
): UseMutationResult<AppendVersionResponse, Error, { note: string; author?: string }> {
  const qc = useQueryClient()
  return useMutation<AppendVersionResponse, Error, { note: string; author?: string }>({
    mutationFn: async (body) => {
      if (!ref) throw new Error("no dataset reference")
      const res = await fetch(`/api/datasets/${encodeRef(ref)}/versions`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      })
      if (!res.ok) throw new Error(`${res.status}: failed to append version`)
      const data = (await res.json()) as AppendVersionResponse
      // The backend returns a 200 with an `error` field for a rejected note.
      if (data.error) throw new Error(data.error)
      return data
    },
    onSuccess: (data) => {
      if (ref) {
        qc.setQueryData<VersionsResponse>(["/api/datasets/versions", ref], {
          ref: data.ref,
          versions: data.versions,
        })
      }
    },
  })
}

/**
 * Trigger a browser download of the dataset's RO-Crate metadata. Fetches
 * through the same credentialed proxy, then saves the JSON as
 * `<name>-ro-crate-metadata.json`. Returns the object so the caller can toast
 * on failure. Not a hook — called from a click handler.
 */
export async function downloadDatasetRoCrate(
  ref: string,
  datasetName?: string,
): Promise<void> {
  const res = await fetch(`/api/datasets/${encodeRef(ref)}/ro-crate`, {
    credentials: "include",
  })
  if (!res.ok) throw new Error(`${res.status}: failed to export RO-Crate`)
  const blob = await res.blob()
  const url = URL.createObjectURL(blob)
  try {
    const a = document.createElement("a")
    a.href = url
    const base = (datasetName || "dataset").replace(/[^\w.-]+/g, "_")
    a.download = `${base}-ro-crate-metadata.json`
    document.body.appendChild(a)
    a.click()
    a.remove()
  } finally {
    URL.revokeObjectURL(url)
  }
}

// ── Full rows (paged) ─────────────────────────────────────────────────────────
// GET /api/projects/:id/files/:fileId/rows?offset=&limit= — one page of the file's
// FULL rows, parsed by the same backend readers as the profiler (csv/tsv/jsonl).

/** Extensions the rows endpoint is asked to parse (and their gzip variants). Delimited
 *  tables + JSONL, and the header-less spec formats (BED family, GFF/GTF, SMILES) the
 *  backend reads with their spec column names. When the backend answers
 *  `tabular: false` the route returns 415 → `unsupported`, and the Preview falls back
 *  to the in-browser text/annotation preview (dataset-object.tsx). */
const ROWS_EXTS = /\.(csv|tsv|tab|txt|jsonl|ndjson|bed|narrowpeak|broadpeak|bedgraph|bedpe|gtf|gff|gff3|smi|smiles)(\.gz)?$/i
export function rowsSupported(name: string): boolean {
  return ROWS_EXTS.test(name)
}

export const ROWS_PAGE = 200
/** "Load all rows" pulls bigger pages and stops at this many rows (browser memory). */
export const LOAD_ALL_CAP = 100_000
const LOAD_ALL_PAGE = 1000

export interface DatasetRowsState {
  columns: string[]
  rows: string[][]
  /** True total row count from the server (null until the first page arrives). */
  total: number | null
  loading: boolean
  /** HTTP status (or 0 for a network failure) of the last failed page. */
  error: number | null
  /** The file is not tabular (415) — the caller falls back to the text preview. */
  unsupported: boolean
  /**
   * Whether line 1 of the file is a header record (the rows reader infers it from the content:
   * a header-less numeric table or gene list has none). The edit route numbers data rows after
   * this many header records. null until the first page arrives (or an older backend).
   */
  headerRow: boolean | null
  /**
   * The file version the loaded rows were read from (the rows response's `version`; null on an
   * older server). An edit sends it as `baseVersion`, so a save made against rows someone has
   * since replaced is refused (409 version_conflict) instead of landing on the wrong row.
   * When pages come from different versions, the OLDEST is kept: the user saw stale rows.
   */
  version: number | null
  /**
   * Leading comment / blank PHYSICAL lines the rows reader skipped before the table (the rows
   * response's `skipLines`; null when not reported). An edit sends it back so the server numbers
   * data rows exactly as the rows the user saw were numbered.
   */
  skipLines: number | null
  /**
   * The field delimiter the rows reader split the table on (the rows response's `delimiter`, e.g.
   * "," "\t" ";"; null when not reported). An edit sends it back so the server splits the file the
   * same way — a semicolon CSV is never re-read as one comma column.
   */
  delimiter: string | null
  /**
   * The decimal mark of the table's numbers when the rows reader reports it (`decimal`, e.g. ","
   * for a European semicolon CSV holding "1,5"); null when not reported (then ".").
   */
  decimal: string | null
  /**
   * The rows reader found no content: `empty_file` (0 bytes) or `blank_content` (only blank
   * lines) — its `{tabular: false, reason: "empty", code}` answer. An empty state, not an error and
   * not "still loading". null otherwise.
   */
  empty: EmptyCode | null
}

export type EmptyCode = "empty_file" | "blank_content"
/** The rows reader's "no content" answer (on a 200 or a 415), else null. */
function emptyCode(body: any): EmptyCode | null {
  if (!body || typeof body !== "object") return null
  if (body.code === "empty_file" || body.code === "blank_content") return body.code
  return body.reason === "empty" ? "empty_file" : null
}

const EMPTY_ROWS: DatasetRowsState = { columns: [], rows: [], total: null, loading: false, error: null, unsupported: false, headerRow: null, version: null, skipLines: null, delimiter: null, decimal: null, empty: null }

/**
 * Same-origin download link for a project file. The server answers with a redirect to a signed
 * URL that carries `Content-Disposition: attachment; filename=<display name>`, so the browser
 * saves the file under its display name and the tab never navigates to the storage URL.
 */
export function fileDownloadUrl(projectId: string, fileId: string): string {
  return `/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(fileId)}/url?redirect=1`
}

/** A TIFF project file's first plane rendered as PNG by the server (owner/member scoped, like Download). */
export function filePreviewPngUrl(projectId: string, fileId: string): string {
  return `/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(fileId)}/preview.png`
}

/** Start a download of a project file through the same-origin redirect (see fileDownloadUrl). */
export function downloadProjectFile(projectId: string, fileId: string, name: string): void {
  const a = document.createElement("a")
  a.href = fileDownloadUrl(projectId, fileId)
  a.download = name.split("/").pop() || name
  a.rel = "noopener"
  document.body.appendChild(a)
  a.click()
  a.remove()
}

/**
 * Page in a project file's full rows. `loadMore()` fetches the next page (no-op
 * while one is in flight or when every row is loaded); `loadAll()` keeps fetching
 * until the file (or LOAD_ALL_CAP) is exhausted. Disabled when projectId/fileId is
 * missing or the extension is not tabular.
 */
export function useDatasetRows(projectId: string | undefined, fileId: string, name: string, wanted = true) {
  const enabled = wanted && Boolean(projectId) && rowsSupported(name)
  const [state, setState] = useState<DatasetRowsState>(EMPTY_ROWS)
  const ref = useRef<DatasetRowsState>(EMPTY_ROWS)
  const inflight = useRef(false)
  const gen = useRef(0)

  const commit = useCallback((next: DatasetRowsState) => {
    ref.current = next
    setState(next)
  }, [])

  const fetchPage = useCallback(async (limit: number): Promise<boolean> => {
    const cur = ref.current
    if (!enabled || inflight.current || cur.unsupported || cur.empty) return false
    if (cur.total != null && cur.rows.length >= cur.total) return false
    inflight.current = true
    const myGen = gen.current
    commit({ ...cur, loading: true, error: null })
    try {
      const res = await fetch(
        `/api/projects/${encodeURIComponent(projectId!)}/files/${encodeURIComponent(fileId)}/rows?offset=${cur.rows.length}&limit=${limit}`,
        { credentials: "include" },
      )
      if (myGen !== gen.current) return false
      if (res.status === 415) {
        const declined = await Promise.resolve().then(() => res.json()).catch(() => null)
        if (myGen !== gen.current) return false
        const empty = emptyCode(declined)
        commit(empty ? { ...ref.current, loading: false, empty, total: 0 } : { ...ref.current, loading: false, unsupported: true })
        return false
      }
      if (!res.ok) { commit({ ...ref.current, loading: false, error: res.status }); return false }
      const body = await res.json()
      if (myGen !== gen.current) return false
      const empty = emptyCode(body)
      if (empty || body?.tabular === false) {
        commit(empty ? { ...ref.current, loading: false, empty, total: 0 } : { ...ref.current, loading: false, unsupported: true })
        return false
      }
      const pageRows: string[][] = Array.isArray(body?.rows) ? body.rows : []
      const total: number | null = typeof body?.totalRows === "number" ? body.totalRows : null
      const columns: string[] = Array.isArray(body?.columns) ? body.columns : ref.current.columns
      const headerRow: boolean | null = typeof body?.headerRow === "boolean" ? body.headerRow : ref.current.headerRow
      const pageVersion: number | null = typeof body?.version === "number" ? body.version : null
      const prevVersion = ref.current.version
      const version = prevVersion == null ? pageVersion : pageVersion == null ? prevVersion : Math.min(prevVersion, pageVersion)
      const skipLines: number | null = Number.isInteger(body?.skipLines) && body.skipLines >= 0 ? body.skipLines : ref.current.skipLines
      const delimiter: string | null = typeof body?.delimiter === "string" && body.delimiter.length > 0 ? body.delimiter : ref.current.delimiter
      const decimal: string | null = body?.decimal === "," || body?.decimal === "." ? body.decimal : ref.current.decimal
      const rows = ref.current.rows.concat(pageRows)
      // A short page means the end of the file even if no total was reported.
      commit({ columns, rows, total: total ?? (pageRows.length < limit ? rows.length : null), loading: false, error: null, unsupported: false, headerRow, version, skipLines, delimiter, decimal, empty: null })
      return pageRows.length > 0
    } catch {
      if (myGen === gen.current) commit({ ...ref.current, loading: false, error: 0 })
      return false
    } finally {
      if (myGen === gen.current) inflight.current = false
    }
  }, [enabled, projectId, fileId, commit])

  const [reloads, setReloads] = useState(0)
  useEffect(() => {
    gen.current += 1
    inflight.current = false
    commit(EMPTY_ROWS)
    if (enabled) void fetchPage(ROWS_PAGE)
  }, [enabled, projectId, fileId, commit, fetchPage, reloads])
  /** Drop the loaded rows and read the file again from the first page (after a save). */
  const reload = useCallback(() => setReloads((n) => n + 1), [])

  const loadMore = useCallback(() => { void fetchPage(ROWS_PAGE) }, [fetchPage])
  const loadAll = useCallback(async () => {
    const myGen = gen.current
    while (myGen === gen.current && ref.current.rows.length < LOAD_ALL_CAP) {
      const cur = ref.current
      if (cur.unsupported || cur.error != null || (cur.total != null && cur.rows.length >= cur.total)) break
      if (inflight.current) { await new Promise((r) => setTimeout(r, 50)); continue }
      if (!(await fetchPage(LOAD_ALL_PAGE))) break
    }
  }, [fetchPage])
  const retry = loadMore

  return { enabled, ...state, loadMore, loadAll, retry, reload }
}

// ── Folder profile ───────────────────────────────────────────────────────────
// GET /api/projects/:id/folders/profile?path=<folder> — what an input folder holds as a whole
// (backend galaxy/ai/folder_profile.py): FASTQ pairs/orphans + samplesheet, 10x matrix sets,
// or a format roll-up. `path` is relative to the inputs root ("" = root).
export interface FolderFinding {
  code: string
  level: "info" | "watch" | "blocked"
  params?: Record<string, unknown>
}

export interface FolderSample {
  sample: string
  forward: string | null
  reverse: string | null
  status: "paired" | "orphan" | "single"
  role?: "forward" | "reverse" | null
  dir?: string
}

export interface TenxSet {
  dir: string
  prefix?: string
  matrix: string
  barcodes?: string | null
  features?: string | null
  version?: "v2" | "v3" | null
  complete: boolean
  missing: string[]
  genes?: number
  cells?: number
  nnz?: number | null
}

export interface FolderProfile {
  path: string
  kind: "fastq_set" | "tenx_matrix" | "mixed" | "empty"
  fileCount: number
  /** Grouped by (format, label): each file labelled by the SAME content decision as its own profile
   *  (featureCounts counts vs TSV), with that decision's view kind. */
  rollup: { format: string; label: string; count: number; pairs?: number; viewKind?: string }[]
  findings: FolderFinding[]
  fastq?: {
    verdict: "paired" | "single_end" | "mixed"
    pattern: string | null
    /** Every read-token style in use ("Rs" = _R1/_R2, "illumina" = _1/_2, "dot12s" = .1/.2). */
    patterns?: string[]
    engine: "galaxy" | "fallback"
    pairs: number
    samples: FolderSample[]
    orphans: string[]
    singles: string[]
  }
  /** The nf-core samplesheet. A run takes ONE layout: with any pair it holds the pairs only
   *  (`layout` "paired") and the unpaired files go to `single` (a single-end sheet), named in
   *  `excluded`; without a pair it IS the single-end sheet. Paths are relative to `pathBase`. */
  samplesheet?: FolderSamplesheet & { single?: FolderSamplesheet; excluded?: string[] }
  tenx?: { sets: TenxSet[] }
}

export interface FolderSamplesheet {
  columns: string[]
  rows: string[][]
  csv: string
  filename: string
  layout?: "paired" | "single_end"
  pathBase?: string
}

export function folderProfileUrl(projectId: string, path: string, download = false): string {
  const q = new URLSearchParams({ path })
  if (download) q.set("download", "samplesheet")
  return `/api/projects/${encodeURIComponent(projectId)}/folders/profile?${q.toString()}`
}

export function useFolderProfile(projectId: string | null | undefined, path: string | null): UseQueryResult<FolderProfile> {
  return useQuery<FolderProfile>({
    queryKey: ["/api/projects/folders/profile", projectId, path],
    enabled: !!projectId && path !== null,
    staleTime: 60 * 1000,
    retry: false,
    queryFn: async () => {
      const res = await fetch(folderProfileUrl(projectId!, path!), { credentials: "include" })
      if (!res.ok) throw new Error(`${res.status}: failed to profile folder`)
      return (await res.json()) as FolderProfile
    },
  })
}
