/**
 * DataHub (/files) — the data-centric surface, styled to the claude-design
 * "dataset as centroid" reference (dataui/DataHub.jsx): a two-pane hub with a
 * persistent file-tree sidebar and a detail pane where any file opens as a
 * first-class DatasetObject (identity · quality · lineage · consumers ·
 * versions · origin).
 *
 * Everything rendered is backed by a real endpoint:
 *   - Project picker cards        → useActiveProject().projects (GET /api/projects)
 *   - File tree + quality dots    → ProjectFileTree (GET /api/projects/:id/files
 *                                   + POST /api/perception/profile per row)
 *   - Dataset detail (all tabs)   → DatasetObject (perception / lineage /
 *                                   consumers / versions / ro-crate endpoints)
 *
 * Nothing is fabricated. Where the backend has no data — a project with no
 * files, a dataset with no lineage/consumers/versions — the honest empty state
 * lives inside ProjectFileTree / DatasetObject and is surfaced as-is.
 *
 * The visual language mirrors the Models module (components/models/*): a Card
 * shell, a breadcrumb header, a dataset-count Badge, and styled rows/cards —
 * not a bare list.
 */

import { DatasetFilePreview } from "@/components/datasets/dataset-file-preview"
import { useEffect, useState } from "react"
import { useSearch } from "wouter"
import {
  Database,
  ChevronRight,
  FolderOpen,
  ArrowLeftRight,
} from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { useActiveProject } from "@/contexts/active-project-context"
import {
  ProjectFileTree,
  type ProjectFile,
} from "@/components/project-file-tree"
import { DatasetObject, type DatasetRef } from "@/components/datasets/dataset-object"
import { t } from "@/lib/i18n"

function toDatasetRef(f: ProjectFile): DatasetRef {
  return {
    id: f.id,
    name: f.name,
    ref: f.s3_key || null,
    // project_files.size is BIGINT → node-postgres returns it as a STRING, so
    // coerce to a real number here (the DatasetRef.size type expects one, and a
    // string silently failed the header size-badge's typeof guard).
    size: f.size == null ? null : Number(f.size),
    contentType: f.content_type || null,
    source: f.source,
    accession: (f.input_context?.accession as string | undefined) ?? null,
    runId: f.run_id,
    workflowName: f.workflow_name,
    stepName: f.step_name,
    createdAt: f.created_at,
    contentHash: f.content_hash ?? null,
  }
}

// Map a project lifecycle status to a dot colour. Purely presentational —
// the status itself comes from the real project record.
const STATUS_DOT: Record<string, string> = {
  active: "bg-emerald-500",
  completed: "bg-sky-500",
  archived: "bg-muted-foreground/50",
}

// Localized label for a known lifecycle status; unknown values (real data we
// don't have a translation for) pass through unchanged rather than showing a
// raw i18n key.
const KNOWN_STATUSES = new Set(["active", "archived", "completed", "paused"])
function statusLabel(status: string): string {
  return KNOWN_STATUSES.has(status) ? t("data_hub.status_" + status) : status
}

function formatDate(iso?: string | null): string | null {
  if (!iso) return null
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return null
  return d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" })
}

/**
 * ProjectPicker — the styled project selector shown when no project is active.
 * A card per project surfacing only real fields: name, lifecycle status,
 * primary domain (when set), description (when set), and created date.
 */
