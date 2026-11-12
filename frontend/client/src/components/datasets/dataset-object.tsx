/**
 * DatasetObject — a file presented as a first-class object, conformed to design
 * spec 04 ("Files & the dataset object") + the rendered prototype
 * (data_centroid_design_v2). See docs/20261020_DATASET_PANEL_DESIGN_AUDIT.md.
 *
 * Header:  name · v{N} chip · quality pill · [Ask in chat] [Download]
 * Tabs:    Preview · Versions · Where it came from
 *   Preview       — Table / Columns / Plot toggle over the file's FULL rows (paged
 *                   from GET /api/projects/:id/files/:fileId/rows), the Data QC card
 *                   directly under the table, and a 4-card stat grid.
 *   Versions      — the append-only version log + "why versions matter".
 *   Where it came — Origin + what used it, with Export for deposit (RO-Crate).
 *
 * Project files use permission-checked content previews and append-only byte
 * versions. Column summaries and plots are explicitly sample-derived. Interactive
 * opening stages a file into the user's Galaxy history; launch failures remain
 * scoped to that action and never replace the preview/provenance content.
 */

import { useState, useEffect, useLayoutEffect, useCallback, useRef, cloneElement, isValidElement, type ReactNode } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import {
  ChevronLeft,
  ChevronRight,
  Eye,
  GitBranch,
  History,
  Download,
  FileArchive,
  Play,
  ShieldCheck,
  Table as TableIcon,
  Columns3,
  BarChart3,
  SquareTerminal,
  Pencil,
  Copy,
  Check,
} from "lucide-react"
import { DataPerception, formatStatValue, type PerceptionQuality, type StructureEvidence } from "@/components/data-perception"
import { datasetKind, datasetViewModel, effectiveQuality, findingsShownAsContent, profileEmptyCode, profileStats, type PreviewView, type StatItem } from "./dataset-view-model"
import { AnnDataSummary, KindSummary, DownloadState } from "./dataset-kind-views"
import { DatasetFilePreview, type FilePreviewStatus } from "./dataset-file-preview"
import { t, tOr, locale } from "@/lib/i18n"
import { HintTip } from "@/components/ui/hint-tip"

// Dates follow the APP language (not the browser default), so a Chinese UI never shows "Nov 10".
const INTL_LOCALE = locale === "zh" ? "zh-CN" : "en-US"
import {
  usePerceptionProfile,
  useDatasetLineage,
  useDatasetConsumers,
  useDatasetVersions,
  downloadDatasetRoCrate,
  useDatasetRows,
  LOAD_ALL_CAP,
} from "./datasets-api"
import { DatasetRowsTable } from "./dataset-rows-table"
import { DatasetVersionsList } from "./dataset-versions-list"
import { DatasetSamplePlot, hasNumericColumns } from "./dataset-sample-plot"
import { DatasetColumnsView } from "./dataset-columns-view"
import { resolveViewer } from "../viewers/inline-content-viewers"
import { datasetShape, editErrorMessage, kindLabel, localizedFormatLabel, openInErrorMessage, sourceLabel } from "./dataset-presentation"
import { breakAtSeparators, splitPath } from "./name-breaks"

// ── DatasetRef — the identity + provenance the caller already holds ──────────
export interface DatasetRef {
  /** Stable id (file id / dataset id). */
  id: string
  /** Display name (file name). */
  name: string
  /** Reference the profiler resolves — an S3 key or a local/absolute path. */
  ref: string | null
  /** Byte size, if known. */
  size?: number | null
  /** MIME / content type, if known. */
  contentType?: string | null
  /** "upload" | "run_output" | string. */
  source?: string | null
  /** Public accession the user supplied that triggered an auto-fetch (GSE/SRR/
   *  GSM/E-MTAB/PXD…). When present it IS the origin for a public pull — shown
   *  as a plain id, no constructed link. */
  accession?: string | null
  /** The run that produced this dataset (run_output only). */
  runId?: string | null
  /** The workflow that produced it. */
  workflowName?: string | null
  /** The step that produced it. */
  stepName?: string | null
  /** ISO timestamp. */
  createdAt?: string | null
  /** Runs / campaigns that read this dataset (empty when unknown). */
  consumers?: string[]
  /** Prior versions of this dataset (empty when unknown). */
  versions?: string[]
  /** sha256 content hash (dedup key), when known. */
  contentHash?: string | null
}

/** A save failure whose message is already localized for the user. */
class EditError extends Error {}

