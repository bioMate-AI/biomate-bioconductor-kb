import { useLocation } from "wouter"
import { Download, FileText, FolderOpen } from "lucide-react"
import { t } from "@/lib/i18n"
import { formatBytes, type ToolBlock } from "./code-execution-block"
import { openFileInPanel } from "@/lib/file-panel-events"

export interface SavedFile { id: string; projectId: string; name: string; fullName: string; size: number; downloadUrl?: string }

/** Every project file this reply's tool calls saved (latest version of each name), in save order.
 *  Deterministic — it does not depend on which files the model chose to mention (founder
 *  2026-11-12: "more files generated than the chat listed, missing important file mentions"). */
export function savedFilesFromBlocks(blocks: ToolBlock[] | undefined): SavedFile[] {
  const byName = new Map<string, SavedFile>()
  for (const b of blocks || []) {
    const files = (b.result?.output as any)?.output_files
    if (!Array.isArray(files)) continue
    for (const f of files) {
      if (!f?.project_file_id || !f?.project_id) continue
      const fullName = String(f.project_file_name || f.name)
      byName.delete(fullName) // keep the latest position
      byName.set(fullName, { id: String(f.project_file_id), projectId: String(f.project_id), name: String(f.name), fullName, size: Number(f.size) || 0, downloadUrl: f.download_url })
    }
  }
  return Array.from(byName.values())
}

/** Tree path of the folder the files were saved in (matches project-file-tree treeFolderOf). */
export function analysisFolderPath(fullName: string): string {
  const dir = fullName.includes("/") ? fullName.slice(0, fullName.lastIndexOf("/")) : ""
  return dir ? `outputs/analysis/${dir}` : "outputs/analysis"
}

/** Links to everything a reply generated: each file opens in the Data page (preview, versions,
 *  where-from) or downloads; the header opens the chat's output folder. */
export function GeneratedFiles({ blocks }: { blocks: ToolBlock[] | undefined }) {
  const [, setLocation] = useLocation()
  const files = savedFilesFromBlocks(blocks)
  if (!files.length) return null
  const projectId = files[0].projectId
  const folder = analysisFolderPath(files[files.length - 1].fullName)
  const go = (e: React.MouseEvent, href: string) => { e.preventDefault(); setLocation(href) }
  const folderHref = `/files?${new URLSearchParams({ project: projectId, folder }).toString()}`
  return (
    <div className="mt-3 rounded-md border border-border bg-muted/30 text-xs" data-testid="generated-files">
      <div className="flex items-center justify-between gap-2 border-b border-border px-3 py-2">
        <span className="font-medium text-foreground">{t("chat.generated_files", { n: files.length })}</span>
        <a href={folderHref} onClick={(e) => go(e, folderHref)} className="inline-flex items-center gap-1 text-primary hover:underline" data-testid="generated-files-folder">
          <FolderOpen className="h-3.5 w-3.5" /> {t("chat.open_output_folder")}
        </a>
      </div>
      <ul className="divide-y divide-border">
        {files.map((f) => {
          const href = `/files?${new URLSearchParams({ project: f.projectId, file: f.id }).toString()}`
          return (
            <li key={f.fullName} className="flex items-center gap-2 px-3 py-1.5" data-testid="generated-file">
              <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              <a href={href} onClick={(e) => { e.preventDefault(); if (!openFileInPanel({ projectId: f.projectId, fileId: f.id })) setLocation(href) }}
                className="min-w-0 flex-1 truncate text-foreground hover:underline" title={t("chat.open_file_panel")} data-testid="generated-file-open">
                {f.name}
              </a>
              <span className="shrink-0 tabular-nums text-muted-foreground">{formatBytes(f.size)}</span>
              {f.downloadUrl && (
                <a href={f.downloadUrl} download={f.name} className="shrink-0 text-primary" aria-label={t("tool_card.download")} data-testid="generated-file-download">
                  <Download className="h-3.5 w-3.5" />
                </a>
              )}
            </li>
          )
        })}
      </ul>
    </div>
  )
}