function ProjectPicker({
  projects,
  loading,
  onPick,
}: {
  projects: ReturnType<typeof useActiveProject>["projects"]
  loading: boolean
  onPick: (id: string) => void
}) {
  if (loading) {
    return (
      <Card data-testid="data-hub-picker">
        <CardContent className="py-8 text-center text-sm text-muted-foreground">
          Loading projects…
        </CardContent>
      </Card>
    )
  }
  if (projects.length === 0) {
    return (
      <Card data-testid="data-hub-picker">
        <CardContent className="flex flex-col items-center justify-center gap-2 py-12 text-center">
          <FolderOpen className="h-8 w-8 text-muted-foreground/40" />
          <p className="text-sm font-medium">No projects yet</p>
          <p className="text-xs text-muted-foreground max-w-sm">
            A project holds your datasets, runs and models. Create one — then upload data or run a
            workflow — and its datasets appear here as first-class objects.
          </p>
        </CardContent>
      </Card>
    )
  }
  return (
    <Card data-testid="data-hub-picker">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">{t('data_hub.choose_project')}</CardTitle>
        <p className="text-xs text-muted-foreground">
          {t('data_hub.project_scoped')}
        </p>
      </CardHeader>
      <CardContent>
        <div className="grid gap-2 sm:grid-cols-2" data-testid="data-hub-project-grid">
          {projects.map((p) => {
            const dot = STATUS_DOT[p.status] ?? STATUS_DOT.archived
            const created = formatDate(p.createdAt)
            return (
              <button
                key={p.id}
                type="button"
                onClick={() => onPick(p.id)}
                className="group flex flex-col gap-1.5 rounded-md border bg-background px-3 py-2.5 text-left transition-colors hover:border-primary/50 hover:bg-muted/40"
                data-testid={`data-hub-project-${p.id}`}
              >
                <div className="flex items-center gap-2">
                  <span className={`h-1.5 w-1.5 rounded-full shrink-0 ${dot}`} title={p.status} />
                  <span className="text-sm font-medium truncate flex-1">{p.name}</span>
                  <ChevronRight className="h-3.5 w-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 shrink-0" />
                </div>
                {p.description && (
                  <p className="text-xs text-muted-foreground line-clamp-2">{p.description}</p>
                )}
                <div className="flex items-center gap-1.5 flex-wrap">
                  <Badge variant="outline" className="text-[10px] capitalize">{statusLabel(p.status)}</Badge>
                  {p.primaryDomain && (
                    <Badge variant="outline" className="text-[10px]">{p.primaryDomain}</Badge>
                  )}
                  {created && (
                    <span className="text-[10px] text-muted-foreground ml-auto">{created}</span>
                  )}
                </div>
              </button>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}

export default function DataHubPage() {
  const { activeProjectId, activeProject, projects, setActiveProjectId, loading } =
    useActiveProject()
  // The selected file row (the whole ProjectFile, so DatasetObject gets every
  // field the tree already fetched — no extra round-trip). Kept in memory,
  // mirroring the reference which holds the selection in component state.
  const [selected, setSelected] = useState<ProjectFile | null>(null)

  // Deep-link: `/files?file=<datasetId>` opens that dataset as an object. This
  // is how a live reference chip elsewhere (composer, outputs, report) resolves
  // to the same object here — the "one object everywhere" handle.
  const search = useSearch()
  const deepLinkFileId = new URLSearchParams(search).get("file") || undefined

  // Clear the selection when the active project changes — a file id from one
  // project is meaningless in another.
  useEffect(() => {
    setSelected(null)
  }, [activeProjectId])

  const handleDownload = async (file: ProjectFile) => {
    if (!activeProjectId) return
    try {
      const res = await fetch(
        `/api/projects/${activeProjectId}/files/${file.id}/url`,
        { credentials: "include" },
      )
      if (!res.ok) return
      const data = await res.json()
      const a = document.createElement("a")
      a.href = data.url
      a.download = data.name
      a.click()
    } catch {
      /* ignore */
    }
  }

  return (
    <div className="w-full px-5 py-4 space-y-4" data-testid="data-hub">
      {/* Breadcrumb + title — Models-module header language. */}
      <div className="space-y-1">
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Database className="h-3.5 w-3.5" />
          <span>{t('nav.data')}</span>
          {activeProject && (
            <>
              <span>/</span>
              <span className="truncate">{activeProject.name}</span>
            </>
          )}
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <h1 className="text-lg font-semibold">{t('nav.data')}</h1>
          {activeProject && (
            <>
              <Badge variant="outline" className="text-[10px] capitalize">
                {statusLabel(activeProject.status)}
              </Badge>
              {activeProject.primaryDomain && (
                <Badge variant="outline" className="text-[10px]">
                  {activeProject.primaryDomain}
                </Badge>
              )}
              <Button
                variant="ghost"
                size="sm"
                className="h-7 text-xs gap-1 ml-auto"
                onClick={() => {
                  setSelected(null)
                  setActiveProjectId(null)
                }}
                data-testid="data-hub-change-project"
              >
                <ArrowLeftRight className="h-3 w-3" />
                {t('data_hub.change_project')}
              </Button>
            </>
          )}
        </div>
        <p className="text-xs text-muted-foreground">
          {t('data_hub.intro')}
        </p>
      </div>

      {!activeProjectId ? (
        <ProjectPicker projects={projects} loading={loading} onPick={setActiveProjectId} />
      ) : (
        // Two-pane hub: persistent file-tree sidebar + detail pane. Mirrors the
        // reference `.hub` grid (252px 1fr).
        <div className="grid gap-3 md:grid-cols-[300px_1fr]" data-testid="data-hub-panes">
          <div className="h-[72vh] min-h-[420px]">
            <ProjectFileTree
              projectId={activeProjectId}
              onOpenDataset={(f) => setSelected(f)}
              selectFileId={deepLinkFileId}
              canEdit
            />
          </div>

          <div className="min-w-0">
            {selected ? (
              <DatasetObject
                dataset={toDatasetRef(selected)}
                projectId={activeProjectId ?? undefined}
                preview={<DatasetFilePreview projectId={activeProjectId!} fileId={selected.id} name={selected.name} />}
                onBack={() => setSelected(null)}
                onDownload={() => handleDownload(selected)}
                onOpenRun={(runId) =>
                  window.location.assign(`/?reuseWorkflow=${encodeURIComponent(runId)}`)
                }
                onAnalyze={() => {
                  // Carry the exact file identity, without choosing a goal or sending a message.
                  const q = new URLSearchParams()
                  if (activeProjectId) q.set("project", activeProjectId)
                  q.set("attachFile", selected.id)
                  window.location.assign(`/?${q.toString()}`)
                }}
                onRunQC={() => {
                  // Run REAL QC through BioMate's engine: attach the dataset and
                  // pre-fill a QC request (?draft= — review before the billable
                  // run, and avoids the attach/auto-send race). The chat pipeline
                  // then selects the QC workflow (FastQC/MultiQC/domain QC), feeds
                  // this file as input, runs it and shows the report — unlike the
                  // lightweight ingest profiler in the Data profile section.
                  const q = new URLSearchParams()
                  if (activeProjectId) q.set("project", activeProjectId)
                  q.set("attachFile", selected.id)
                  q.set("draft", t("dataset_obj.qc_request"))
                  window.location.assign(`/?${q.toString()}`)
                }}
              />
            ) : (
              // No file picked yet — an honest prompt, not a blank pane.
              <Card className="h-full" data-testid="data-hub-detail-empty">
                <CardContent className="flex h-full flex-col items-center justify-center gap-2 py-16 text-center">
                  <Database className="h-8 w-8 text-muted-foreground/40" />
                  <p className="text-sm font-medium">{t('data_hub.select_dataset')}</p>
                  <p className="text-xs text-muted-foreground max-w-xs">
                    {t('data_hub.select_dataset_hint')}
                  </p>
                </CardContent>
              </Card>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
