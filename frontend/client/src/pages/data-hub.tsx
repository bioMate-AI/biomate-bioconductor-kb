import "./data-hub.css"
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
import { useEffect, useRef, useState } from "react"
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
import { FolderProfileView } from "@/components/datasets/folder-profile-view"
import { downloadProjectFile } from "@/components/datasets/datasets-api"
import { followFileList, followFolderRename } from "@/components/datasets/open-object-follow"
import { PaneResizeHandle, useTreeWidth } from "@/components/datasets/pane-resize-handle"
import { t, tOr, locale } from "@/lib/i18n"
import { analyzeFolderChatUrl } from "@/lib/folder-as-input"
import { toDatasetRef } from "@/components/datasets/to-dataset-ref"

/** The detail pane sits under the file list (stacked panes), not beside it. */
export function isStackedBelow(list: HTMLElement, detail: HTMLElement): boolean {
  const l = list.getBoundingClientRect(), d = detail.getBoundingClientRect()
  return l.height > 0 && d.top >= l.bottom - 1
}

/** The chat entry for "Run full QC": this project, this file attached, the QC request sent. The
 *  request's first sentence ("QC report: <file>") is the chat's title — a whole phrase naming what
 *  it checks (fallbackTitle titles a chat by its first sentence). */
export function runQcChatUrl(projectId: string | null, fileId: string, fileName: string): string {
  const q = new URLSearchParams()
  if (projectId) q.set("project", projectId)
  q.set("attachFile", fileId)
  q.set("draft", t("dataset_obj.qc_request", { name: fileName.split("/").pop() || fileName }))
  q.set("send", "1")
  return `/?${q.toString()}`
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
  return d.toLocaleDateString(locale === "zh" ? "zh-CN" : "en-US", { year: "numeric", month: "short", day: "numeric" })
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
          {t("data_hub.loading_projects")}
        </CardContent>
      </Card>
    )
  }
  if (projects.length === 0) {
    return (
      <Card data-testid="data-hub-picker">
        <CardContent className="flex flex-col items-center justify-center gap-2 py-12 text-center">
          <FolderOpen className="h-8 w-8 text-muted-foreground/40" />
          <p className="text-sm font-medium">{t("data_hub.no_projects")}</p>
          <p className="text-xs text-muted-foreground max-w-sm">{t("data_hub.no_projects_hint")}</p>
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
                  <span className={`h-1.5 w-1.5 rounded-full shrink-0 ${dot}`} title={statusLabel(p.status)} />
                  <span className="text-sm font-medium truncate flex-1">{p.name}</span>
                  <ChevronRight className="h-3.5 w-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 shrink-0" />
                </div>
                {p.description && (
                  <p className="text-xs text-muted-foreground line-clamp-2">{p.description}</p>
                )}
                <div className="flex items-center gap-1.5 flex-wrap">
                  <Badge variant="outline" className="text-fs-xs capitalize">{statusLabel(p.status)}</Badge>
                  {p.primaryDomain && (
                    <Badge variant="outline" className="text-fs-xs">{tOr(`domains.${p.primaryDomain}`, p.primaryDomain)}</Badge>
                  )}
                  {created && (
                    <span className="text-fs-xs text-muted-foreground ml-auto">{created}</span>
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
  // File-tree width in the two-pane layout: user-resizable, remembered (pane-resize-handle).
  const [treeWidth, setTreeWidth] = useTreeWidth()
  // The opened file / folder: when the panes are stacked (a narrow workspace), the object opens
  // BELOW the whole file list — bring it into view, or a tap on a file seems to do nothing.
  const listRef = useRef<HTMLDivElement>(null)
  const detailRef = useRef<HTMLDivElement>(null)
  // Or an input folder, opened as one object (pairs, 10x matrix, format roll-up). One of the
  // two is shown; picking either replaces the other.
  const [selectedFolder, setSelectedFolder] = useState<string | null>(null)
  // The open file was deleted (from the tree): its name, shown in place of the object.
  const [deletedName, setDeletedName] = useState<string | null>(null)
  const openedKey = selected ? `file:${selected.id}` : selectedFolder !== null ? `folder:${selectedFolder}` : null
  useEffect(() => {
    if (!openedKey) return
    const list = listRef.current, detail = detailRef.current
    if (!list || !detail) return
    if (isStackedBelow(list, detail)) detail.scrollIntoView?.({ block: "start", behavior: "smooth" })
  }, [openedKey])
  // Bumped when the open file is saved / restored as a new version, so the tree re-reads the list
  // (sizes, keys) and the selected row is the current one.
  const [treeReload, setTreeReload] = useState(0)

  // Deep-link: `/files?file=<datasetId>` opens that dataset as an object. This
  // is how a live reference chip elsewhere (composer, outputs, report) resolves
  // to the same object here — the "one object everywhere" handle.
  const search = useSearch()
  const deepLinkFileId = new URLSearchParams(search).get("file") || undefined
  // "Open folder" from a chat's generated-files list: reveal that folder in the tree.
  const deepLinkFolder = new URLSearchParams(search).get("folder") || undefined

  // Clear the selection when the active project changes — a file id from one
  // project is meaningless in another.
  useEffect(() => {
    setSelected(null)
    setSelectedFolder(null)
    setDeletedName(null)
  }, [activeProjectId])

  // The open object follows the tree's file list by id: a renamed / moved file shows its new name
  // (and is profiled under it), a new version its new key; a deleted file closes, saying so.
  // (The tree always calls the latest callback, so `selected` here is current.)
  const followList = (files: ProjectFile[]) => {
    if (!selected) return
    const r = followFileList(selected, files)
    if (r.kind === "updated") setSelected(r.file)
    else if (r.kind === "deleted") { setSelected(null); setDeletedName(r.name) }
  }

  // Header Download: a same-origin link the server redirects to a signed URL carrying the display
  // name as the attachment filename — the browser saves "counts.csv" (never the storage key
  // "counts.csv.v2"), and the tab is never navigated to the raw storage URL.
  const handleDownload = (file: ProjectFile) => {
    if (!activeProjectId) return
    downloadProjectFile(activeProjectId, file.id, file.name)
  }

  return (
    <div className="data-hub-container flex-1 min-h-0 overflow-y-auto w-full min-w-0 px-5 py-4 space-y-4" data-testid="data-hub">
      {/* One clean header: a small "Data" crumb over the project name (no duplicate
          "Data" heading, no lifecycle badge, no intro paragraph). */}
      <div className="space-y-0.5" data-testid="data-hub-header">
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Database className="h-3.5 w-3.5" />
          <span>{t('nav.data')}</span>
        </div>
        <div className="flex min-w-0 items-center gap-2">
          <h1 className="min-w-0 truncate text-lg font-semibold" data-testid="data-hub-title" title={activeProject?.name}>
            {activeProject ? activeProject.name : t('nav.data')}
          </h1>
          {activeProject?.primaryDomain && (
            <Badge variant="outline" className="text-fs-xs shrink-0">
              {tOr(`domains.${activeProject.primaryDomain}`, activeProject.primaryDomain)}
            </Badge>
          )}
          {activeProject && (
            <Button
              variant="ghost"
              size="sm"
              className="h-7 text-xs gap-1 ml-auto shrink-0"
              onClick={() => {
                setSelected(null)
                setActiveProjectId(null)
              }}
              data-testid="data-hub-change-project"
            >
              <ArrowLeftRight className="h-3 w-3" />
              {t('data_hub.change_project')}
            </Button>
          )}
        </div>
      </div>

      {!activeProjectId ? (
        <ProjectPicker projects={projects} loading={loading} onPick={setActiveProjectId} />
      ) : (
        // Stack by available workspace width, including sidebar/panel resizing.
        // The reference two-pane layout remains when both panes fit.
        <div className="data-hub-panes" data-testid="data-hub-panes" style={{ ["--data-hub-tree-w" as any]: `${treeWidth}px` }}>
          <div className="data-hub-file-list min-w-0" ref={listRef}>
            <PaneResizeHandle width={treeWidth} onWidth={setTreeWidth} />
            <ProjectFileTree
              projectId={activeProjectId}
              onOpenDataset={(f) => { setSelectedFolder(null); setDeletedName(null); setSelected(f) }}
              onOpenFolder={(p) => { setSelected(null); setDeletedName(null); setSelectedFolder(p) }}
              onFileList={followList}
              onFolderRenamed={(from, to) => setSelectedFolder((p) => (p === null ? p : followFolderRename(p, from, to)))}
              selectedFolder={selectedFolder}
              selectFileId={deepLinkFileId}
              revealFolder={deepLinkFolder}
              reloadKey={treeReload}
              canEdit
            />
          </div>

          <div className="min-w-0" ref={detailRef} data-testid="data-hub-detail">
            {selectedFolder !== null && !selected ? (
              <FolderProfileView
                projectId={activeProjectId}
                path={selectedFolder}
                onAnalyze={() => {
                  window.location.assign(analyzeFolderChatUrl(activeProjectId, selectedFolder))
                }}
              />
            ) : selected ? (
              <DatasetObject
                dataset={toDatasetRef(selected)}
                projectId={activeProjectId ?? undefined}
                // Keyed by the storage key and name: a new version (save / restore) re-reads the
                // content, and a rename re-reads it under the new name (the name sets its kind).
                preview={<DatasetFilePreview key={`${selected.id}:${selected.s3_key ?? ""}:${selected.name}`} projectId={activeProjectId!} fileId={selected.id} name={selected.name} />}
                onFileChanged={(file) => {
                  // The server's row for the new version: its storage key replaces the archived one,
                  // so the profile / rows / links of the open file read the CURRENT version.
                  setSelected((prev) => (prev && prev.id === file.id ? ({ ...prev, ...(file as Partial<ProjectFile>) }) : prev))
                  setTreeReload((n) => n + 1)
                }}
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
                  // "Run full QC": open a chat in this project with the dataset attached and the QC
                  // request SENT (`send=1`). The composer sends it only after the file is linked (no
                  // attach/send race); the chat then decides how to check the file — an analysis of
                  // its contents, or a QC workflow where one fits — and writes a QC report. The
                  // button's tooltip (dataset_obj.run_qc_tip) says exactly this, nothing more.
                  window.location.assign(runQcChatUrl(activeProjectId, selected.id, selected.name))
                }}
              />
            ) : (
              // No file picked yet — the empty pane is as tall as the file list beside it
              // (data-hub.css .data-hub-detail-empty), not a short box floating at the top.
              <Card data-testid="data-hub-detail-empty" className="data-hub-detail-empty flex flex-col">
                <CardContent className="flex flex-1 flex-col items-center justify-center gap-1.5 py-8 text-center">
                  <Database className="h-7 w-7 text-muted-foreground/40" />
                  {deletedName && (
                    <p className="text-sm text-muted-foreground [overflow-wrap:anywhere]" data-testid="data-hub-open-file-deleted">
                      {t('data_hub.open_file_deleted', { name: deletedName })}
                    </p>
                  )}
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
