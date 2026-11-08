/**
 * DatasetObject — a file presented as a first-class object, conformed to design
 * spec 04 ("Files & the dataset object") + the rendered prototype
 * (data_centroid_design_v2). See docs/20261020_DATASET_PANEL_DESIGN_AUDIT.md.
 *
 * Header:  name · v{N} chip · quality pill · [Ask in chat] [Download]
 * Tabs:    Preview · Versions · Where it came from
 *   Preview       — Table / Columns / Plot toggle + a 4-card stat grid.
 *   Versions      — the append-only version log + "why versions matter".
 *   Where it came — Origin + Quality-at-ingest (the perception profile) +
 *                   what used it, with Export for deposit (RO-Crate).
 *
 * Project files use permission-checked content previews and append-only byte
 * versions. Column summaries and plots are explicitly sample-derived. Interactive
 * opening stages a file into the user's Galaxy history; launch failures remain
 * scoped to that action and never replace the preview/provenance content.
 */

import { useState, useEffect, type ReactNode } from "react"
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
import { t } from "@/lib/i18n"
import {
  usePerceptionProfile,
  useDatasetLineage,
  useDatasetConsumers,
  useDatasetVersions,
  downloadDatasetRoCrate,
} from "./datasets-api"
import { DatasetSamplePlot, hasNumericColumns } from "./dataset-sample-plot"
import { DatasetColumnsView } from "./dataset-columns-view"
import { resolveViewer } from "../viewers/inline-content-viewers"
import { datasetContentType, datasetShape, openInErrorMessage } from "./dataset-presentation"

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

// Header quality pill — Good / Watch / Blocked, so identity (quality + version)
// reads at a glance.
const HEADER_QUALITY: Record<PerceptionQuality, { dot: string; label: string }> = {
  good: { dot: "bg-emerald-500", label: "Good" },
  watch: { dot: "bg-amber-500", label: "Watch" },
  blocked: { dot: "bg-red-500", label: "Blocked" },
}

