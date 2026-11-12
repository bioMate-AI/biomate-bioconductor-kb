import { useEffect, useState } from "react"
import { useLocation } from "wouter"
import { ExternalLink, X } from "lucide-react"
import { t } from "@/lib/i18n"
import type { ProjectFile } from "@/components/project-file-tree"
import { DatasetObject } from "./dataset-object"
import { DatasetFilePreview } from "./dataset-file-preview"
import { downloadProjectFile } from "./datasets-api"
import { toDatasetRef } from "./to-dataset-ref"

/** A project file shown in the chat's right panel: the same dataset object as the Data page
 *  (preview, versions, where-from), plus "open in Data page" and close. */
export function FilePanel({ projectId, fileId, onClose }: { projectId: string; fileId: string; onClose: () => void }) {
  const [, setLocation] = useLocation()
  const [file, setFile] = useState<ProjectFile | null>(null)
  const [error, setError] = useState<number | null>(null)
  useEffect(() => {
    let alive = true
    setFile(null); setError(null)
    fetch(`/api/projects/${encodeURIComponent(projectId)}/files`, { credentials: "include" })
      .then(async (r) => {
        if (!r.ok) { if (alive) setError(r.status); return }
        const j = await r.json()
        const f = (j?.files ?? []).find((x: ProjectFile) => String(x.id) === String(fileId)) ?? null
        if (alive) { if (f) setFile(f); else setError(404) }
      })
      .catch(() => { if (alive) setError(0) })
    return () => { alive = false }
  }, [projectId, fileId])
  const dataHref = `/files?${new URLSearchParams({ project: projectId, file: fileId }).toString()}`
  return (
    <div className="absolute inset-0 z-30 flex flex-col bg-background" data-testid="chat-file-panel">
      <div className="flex items-center justify-between gap-2 border-b px-3 py-2 text-xs">
        <a href={dataHref} onClick={(e) => { e.preventDefault(); setLocation(dataHref) }} className="inline-flex items-center gap-1 text-primary hover:underline" data-testid="chat-file-panel-open-data">
          <ExternalLink className="h-3.5 w-3.5" /> {t("chat.open_in_data")}
        </a>
        <button type="button" onClick={onClose} aria-label={t("runs_ui.close_panel")} data-testid="chat-file-panel-close"><X className="h-4 w-4" /></button>
      </div>
      <div className="min-h-0 flex-1 overflow-auto p-3">
        {error != null ? (
          <p role="alert" className="text-sm text-muted-foreground" data-testid="chat-file-panel-error">{t("chat.file_panel_error")}</p>
        ) : !file ? (
          <p role="status" className="text-xs text-muted-foreground">{t("dataset_obj.preview_loading")}</p>
        ) : (
          <DatasetObject
            dataset={toDatasetRef(file)}
            projectId={projectId}
            preview={<DatasetFilePreview projectId={projectId} fileId={file.id} name={file.name} />}
            onDownload={() => downloadProjectFile(projectId, file.id, file.name)}
          />
        )}
      </div>
    </div>
  )
}