function formatBytes(n: number | null | undefined): string {
  if (n === null || n === undefined) return "—"
  if (n < 1024) return `${n} B`
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`
}

function fmt(v: string | number | null | undefined): string {
  return v === null || v === undefined || v === "" ? "—" : String(v)
}

interface DatasetObjectProps {
  dataset: DatasetRef
  onBack?: () => void
  onDownload?: () => void
  /** Open the workflow run that produced (or reads) this dataset. */
  onOpenRun?: (runId: string) => void
  /** Project the dataset lives in — lets the lineage section resolve each
   *  consumer run's produced datasets (project_files) so "what came out" chains
   *  as openable dataset objects (spec 04 §4.5.3). */
  projectId?: string
  /** Ask in chat FROM this dataset — opens the composer with it attached. */
  onAnalyze?: () => void
  /** Run a full QC workflow ON this dataset through BioMate's engine. */
  onRunQC?: () => void
  /** A save or restore wrote a new version: the server's updated file row (new storage key, size,
   *  hash, version_no). The owner replaces its copy of the row and refreshes its file list, so
   *  what it passes back as `dataset` is the current version — never the archived key. */
  onFileChanged?: (file: Record<string, unknown>) => void
  className?: string
  preview?: ReactNode
}

// Header quality pill dot — the label is localized (dataset_obj.quality_*).
const HEADER_QUALITY: Record<PerceptionQuality, { dot: string }> = {
  good: { dot: "bg-emerald-500" },
  watch: { dot: "bg-amber-500" },
  blocked: { dot: "bg-red-500" },
  // Identified but not analysed: neutral, never a warning colour.
  unassessed: { dot: "bg-muted-foreground/50" },
}

export function DatasetObject({
  dataset: datasetProp,
  onBack,
  onDownload,
  onOpenRun,
  onAnalyze,
  onRunQC,
  className,
  preview,
  projectId,
  onFileChanged,
}: DatasetObjectProps) {
  // A save / restore moves the file to a NEW storage key (the old one becomes an archived version
  // the profile gate refuses). Until the owner passes the updated row back, the panel uses the key
  // the server returned — so the profile, rows and links never ask for the pre-edit key. Applies
  // only while the owner still passes the ref it replaced; the owner's newer row then wins.
  const [fileUpdate, setFileUpdate] = useState<{ id: string; fromRef: string | null; ref: string; size: number | null; contentHash: string | null } | null>(null)
  const dataset: DatasetRef = fileUpdate && fileUpdate.id === datasetProp.id && fileUpdate.fromRef === datasetProp.ref
    ? { ...datasetProp, ref: fileUpdate.ref, size: fileUpdate.size ?? datasetProp.size, contentHash: fileUpdate.contentHash ?? datasetProp.contentHash }
    : datasetProp
  // The file currently shown — async results (compare, version list) for another file are dropped.
  const fileIdRef = useRef(dataset.id)
  fileIdRef.current = dataset.id
  const { folders: folderParts, base: baseName } = splitPath(dataset.name)
  // "Where it came from" + Versions lazily fetch their backing data on first open.
  const [wherefromOpened, setWherefromOpened] = useState(false)
  const [versionsOpened, setVersionsOpened] = useState(false)
  // View + tab choices belong to the file they were made on: opening another file starts
  // from its own default view (an image never inherits "Columns" from the CSV before it).
  const [viewSel, setViewSel] = useState<{ id: string; view: PreviewView } | null>(null)
  const [tabSel, setTabSel] = useState<{ id: string; tab: "preview" | "versions" | "wherefrom" } | null>(null)
  const tab = tabSel?.id === dataset.id ? tabSel.tab : "preview"
  const setTab = (next: "preview" | "versions" | "wherefrom") => setTabSel({ id: dataset.id, tab: next })
  // Tab list overflow (narrow panels): which sides hold tabs scrolled out of view.
  const tablistRef = useRef<HTMLDivElement>(null)
  const [tabOverflow, setTabOverflow] = useState<{ left: boolean; right: boolean }>({ left: false, right: false })
  const measureTabOverflow = useCallback(() => {
    const el = tablistRef.current
    if (!el) return
    const left = el.scrollLeft > 1
    const right = el.scrollLeft + el.clientWidth < el.scrollWidth - 1
    setTabOverflow((prev) => (prev.left === left && prev.right === right ? prev : { left, right }))
  }, [])
  useLayoutEffect(() => {
    measureTabOverflow()
    const el = tablistRef.current
    if (!el || typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", measureTabOverflow)
      return () => window.removeEventListener("resize", measureTabOverflow)
    }
    const ro = new ResizeObserver(measureTabOverflow)
    ro.observe(el)
    return () => ro.disconnect()
  }, [measureTabOverflow])
  const setPreviewView = (view: PreviewView) => setViewSel({ id: dataset.id, view })

  // Preview is the default tab and needs the profile (columns + sample rows), so
  // profiling runs when the object opens.
  const { data: profile, isLoading, isError, refetch: refetchProfile } = usePerceptionProfile(
    dataset.ref,
    dataset.name,
  )
  // The file's data kind — content-first (the profiler read the bytes), else its extension — and
  // the view model that decides which views, stats and actions apply to it.
  const kind = datasetKind(dataset.name, profile)
  // The FULL rows of a project file (paged), parsed by the profiler's own readers — only for
  // kinds shown as rows. Falls back to the profile's sample when the file is not a project file
  // or not tabular (415).
  const rowsQ = useDatasetRows(projectId, dataset.id, dataset.name, datasetViewModel(kind, { name: dataset.name }).useRows)
  const lineageQ = useDatasetLineage(wherefromOpened ? dataset.ref : null)
  // Consumers power both the Where-it-came-from lineage AND the Versions tab's
  // "used by N runs" on the current version (spec §4.4), so fetch for either.
  const consumersQ = useDatasetConsumers((wherefromOpened || versionsOpened) ? dataset.ref : null)
  const versionsQ = useDatasetVersions(versionsOpened ? dataset.ref : null)

  const [exporting, setExporting] = useState(false)
  const [exportError, setExportError] = useState<string | null>(null)

  // Open-in an interactive tool (design §4.3.1). Galaxy's Jupyter/RStudio ITs
  // already launch; the backend stages this project file into the user's history
  // and launches the tool against it. Tool by file type: R → RStudio, else Jupyter.
  const [openingIn, setOpeningIn] = useState(false)
  const [openInError, setOpenInError] = useState<string | null>(null)
  useEffect(() => { setOpenInError(null) }, [dataset.id])
  const fileExt = (dataset.name.split(".").pop() || "").toLowerCase()
  const openTool = /^(r|rds|rdata|rda)$/.test(fileExt) ? "rstudio" : "jupyter"
  const handleOpenIn = async () => {
    if (!projectId) return
    setOpeningIn(true); setOpenInError(null)
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/open-in`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ tool: openTool }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || !j?.url) throw new Error(openInErrorMessage(j, openTool === "rstudio" ? "RStudio" : "Jupyter", r.status))
      window.open(j.url, "_blank", "noopener")
    } catch (e: any) {
      setOpenInError(e?.message ?? t('dataset_obj.open_in_failed'))
    } finally {
      setOpeningIn(false)
    }
  }

  // Lineage "what came out" (spec 04 §4.5.3): beneath each run that read this
  // file, the datasets that run produced — each openable as its own object. Run
  // outputs are registered into project_files (source='run_output'); resolve
  // them by run_id so a produced counts matrix / DE table chains as an object
  // rather than needing a separate lineage viewer. Lazy (Where-it-came-from only).
  const [producedByRun, setProducedByRun] = useState<Record<string, Array<{ id: string; name: string; ext: string }>>>({})
  useEffect(() => {
    if (!wherefromOpened || !projectId) return
    let cancelled = false
    ;(async () => {
      try {
        const res = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files`, { credentials: "include" })
        if (!res.ok || cancelled) return
        const data = await res.json()
        const files = (data?.files ?? []) as Array<{ id?: string; name?: string; source?: string; run_id?: string | null }>
        const byRun: Record<string, Array<{ id: string; name: string; ext: string }>> = {}
        for (const f of files) {
          if (!f?.id || !f?.name || f.source !== "run_output" || !f.run_id) continue
          const ext = (f.name.split(".").pop() || "").toLowerCase()
          ;(byRun[f.run_id] = byRun[f.run_id] || []).push({ id: f.id, name: f.name, ext })
        }
        if (!cancelled) setProducedByRun(byRun)
      } catch { /* best-effort — the produced list just won't show */ }
    })()
    return () => { cancelled = true }
  }, [wherefromOpened, projectId])

  const consumers = consumersQ.data?.consumers ?? []
  const propConsumers = dataset.consumers ?? []
  const versions = versionsQ.data?.versions ?? []
  const propVersions = dataset.versions ?? []
  const isRunOutput = dataset.source === "run_output"

  // App-level content versions for a PROJECT FILE (design §4.4) come from the Node
  // project_file_versions store (real byte-versions), not the Galaxy note-log — fetch
  // them and offer Restore. Only for user-ingested files in a project (not run outputs).
  const versionable = Boolean(projectId) && !isRunOutput
  const [projectVersions, setProjectVersions] = useState<typeof versions | null>(null)
  const [restoringVersion, setRestoringVersion] = useState<string | null>(null)
  const [versionError, setVersionError] = useState<string | null>(null)
  const loadProjectVersions = async () => {
    if (!projectId) return
    const forId = dataset.id
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(forId)}/versions`, { credentials: "include" })
      if (!r.ok) return
      const j = await r.json()
      if (fileIdRef.current !== forId) return
      setProjectVersions((j?.versions ?? []) as typeof versions)
    } catch { /* best-effort — falls back to the note-log list */ }
  }
  // Load the version list when the file opens, not only when the Versions tab is opened: the
  // header chip shows the CURRENT version and read "v1" for an edited/re-uploaded file until the
  // tab was visited. Cleared per file so one file's label never shows on another.
  useEffect(() => {
    setProjectVersions(null)
    if (!versionable) return
    let cancelled = false
    ;(async () => { if (!cancelled) await loadProjectVersions() })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projectId, dataset.id, versionable])
  // Compare a past version against current (design §4.4 — column + cell diff).
  const [diffFor, setDiffFor] = useState<string | null>(null)
  const [diffData, setDiffData] = useState<any | null>(null)
  const [diffLoading, setDiffLoading] = useState(false)
  // "Restored v1 as v3" after a restore (cleared by the next save / restore / file).
  const [restored, setRestored] = useState<{ from: string; to: number | null } | null>(null)
  // Versions state belongs to the file it was made on: opening another file never shows this
  // file's open diff, error, restore-in-progress or restore message.
  useEffect(() => {
    setDiffFor(null); setDiffData(null); setDiffLoading(false)
    setVersionError(null); setRestoringVersion(null); setRestored(null)
  }, [dataset.id])

  // A save / restore answered with the file's new row: use its storage key from now on (the
  // profile re-reads the NEW key — the old key is an archived version), and tell the owner.
  const applyFileRow = (file: any) => {
    const ref = file && typeof file === "object" && typeof file.s3_key === "string" && file.s3_key ? file.s3_key : null
    if (ref && ref !== dataset.ref) {
      setFileUpdate({
        id: datasetProp.id, fromRef: datasetProp.ref, ref,
        size: file.size == null ? null : Number(file.size),
        contentHash: typeof file.content_hash === "string" ? file.content_hash : null,
      })
    } else {
      // Same key (or an older server that sends no row): re-profile what is there.
      refetchProfile?.()
    }
    if (file && typeof file === "object") onFileChanged?.(file)
  }

  const handleRestore = async (versionNo: string) => {
    if (!projectId) return
    const forId = dataset.id
    setRestoringVersion(versionNo); setVersionError(null); setRestored(null)
    // The version the user is looking at: the server refuses (409) a restore made from a stale list.
    const seen = Number(projectVersions?.find((v) => v.current)?.version)
    const fromLabel = projectVersions?.find((v) => v.version === versionNo)?.label || `v${versionNo}`
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/versions/${encodeURIComponent(versionNo)}/restore`, {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(Number.isInteger(seen) && seen >= 1 ? { baseVersion: seen } : {}),
      })
      if (r.status === 409) {
        await loadProjectVersions()
        throw new EditError(t('dataset_obj.restore_conflict_version'))
      }
      if (!r.ok) throw new EditError(t('dataset_obj.with_status', { message: t('dataset_obj.restore_failed'), status: r.status }))
      const j = await r.json().catch(() => ({}))
      if (fileIdRef.current !== forId) return
      // The restored content is now current: a diff opened against the previous current version
      // and the previous "Saved as vN" no longer describe the file.
      setDiffFor(null); setDiffData(null); setEditSaved(null)
      const to = Number((j as any)?.file?.version_no)
      setRestored({ from: fromLabel, to: Number.isInteger(to) && to >= 1 ? to : null })
      await loadProjectVersions()
      // The file's content changed: re-profile it (at its new key) and re-read its rows, so what is
      // shown — and the `version` the next edit sends as baseVersion — is the restored version.
      setCellEdits({})
      applyFileRow((j as any)?.file)
      rowsQ.reload()
    } catch (e: any) {
      if (fileIdRef.current === forId) setVersionError(e instanceof EditError ? e.message : t('dataset_obj.restore_failed'))
    } finally {
      if (fileIdRef.current === forId) setRestoringVersion(null)
    }
  }
  const effectiveVersions = versionable ? (projectVersions ?? []) : versions

  const handleCompare = async (versionNo: string) => {
    if (!projectId) return
    if (diffFor === versionNo) { setDiffFor(null); setDiffData(null); return }  // toggle off
    const forId = dataset.id
    setDiffFor(versionNo); setDiffData(null); setDiffLoading(true); setVersionError(null); setRestored(null)
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/versions/${encodeURIComponent(versionNo)}/diff`, { credentials: "include" })
      if (!r.ok) throw new Error(t('dataset_obj.with_status', { message: t('dataset_obj.compare_failed'), status: r.status }))
      const body = await r.json()
      if (fileIdRef.current === forId) setDiffData(body)
    } catch (e: any) {
      if (fileIdRef.current !== forId) return
      setVersionError(e instanceof Error && e.message.startsWith(t('dataset_obj.compare_failed')) ? e.message : t('dataset_obj.compare_failed')); setDiffFor(null)
    } finally {
      if (fileIdRef.current === forId) setDiffLoading(false)
    }
  }

  // Edit-in-place → save as a new version (design §4.3/§4.4). Only tabular files in a project.
  // Editing happens on the full-rows table (untruncated values, any loaded row); the server
  // rewrites only the edited cells and refuses (409) if a cell no longer holds the value shown.
  // key `${row}:${col}`; `rowFrom` = the whole row as the user saw it when typing (the server
  // checks it, so an edit on a repeated value can never land on another row holding that value).
  const [cellEdits, setCellEdits] = useState<Record<string, { from: string; value: string; rowFrom: string[] }>>({})
  const onCellEdit = (row: number, col: number, from: string, value: string) =>
    setCellEdits((prev) => {
      const next = { ...prev }
      const key = `${row}:${col}`
      if (value === from) delete next[key]
      else next[key] = { from, value, rowFrom: prev[key]?.rowFrom ?? (rowsQ.rows[row] ?? []).map(String) }
      return next
    })
  const [savingEdit, setSavingEdit] = useState(false)
  const [editError, setEditError] = useState<string | null>(null)
  const [editSaved, setEditSaved] = useState<number | null>(null)
  // Unsaved edits belong to the file they were typed into — never carried to the next file.
  useEffect(() => { setCellEdits({}); setEditError(null); setEditSaved(null) }, [dataset.id])
  const handleSaveEdit = async () => {
    if (!projectId) return
    const edits = Object.entries(cellEdits).map(([k, e]) => {
      const i = k.indexOf(":")
      return { row: Number(k.slice(0, i)), col: Number(k.slice(i + 1)), from: e.from, value: e.value, rowFrom: e.rowFrom }
    })
    if (edits.length === 0) return
    setSavingEdit(true); setEditError(null); setEditSaved(null)
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/edit`, {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        // Row indices are data rows as the rows reader numbered them: after the header record when
        // the file has one, from line 1 when it does not (a header-less table).
        // `baseVersion`: the version the edited rows were read from — the server refuses the save
        // (409 version_conflict) if the file has moved on since, so an edit never lands on a
        // row that someone else's save renumbered. `skipLines`: the leading comment / blank lines
        // the rows reader skipped, so the server numbers data rows the same way. `delimiter`: the
        // separator the rows reader split on, so the server splits the file the same way.
        body: JSON.stringify({
          edits,
          ...(rowsQ.headerRow === null ? {} : { headerRows: rowsQ.headerRow ? 1 : 0 }),
          ...(rowsQ.version != null ? { baseVersion: rowsQ.version } : {}),
          ...(rowsQ.skipLines != null ? { skipLines: rowsQ.skipLines } : {}),
          ...(rowsQ.delimiter != null ? { delimiter: rowsQ.delimiter } : {}),
        }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new EditError(editErrorMessage(r.status, j))
      setCellEdits({}); setEditSaved((j as any)?.file?.version_no ?? null)
      // An open diff compared against the version this save replaced; a restore message is stale.
      setDiffFor(null); setDiffData(null); setRestored(null)
      await loadProjectVersions()
      // The saved version lives at a NEW storage key: profile it there (never the archived key).
      applyFileRow((j as any)?.file)
      // Re-read the rows from the first page: the next edit must be based on the saved version.
      rowsQ.reload()
    } catch (e: any) {
      setEditError(e instanceof EditError ? e.message : t('dataset_obj.edit_failed'))
    } finally {
      setSavingEdit(false)
    }
  }

  // Current version label for the header chip + stat grid. Falls back to the
  // caller's list, else v1 (every file has at least an implicit v1).
  const currentVersionLabel =
    effectiveVersions.find((v) => v.current)?.label ||
    effectiveVersions[0]?.label ||
    propVersions[0] ||
    "v1"

  async function handleExportRoCrate() {
    if (!dataset.ref) return
    setExportError(null)
    setExporting(true)
    try {
      await downloadDatasetRoCrate(dataset.ref, dataset.name)
    } catch (e: any) {
      setExportError(t("dataset_obj.rocrate_failed"))
    } finally {
      setExporting(false)
    }
  }

  const { rows: profileRows, cols: profileCols } = datasetShape(profile)
  // The rows endpoint reports the TRUE total and every column; prefer it.
  const hasFullRows = rowsQ.enabled && !rowsQ.unsupported && rowsQ.columns.length > 0
  const shapeRows = hasFullRows && rowsQ.total != null ? rowsQ.total : profileRows
  const shapeCols = hasFullRows ? rowsQ.columns.length : profileCols
  // Columns + Plot views compute over the loaded full rows when present, else the sample.
  const statCols = hasFullRows ? rowsQ.columns : profile?.columns
  const statRows = (hasFullRows ? rowsQ.rows : profile?.sampleRows) ?? []
  const hasColumns = Boolean(statCols?.length)
  const rowsInFlight = rowsQ.enabled && !rowsQ.unsupported && (rowsQ.error != null || (rowsQ.total == null && rowsQ.columns.length === 0))
  // No content (the rows reader's empty answer, or the profile's empty_file / blank_content).
  const emptyCode = rowsQ.empty ?? profileEmptyCode(profile)
  const vm = datasetViewModel(kind, {
    name: dataset.name,
    empty: Boolean(emptyCode) && !hasFullRows,
    hasColumns,
    columnsPending: rowsInFlight || (isLoading && !hasColumns),
    versionable,
    projectFile: Boolean(projectId),
    // A header-only table (the rows reader's true total is 0, or the profile read 0 rows under a
    // header) has no rows to edit or to QC.
    noDataRows: hasColumns && (hasFullRows ? rowsQ.total === 0 : !rowsInFlight && profileRows === 0),
  })
  const editable = vm.canEdit
  const canOpenIn = vm.canOpenIn
  // Plot only where something can be plotted: a column of numbers in the loaded rows (a header-only
  // table, a gene list, barcodes or an all-text sheet has none). A table whose decimal mark is a
  // comma ("1,5") counts once the reader reports `decimal: ","`.
  const decimal = rowsQ.decimal ?? (typeof profile?.decimal === "string" ? profile.decimal : null)
  const plotable = hasColumns && statRows.length > 0 && hasNumericColumns(statCols!, statRows, decimal)
  const views = vm.views.filter((v) => v !== "plot" || plotable)
  const previewView: PreviewView =
    viewSel?.id === dataset.id && views.includes(viewSel.view) ? viewSel.view : views[0]
  const quality = profile ? effectiveQuality(profile) : undefined
  // The file's own viewer, told the content kind (a FASTQ named .txt shows as reads) and asked
  // to report what it shows (loading / ready / error / none) for `data-preview-kind`.
  const [fileStatus, setFileStatus] = useState<{ id: string; status: FilePreviewStatus } | null>(null)
  const onFileStatus = useCallback((status: FilePreviewStatus) => setFileStatus({ id: dataset.id, status }), [dataset.id])
  const isFilePreview = isValidElement(preview) && preview.type === DatasetFilePreview
  const kindPreview = isFilePreview
    ? cloneElement(preview as React.ReactElement<{ kind?: string; format?: string; structure?: StructureEvidence | null; onStatus?: (s: FilePreviewStatus) => void; profilePending?: boolean }>,
        { kind, format: profile?.format?.ext, structure: profile?.structure ?? null, onStatus: onFileStatus, profilePending: isLoading })
    : preview
  // Another preview element reports nothing: it is taken as drawn.
  const filePreviewStatus: FilePreviewStatus = !isFilePreview ? "ready"
    : fileStatus?.id === dataset.id ? fileStatus.status : "loading"

  // The table-ish branch shown for the Table view / a rows kind's content view.
  const rowsBranch: "rows" | "error" | "loading" | "file" | "sample" | "none" =
    hasFullRows ? "rows"
    : rowsQ.enabled && !rowsQ.unsupported && rowsQ.error != null ? "error"
    : (rowsQ.enabled && !rowsQ.unsupported) || (!hasFullRows && isLoading) ? "loading"
    : !vm.tableShape && kindPreview ? "file"
    : profile?.columns?.length && profile.sampleRows?.length ? "sample"
    : kindPreview ? "file"
    : "none"
  // What the Preview actually shows (`data-preview-kind`: the kind whose renderer is drawn, or
  // none / error) and whether it is still loading (`aria-busy`) — e2e reads these, never text.
  const shownFile = (): { shown: string; busy: boolean } =>
    filePreviewStatus === "loading" ? { shown: kind, busy: true }
    : filePreviewStatus === "ready" ? { shown: kind, busy: false }
    : { shown: filePreviewStatus, busy: false }
  const previewShown: { shown: string; busy: boolean } =
    previewView === "table" || (previewView === "content" && vm.content === "rows")
      ? rowsBranch === "rows" || rowsBranch === "sample" ? { shown: kind, busy: false }
        : rowsBranch === "error" ? { shown: "error", busy: false }
        : rowsBranch === "loading" ? { shown: kind, busy: true }
        : rowsBranch === "file" ? shownFile()
        : { shown: "none", busy: false }
    : previewView === "content" && vm.content === "viewer" ? (kindPreview ? shownFile() : { shown: "none", busy: false })
    : previewView === "content" && vm.content === "empty" ? { shown: "none", busy: false }
    : previewView === "content" && (vm.content === "anndata" || vm.content === "summary") ? { shown: kind, busy: isLoading }
    : previewView === "content" ? { shown: kind, busy: false }  // download: the honest download state IS this kind's view
    : previewView === "columns" ? { shown: kind, busy: !hasColumns }
    : previewView === "edit" ? (hasFullRows ? { shown: kind, busy: false } : { shown: "none", busy: false })
    : { shown: kind, busy: false }  // plot
  // The profile decides the kind: until it arrives the preview is provisional.
  const previewBusy = previewShown.busy || isLoading

  // Stat grid: the kind's own measures (rows × columns only for tables, cells × genes, reads…),
  // then size and kind. Row / column counts come from the rows endpoint when it has them (the
  // TRUE totals of the loaded file).
  const ROW_COUNT_STATS = new Set(["rows", "records", "regions", "features"])
  let gridStats: StatItem[] = profile ? profileStats(profile, kind) : []
  if (vm.tableShape && hasColumns && !gridStats.some((s) => s.code === "rows" || s.code === "records")) {
    gridStats = [{ code: "rows", value: shapeRows ?? "—" }, { code: "columns", value: shapeCols ?? "—" }, ...gridStats.filter((s) => s.code !== "columns")]
  }
  if (hasFullRows) {
    gridStats = gridStats.map((s) =>
      ROW_COUNT_STATS.has(s.code) && rowsQ.total != null ? { code: s.code, value: rowsQ.total }
      : s.code === "columns" ? { code: s.code, value: rowsQ.columns.length }
      : s)
  }
  // A JSON / YAML document's "entries" are its top-level keys (object) or items (array) — said so,
  // since the QC card also counts keys and values at every level.
  const structuredRoot = profile?.structured?.root
  const statLabel = (code: string) =>
    code === "rows" ? t('dataset_obj.stat_rows') : code === "columns" ? t('dataset_obj.stat_columns')
    : code === "entries" && structuredRoot === "object" ? t('dataset_obj.stat_top_keys')
    : code === "entries" && structuredRoot === "array" ? t('dataset_obj.stat_top_items')
    : tOr(`perception.stat.${code}`, code)
  const statHint = (code: string) =>
    code === "entries" && (structuredRoot === "object" || structuredRoot === "array") ? t(`dataset_obj.stat_top_${structuredRoot === "object" ? "keys" : "items"}_tip`) : undefined
  const viewToggles: Array<[PreviewView, typeof TableIcon, string]> = [
    ["table", TableIcon, t('dataset_obj.view_table')],
    ["columns", Columns3, t('dataset_obj.view_columns')],
    ["plot", BarChart3, t('dataset_obj.view_plot')],
    ["edit", Pencil, t('dataset_obj.view_edit')],
  ]

  return (
    <Card className={`min-w-0 max-w-full ${className ?? ""}`} data-testid="dataset-object" data-view-kind={kind}>
      <CardHeader className="pb-2 space-y-2">
        {/* Breadcrumb — project crumb is shown by the page; here: Files / kind / name */}
        <div className="flex min-w-0 items-center gap-2 text-xs text-muted-foreground" data-testid="dataset-object-crumb">
          {onBack && (
            <button
              type="button"
              className="inline-flex shrink-0 items-center gap-1 hover:text-foreground"
              onClick={onBack}
              data-testid="dataset-object-back"
            >
              <ChevronLeft className="h-3 w-3" />
              {t('nav.data')}
            </button>
          )}
          <span className="shrink-0">/</span>
          <span className="shrink-0">{isRunOutput ? t('dataset_obj.outputs') : t('dataset_obj.inputs')}</span>
          {/* Each folder of the file's path is its own crumb ("pairs / S1_R1.fastq.gz"), so the
              title can be the bare file name. */}
          {folderParts.map((part, i) => (
            <span key={i} className="contents">
              <span className="shrink-0">/</span>
              <span className="min-w-0 max-w-[10rem] truncate" data-testid="dataset-object-crumb-folder" title={folderParts.slice(0, i + 1).join("/")}>{part}</span>
            </span>
          ))}
          <span className="shrink-0">/</span>
          <span className="min-w-0 flex-1 truncate" data-testid="dataset-object-id" title={dataset.name}>
            {baseName}
          </span>
        </div>

        {/* Identity row: name · v{N} · quality pill · actions */}
        <div className="flex items-center gap-2 flex-wrap">
          {/* The bare file name (its folders are in the breadcrumb, the full path on hover). Breaks
              only at name separators (_ . -), never inside a word. */}
          <CardTitle className="text-lg font-mono font-semibold min-w-0 max-w-full break-normal" title={dataset.name} data-testid="dataset-object-name">
            {breakAtSeparators(baseName)}
          </CardTitle>
          {/* Type + size badges removed from the header (item 6 H6): they
              duplicated the stat grid below. The header keeps only identity —
              the v{N} version chip + quality pill — per the design spec. */}
          <Badge variant="secondary" className="text-xs" data-testid="dataset-header-version">
            {currentVersionLabel}
          </Badge>
          {/* Format chip — the profiler's detected format (Galaxy datatype or BioMate
              sniffing). Absent on profiles from older backends → no chip. */}
          {profile?.format?.label && (
            <Badge
              variant="outline"
              className="text-xs font-mono"
              data-testid="dataset-header-format"
              data-format-source={profile.format.source}
              data-format-layout={profile.format.layout || undefined}
              title={t('dataset_obj.format_chip_title', {
                label: localizedFormatLabel(profile.format),
                source: t(profile.format.source === "galaxy" ? 'dataset_obj.format_source_galaxy' : 'dataset_obj.format_source_biomate'),
              })}
            >
              {localizedFormatLabel(profile.format)}
            </Badge>
          )}
          {quality && HEADER_QUALITY[quality] && (
            <span
              className={`inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-xs${quality === "unassessed" ? " text-muted-foreground" : ""}`}
              data-testid="dataset-header-quality"
              data-quality={quality}
              title={t('file_tree.quality', { quality: t('dataset_obj.quality_' + quality) })}
            >
              <span className={`h-2 w-2 rounded-full ${HEADER_QUALITY[quality].dot}`} />
              {t('dataset_obj.quality_' + quality)}
            </span>
          )}

          <div className="ml-auto flex flex-wrap items-center gap-2">
            {/* Open in — Jupyter / RStudio by file type (design §4.3.1). Stages the
                project file into the user's Galaxy history and launches the IT. Offered only
                when OPEN_IN_AVAILABLE (dataset-view-model.ts; off since 2026-11-11 until the
                interactive-tool launch path works) — the notes that mention it follow the same switch. */}
            {canOpenIn && (
              <Button
                variant="outline"
                size="sm"
                className="h-8 text-sm px-3 gap-1.5"
                onClick={handleOpenIn}
                disabled={openingIn}
                data-testid="dataset-object-open-in"
                title={t('dataset_obj.open_in_title', { tool: openTool === "rstudio" ? "RStudio" : "Jupyter" })}
              >
                <SquareTerminal className="h-3.5 w-3.5" />
                {openingIn
                  ? t('dataset_obj.open_in_launching')
                  : t('dataset_obj.open_in', { tool: openTool === "rstudio" ? "RStudio" : "Jupyter" })}
              </Button>
            )}
            {onAnalyze && (
              <Button
                size="sm"
                className="h-8 text-sm px-3 gap-1.5"
                onClick={onAnalyze}
                data-testid="dataset-object-analyze"
                title={t('file_tree.attach_to_chat')}
              >
                <Play className="h-3.5 w-3.5" />
                {t('dataset_obj.ask_in_chat')}
              </Button>
            )}
            {onDownload && (
              <Button
                variant="outline"
                size="sm"
                className="h-8 text-sm px-3 gap-1.5"
                onClick={onDownload}
                data-testid="dataset-object-download"
              >
                <Download className="h-3.5 w-3.5" />
                {t('actions.download')}
              </Button>
            )}
          </div>
        </div>
        {openInError && (
          <p role="alert" className="text-xs text-destructive mt-1 break-words" data-testid="dataset-open-in-error">{openInError}</p>
        )}
      </CardHeader>

      <CardContent>
        {/* Segmented pill tabs (design i05-2 / t10-1): a gray track with the
            selected tab as a raised white box, not an underline. */}
        {/* One line at every width: a narrow panel scrolls the tab list sideways rather than
            wrapping a tab onto a second row. */}
        {/* When the tabs do not fit (a 390 px phone: "Provenance" cut mid-word), the hidden side
            fades out and a chevron scrolls to it — a cut tab never reads as the whole label. */}
        <div className="relative mb-3" data-testid="dataset-tablist-wrap" data-overflow-right={tabOverflow.right ? "true" : undefined} data-overflow-left={tabOverflow.left ? "true" : undefined}>
        <div ref={tablistRef} onScroll={measureTabOverflow} className="flex w-full min-w-0 flex-nowrap items-center gap-0.5 overflow-x-auto rounded-lg bg-muted p-0.5 [scrollbar-width:none]" role="tablist" data-testid="dataset-tablist">
          {([
            ["preview", Eye, t('file_tree.preview')],
            ["versions", History, t('dataset_obj.versions')],
            ["wherefrom", GitBranch, t('dataset_obj.where_from')],
          ] as const).map(([key, Icon, label]) => (
            <HintTip key={key} hint={t(`hint.dataset.${key}`)} side="bottom">
            <button
              type="button"
              role="tab"
              aria-selected={tab === key}
              data-testid={`dataset-tab-${key}`}
              onClick={(e) => {
                setTab(key)
                // A tab chosen while partly scrolled out of a narrow list comes fully into view.
                e.currentTarget.scrollIntoView?.({ block: "nearest", inline: "nearest" })
                if (key === "wherefrom") setWherefromOpened(true)
                else if (key === "versions") setVersionsOpened(true)
              }}
              className={
                "inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-md px-3 py-1.5 text-sm transition-colors " +
                (tab === key
                  ? "bg-background border border-border shadow-sm text-foreground font-medium"
                  : "border border-transparent text-muted-foreground hover:text-foreground")
              }
            >
              <Icon className="h-3.5 w-3.5" />{label}
            </button>
            </HintTip>
          ))}
        </div>
        {tabOverflow.left && (
          <div aria-hidden className="pointer-events-none absolute inset-y-0 left-0 w-8 rounded-l-lg bg-gradient-to-r from-muted to-transparent" data-testid="dataset-tablist-fade-left" />
        )}
        {tabOverflow.right && (
          <>
            <div aria-hidden className="pointer-events-none absolute inset-y-0 right-0 w-12 rounded-r-lg bg-gradient-to-l from-muted via-muted/80 to-transparent" data-testid="dataset-tablist-fade" />
            <button
              type="button"
              className="absolute inset-y-0 right-0 flex w-7 items-center justify-center rounded-r-lg text-muted-foreground hover:text-foreground"
              onClick={() => tablistRef.current?.scrollBy?.({ left: tablistRef.current.clientWidth * 0.6, behavior: "smooth" })}
              aria-label={t('dataset_obj.tabs_more')}
              title={t('dataset_obj.tabs_more')}
              data-testid="dataset-tablist-more"
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          </>
        )}
        </div>

          {/* ── Preview: Table / Columns / Plot + stat grid ── */}
          {tab === "preview" && (<div className="space-y-3 text-sm" data-testid="dataset-preview" data-kind={kind}
            data-preview-kind={previewShown.shown} aria-busy={previewBusy ? true : undefined}>
            {/* View toggles only where a file has more than one meaningful view (tables and
                records: Table / Columns / Plot / Edit). Every other kind has one view — its own. */}
            {views.length > 1 && (
              <div className="flex flex-wrap items-center gap-1.5" data-testid="dataset-preview-toggles">
                {viewToggles.filter(([key]) => views.includes(key)).map(([key, Icon, label]) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setPreviewView(key)}
                    data-testid={`dataset-preview-toggle-${key}`}
                    aria-pressed={previewView === key}
                    className={
                      "inline-flex items-center gap-1 rounded-md border px-2 py-1 text-sm " +
                      (previewView === key
                        ? "border-primary bg-primary text-primary-foreground"
                        : "hover:bg-muted/50")
                    }
                  >
                    <Icon className="h-3 w-3" />{label}
                  </button>
                ))}
              </div>
            )}

            {(previewView === "table" || (previewView === "content" && vm.content === "rows")) && (
              rowsBranch === "rows" ? (
                <DatasetRowsTable
                  columns={rowsQ.columns}
                  rows={rowsQ.rows}
                  total={rowsQ.total}
                  loading={rowsQ.loading}
                  error={rowsQ.error}
                  onNeedMore={rowsQ.loadMore}
                  onLoadAll={rowsQ.loadAll}
                  onRetry={rowsQ.retry}
                  loadAllCap={LOAD_ALL_CAP}
                />
              ) : rowsBranch === "error" ? (
                <p role="alert" className="text-sm text-destructive" data-testid="dataset-rows-error">
                  {t('dataset_obj.rows_error', { status: rowsQ.error || "—" })}{" "}
                  <button type="button" className="underline" onClick={rowsQ.retry}>{t('dataset_obj.rows_retry')}</button>
                </p>
              ) : rowsBranch === "loading" ? (
                <div className="space-y-2" data-testid="dataset-preview-loading">
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : rowsBranch === "file" && !vm.tableShape ? (
                // Intervals / annotation the rows reader declined: the file's own viewer.
                kindPreview
              ) : rowsBranch === "sample" ? (
                // Not a project file (no rows endpoint) — the profiler's sample, labelled as such.
                <DatasetRowsTable
                  columns={profile!.columns!}
                  rows={profile!.sampleRows!}
                  total={shapeRows ?? null}
                  loading={false}
                  error={null}
                  onNeedMore={() => {}}
                />
              ) : (
                kindPreview ?? (
                  <p className="text-sm text-muted-foreground" data-testid="dataset-preview-none">
                    {t('dataset_obj.no_preview')}
                  </p>
                )
              )
            )}

            {previewView === "content" && vm.content === "viewer" && (
              kindPreview ?? <DownloadState kind={kind} onDownload={onDownload} />
            )}
            {previewView === "content" && vm.content === "anndata" && (
              isLoading ? <Skeleton className="h-16 w-full" /> : <AnnDataSummary profile={profile} kind={kind} canOpenIn={canOpenIn} />
            )}
            {previewView === "content" && vm.content === "summary" && (
              isLoading ? <Skeleton className="h-16 w-full" /> : <KindSummary profile={profile} kind={kind} />
            )}
            {previewView === "content" && vm.content === "empty" && emptyCode && (
              // The file has no content: say so (0 bytes / only blank lines) — not an error, not a
              // table still loading, not "cannot be shown here".
              <p className="text-sm text-muted-foreground" data-testid="dataset-preview-empty" data-empty-code={emptyCode}>
                {t(`perception.msg.${emptyCode}`)}
              </p>
            )}
            {previewView === "content" && vm.content === "download" && (
              <DownloadState kind={kind} onDownload={onDownload} />
            )}

            {previewView === "columns" && (
              // Per-column type / % missing / distinct / watch chip (design §4.3) over the loaded
              // rows; a header-only table still lists its columns ("no data rows yet").
              hasColumns ? (
                <div className="space-y-1">
                  <DatasetColumnsView
                    columns={statCols!}
                    sampleRows={statRows}
                    findings={profile?.findings ?? []}
                    totalRows={shapeRows ?? undefined}
                    profileStats={profile?.columnStats ?? null}
                    profiledRows={profile?.profiledRows ?? null}
                    decimal={decimal}
                    t={t}
                  />
                  {/* Whole-file statistics need every row loaded — unless the profiler's columnStats
                      already describe every column. */}
                  {hasFullRows && rowsQ.total != null && rowsQ.rows.length < rowsQ.total && rowsQ.total <= LOAD_ALL_CAP
                    && !statCols!.every((c) => profile?.columnStats?.some((cs) => cs.name === c)) && (
                    <Button size="sm" variant="outline" className="h-6 px-2 text-xs" disabled={rowsQ.loading}
                      onClick={rowsQ.loadAll} data-testid="dataset-columns-load-all">
                      {t('dataset_obj.load_all')}
                    </Button>
                  )}
                </div>
              ) : (
                <div className="space-y-2" data-testid="dataset-preview-columns-loading">
                  <Skeleton className="h-16 w-full" />
                </div>
              )
            )}

            {previewView === "plot" && (
              // Histogram of a numeric column over the loaded rows. Nothing numeric (or no data
              // rows) → say so and offer chat, rather than an empty axis (spec §4.3).
              plotable ? (
                <DatasetSamplePlot columns={statCols!} sampleRows={statRows} decimal={decimal} t={t}
                  columnStats={profile?.columnStats ?? null}
                  // A partially loaded table says the plot uses the loaded rows, and offers them all.
                  total={hasFullRows ? rowsQ.total : null}
                  onLoadAll={hasFullRows && rowsQ.total != null && rowsQ.total <= LOAD_ALL_CAP ? rowsQ.loadAll : undefined}
                  loading={rowsQ.loading} />
              ) : (
                <div className="rounded border bg-muted/20 p-3 text-sm text-muted-foreground space-y-2" data-testid="dataset-preview-plot-future">
                  <p>{t(hasColumns && !statRows.length ? 'dataset_obj.plot_no_rows' : canOpenIn ? 'dataset_obj.plot_future' : 'dataset_obj.plot_future_chat')}</p>
                  {onAnalyze && (
                    <Button size="sm" variant="outline" className="h-7 text-xs gap-1" onClick={onAnalyze}>
                      <Play className="h-3 w-3" />{t('dataset_obj.ask_in_chat')}
                    </Button>
                  )}
                </div>
              )
            )}

            {previewView === "edit" && (
              hasFullRows ? (
                <div className="space-y-2" data-testid="dataset-preview-edit">
                  <p className="text-xs text-muted-foreground">{t('dataset_obj.edit_hint_full')}</p>
                  <DatasetRowsTable
                    columns={rowsQ.columns}
                    rows={rowsQ.rows}
                    total={rowsQ.total}
                    loading={rowsQ.loading}
                    error={rowsQ.error}
                    onNeedMore={rowsQ.loadMore}
                    onLoadAll={rowsQ.loadAll}
                    onRetry={rowsQ.retry}
                    loadAllCap={LOAD_ALL_CAP}
                    editable
                    edits={cellEdits}
                    onEdit={onCellEdit}
                  />
                  {editError && <p role="alert" className="text-xs text-destructive" data-testid="dataset-edit-error">{editError}</p>}
                  {editSaved != null && <p className="text-xs text-emerald-600 dark:text-emerald-400" data-testid="dataset-edit-saved">{t('dataset_obj.edit_saved', { v: editSaved })}</p>}
                  <div className="flex items-center gap-2">
                    <Button
                      size="sm"
                      className="h-7 text-xs"
                      onClick={handleSaveEdit}
                      disabled={savingEdit || Object.keys(cellEdits).length === 0}
                      data-testid="dataset-edit-save"
                    >{savingEdit ? t('dataset_obj.edit_saving') : t('dataset_obj.edit_save', { n: Object.keys(cellEdits).length })}</Button>
                    <span className="text-xs text-muted-foreground">{t('dataset_obj.edit_appendonly')}</span>
                  </div>
                </div>
              ) : (
                <p className="text-sm text-muted-foreground" data-testid="dataset-preview-edit-none">{t('dataset_obj.no_preview')}</p>
              )
            )}

            {/* Data QC (design §4.5.2) — directly under the table (moved from Provenance: QC
                describes the rows shown above, so it belongs beside them). */}
            <div className="rounded border p-2.5 space-y-2" data-testid="dataset-quality">
              <div className="flex items-center gap-2">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground flex-1">
                  {t('dataset_obj.quality_heading')}
                </p>
                {/* Run full QC only for data a QC workflow exists for (reads, alignments, tables…),
                    never for an image, document or archive. */}
                {onRunQC && vm.canRunQC && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-6 text-sm gap-1"
                    onClick={onRunQC}
                    data-testid="dataset-object-run-qc"
                    title={t('dataset_obj.run_qc_tip')}
                  >
                    <ShieldCheck className="h-3 w-3" />{t('dataset_obj.run_qc')}
                  </Button>
                )}
              </div>
              {!dataset.ref ? (
                <p className="text-sm text-muted-foreground" data-testid="dataset-quality-noref">
                  {t('dataset_obj.quality_noref')}
                </p>
              ) : isLoading ? (
                <div className="space-y-2" data-testid="dataset-quality-loading">
                  <Skeleton className="h-4 w-40" />
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : isError || !profile ? (
                <p className="text-sm text-muted-foreground" data-testid="dataset-quality-error">
                  {t('dataset_obj.quality_error')}
                </p>
              ) : (
                <DataPerception
                  profile={profile}
                  planImpact={profile.planImpact}
                  datasetName={dataset.name}
                  kind={kind}
                  // The kind's measures (rows × columns, reads, cells…) are in the stat grid below:
                  // shown once, not in both places.
                  hideStats
                  // …and what the Preview shows as content (AnnData parts, a sheet's values) is not
                  // listed again among the notes.
                  hideFindings={previewView === "content" ? findingsShownAsContent(vm.content, profile) : undefined}
                  // …nor a finding that only restates the stat grid's numbers (variants · samples,
                  // cells × genes, rows · columns), matched by code + params.
                  shownStats={gridStats}
                />
              )}
            </div>

            {/* Stat grid (design §4.3): rows · columns (tables only) · size · kind. */}
            <div className="grid gap-2" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 12rem), 1fr))" }} data-testid="dataset-stat-grid">
              {/* Rows / columns only for tables: for reads, sequences, alignments or matrices the
                  shape is not rows × columns; the QC card above shows those kinds' own measures. */}
              {gridStats.map((s) => <StatCard key={s.code} stat={s.code} k={statLabel(s.code)} hint={statHint(s.code)} v={formatStatValue(s)} />)}
              <StatCard stat="size" k={t('dataset_obj.stat_size')} v={formatBytes(dataset.size)} />
              <StatCard stat="type" k={t('dataset_obj.stat_type')} v={kindLabel(kind)} />
            </div>
            {/* FUTURE: "Ask BioMate to edit this" — a conversational edit that writes
                a new version. Needs an edit-save / content-versioning endpoint
                (POST versions appends a NOTE only). Tracked in the audit doc. */}
          </div>)}

          {/* ── Versions ── */}
          {tab === "versions" && (<div className="space-y-2" data-testid="dataset-versions">
            {restored && (
              <p role="status" className="text-xs text-emerald-600 dark:text-emerald-400" data-testid="dataset-version-restored">
                {restored.to != null
                  ? t('dataset_obj.restored_as', { from: restored.from, to: `v${restored.to}` })
                  : t('dataset_obj.restored', { from: restored.from })}
              </p>
            )}
            {versionsQ.isLoading ? (
              <div className="space-y-2" data-testid="dataset-versions-loading">
                <Skeleton className="h-8 w-full" />
              </div>
            ) : effectiveVersions.length ? (
              <DatasetVersionsList
                key={dataset.id}
                versions={effectiveVersions}
                usedByCount={consumers.length}
                versionable={versionable}
                error={versionError}
                diffFor={diffFor}
                diffData={diffData}
                diffLoading={diffLoading}
                restoringVersion={restoringVersion}
                onCompare={handleCompare}
                onRestore={handleRestore}
              />
            ) : propVersions.length ? (
              propVersions.map((v) => (
                <div key={v} className="rounded border px-2 py-1 text-xs" data-testid={`dataset-version-${v}`}>
                  <span className="font-mono font-semibold">{v}</span>
                </div>
              ))
            ) : (
              <p className="text-sm text-muted-foreground" data-testid="dataset-no-versions">
                {t('dataset_obj.one_version_only')}
              </p>
            )}

            {/* Why versions matter (design §4.4) — static, always-true copy. */}
            <div className="rounded border bg-muted/20 p-2.5 space-y-1" data-testid="dataset-why-versions">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {t('dataset_obj.why_versions_title')}
              </p>
              <p className="text-sm text-muted-foreground">{t('dataset_obj.why_versions_body')}</p>
            </div>

            {/* FUTURE: a manual add-note box created versions by hand; the design
                has versions come from edits / runs, which need the edit-save
                endpoint. Removed until that exists. */}
          </div>)}

          {/* ── Where it came from ── */}
          {tab === "wherefrom" && (<div className="space-y-3 text-sm" data-testid="dataset-wherefrom">
            {/* Origin */}
            <div className="rounded border p-2.5 space-y-1" data-testid="dataset-origin">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {t('dataset_obj.origin')}
              </p>
              {/* For a public pull, the accession the user supplied IS the
                  origin — show the id plainly. Otherwise the source type. */}
              <Row
                k={dataset.accession ? t('dataset_obj.accession') : t('dataset_obj.source')}
                v={dataset.accession ? dataset.accession : sourceLabel(dataset.source)}
                mono={Boolean(dataset.accession)}
              />
              {isRunOutput ? (
                lineageQ.isLoading ? (
                  <Skeleton className="h-4 w-40" />
                ) : (() => {
                  // Show the human workflow NAME, never a raw run id. When only
                  // the opaque id is known, show the action ("Open the run that
                  // produced it →") — the id is the link target, not the label.
                  const wf = lineageQ.data?.producedBy?.workflow ?? dataset.workflowName
                  const rid = lineageQ.data?.producedBy?.runId || dataset.runId
                  const step = dataset.stepName?.trim()
                  const canOpen = Boolean(onOpenRun && rid)
                  if (!wf && !rid) return null
                  // Pin provenance to the exact step when known: "<workflow> · <step>".
                  const wfLabel = wf ? (step ? `${fmt(wf)} · ${step}` : fmt(wf)) : t('dataset_obj.open_run')
                  return (
                    <>
                      <Row
                        k={t('dataset_obj.produced_by')}
                        v={wfLabel}
                        onClick={canOpen ? () => onOpenRun!(rid!) : undefined}
                        testid="lineage-open-run"
                      />
                      {lineageQ.data?.producedBy?.status && (
                        <Row k={t('dataset_obj.status')} v={fmt(lineageQ.data.producedBy.status)} />
                      )}
                    </>
                  )
                })()
              ) : null}
              <Row
                k={t('dataset_obj.added')}
                v={dataset.createdAt ? new Date(dataset.createdAt).toLocaleString(INTL_LOCALE) : "—"}
              />
              {/* The file's fingerprint (sha256 of its bytes, design §4.5.1) — the dedup identity:
                  the same bytes added twice link to one entry. Called a fingerprint, explained on
                  hover; abbreviated, with Copy for the full value. */}
              {dataset.contentHash && (
                <Row
                  k={t('dataset_obj.content_hash')}
                  v={<Fingerprint hash={dataset.contentHash} />}
                  last
                />
              )}
              {/* The internal storage ref (S3 key) is plumbing, not provenance —
                  intentionally not surfaced. The project/account visibility control
                  needs a backend `scope` column (documented follow-up). */}
            </div>

            {/* What used it, and what came out (design §4.5.3) */}
            <div className="rounded border p-2.5 space-y-1" data-testid="dataset-consumers">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {t('dataset_obj.what_used_it')}
              </p>
              {consumersQ.isLoading ? (
                <div className="space-y-2" data-testid="dataset-consumers-loading">
                  <Skeleton className="h-8 w-full" />
                </div>
              ) : consumers.length ? (
                consumers.map((c) => {
                  const produced = producedByRun[c.runId] ?? []
                  return (
                  <div key={c.runId} className="space-y-1">
                    <div
                      role={onOpenRun ? "button" : undefined}
                      onClick={onOpenRun ? () => onOpenRun(c.runId) : undefined}
                      className={`flex items-center gap-2 rounded border px-2 py-1 text-xs${onOpenRun ? " cursor-pointer hover:bg-muted/50" : ""}`}
                      data-testid={`dataset-consumer-${c.runId}`}
                    >
                      <Badge variant="outline" className="text-xs">{t('dataset_obj.reads')}</Badge>
                      <span className="truncate">{c.workflow ?? t('dataset_obj.open_run')}</span>
                      {c.status && <Badge variant="outline" className="text-xs ml-auto">{c.status}</Badge>}
                    </div>
                    {/* What came out — datasets this run produced, each openable as
                        its own object (spec §4.5.3). Typed by evidence class. */}
                    {produced.length > 0 && (
                      <div className="ml-4 space-y-1 border-l pl-2" data-testid={`dataset-produced-${c.runId}`}>
                        <p className="text-fs-xs uppercase tracking-wide text-muted-foreground">{t('dataset_obj.produced')}</p>
                        {produced.map((p) => (
                          <a
                            key={p.id}
                            href={`/files?file=${encodeURIComponent(p.id)}`}
                            className="flex items-center gap-2 rounded border px-2 py-1 text-xs hover:bg-muted/50 no-underline text-inherit"
                            data-testid="dataset-produced-output"
                            title={t('dataset_obj.open_as_dataset_title')}
                          >
                            <Badge variant="outline" className="text-xs">{resolveViewer(p.ext)}</Badge>
                            <span className="font-mono truncate">{p.name}</span>
                            <span className="ml-auto text-muted-foreground" aria-hidden>↗</span>
                          </a>
                        ))}
                      </div>
                    )}
                  </div>
                  )
                })
              ) : propConsumers.length ? (
                propConsumers.map((c) => (
                  <div key={c} className="flex items-center gap-2 rounded border px-2 py-1 text-xs" data-testid={`dataset-consumer-${c}`}>
                    <Badge variant="outline" className="text-xs">{t('dataset_obj.reads')}</Badge>
                    <span className="font-mono truncate">{c}</span>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted-foreground" data-testid="dataset-no-consumers">
                  {t('dataset_obj.no_consumers')}
                </p>
              )}
            </div>

            {/* Export — packaging the file with its provenance is its own action, not part of
                "Input to workflow". */}
            {dataset.ref && (
              <div className="rounded border p-2.5 space-y-1.5" data-testid="dataset-export">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  {t('dataset_obj.export_heading')}
                </p>
                <p className="text-sm text-muted-foreground">{t('dataset_obj.export_body')}</p>
                <Button
                  variant="outline"
                  size="sm"
                  className="h-7 text-sm gap-1"
                  onClick={handleExportRoCrate}
                  disabled={exporting}
                  title={t('file_tree.export_crate')}
                  data-testid="dataset-object-rocrate"
                >
                  <FileArchive className="h-3 w-3" />
                  {exporting ? t('dataset_obj.exporting') : t('dataset_obj.export_for_deposit')}
                </Button>
                {exportError && (
                  <p className="text-xs text-destructive" data-testid="dataset-rocrate-error">{exportError}</p>
                )}
              </div>
            )}
          </div>)}
      </CardContent>
    </Card>
  )
}

/** The file's sha256 fingerprint: short form, explained on hover, full value copied on click. */
function Fingerprint({ hash }: { hash: string }) {
  const [copied, setCopied] = useState(false)
  const copy = async () => {
    try { await navigator.clipboard?.writeText(`sha256:${hash}`); setCopied(true); setTimeout(() => setCopied(false), 1500) }
    catch { /* clipboard refused: the full value is still in the tooltip */ }
  }
  return (
    <span className="inline-flex min-w-0 flex-wrap items-center gap-x-1.5" data-testid="dataset-content-hash">
      <span className="font-mono cursor-help underline decoration-dotted underline-offset-2"
        title={t('dataset_obj.fingerprint_tip', { hash: `sha256:${hash}` })} data-testid="dataset-fingerprint">{hash.slice(0, 12)}…</span>
      <button type="button" className="inline-flex items-center gap-0.5 rounded border px-1 text-xs text-muted-foreground hover:text-foreground"
        onClick={copy} data-testid="dataset-fingerprint-copy" aria-label={t('dataset_obj.fingerprint_copy')}>
        {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}{copied ? t('dataset_obj.fingerprint_copied') : t('dataset_obj.fingerprint_copy')}
      </button>
      <span className="text-muted-foreground">{t('dataset_obj.dedup_note')}</span>
    </span>
  )
}

/** One stat card: `data-testid="dataset-stat"` + `data-stat=<code>` (rows, columns, reads,
 *  cells, …, size, type) — what e2e reads, never the label text. */
function StatCard({ k, v, stat, hint }: { k: string; v: string; stat: string; hint?: string }) {
  return (
    <div className="min-w-0 rounded border px-2.5 py-2" data-testid="dataset-stat" data-stat={stat}>
      <div className={`text-fs-xs uppercase tracking-wide text-muted-foreground${hint ? " cursor-help underline decoration-dotted underline-offset-2" : ""}`} title={hint}>{k}</div>
      <div className="text-sm font-mono font-semibold text-foreground [overflow-wrap:anywhere]" title={v}>{v}</div>
    </div>
  )
}

function Row({
  k,
  v,
  mono,
  last,
  onClick,
  testid,
}: {
  k: string
  v: ReactNode
  mono?: boolean
  last?: boolean
  onClick?: () => void
  testid?: string
}) {
  return (
    <div className={`grid grid-cols-[9rem_1fr] gap-1 py-1${last ? "" : " border-b"}`}>
      <span className="text-muted-foreground">{k}</span>
      {onClick ? (
        <button
          type="button"
          data-testid={testid}
          onClick={onClick}
          className={`text-left underline underline-offset-2 hover:text-foreground cursor-pointer truncate${mono ? " font-mono" : ""}`}
        >
          {v}
        </button>
      ) : (
        // Plain text truncates; a composed value (the fingerprint + Copy) lays itself out.
        <span className={typeof v === "string" ? (mono ? "font-mono truncate" : "truncate") : "min-w-0"}>{v}</span>
      )}
    </div>
  )
}