type PreviewView = "table" | "columns" | "plot" | "edit"

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
  const [previewView, setPreviewView] = useState<PreviewView>("table")
  const [tab, setTab] = useState<"preview" | "versions" | "wherefrom">("preview")
  // Make the preview table manipulable (sort + filter) on the fetched sample — the
  // feasible client-side slice of "data manipulable wherever feasible". Full-dataset
  // sort/paging stays the table-viewer path.
  const [sortCol, setSortCol] = useState<number | null>(null)
  const [sortAsc, setSortAsc] = useState(true)
  const [filterText, setFilterText] = useState("")

  // Preview is the default tab and needs the profile (columns + sample rows), so
  // profiling runs when the object opens.
  const { data: profile, isLoading, isError, refetch: refetchProfile } = usePerceptionProfile(
    dataset.ref,
    dataset.name,
  )
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
  // Offer it for data files (a figure/pdf/html doesn't open in a kernel).
  const canOpenIn = Boolean(projectId) &&
    ["table", "sequence", "vcf", "annotation", "structure", "r-object", "singlecell", "text"].includes(resolveViewer(fileExt))
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
      if (!r.ok) throw new Error((await r.json().catch(() => ({})))?.error || `Restore failed (${r.status})`)
      await loadProjectVersions()
    } catch (e: any) {
      setVersionError(e?.message ?? t('dataset_obj.restore_failed'))
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
      if (!r.ok) throw new Error((await r.json().catch(() => ({})))?.error || `Compare failed (${r.status})`)
      setDiffData(await r.json())
    } catch (e: any) {
      setVersionError(e?.message ?? t('dataset_obj.compare_failed')); setDiffFor(null)
    } finally {
      setDiffLoading(false)
    }
  }

  // Edit-in-place → save as a new version (design §4.3/§4.4). Only tabular files in
  // a project. The sample table is editable; edits are applied to the FULL file
  // server-side (no truncation) and written as a new version.
  const editable = versionable && ["csv", "tsv", "tab", "txt"].includes(fileExt)
  const [cellEdits, setCellEdits] = useState<Record<string, string>>({})  // key `${row}:${colName}`
  const [savingEdit, setSavingEdit] = useState(false)
  const [editError, setEditError] = useState<string | null>(null)
  const [editSaved, setEditSaved] = useState<number | null>(null)
  const handleSaveEdit = async () => {
    if (!projectId) return
    const edits = Object.entries(cellEdits).map(([k, value]) => {
      const i = k.indexOf(":")
      return { row: Number(k.slice(0, i)), col: k.slice(i + 1), value }
    })
    if (edits.length === 0) return
    setSavingEdit(true); setEditError(null); setEditSaved(null)
    try {
      const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(dataset.id)}/edit`, {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ edits }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error((j as any)?.error || `Save failed (${r.status})`)
      setCellEdits({}); setEditSaved((j as any)?.file?.version_no ?? null)
      await loadProjectVersions()
      refetchProfile?.()
    } catch (e: any) {
      setEditError(e?.message ?? t('dataset_obj.edit_failed'))
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
      setExportError(e?.message || "RO-Crate export failed")
    } finally {
      setExporting(false)
    }
  }

  const { rows: shapeRows, cols: shapeCols } = datasetShape(profile)

  return (
    <Card className={`min-w-0 max-w-full ${className ?? ""}`} data-testid="dataset-object">
      <CardHeader className="pb-2 space-y-2">
        {/* Breadcrumb — project crumb is shown by the page; here: Files / kind / name */}
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          {onBack && (
            <button
              type="button"
              className="inline-flex items-center gap-1 hover:text-foreground"
              onClick={onBack}
              data-testid="dataset-object-back"
            >
              <ChevronLeft className="h-3 w-3" />
              {t('nav.data')}
            </button>
          )}
          <span>/</span>
          <span>{isRunOutput ? t('dataset_obj.outputs') : t('dataset_obj.inputs')}</span>
          <span>/</span>
          <span className="truncate" data-testid="dataset-object-id" title={dataset.id}>
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
          {profile?.quality && HEADER_QUALITY[profile.quality] && (
            <span
              className="inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-xs"
              data-testid="dataset-header-quality"
              data-quality={profile.quality}
              title={t('file_tree.quality', { quality: profile.quality })}
            >
              <span className={`h-2 w-2 rounded-full ${HEADER_QUALITY[profile.quality].dot}`} />
              {t('dataset_obj.quality_' + profile.quality)}
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
          {tab === "preview" && (<div className="space-y-3 text-sm" data-testid="dataset-preview">
            {/* Columns and plots use the fetched sample, with a clear fallback
                for non-tabular content that has no numeric columns. */}
            <div className="flex flex-wrap items-center gap-1.5">
              {([
                ["table", TableIcon, t('dataset_obj.view_table')],
                ["columns", Columns3, t('dataset_obj.view_columns')],
                ["plot", BarChart3, t('dataset_obj.view_plot')],
              ] as const).map(([key, Icon, label]) => (
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
              {editable && (
                <button
                  type="button"
                  onClick={() => setPreviewView("edit")}
                  data-testid="dataset-preview-toggle-edit"
                  aria-pressed={previewView === "edit"}
                  className={
                    "inline-flex items-center gap-1 rounded-md border px-2 py-1 text-sm " +
                    (previewView === "edit" ? "border-primary bg-primary text-primary-foreground" : "hover:bg-muted/50")
                  }
                >
                  <Pencil className="h-3 w-3" />{t('dataset_obj.view_edit')}
                </button>
              )}
            </div>

            {previewView === "table" && (
              profile?.columns?.length && profile.sampleRows?.length ? (
                (() => {
                  const cols = profile.columns!
                  const q = filterText.trim().toLowerCase()
                  let rows = profile.sampleRows!.filter(
                    (r) => !q || r.some((c) => String(c ?? "").toLowerCase().includes(q)),
                  )
                  if (sortCol !== null) {
                    rows = rows.slice().sort((a, b) => {
                      const av = a[sortCol] ?? "", bv = b[sortCol] ?? ""
                      const an = Number(av), bn = Number(bv)
                      const cmp =
                        av !== "" && bv !== "" && Number.isFinite(an) && Number.isFinite(bn)
                          ? an - bn
                          : String(av).localeCompare(String(bv))
                      return sortAsc ? cmp : -cmp
                    })
                  }
                  return (
                <div className="space-y-1" data-testid="dataset-preview-table">
                  <input
                    value={filterText}
                    onChange={(e) => setFilterText(e.target.value)}
                    placeholder="Filter rows…"
                    data-testid="dataset-preview-filter"
                    className="w-full rounded border bg-background px-2 py-1 text-xs mb-1"
                  />
                  <div className="overflow-x-auto rounded border">
                    <table className="w-full border-collapse text-sm">
                      <thead>
                        <tr style={{ background: 'var(--bm-accent-soft)' }}>
                          {cols.map((c, i) => (
                            <th
                              key={i}
                              onClick={() => { if (sortCol === i) { setSortAsc((a) => !a) } else { setSortCol(i); setSortAsc(true) } }}
                              data-testid={`dataset-col-sort-${i}`}
                              title="Sort by this column"
                              className="whitespace-nowrap px-2 py-1 text-left font-semibold border-b cursor-pointer select-none"
                              style={{ color: 'var(--bm-accent-ink)' }}
                            >
                              {c}{sortCol === i ? (sortAsc ? ' ▲' : ' ▼') : ''}
                            </th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((r, ri) => (
                          <tr key={ri} className="odd:bg-muted/20">
                            {cols.map((_, ci) => (
                              <td key={ci} className="whitespace-nowrap px-2 py-0.5 font-mono border-b">
                                {r[ci] ?? ""}
                              </td>
                            ))}
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {t('dataset_obj.preview_rows', {
                      shown: rows.length,
                      of: shapeRows ? t('dataset_obj.rows_of', { total: shapeRows.toLocaleString() }) : "",
                    })}
                  </p>
                </div>
                  )
                })()
              ) : isLoading ? (
                <div className="space-y-2" data-testid="dataset-preview-loading">
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : (
                preview ?? (
                  <p className="text-sm text-muted-foreground" data-testid="dataset-preview-none">
                    {t('dataset_obj.no_preview')}
                  </p>
                )
              )
            )}

            {previewView === "columns" && (
              // Per-column type / % missing / distinct / watch chip (design §4.3) —
              // derived client-side from the profiler's column headers + sampled rows
              // + quality notes, labelled as sample-derived (we never present a sample
              // stat as whole-file truth). Needs a table-like sample to profile.
              profile?.columns?.length && profile.sampleRows?.length ? (
                <DatasetColumnsView
                  columns={profile.columns}
                  sampleRows={profile.sampleRows}
                  notes={profile.notes}
                  totalRows={shapeRows ?? undefined}
                  t={t}
                />
              ) : isLoading ? (
                <div className="space-y-2" data-testid="dataset-preview-columns-loading">
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : (
                <div className="rounded border bg-muted/20 p-3 text-sm text-muted-foreground space-y-2" data-testid="dataset-preview-columns-none">
                  <p>{t('dataset_obj.columns_not_tabular')}</p>
                  {onAnalyze && (
                    <Button size="sm" variant="outline" className="h-7 text-xs gap-1" onClick={onAnalyze}>
                      <Play className="h-3 w-3" />{t('dataset_obj.ask_in_chat')}
                    </Button>
                  )}
                </div>
              )
            )}

            {previewView === "plot" && (
              // Leverage the SAMPLE rows already fetched for the Table view: chart
              // numeric columns client-side (histogram) instead of the old "no plot
              // data" stub. Non-numeric / too-small samples fall through to the
              // spec-sanctioned fallback (§4.3): "if nothing numeric is present the
              // view says so and offers Jupyter or chat, rather than an empty axis."
              // Full-dataset distributions/PCA remain a Jupyter/chat path.
              profile?.columns?.length && profile.sampleRows?.length &&
              hasNumericColumns(profile.columns, profile.sampleRows) ? (
                <DatasetSamplePlot columns={profile.columns} sampleRows={profile.sampleRows} t={t} />
              ) : (
                <div className="rounded border bg-muted/20 p-3 text-sm text-muted-foreground space-y-2" data-testid="dataset-preview-plot-future">
                  <p>{t('dataset_obj.plot_future')}</p>
                  {onAnalyze && (
                    <Button size="sm" variant="outline" className="h-7 text-xs gap-1" onClick={onAnalyze}>
                      <Play className="h-3 w-3" />{t('dataset_obj.ask_in_chat')}
                    </Button>
                  )}
                </div>
              )
            )}

            {previewView === "edit" && (
              profile?.columns?.length && profile.sampleRows?.length ? (
                <div className="space-y-2" data-testid="dataset-preview-edit">
                  <p className="text-xs text-muted-foreground">
                    {t('dataset_obj.edit_hint', { n: profile.sampleRows.length })}
                  </p>
                  <div className="overflow-x-auto rounded border">
                    <table className="w-full border-collapse text-sm">
                      <thead>
                        <tr style={{ background: 'var(--bm-accent-soft)' }}>
                          {profile.columns.map((c, i) => (
                            <th key={i} className="whitespace-nowrap px-2 py-1 text-left font-semibold border-b" style={{ color: 'var(--bm-accent-ink)' }}>{c}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {profile.sampleRows.map((r, ri) => (
                          <tr key={ri} className="odd:bg-muted/20">
                            {profile.columns!.map((c, ci) => {
                              const key = `${ri}:${c}`
                              const edited = key in cellEdits
                              return (
                                <td key={ci} className="px-1 py-0.5 border-b">
                                  <input
                                    className={`w-full min-w-[6rem] rounded px-1 py-0.5 font-mono text-xs bg-transparent border ${edited ? "border-amber-500/60 bg-amber-500/5" : "border-transparent hover:border-border"}`}
                                    value={edited ? cellEdits[key] : (r[ci] ?? "")}
                                    data-testid={`dataset-edit-cell-${ri}-${ci}`}
                                    onChange={(e) => {
                                      const val = e.target.value
                                      setCellEdits((prev) => {
                                        const next = { ...prev }
                                        if (val === (r[ci] ?? "")) delete next[key]
                                        else next[key] = val
                                        return next
                                      })
                                    }}
                                  />
                                </td>
                              )
                            })}
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  {editError && <p className="text-xs text-destructive" data-testid="dataset-edit-error">{editError}</p>}
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

            {/* Stat grid (design §4.3): rows · columns · size · current version. */}
            <div className="grid gap-2" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 12rem), 1fr))" }} data-testid="dataset-stat-grid">
              <StatCard k={t('dataset_obj.stat_rows')} v={shapeRows != null ? shapeRows.toLocaleString() : "—"} />
              <StatCard k={t('dataset_obj.stat_columns')} v={shapeCols != null ? String(shapeCols) : "—"} />
              <StatCard k={t('dataset_obj.stat_size')} v={formatBytes(dataset.size)} />
              <StatCard k={t('dataset_obj.stat_type')} v={datasetContentType(dataset.name, dataset.contentType)} />
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
                        ).toLocaleString()}
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
                            <p key={ci} className="font-mono text-[11px]">
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
                v={dataset.createdAt ? new Date(dataset.createdAt).toLocaleString() : "—"}
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

            {/* Quality, at ingest (design §4.5.2) — the perception profile lives here. */}
            <div className="rounded border p-2.5 space-y-2" data-testid="dataset-quality">
              <div className="flex items-center gap-2">
                <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground flex-1">
                  {t('dataset_obj.quality_heading')}
                </p>
                {onRunQC && (
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
                />
              )}
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
                        <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{t('dataset_obj.produced')}</p>
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

function StatCard({ k, v }: { k: string; v: string }) {
  return (
    <div className="min-w-0 rounded border px-2.5 py-2">
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{k}</div>
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
