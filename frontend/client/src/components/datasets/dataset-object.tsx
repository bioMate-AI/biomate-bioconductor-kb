/**
 * DatasetObject — a dataset presented as a first-class object, mirroring the
 * proven ModelObject template (components/models/model-object.tsx): identity in
 * the header, then a tabbed body. Tabs:
 *
 *   Preview / Quality / Lineage / Consumers / Versions / Origin
 *
 * Data arrives via the `dataset` prop (a DatasetRef built by the caller — the
 * file tree already has every field). The Quality tab mounts the orphaned
 * `DataPerception` panel, fed by the backend perception profiler
 * (POST /api/perception/profile). Everything the backend cannot yet answer —
 * lineage graph, consumer list, version history — is rendered as an honest
 * "not available yet" state, NEVER a fabricated value. This mirrors how
 * ModelObject shows `not_evaluated` for an unmeasured gate.
 */

import { useState, type ReactNode } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Skeleton } from "@/components/ui/skeleton"
import {
  ChevronLeft,
  Eye,
  GitBranch,
  History,
  Download,
  FileArchive,
  Plus,
  Play,
} from "lucide-react"
import { DataPerception, type PerceptionQuality } from "@/components/data-perception"
import { t } from "@/lib/i18n"
import {
  usePerceptionProfile,
  useDatasetLineage,
  useDatasetConsumers,
  useDatasetVersions,
  useAppendDatasetVersion,
  downloadDatasetRoCrate,
} from "./datasets-api"

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
  /** Open the workflow run that produced (or reads) this dataset — makes
   *  lineage/consumers navigable rather than static text (data-centric flow). */
  onOpenRun?: (runId: string) => void
  /** Launch an analysis FROM this dataset — opens chat primed (review-before-send)
   *  to run a workflow on it, so work flows OUT of the data panel. */
  onAnalyze?: () => void
  className?: string
  preview?: ReactNode
}

// Header quality pill — reinforces the file-tree row's dot on the object itself
// (Good/Watch/Blocked), so identity (quality + version) reads at a glance rather
// than hiding behind the Quality/Versions tabs.
const HEADER_QUALITY: Record<PerceptionQuality, { dot: string; label: string }> = {
  good: { dot: "bg-emerald-500", label: "Good" },
  watch: { dot: "bg-amber-500", label: "Watch" },
  blocked: { dot: "bg-red-500", label: "Blocked" },
}

