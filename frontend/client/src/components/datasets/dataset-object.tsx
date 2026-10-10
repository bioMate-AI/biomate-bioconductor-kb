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

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Skeleton } from "@/components/ui/skeleton"
import {
  ChevronLeft,
  Eye,
  ShieldCheck,
  GitBranch,
  Boxes,
  History,
  MapPin,
  Download,
  FileArchive,
  Plus,
  Play,
} from "lucide-react"
import { DataPerception, type PerceptionQuality } from "@/components/data-perception"
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
              Data
            </button>
          )}
          <span>/</span>
          <span>{isRunOutput ? "Outputs" : "Inputs"}</span>
          <span>/</span>
          <span className="font-mono truncate" data-testid="dataset-object-id">
            {dataset.id}
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
              title={`Ingest quality: ${profile.quality}`}
            >
              <span className={`h-2 w-2 rounded-full ${HEADER_QUALITY[profile.quality].dot}`} />
              {HEADER_QUALITY[profile.quality].label}
            </span>
          )}
          {/* Version count chip — surfaces that the object has history without
              opening the Versions tab. Honest count; details live in the tab. */}
          {propVersions.length > 0 && (
            <Badge
              variant="outline"
              className="text-[10px] gap-1"
              data-testid="dataset-header-versions"
              title={`${propVersions.length} version${propVersions.length > 1 ? "s" : ""} recorded — see the Versions tab`}
            >
              <History className="h-3 w-3" />
              {propVersions.length} ver{propVersions.length > 1 ? "s" : ""}
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
                title="Export an RO-Crate metadata manifest for this dataset"
                data-testid="dataset-object-rocrate"
              >
                <FileArchive className="h-3 w-3" />
                {exporting ? "Exporting…" : "Export RO-Crate"}
              </Button>
            )}
            {onAnalyze && (
              <Button
                size="sm"
                className="h-7 text-xs gap-1"
                onClick={onAnalyze}
                data-testid="dataset-object-analyze"
                title="Run an analysis on this dataset — opens chat for you to review and send"
              >
                <Play className="h-3 w-3" />
                Analyze
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
                Download
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
          defaultValue="preview"
          onValueChange={(v) => {
            if (v === "lineage") setLineageOpened(true)
            else if (v === "consumers") setConsumersOpened(true)
            else if (v === "versions") setVersionsOpened(true)
          }}
        >
          <TabsList className="mb-3 flex-wrap h-auto">
            <TabsTrigger value="preview" className="text-xs" data-testid="dataset-tab-preview">
              <Eye className="h-3 w-3 mr-1" />Preview
            </TabsTrigger>
            <TabsTrigger value="quality" className="text-xs" data-testid="dataset-tab-quality">
              <ShieldCheck className="h-3 w-3 mr-1" />Quality
            </TabsTrigger>
            <TabsTrigger value="lineage" className="text-xs" data-testid="dataset-tab-lineage">
              <GitBranch className="h-3 w-3 mr-1" />Lineage
            </TabsTrigger>
            <TabsTrigger value="consumers" className="text-xs" data-testid="dataset-tab-consumers">
              <Boxes className="h-3 w-3 mr-1" />Consumers
            </TabsTrigger>
            <TabsTrigger value="versions" className="text-xs" data-testid="dataset-tab-versions">
              <History className="h-3 w-3 mr-1" />Versions
            </TabsTrigger>
            <TabsTrigger value="origin" className="text-xs" data-testid="dataset-tab-origin">
              <MapPin className="h-3 w-3 mr-1" />Origin
            </TabsTrigger>
          </TabsList>

          {/* ── Preview: the actual data (columns + first rows) then identity ── */}
          <TabsContent value="preview" className="space-y-2 text-xs" data-testid="dataset-preview">
            {profile?.columns?.length && profile.sampleRows?.length ? (
              <div className="space-y-1" data-testid="dataset-preview-table">
                <div className="overflow-x-auto rounded border">
                  <table className="w-full border-collapse text-[11px]">
                    <thead>
                      <tr className="bg-muted/50">
                        {profile.columns.map((c, i) => (
                          <th
                            key={i}
                            className="whitespace-nowrap px-2 py-1 text-left font-medium border-b"
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
                  First {profile.sampleRows.length} rows{profile.shape?.rows
                    ? ` of ${profile.shape.rows.toLocaleString()}`
                    : ""}. Sorting, filtering and full paging use the table viewer.
                </p>
              </div>
            ) : null}
            <Row k="Name" v={dataset.name} mono />
            <Row k="Size" v={formatBytes(dataset.size)} mono />
            <Row k="Type" v={fmt(dataset.contentType)} mono />
            <Row k="Reference" v={fmt(dataset.ref)} mono last />
            <p className="text-[10px] text-muted-foreground pt-1">
              A dataset is an object, not a path in a chat message: it carries its own identity,
              quality, lineage, and the list of runs that read it.
            </p>
          </TabsContent>

          {/* ── Quality: the mounted perception panel ── */}
          <TabsContent value="quality" className="space-y-2" data-testid="dataset-quality">
            {!dataset.ref ? (
              <p className="text-[11px] text-muted-foreground" data-testid="dataset-quality-noref">
                No resolvable reference — quality profiling is not available for this dataset.
              </p>
            ) : isLoading ? (
              <div className="space-y-2" data-testid="dataset-quality-loading">
                <Skeleton className="h-4 w-40" />
                <Skeleton className="h-16 w-full" />
              </div>
            ) : isError || !profile ? (
              <p className="text-[11px] text-muted-foreground" data-testid="dataset-quality-error">
                Quality not available — the profiler could not read this dataset.
              </p>
            ) : (
              <DataPerception
                profile={profile}
                planImpact={profile.planImpact}
                datasetName={dataset.name}
              />
            )}
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
                  k="Produced by run"
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
                  k="Workflow"
                  v={fmt(lineageQ.data.producedBy.workflow ?? dataset.workflowName)}
                  mono
                />
                <Row k="Status" v={fmt(lineageQ.data.producedBy.status)} mono />
                <Row k="Step" v={fmt(dataset.stepName)} mono last />
                <p className="text-[10px] text-muted-foreground pt-1">
                  This dataset was written by a workflow run; the run is an object you can open,
                  not a string in a description.
                </p>
              </>
            ) : isRunOutput ? (
              // Prop says it's a run output but the backend has no surviving
              // provenance record — show what the caller holds, honestly.
              <>
                <Row
                  k="Produced by run"
                  v={fmt(dataset.runId)}
                  mono
                  onClick={onOpenRun && dataset.runId ? () => onOpenRun(dataset.runId!) : undefined}
                  testid="lineage-open-run"
                />
                <Row k="Workflow" v={fmt(dataset.workflowName)} mono />
                <Row k="Step" v={fmt(dataset.stepName)} mono last />
                <p className="text-[10px] text-muted-foreground pt-1">
                  This dataset was written by a workflow run; live provenance is no longer
                  retained for this run.
                </p>
              </>
            ) : (
              <p className="text-[11px] text-muted-foreground" data-testid="dataset-lineage-uploaded">
                Uploaded input — no upstream workflow produced this dataset.
              </p>
            )}
          </TabsContent>

          {/* ── Consumers: what reads it ── */}
          <TabsContent value="consumers" className="space-y-1" data-testid="dataset-consumers">
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
                  <Badge variant="outline" className="text-[10px]">reads</Badge>
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
                  <Badge variant="outline" className="text-[10px]">reads</Badge>
                  <span className="font-mono truncate">{c}</span>
                </div>
              ))
            ) : (
              <p className="text-[11px] text-muted-foreground" data-testid="dataset-no-consumers">
                No runs are recorded as reading this dataset yet.
              </p>
            )}
            <p className="text-[10px] text-muted-foreground pt-1">
              When consumers are recorded, replacing a dataset becomes a decision with a visible
              blast radius rather than a silent change under a running analysis.
            </p>
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
                      <Badge variant="outline" className="text-[10px]">current</Badge>
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
                Version history is not available yet — only the current dataset is recorded.
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
                    placeholder="Add a version note (e.g. re-derived after QC fix)"
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
                    {appendVersion.isPending ? "Adding…" : "Add version"}
                  </Button>
                </div>
                {appendVersion.isError && (
                  <p className="text-[10px] text-destructive" data-testid="dataset-version-add-error">
                    {(appendVersion.error as Error)?.message || "Could not add version"}
                  </p>
                )}
                <p className="text-[10px] text-muted-foreground">
                  Version entries are append-only — a note records a re-derivation or sign-off
                  without ever rewriting a prior entry.
                </p>
              </div>
            )}
          </TabsContent>

          {/* ── Origin: where it lives + when it arrived ── */}
          <TabsContent value="origin" className="space-y-1 text-xs" data-testid="dataset-origin">
            <Row k="Source" v={fmt(dataset.source)} />
            <Row k="Storage ref" v={fmt(dataset.ref)} mono />
            <Row
              k="Added"
              v={dataset.createdAt ? new Date(dataset.createdAt).toLocaleString() : "—"}
              last
            />
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
