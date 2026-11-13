import { useLocation } from "wouter"
import { Download, FileText, FolderOpen } from "lucide-react"
import { t } from "@/lib/i18n"
import { formatBytes, type ToolBlock } from "./code-execution-block"
import { openFileInPanel } from "@/lib/file-panel-events"
import { fileTime } from "./project-file-tree"

export interface SavedFile {
  id: string
  projectId: string
  name: string
  fullName: string
  size: number
  downloadUrl?: string
  /** ISO timestamp from project_files.created_at when the save path returned it. */
  createdAt?: string
}

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
      const createdAt = f.created_at || f.createdAt
      byName.set(fullName, {
        id: String(f.project_file_id),
        projectId: String(f.project_id),
        name: String(f.name),
        fullName,
        size: Number(f.size) || 0,
        downloadUrl: f.download_url,
        createdAt: createdAt ? String(createdAt) : undefined,
      })
    }
  }
  return Array.from(byName.values())
}

/** Tree path of the folder the files were saved in (matches project-file-tree treeFolderOf). */
export function analysisFolderPath(fullName: string): string {
  const dir = fullName.includes("/") ? fullName.slice(0, fullName.lastIndexOf("/")) : ""
  return dir ? `outputs/analysis/${dir}` : "outputs/analysis"
}

/** Per-chat folder segment of a saved project_file name ("<title> · <stamp>/file"). */
export function chatFolderOf(fullName: string): string {
  return fullName.includes("/") ? fullName.slice(0, fullName.lastIndexOf("/")) : ""
}

/** Group saved files under each chat folder (order = first appearance). Ungrouped files use "". */
export function groupSavedFilesByChat(files: SavedFile[]): Array<{ chat: string; files: SavedFile[] }> {
  const order: string[] = []
  const byChat = new Map<string, SavedFile[]>()
  for (const f of files) {
    const chat = chatFolderOf(f.fullName)
    if (!byChat.has(chat)) {
      order.push(chat)
      byChat.set(chat, [])
    }
    byChat.get(chat)!.push(f)
  }
  return order.map((chat) => ({ chat, files: byChat.get(chat)! }))
}

/** Compact date beside a file: project created_at, else the chat-folder stamp ("· YYYY-MM-DD HH.mm"). */
export function fileDateLabel(file: SavedFile, now: Date = new Date()): string {
  if (file.createdAt) return fileTime(file.createdAt, now)
  const chat = chatFolderOf(file.fullName)
  const m = chat.match(/·\s*(\d{4})-(\d{2})-(\d{2})\s+(\d{2})\.(\d{2})\s*$/)
  if (!m) return ""
  const [, y, mo, d, h, mi] = m
  const md = `${mo}-${d} ${h}:${mi}`
  return Number(y) === now.getFullYear() ? md : `${y}-${md}`
}

/** Links to everything a reply generated: each file opens in the Data page (preview, versions,
 *  where-from) or downloads; the header opens the chat's output folder. Files are listed under
 *  each chat folder (same grouping as the Data tree). */
export function GeneratedFiles({ blocks }: { blocks: ToolBlock[] | undefined }) {
  const [, setLocation] = useLocation()
  const files = savedFilesFromBlocks(blocks)
  if (!files.length) return null
  const projectId = files[0].projectId
  const folder = analysisFolderPath(files[files.length - 1].fullName)
  const go = (e: React.MouseEvent, href: string) => { e.preventDefault(); setLocation(href) }
  const folderHref = `/files?${new URLSearchParams({ project: projectId, folder }).toString()}`
  const groups = groupSavedFilesByChat(files)
  const showChatHeaders = groups.some((g) => g.chat) && (groups.length > 1 || !!groups[0]?.chat)
  return (
    <div className="mt-3 rounded-md border border-border bg-muted/30 text-xs" data-testid="generated-files">
      <div className="flex items-center justify-between gap-2 border-b border-border px-3 py-2">
        <span className="font-medium text-foreground">{t("chat.generated_files", { n: files.length })}</span>
        <a href={folderHref} onClick={(e) => go(e, folderHref)} className="inline-flex items-center gap-1 text-primary hover:underline" data-testid="generated-files-folder">
          <FolderOpen className="h-3.5 w-3.5" /> {t("chat.open_output_folder")}
        </a>
      </div>
      <ul className="divide-y divide-border">
        {groups.map(({ chat, files: groupFiles }) => (
          <li key={chat || "__root__"} className="list-none" data-testid="generated-files-chat-group" data-chat={chat || undefined}>
            {showChatHeaders && chat && (
              <div className="px-3 pt-2 pb-1 text-[11px] font-medium text-muted-foreground truncate" title={chat} data-testid="generated-files-chat-title">
                {chat}
              </div>
            )}
            <ul className="divide-y divide-border">
              {groupFiles.map((f) => {
                const href = `/files?${new URLSearchParams({ project: f.projectId, file: f.id }).toString()}`
                const when = fileDateLabel(f)
                return (
                  <li key={f.fullName} className="flex items-center gap-2 px-3 py-1.5" data-testid="generated-file">
                    <FileText className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                    <a href={href} onClick={(e) => { e.preventDefault(); if (!openFileInPanel({ projectId: f.projectId, fileId: f.id })) setLocation(href) }}
                      className="min-w-0 flex-1 truncate text-foreground hover:underline" title={t("chat.open_file_panel")} data-testid="generated-file-open">
                      {f.name}
                    </a>
                    {when && (
                      <span className="shrink-0 tabular-nums text-muted-foreground/80" title={f.createdAt ? new Date(f.createdAt).toLocaleString() : chat} data-testid="generated-file-time">
                        {when}
                      </span>
                    )}
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
          </li>
        ))}
      </ul>
    </div>
  )
}