export function DatasetObject({
  dataset,
  onBack,
  onDownload,
  onOpenRun,
  onAnalyze,
  className,
  preview,
}: DatasetObjectProps) {
  // Tabs lazily fetch their backing data when first opened (mirrors Quality).
  const [lineageOpened, setLineageOpened] = useState(false)
  const [consumersOpened, setConsumersOpened] = useState(false)
  const [versionsOpened, setVersionsOpened] = useState(false)
  // Preview is the default tab and needs the profile (columns + sample rows), so
  // profiling runs when the object opens — not gated behind the Quality tab.
  const { data: profile, isLoading, isError } = usePerceptionProfile(
    dataset.ref,
    dataset.name,
  )
  const lineageQ = useDatasetLineage(lineageOpened ? dataset.ref : null)
  const consumersQ = useDatasetConsumers(consumersOpened ? dataset.ref : null)
  const versionsQ = useDatasetVersions(versionsOpened ? dataset.ref : null)
  const appendVersion = useAppendDatasetVersion(dataset.ref)

  // Draft note for the "add version" input (append-only log).
  const [note, setNote] = useState("")
  const [exporting, setExporting] = useState(false)
  const [exportError, setExportError] = useState<string | null>(null)

  // Consumers: prefer live backend data; fall back to any refs the caller held.
  const consumers = consumersQ.data?.consumers ?? []
  const propConsumers = dataset.consumers ?? []
  // Versions: backend returns at least "v1 · current"; else the caller's list.
  const versions = versionsQ.data?.versions ?? []
  const propVersions = dataset.versions ?? []
  const isRunOutput = dataset.source === "run_output"

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

  function handleAddVersion() {
    const trimmed = note.trim()
    if (!trimmed || appendVersion.isPending) return
    appendVersion.mutate(
      { note: trimmed },
      { onSuccess: () => setNote("") },
    )
  }

  return (
    <Card className={className} data-testid="dataset-object">
      <CardHeader className="pb-2 space-y-2">
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
          {/* Breadcrumb ends in the human filename, not the raw UUID (poor UX,
              and diverges from the reference's path-like crumb). The immutable
              id stays available on hover for identity-on-demand. */}
          <span className="truncate" data-testid="dataset-object-id" title={dataset.id}>
            {dataset.name}
          </span>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <CardTitle className="text-base font-mono truncate" data-testid="dataset-object-name">
            {dataset.name}
          </CardTitle>
          {dataset.contentType && (
            <Badge variant="outline" className="text-[10px]">{dataset.contentType}</Badge>
          )}
          <Badge variant="outline" className="text-[10px]">{formatBytes(dataset.size)}</Badge>
          {/* Quality pill (from the already-fetched perception profile) — object
              identity on the header, not buried in the Quality tab. */}
          {profile?.quality && HEADER_QUALITY[profile.quality] && (
            <span
              className="inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-[10px]"
              data-testid="dataset-header-quality"
              data-quality={profile.quality}
              title={t('file_tree.quality', { quality: profile.quality })}
            >
              <span className={`h-2 w-2 rounded-full ${HEADER_QUALITY[profile.quality].dot}`} />
              {t('dataset_obj.quality_' + profile.quality)}
            </span>
          )}
          {/* Version count chip — surfaces that the object has history without
              opening the Versions tab. Honest count; details live in the tab. */}
          {propVersions.length > 0 && (
            <Badge
              variant="outline"
              className="text-[10px] gap-1"
              data-testid="dataset-header-versions"
              title={t(propVersions.length === 1 ? 'dataset_obj.versions_recorded_one' : 'dataset_obj.versions_recorded_other', { n: propVersions.length })}
            >
              <History className="h-3 w-3" />
              {t(propVersions.length === 1 ? 'dataset_obj.ver_count_one' : 'dataset_obj.ver_count_other', { n: propVersions.length })}
            </Badge>
          )}
          <div className="ml-auto flex items-center gap-2">
            {dataset.ref && (
              <Button
                variant="outline"
                size="sm"
                className="h-7 text-xs gap-1"
                onClick={handleExportRoCrate}
                disabled={exporting}
                title={t('file_tree.export_crate')}
                data-testid="dataset-object-rocrate"
              >
                <FileArchive className="h-3 w-3" />
                {exporting ? t('dataset_obj.exporting') : t('dataset_obj.export_rocrate')}
              </Button>
            )}
            {onAnalyze && (
              <Button
                size="sm"
                className="h-7 text-xs gap-1"
                onClick={onAnalyze}
                data-testid="dataset-object-analyze"
                title={t('file_tree.attach_to_chat')}
              >
                <Play className="h-3 w-3" />
                {t('dataset_obj.use_in_chat')}
              </Button>
            )}
            {onDownload && (
              <Button
                variant="outline"
                size="sm"
                className="h-7 text-xs gap-1"
                onClick={onDownload}
                data-testid="dataset-object-download"
              >
                <Download className="h-3 w-3" />
                {t('actions.download')}
              </Button>
            )}
          </div>
        </div>
        {exportError && (
          <p className="text-[10px] text-destructive" data-testid="dataset-rocrate-error">
            {exportError}
          </p>
        )}
      </CardHeader>

      <CardContent>
        <Tabs
          // Remount per dataset so selecting a different file resets to Preview
          // instead of keeping whatever tab the previous file was showing.
          key={dataset.id}
          defaultValue="preview"
          onValueChange={(v) => {
            // Lineage now also holds Consumers (and Origin), so opening it
            // lazy-loads both the producedBy and the consumers queries.
            if (v === "lineage") { setLineageOpened(true); setConsumersOpened(true) }
            else if (v === "versions") setVersionsOpened(true)
          }}
        >
          {/* Three tabs, not six: Quality folds into Preview (the header already
              carries the quality badge); Consumers + Origin fold into Lineage as
              one "where it came from / what reads it" provenance view. */}
          <TabsList className="mb-3 flex-wrap h-auto">
            <TabsTrigger value="preview" className="text-xs" data-testid="dataset-tab-preview">
              <Eye className="h-3 w-3 mr-1" />{t('file_tree.preview')}
            </TabsTrigger>
            <TabsTrigger value="lineage" className="text-xs" data-testid="dataset-tab-lineage">
              <GitBranch className="h-3 w-3 mr-1" />{t('dataset_obj.lineage')}
            </TabsTrigger>
            <TabsTrigger value="versions" className="text-xs" data-testid="dataset-tab-versions">
              <History className="h-3 w-3 mr-1" />{t('dataset_obj.versions')}
            </TabsTrigger>
          </TabsList>

          {/* ── Preview: the actual data (columns + first rows) then identity ── */}
          <TabsContent value="preview" className="space-y-2 text-xs" data-testid="dataset-preview">
            {profile?.columns?.length && profile.sampleRows?.length ? (
              <div className="space-y-1" data-testid="dataset-preview-table">
                <div className="overflow-x-auto rounded border">
                  <table className="w-full border-collapse text-[11px]">
                    {/* Header reads as a header without a heavy rule — a light
                        blue band (--bm-accent-soft) + accent-ink text, mirroring
                        the reference data-table header. */}
                    <thead>
                      <tr style={{ background: 'var(--bm-accent-soft)' }}>
                        {profile.columns.map((c, i) => (
                          <th
                            key={i}
                            className="whitespace-nowrap px-2 py-1 text-left font-semibold border-b"
                            style={{ color: 'var(--bm-accent-ink)' }}
                          >
                            {c}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {profile.sampleRows.map((r, ri) => (
                        <tr key={ri} className="odd:bg-muted/20">
                          {profile.columns!.map((_, ci) => (
                            <td key={ci} className="whitespace-nowrap px-2 py-0.5 font-mono border-b">
                              {r[ci] ?? ""}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <p className="text-[10px] text-muted-foreground">
                  {t('dataset_obj.preview_rows', {
                    shown: profile.sampleRows.length,
                    of: profile.shape?.rows ? t('dataset_obj.rows_of', { total: profile.shape.rows.toLocaleString() }) : "",
                  })}
                </p>
              </div>
            ) : preview ?? null}
            <Row k={t('dataset_obj.row_name')} v={dataset.name} mono />
            <Row k={t('dataset_obj.row_size')} v={formatBytes(dataset.size)} mono />
            <Row k={t('dataset_obj.row_type')} v={fmt(dataset.contentType)} mono />
            <Row k={t('dataset_obj.row_reference')} v={fmt(dataset.ref)} mono last />
            <p className="text-[10px] text-muted-foreground pt-1">
              {t('dataset_obj.preview_note')}
            </p>
            {/* Quality folded into Preview — the header already carries the
                pass/watch/blocked badge, so it needs no separate tab. */}
            <div className="pt-3 mt-1 border-t space-y-2" data-testid="dataset-quality">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">{t('dataset_obj.quality_heading')}</p>
              {!dataset.ref ? (
                <p className="text-[11px] text-muted-foreground" data-testid="dataset-quality-noref">
                  {t('dataset_obj.quality_noref')}
                </p>
              ) : isLoading ? (
                <div className="space-y-2" data-testid="dataset-quality-loading">
                  <Skeleton className="h-4 w-40" />
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : isError || !profile ? (
                <p className="text-[11px] text-muted-foreground" data-testid="dataset-quality-error">
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
          </TabsContent>

          {/* ── Lineage: what produced it ── */}
          <TabsContent value="lineage" className="space-y-1 text-xs" data-testid="dataset-lineage">
            {lineageQ.isLoading ? (
              <div className="space-y-2" data-testid="dataset-lineage-loading">
                <Skeleton className="h-4 w-40" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : lineageQ.data?.available && lineageQ.data.producedBy ? (
              <>
                <Row
                  k={t('dataset_obj.produced_by')}
                  v={fmt(lineageQ.data.producedBy.runId)}
                  mono
                  onClick={
                    onOpenRun && lineageQ.data.producedBy.runId
                      ? () => onOpenRun(lineageQ.data!.producedBy!.runId!)
                      : undefined
                  }
                  testid="lineage-open-run"
                />
                <Row
                  k={t('workflow.labels.workflow')}
                  v={fmt(lineageQ.data.producedBy.workflow ?? dataset.workflowName)}
                  mono
                />
                <Row k={t('dataset_obj.status')} v={fmt(lineageQ.data.producedBy.status)} mono />
                <Row k={t('workflow.labels.step')} v={fmt(dataset.stepName)} mono last />
                <p className="text-[10px] text-muted-foreground pt-1">
                  {t('dataset_obj.lineage_note')}
                </p>
              </>
            ) : isRunOutput ? (
              // Prop says it's a run output but the backend has no surviving
              // provenance record — show what the caller holds, honestly.
              <>
                <Row
                  k={t('dataset_obj.produced_by')}
                  v={fmt(dataset.runId)}
                  mono
                  onClick={onOpenRun && dataset.runId ? () => onOpenRun(dataset.runId!) : undefined}
                  testid="lineage-open-run"
                />
                <Row k={t('workflow.labels.workflow')} v={fmt(dataset.workflowName)} mono />
                <Row k={t('workflow.labels.step')} v={fmt(dataset.stepName)} mono last />
                <p className="text-[10px] text-muted-foreground pt-1">
                  {t('dataset_obj.lineage_note_noprov')}
                </p>
              </>
            ) : (
              <p className="text-[11px] text-muted-foreground" data-testid="dataset-lineage-uploaded">
                {t('dataset_obj.uploaded_input')}
              </p>
            )}

            {/* Read by (consumers) — folded into Lineage: downstream runs that
                read this dataset, so provenance is one view, not three tabs. */}
            <div className="pt-3 mt-2 border-t space-y-1" data-testid="dataset-consumers">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">{t('dataset_obj.read_by')}</p>
            {consumersQ.isLoading ? (
              <div className="space-y-2" data-testid="dataset-consumers-loading">
                <Skeleton className="h-8 w-full" />
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
                  <Badge variant="outline" className="text-[10px]">{t('dataset_obj.reads')}</Badge>
                  <span className="font-mono truncate">{c.workflow ?? c.runId}</span>
                  {c.status && (
                    <Badge variant="outline" className="text-[10px] ml-auto">{c.status}</Badge>
                  )}
                </div>
              ))
            ) : propConsumers.length ? (
              propConsumers.map((c) => (
                <div
                  key={c}
                  className="flex items-center gap-2 rounded border px-2 py-1 text-xs"
                  data-testid={`dataset-consumer-${c}`}
                >
                  <Badge variant="outline" className="text-[10px]">{t('dataset_obj.reads')}</Badge>
                  <span className="font-mono truncate">{c}</span>
                </div>
              ))
            ) : (
              <p className="text-[11px] text-muted-foreground" data-testid="dataset-no-consumers">
                {t('dataset_obj.no_consumers')}
              </p>
            )}
              <p className="text-[10px] text-muted-foreground pt-1">
                {t('dataset_obj.consumers_note')}
              </p>
            </div>

            {/* Origin — where it lives + when it arrived (folded into Lineage) */}
            <div className="pt-3 mt-2 border-t space-y-1" data-testid="dataset-origin">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">{t('dataset_obj.origin')}</p>
              <Row k={t('dataset_obj.source')} v={fmt(dataset.source)} />
              <Row k={t('dataset_obj.storage_ref')} v={fmt(dataset.ref)} mono />
              <Row
                k={t('dataset_obj.added')}
                v={dataset.createdAt ? new Date(dataset.createdAt).toLocaleString() : "—"}
                last
              />
            </div>
          </TabsContent>

          {/* ── Versions ── */}
          <TabsContent value="versions" className="space-y-1" data-testid="dataset-versions">
            {versionsQ.isLoading ? (
              <div className="space-y-2" data-testid="dataset-versions-loading">
                <Skeleton className="h-8 w-full" />
              </div>
            ) : versions.length ? (
              versions.map((v) => (
                <div
                  key={v.version}
                  className="rounded border px-2 py-1 text-xs"
                  data-testid={`dataset-version-${v.version}`}
                >
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-semibold">{v.label}</span>
                    {v.current && (
                      <Badge variant="outline" className="text-[10px]">{t('dataset_obj.current')}</Badge>
                    )}
                    {v.createdAt && (
                      <span className="ml-auto text-[10px] text-muted-foreground">
                        {new Date(
                          typeof v.createdAt === "number" ? v.createdAt * 1000 : v.createdAt,
                        ).toLocaleString()}
                      </span>
                    )}
                  </div>
                  {v.note && (
                    <p className="text-[11px] text-foreground pt-0.5">
                      {v.note}
                      {v.author && (
                        <span className="text-muted-foreground"> — {v.author}</span>
                      )}
                    </p>
                  )}
                </div>
              ))
            ) : propVersions.length ? (
              propVersions.map((v) => (
                <div
                  key={v}
                  className="flex items-center gap-2 rounded border px-2 py-1 text-xs"
                  data-testid={`dataset-version-${v}`}
                >
                  <span className="font-mono font-semibold">{v}</span>
                </div>
              ))
            ) : (
              <p className="text-[11px] text-muted-foreground" data-testid="dataset-no-versions">
                {t('dataset_obj.no_versions')}
              </p>
            )}

            {/* Append-only version note — never mutates a prior entry. */}
            {dataset.ref && (
              <div className="pt-2 space-y-1" data-testid="dataset-version-add">
                <div className="flex items-center gap-2">
                  <Input
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") handleAddVersion()
                    }}
                    placeholder={t('file_tree.version_note_placeholder')}
                    className="h-7 text-xs"
                    disabled={appendVersion.isPending}
                    data-testid="dataset-version-note-input"
                  />
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-7 text-xs gap-1 shrink-0"
                    onClick={handleAddVersion}
                    disabled={!note.trim() || appendVersion.isPending}
                    data-testid="dataset-version-add-button"
                  >
                    <Plus className="h-3 w-3" />
                    {appendVersion.isPending ? t('dataset_obj.adding') : t('dataset_obj.add_version')}
                  </Button>
                </div>
                {appendVersion.isError && (
                  <p className="text-[10px] text-destructive" data-testid="dataset-version-add-error">
                    {(appendVersion.error as Error)?.message || t('dataset_obj.add_version_error')}
                  </p>
                )}
                <p className="text-[10px] text-muted-foreground">
                  {t('dataset_obj.version_note_help')}
                </p>
              </div>
            )}
          </TabsContent>

        </Tabs>
      </CardContent>
    </Card>
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
