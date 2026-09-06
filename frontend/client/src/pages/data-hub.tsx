/**
 * DataHub (/files) — the data-centric surface. Lists a project's datasets in
 * the file tree and lets any row open as a first-class DatasetObject
 * (identity · quality · lineage · consumers · versions · origin).
 *
 * Wiring only: it reuses ProjectFileTree (file listing + quality dots +
 * click-through) and DatasetObject (the tabbed detail with the mounted
 * DataPerception quality panel). The active project comes from
 * ActiveProjectContext; a lightweight picker is shown when none is selected.
 */

import { useState } from "react"
import { Database, ChevronLeft } from "lucide-react"
import { useActiveProject } from "@/contexts/active-project-context"
import {
  ProjectFileTree,
  type ProjectFile,
} from "@/components/project-file-tree"
import { DatasetObject, type DatasetRef } from "@/components/datasets/dataset-object"

function toDatasetRef(f: ProjectFile): DatasetRef {
  return {
    id: f.id,
    name: f.name,
    ref: f.s3_key || null,
    size: f.size,
    contentType: f.content_type || null,
    source: f.source,
    runId: f.run_id,
    workflowName: f.workflow_name,
    stepName: f.step_name,
    createdAt: f.created_at,
  }
}

export default function DataHubPage() {
  const { activeProjectId, activeProject, projects, setActiveProjectId, loading } =
    useActiveProject()
  const [selected, setSelected] = useState<ProjectFile | null>(null)

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
    <div className="max-w-5xl mx-auto p-4 space-y-4" data-testid="data-hub">
      <div className="flex items-center gap-2">
        <Database className="h-5 w-5 text-muted-foreground" />
        <h1 className="text-lg font-semibold">Data</h1>
        {activeProject && (
          <span className="text-sm text-muted-foreground">· {activeProject.name}</span>
        )}
      </div>

      {/* No active project → pick one. */}
      {!activeProjectId ? (
        <div className="rounded-md border p-4" data-testid="data-hub-picker">
          {loading ? (
            <p className="text-sm text-muted-foreground">Loading projects…</p>
          ) : projects.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No projects yet. Create a project to attach and inspect datasets.
            </p>
          ) : (
            <div className="space-y-2">
              <p className="text-sm text-muted-foreground">Choose a project to view its data:</p>
              <div className="flex flex-col gap-1">
                {projects.map((p) => (
                  <button
                    key={p.id}
                    type="button"
                    onClick={() => setActiveProjectId(p.id)}
                    className="text-left text-sm rounded px-2 py-1 hover:bg-muted"
                    data-testid={`data-hub-project-${p.id}`}
                  >
                    {p.name}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      ) : selected ? (
        <div className="space-y-2">
          <button
            type="button"
            onClick={() => setSelected(null)}
            className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
            data-testid="data-hub-back"
          >
            <ChevronLeft className="h-3 w-3" />
            Back to data
          </button>
          <DatasetObject
            dataset={toDatasetRef(selected)}
            onBack={() => setSelected(null)}
            onDownload={() => handleDownload(selected)}
          />
        </div>
      ) : (
        <div className="h-[70vh]">
          <ProjectFileTree
            projectId={activeProjectId}
            onOpenDataset={(f) => setSelected(f)}
            canEdit
          />
        </div>
      )}
    </div>
  )
}
