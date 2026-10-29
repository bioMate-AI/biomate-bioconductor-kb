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
 * Everything rendered is backed by a real endpoint. Parts of the design that
 * have NO backend yet are commented out with a FUTURE marker rather than faked:
 *   - Open in Jupyter / RStudio / Plot viewer  (needs a dataset→history staging
 *     endpoint; interactive tools can't bind an arbitrary project file today)
 *   - Preview → Columns per-column stats, Preview → Plot distributions
 *     (the perception profiler returns column names + a sample only)
 *   - Edit → new version + "Ask BioMate to edit this" (no content-versioning /
 *     edit-save endpoint — POST versions appends a NOTE only)
 *   - Versions → Compare / Restore (no diff/restore endpoint)
 *   - Origin → content hash + dedup, visibility control; Produced outputs list
 * These are tracked as backend work in the audit doc.
 */

import { useState, type ReactNode } from "react"
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

type PreviewView = "table" | "columns" | "plot"

export function DatasetObject({
  dataset,
  onBack,
  onDownload,
  onOpenRun,
  onAnalyze,
  onRunQC,
  className,
  preview,
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
  const { data: profile, isLoading, isError } = usePerceptionProfile(
    dataset.ref,
    dataset.name,
  )
  const lineageQ = useDatasetLineage(wherefromOpened ? dataset.ref : null)
  const consumersQ = useDatasetConsumers(wherefromOpened ? dataset.ref : null)
  const versionsQ = useDatasetVersions(versionsOpened ? dataset.ref : null)

  const [exporting, setExporting] = useState(false)
  const [exportError, setExportError] = useState<string | null>(null)

  const consumers = consumersQ.data?.consumers ?? []
  const propConsumers = dataset.consumers ?? []
  const versions = versionsQ.data?.versions ?? []
  const propVersions = dataset.versions ?? []
  const isRunOutput = dataset.source === "run_output"

  // Current version label for the header chip + stat grid. Falls back to the
  // caller's list, else v1 (every file has at least an implicit v1).
  const currentVersionLabel =
    versions.find((v) => v.current)?.label ||
    versions[0]?.label ||
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

  const shapeRows = profile?.shape?.rows
  const shapeCols = profile?.shape?.cols

  return (
    <Card className={className} data-testid="dataset-object">
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
          <CardTitle className="text-lg font-mono font-semibold truncate" data-testid="dataset-object-name">
            {dataset.name}
          </CardTitle>
          {dataset.contentType && (
            <Badge variant="secondary" className="text-xs font-mono" data-testid="dataset-header-type">
              {dataset.contentType}
            </Badge>
          )}
          {typeof dataset.size === 'number' && dataset.size > 0 && (
            <Badge variant="secondary" className="text-xs" data-testid="dataset-header-size">
              {formatBytes(dataset.size)}
            </Badge>
          )}
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

          <div className="ml-auto flex items-center gap-2">
            {/* Open in — Jupyter / RStudio / Plot viewer (design §4.3.1).
                FUTURE: launching an interactive tool on a data-hub dataset needs a
                dataset→history staging endpoint (presign → import-url → launch);
                interactive tools can't bind an arbitrary project file today. Wire
                these here once that endpoint exists. For now, "Ask in chat" is the
                supported path to work on a file interactively. */}
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
      </CardHeader>

      <CardContent>
        {/* Segmented pill tabs (design i05-2 / t10-1): a gray track with the
            selected tab as a raised white box, not an underline. */}
        <div className="inline-flex items-center gap-0.5 rounded-lg bg-muted p-0.5 mb-3" role="tablist">
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
            {/* View toggle (design §4.3). Table is backed today; Columns + Plot
                show the honest "open in Jupyter / ask in chat" fallback until the
                profiler returns per-column stats + distributions. */}
            <div className="flex items-center gap-1.5">
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
              // FUTURE: per-column type / % missing / distinct. The profiler returns
              // column names + a sample only — no per-column stats — so we don't fake
              // a column profile. Offer the real path to look deeper.
              <div className="rounded border bg-muted/20 p-3 text-sm text-muted-foreground space-y-2" data-testid="dataset-preview-columns-future">
                <p>{t('dataset_obj.columns_future')}</p>
                {onAnalyze && (
                  <Button size="sm" variant="outline" className="h-7 text-xs gap-1" onClick={onAnalyze}>
                    <Play className="h-3 w-3" />{t('dataset_obj.ask_in_chat')}
                  </Button>
                )}
              </div>
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

            {/* Stat grid (design §4.3): rows · columns · size · current version. */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2" data-testid="dataset-stat-grid">
              <StatCard k={t('dataset_obj.stat_rows')} v={shapeRows != null ? shapeRows.toLocaleString() : "—"} />
              <StatCard k={t('dataset_obj.stat_columns')} v={shapeCols != null ? String(shapeCols) : "—"} />
              <StatCard k={t('dataset_obj.stat_size')} v={formatBytes(dataset.size)} />
              <StatCard k={t('dataset_obj.stat_version')} v={currentVersionLabel} />
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
            ) : versions.length ? (
              versions.map((v) => (
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
                  {/* FUTURE: Compare / Restore — no diff/restore endpoint yet. */}
                </div>
              ))
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
                ) : (
                  <>
                    <Row
                      k={t('dataset_obj.produced_by')}
                      v={fmt(lineageQ.data?.producedBy?.workflow ?? dataset.workflowName ?? dataset.runId)}
                      mono
                      onClick={
                        onOpenRun && (lineageQ.data?.producedBy?.runId || dataset.runId)
                          ? () => onOpenRun((lineageQ.data?.producedBy?.runId || dataset.runId)!)
                          : undefined
                      }
                      testid="lineage-open-run"
                    />
                    {lineageQ.data?.producedBy?.status && (
                      <Row k={t('dataset_obj.status')} v={fmt(lineageQ.data.producedBy.status)} />
                    )}
                  </>
                )
              ) : null}
              <Row
                k={t('dataset_obj.added')}
                v={dataset.createdAt ? new Date(dataset.createdAt).toLocaleString() : "—"}
                last
              />
              {/* The internal storage ref (S3 key) is plumbing, not provenance —
                  intentionally not surfaced. FUTURE: content hash + dedup note and
                  a this-project / whole-account visibility control, once the
                  backend exposes them. */}
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
                consumers.map((c) => (
                  <div
                    key={c.runId}
                    role={onOpenRun ? "button" : undefined}
                    onClick={onOpenRun ? () => onOpenRun(c.runId) : undefined}
                    className={`flex items-center gap-2 rounded border px-2 py-1 text-xs${onOpenRun ? " cursor-pointer hover:bg-muted/50" : ""}`}
                    data-testid={`dataset-consumer-${c.runId}`}
                  >
                    <Badge variant="outline" className="text-xs">{t('dataset_obj.reads')}</Badge>
                    <span className="font-mono truncate">{c.workflow ?? c.runId}</span>
                    {c.status && <Badge variant="outline" className="text-xs ml-auto">{c.status}</Badge>}
                  </div>
                ))
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
              {/* FUTURE: the "Produced" list (typed outputs that open as dataset
                  objects) — not available from the lineage endpoint yet. */}
            </div>
          </div>)}
      </CardContent>
    </Card>
  )
}

function StatCard({ k, v }: { k: string; v: string }) {
  return (
    <div className="rounded border px-2.5 py-2">
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{k}</div>
      <div className="text-lg font-mono font-semibold text-foreground">{v}</div>
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
  v: string
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
