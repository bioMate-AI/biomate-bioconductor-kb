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

import { useState, useEffect, cloneElement, isValidElement, type ReactNode } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import {
  ChevronLeft,
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
} from "lucide-react"
import { DataPerception, type PerceptionQuality } from "@/components/data-perception"
import { datasetKind, datasetViewModel, effectiveQuality, type PreviewView } from "./dataset-view-model"
import { AnnDataSummary, KindSummary, DownloadState } from "./dataset-kind-views"
import { DatasetFilePreview } from "./dataset-file-preview"
import { t, locale } from "@/lib/i18n"

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
import { DatasetSamplePlot, hasNumericColumns } from "./dataset-sample-plot"
import { DatasetColumnsView } from "./dataset-columns-view"
import { resolveViewer } from "../viewers/inline-content-viewers"
import { datasetShape, kindLabel, localizedFormatLabel, openInErrorMessage } from "./dataset-presentation"

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
  dataset,
  onBack,
  onDownload,
  onOpenRun,
  onAnalyze,
  onRunQC,
  className,
  preview,
  projectId,
}: DatasetObjectProps) {
  // "Where it came from" + Versions lazily fetch their backing data on first open.
  const [wherefromOpened, setWherefromOpened] = useState(false)
  const [versionsOpened, setVersionsOpened] = useState(false)
  // View + tab choices belong to the file they were made on: opening another file starts
  // from its own default view (an image never inherits "Columns" from the CSV before it).
  const [viewSel, setViewSel] = useState<{ id: string; view: PreviewView } | null>(null)
  const [tabSel, setTabSel] = useState<{ id: string; tab: "preview" | "versions" | "wherefrom" } | null>(null)
  const tab = tabSel?.id === dataset.id ? tabSel.tab : "preview"
  const setTab = (next: "preview" | "versions" | "wherefrom") => setTabSel({ id: dataset.id, tab: next })
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
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/versions`, { credentials: "include" })
      if (!r.ok) return
      const j = await r.json()
      setProjectVersions((j?.versions ?? []) as typeof versions)
    } catch { /* best-effort — falls back to the note-log list */ }
  }
  useEffect(() => {
    if (!versionsOpened || !versionable) return
    let cancelled = false
    ;(async () => { if (!cancelled) await loadProjectVersions() })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [versionsOpened, projectId, dataset.id, versionable])
  const handleRestore = async (versionNo: string) => {
    if (!projectId) return
    setRestoringVersion(versionNo); setVersionError(null)
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/versions/${encodeURIComponent(versionNo)}/restore`, {
        method: "POST", credentials: "include",
      })
      if (!r.ok) throw new Error(t('dataset_obj.with_status', { message: t('dataset_obj.restore_failed'), status: r.status }))
      await loadProjectVersions()
    } catch (e: any) {
      setVersionError(e instanceof Error && e.message.startsWith(t('dataset_obj.restore_failed')) ? e.message : t('dataset_obj.restore_failed'))
    } finally {
      setRestoringVersion(null)
    }
  }
  const effectiveVersions = versionable ? (projectVersions ?? []) : versions

  // Compare a past version against current (design §4.4 — column + cell diff).
  const [diffFor, setDiffFor] = useState<string | null>(null)
  const [diffData, setDiffData] = useState<any | null>(null)
  const [diffLoading, setDiffLoading] = useState(false)
  const handleCompare = async (versionNo: string) => {
    if (!projectId) return
    if (diffFor === versionNo) { setDiffFor(null); setDiffData(null); return }  // toggle off
    setDiffFor(versionNo); setDiffData(null); setDiffLoading(true); setVersionError(null)
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/versions/${encodeURIComponent(versionNo)}/diff`, { credentials: "include" })
      if (!r.ok) throw new Error(t('dataset_obj.with_status', { message: t('dataset_obj.compare_failed'), status: r.status }))
      setDiffData(await r.json())
    } catch (e: any) {
      setVersionError(e instanceof Error && e.message.startsWith(t('dataset_obj.compare_failed')) ? e.message : t('dataset_obj.compare_failed')); setDiffFor(null)
    } finally {
      setDiffLoading(false)
    }
  }

  // Edit-in-place → save as a new version (design §4.3/§4.4). Only tabular files in a project.
  // Editing happens on the full-rows table (untruncated values, any loaded row); the server
  // rewrites only the edited cells and refuses (409) if a cell no longer holds the value shown.
  const [cellEdits, setCellEdits] = useState<Record<string, { from: string; value: string }>>({})  // key `${row}:${col}`
  const onCellEdit = (row: number, col: number, from: string, value: string) =>
    setCellEdits((prev) => {
      const next = { ...prev }
      const key = `${row}:${col}`
      if (value === from) delete next[key]
      else next[key] = { from, value }
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
      return { row: Number(k.slice(0, i)), col: Number(k.slice(i + 1)), from: e.from, value: e.value }
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
        // row that someone else's save renumbered.
        body: JSON.stringify({
          edits,
          ...(rowsQ.headerRow === null ? {} : { headerRows: rowsQ.headerRow ? 1 : 0 }),
          ...(rowsQ.version != null ? { baseVersion: rowsQ.version } : {}),
        }),
      })
      const j = await r.json().catch(() => ({}))
      if (r.status === 409) {
        const code = (j as any)?.error
        throw new EditError(t(code === "version_conflict" ? 'dataset_obj.edit_conflict_version'
          : code === "cell_conflict" ? 'dataset_obj.edit_conflict_cell' : 'dataset_obj.edit_conflict'))
      }
      if (!r.ok) throw new EditError(t('dataset_obj.with_status', { message: t('dataset_obj.edit_failed'), status: r.status }))
      setCellEdits({}); setEditSaved((j as any)?.file?.version_no ?? null)
      await loadProjectVersions()
      refetchProfile?.()
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
  const vm = datasetViewModel(kind, {
    name: dataset.name,
    hasColumns,
    columnsPending: rowsInFlight || (isLoading && !hasColumns),
    versionable,
    projectFile: Boolean(projectId),
  })
  const editable = vm.canEdit
  const canOpenIn = vm.canOpenIn
  const previewView: PreviewView =
    viewSel?.id === dataset.id && vm.views.includes(viewSel.view) ? viewSel.view : vm.views[0]
  const quality = profile ? effectiveQuality(profile) : undefined
  // The file's own viewer, told the content kind (a FASTQ named .txt shows as reads).
  const kindPreview = isValidElement(preview) && preview.type === DatasetFilePreview
    ? cloneElement(preview as React.ReactElement<{ kind?: string }>, { kind })
    : preview
  const viewToggles: Array<[PreviewView, typeof TableIcon, string]> = [
    ["table", TableIcon, t('dataset_obj.view_table')],
    ["columns", Columns3, t('dataset_obj.view_columns')],
    ["plot", BarChart3, t('dataset_obj.view_plot')],
    ["edit", Pencil, t('dataset_obj.view_edit')],
  ]

  return (
    <Card className={`min-w-0 max-w-full ${className ?? ""}`} data-testid="dataset-object">
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
          <span className="shrink-0">/</span>
          <span className="min-w-0 flex-1 truncate" data-testid="dataset-object-id" title={dataset.name}>
            {dataset.name}
          </span>
        </div>

        {/* Identity row: name · v{N} · quality pill · actions */}
        <div className="flex items-center gap-2 flex-wrap">
          <CardTitle className="text-lg font-mono font-semibold min-w-0 max-w-full [overflow-wrap:anywhere]" title={dataset.name} data-testid="dataset-object-name">
            {dataset.name}
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
                project file into the user's Galaxy history and launches the IT. */}
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
        <div className="flex w-full min-w-0 flex-wrap items-center gap-0.5 rounded-lg bg-muted p-0.5 mb-3" role="tablist">
          {([
            ["preview", Eye, t('file_tree.preview')],
            ["versions", History, t('dataset_obj.versions')],
            ["wherefrom", GitBranch, t('dataset_obj.where_from')],
          ] as const).map(([key, Icon, label]) => (
            <button
              key={key}
              type="button"
              role="tab"
              aria-selected={tab === key}
              data-testid={`dataset-tab-${key}`}
              onClick={() => {
                setTab(key)
                if (key === "wherefrom") setWherefromOpened(true)
                else if (key === "versions") setVersionsOpened(true)
              }}
              className={
                "inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm transition-colors " +
                (tab === key
                  ? "bg-background border border-border shadow-sm text-foreground font-medium"
                  : "border border-transparent text-muted-foreground hover:text-foreground")
              }
            >
              <Icon className="h-3.5 w-3.5" />{label}
            </button>
          ))}
        </div>

          {/* ── Preview: Table / Columns / Plot + stat grid ── */}
          {tab === "preview" && (<div className="space-y-3 text-sm" data-testid="dataset-preview" data-kind={kind}>
            {/* View toggles only where a file has more than one meaningful view (tables and
                records: Table / Columns / Plot / Edit). Every other kind has one view — its own. */}
            {vm.views.length > 1 && (
              <div className="flex flex-wrap items-center gap-1.5" data-testid="dataset-preview-toggles">
                {viewToggles.filter(([key]) => vm.views.includes(key)).map(([key, Icon, label]) => (
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
              hasFullRows ? (
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
              ) : rowsQ.enabled && !rowsQ.unsupported && rowsQ.error != null ? (
                <p role="alert" className="text-sm text-destructive" data-testid="dataset-rows-error">
                  {t('dataset_obj.rows_error', { status: rowsQ.error || "—" })}{" "}
                  <button type="button" className="underline" onClick={rowsQ.retry}>{t('dataset_obj.rows_retry')}</button>
                </p>
              ) : (rowsQ.enabled && !rowsQ.unsupported) || (!hasFullRows && isLoading) ? (
                <div className="space-y-2" data-testid="dataset-preview-loading">
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : !vm.tableShape && kindPreview ? (
                // Intervals / annotation / molecules the rows reader declined: the file's own viewer.
                kindPreview
              ) : profile?.columns?.length && profile.sampleRows?.length ? (
                // Not a project file (no rows endpoint) — the profiler's sample, labelled as such.
                <DatasetRowsTable
                  columns={profile.columns}
                  rows={profile.sampleRows}
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
              isLoading ? <Skeleton className="h-16 w-full" /> : <AnnDataSummary profile={profile} kind={kind} onAnalyze={onAnalyze} />
            )}
            {previewView === "content" && vm.content === "summary" && (
              isLoading ? <Skeleton className="h-16 w-full" /> : <KindSummary profile={profile} kind={kind} onDownload={onDownload} />
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
                    t={t}
                  />
                  {hasFullRows && rowsQ.total != null && rowsQ.rows.length < rowsQ.total && rowsQ.total <= LOAD_ALL_CAP && (
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
              hasColumns && statRows.length && hasNumericColumns(statCols!, statRows) ? (
                <DatasetSamplePlot columns={statCols!} sampleRows={statRows} t={t} />
              ) : (
                <div className="rounded border bg-muted/20 p-3 text-sm text-muted-foreground space-y-2" data-testid="dataset-preview-plot-future">
                  <p>{t(hasColumns && !statRows.length ? 'dataset_obj.plot_no_rows' : 'dataset_obj.plot_future')}</p>
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
                />
              )}
            </div>

            {/* Stat grid (design §4.3): rows · columns (tables only) · size · kind. */}
            <div className="grid gap-2" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 12rem), 1fr))" }} data-testid="dataset-stat-grid">
              {/* Rows / columns only for tables: for reads, sequences, alignments or matrices the
                  shape is not rows × columns; the QC card above shows those kinds' own measures. */}
              {vm.tableShape && hasColumns && <StatCard k={t('dataset_obj.stat_rows')} v={shapeRows != null ? shapeRows.toLocaleString(INTL_LOCALE) : "—"} />}
              {vm.tableShape && hasColumns && <StatCard k={t('dataset_obj.stat_columns')} v={shapeCols != null ? String(shapeCols) : "—"} />}
              <StatCard k={t('dataset_obj.stat_size')} v={formatBytes(dataset.size)} />
              <StatCard k={t('dataset_obj.stat_type')} v={kindLabel(kind)} testId="dataset-stat-type" />
            </div>
            {/* FUTURE: "Ask BioMate to edit this" — a conversational edit that writes
                a new version. Needs an edit-save / content-versioning endpoint
                (POST versions appends a NOTE only). Tracked in the audit doc. */}
          </div>)}

          {/* ── Versions ── */}
          {tab === "versions" && (<div className="space-y-2" data-testid="dataset-versions">
            {versionsQ.isLoading ? (
              <div className="space-y-2" data-testid="dataset-versions-loading">
                <Skeleton className="h-8 w-full" />
              </div>
            ) : effectiveVersions.length ? (
              <>
              {versionError && <p className="text-xs text-destructive" data-testid="dataset-version-error">{versionError}</p>}
              {effectiveVersions.map((v) => (
                <div
                  key={v.version}
                  className={`rounded border px-2 py-1.5 text-xs ${v.current ? "bg-primary/5 border-primary/40" : ""}`}
                  data-testid={`dataset-version-${v.version}`}
                >
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-semibold">{v.label}</span>
                    {v.current && (
                      <Badge variant="outline" className="text-xs">{t('dataset_obj.current')}</Badge>
                    )}
                    {v.current && consumers.length > 0 && (
                      <span className="text-xs text-muted-foreground" data-testid="dataset-version-usedby">
                        {t('dataset_obj.used_by_runs', { n: consumers.length })}
                      </span>
                    )}
                    {/* Compare this version against current (column + cell diff). */}
                    {versionable && !v.current && (
                      <button
                        className="text-xs text-primary hover:underline disabled:opacity-50"
                        data-testid={`dataset-version-compare-${v.version}`}
                        disabled={diffLoading && diffFor === v.version}
                        onClick={() => handleCompare(v.version)}
                      >{diffFor === v.version ? t('dataset_obj.compare_hide') : t('dataset_obj.compare')}</button>
                    )}
                    {/* Restore a past version (append-only — writes a new version). */}
                    {versionable && !v.current && (
                      <button
                        className="text-xs text-primary hover:underline disabled:opacity-50"
                        data-testid={`dataset-version-restore-${v.version}`}
                        disabled={restoringVersion === v.version}
                        onClick={() => handleRestore(v.version)}
                      >{restoringVersion === v.version ? t('dataset_obj.restoring') : t('dataset_obj.restore')}</button>
                    )}
                    {v.createdAt && (
                      <span className="ml-auto text-xs text-muted-foreground">
                        {new Date(
                          typeof v.createdAt === "number" ? v.createdAt * 1000 : v.createdAt,
                        ).toLocaleString(INTL_LOCALE)}
                      </span>
                    )}
                  </div>
                  {v.note && (
                    <p className="text-sm text-foreground pt-0.5">
                      {v.note}
                      {v.author && <span className="text-muted-foreground"> — {v.author}</span>}
                    </p>
                  )}
                  {diffFor === v.version && (
                    <div className="mt-1.5 rounded border bg-muted/20 p-2 text-xs space-y-1" data-testid={`dataset-version-diff-${v.version}`}>
                      {diffLoading ? (
                        <p className="text-muted-foreground">{t('dataset_obj.comparing')}</p>
                      ) : diffData?.identical ? (
                        <p className="text-muted-foreground">{t('dataset_obj.diff_identical')}</p>
                      ) : diffData?.tabular === false ? (
                        <p className="text-muted-foreground">{t('dataset_obj.diff_nontabular', { a: diffData?.target?.size ?? "?", b: diffData?.current?.size ?? "?" })}</p>
                      ) : diffData ? (
                        <>
                          {(diffData.columns?.added?.length || diffData.columns?.removed?.length) ? (
                            <p>
                              {diffData.columns.added?.length ? <span className="text-emerald-600 dark:text-emerald-400">+{diffData.columns.added.join(", ")} </span> : null}
                              {diffData.columns.removed?.length ? <span className="text-red-600 dark:text-red-400 line-through">−{diffData.columns.removed.join(", ")}</span> : null}
                            </p>
                          ) : null}
                          <p className="text-muted-foreground" data-testid="dataset-diff-cellcount">
                            {t('dataset_obj.diff_changed_cells', { n: diffData.changedCells?.length ?? 0 })}
                            {diffData.truncated ? ` ${t('dataset_obj.diff_sampled')}` : ""}
                          </p>
                          {(diffData.changedCells ?? []).slice(0, 5).map((c: any, ci: number) => (
                            <p key={ci} className="font-mono text-fs-xs">
                              <span className="text-muted-foreground">r{c.row} · {c.col}: </span>
                              <span className="text-red-600 dark:text-red-400 line-through">{String(c.from) || "∅"}</span>
                              {" → "}
                              <span className="text-emerald-600 dark:text-emerald-400">{String(c.to) || "∅"}</span>
                            </p>
                          ))}
                        </>
                      ) : null}
                    </div>
                  )}
                </div>
              ))}
              </>
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
                v={dataset.accession ? dataset.accession : fmt(dataset.source)}
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
              {/* Content hash (design §4.5.1) — the dedup identity. Same bytes added
                  twice link to one entry. Shown abbreviated; full value on hover. */}
              {dataset.contentHash && (
                <Row
                  k={t('dataset_obj.content_hash')}
                  v={
                    <span title={`sha256:${dataset.contentHash}`} data-testid="dataset-content-hash">
                      <span className="font-mono">{dataset.contentHash.slice(0, 12)}…</span>
                      <span className="text-muted-foreground"> · {t('dataset_obj.dedup_note')}</span>
                    </span>
                  }
                  last
                />
              )}
              {/* The internal storage ref (S3 key) is plumbing, not provenance —
                  intentionally not surfaced. The project/account visibility control
                  needs a backend `scope` column (documented follow-up). */}
            </div>

            {/* What used it, and what came out (design §4.5.3) */}
            <div className="rounded border p-2.5 space-y-1" data-testid="dataset-consumers">
              <div className="flex items-center gap-2">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground flex-1">
                  {t('dataset_obj.what_used_it')}
                </p>
                {dataset.ref && (
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-6 text-sm gap-1"
                    onClick={handleExportRoCrate}
                    disabled={exporting}
                    title={t('file_tree.export_crate')}
                    data-testid="dataset-object-rocrate"
                  >
                    <FileArchive className="h-3 w-3" />
                    {exporting ? t('dataset_obj.exporting') : t('dataset_obj.export_for_deposit')}
                  </Button>
                )}
              </div>
              {exportError && (
                <p className="text-xs text-destructive" data-testid="dataset-rocrate-error">{exportError}</p>
              )}
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
          </div>)}
      </CardContent>
    </Card>
  )
}

function StatCard({ k, v, testId }: { k: string; v: string; testId?: string }) {
  return (
    <div className="min-w-0 rounded border px-2.5 py-2" data-testid={testId}>
      <div className="text-fs-xs uppercase tracking-wide text-muted-foreground">{k}</div>
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
        <span className={mono ? "font-mono truncate" : "truncate"}>{v}</span>
      )}
    </div>
  )
}
