/**
 * Data Hub: browse configured public FTP/HTTP sources → fetch → land in project_files.
 * Uses existing GET /api/data/sources|browse and POST /api/data/fetch, then
 * POST /api/projects/:id/files/import-url with the staged presigned/HTTP URL.
 */
import { useCallback, useEffect, useState } from "react"
import { ChevronRight, Folder, File, Loader2, RefreshCw } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { t, tOr } from "@/lib/i18n"

type Source = { id: string; label: string; type?: string }
type BrowseEntry = {
  name?: string
  path?: string
  uri?: string
  url?: string
  class?: string
  type?: string
  is_folder?: boolean
}

function entryName(e: BrowseEntry): string {
  return String(e.name || e.path || e.uri || "").split("/").filter(Boolean).pop() || String(e.uri || e.path || "item")
}

function entryIsFolder(e: BrowseEntry): boolean {
  if (e.is_folder === true) return true
  const c = String(e.class || e.type || "").toLowerCase()
  return c === "directory" || c === "folder" || c === "dir"
}

function entryPath(e: BrowseEntry, parentPath: string): string {
  if (typeof e.path === "string" && e.path) return e.path.replace(/^\/+/, "")
  if (typeof e.uri === "string" && e.uri.includes("://")) {
    const after = e.uri.replace(/^[^:]+:\/\//, "").replace(/^[^/]+\//, "")
    if (after) return after
  }
  const name = entryName(e)
  return parentPath ? `${parentPath.replace(/\/+$/, "")}/${name}` : name
}

export function RemoteSourcePicker({
  projectId,
  onImported,
  onClose,
}: {
  projectId: string
  onImported: () => void | Promise<void>
  onClose: () => void
}) {
  const [sources, setSources] = useState<Source[]>([])
  const [sourceId, setSourceId] = useState<string>("")
  const [path, setPath] = useState("")
  const [entries, setEntries] = useState<BrowseEntry[]>([])
  const [loading, setLoading] = useState(false)
  const [fetching, setFetching] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const loadSources = useCallback(async () => {
    setError(null)
    try {
      const res = await fetch("/api/data/sources", { credentials: "include" })
      if (!res.ok) throw new Error(`sources ${res.status}`)
      const body = await res.json()
      const list: Source[] = Array.isArray(body.sources) ? body.sources : []
      setSources(list)
      if (!sourceId && list[0]?.id) setSourceId(list[0].id)
    } catch (e: any) {
      setError(e?.message || tOr("file_tree.remote_err", "Could not list remote sources"))
    }
  }, [sourceId])

  const loadBrowse = useCallback(async (src: string, browsePath: string) => {
    if (!src) return
    setLoading(true)
    setError(null)
    try {
      const qs = new URLSearchParams({ source: src })
      if (browsePath) qs.set("path", browsePath)
      const res = await fetch(`/api/data/browse?${qs}`, { credentials: "include" })
      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(typeof body.error === "string" ? body.error : `browse ${res.status}`)
      }
      const body = await res.json()
      const list: BrowseEntry[] = Array.isArray(body) ? body
        : Array.isArray(body.entries) ? body.entries
          : Array.isArray(body.files) ? body.files
            : []
      setEntries(list)
      setPath(browsePath)
    } catch (e: any) {
      setEntries([])
      setError(e?.message || tOr("file_tree.remote_browse_err", "Could not browse that path"))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { void loadSources() }, [loadSources])
  useEffect(() => {
    if (sourceId) void loadBrowse(sourceId, "")
  }, [sourceId, loadBrowse])

  const importEntry = async (e: BrowseEntry) => {
    if (!sourceId || entryIsFolder(e)) return
    const remotePath = entryPath(e, path)
    const key = remotePath || entryName(e)
    setFetching(key)
    setError(null)
    try {
      const fetchRes = await fetch("/api/data/fetch", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          source: sourceId,
          path: remotePath,
          url: typeof e.url === "string" ? e.url : undefined,
        }),
      })
      const fetchBody = await fetchRes.json().catch(() => ({})) as {
        error?: string; presigned_url?: string; url?: string; s3_uri?: string; filename?: string
      }
      if (!fetchRes.ok) throw new Error(fetchBody.error || `fetch ${fetchRes.status}`)
      const landUrl = fetchBody.presigned_url || fetchBody.url
      if (!landUrl || typeof landUrl !== "string") {
        throw new Error(tOr("file_tree.remote_no_url", "Fetch succeeded but no download URL was returned"))
      }
      const imp = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/import-url`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          url: landUrl,
          filename: fetchBody.filename || entryName(e),
        }),
      })
      if (!imp.ok) {
        const body = await imp.json().catch(() => ({})) as { error?: string }
        throw new Error(body.error || `import ${imp.status}`)
      }
      await onImported()
    } catch (err: any) {
      setError(err?.message || tOr("file_tree.remote_import_err", "Could not import that file into the project"))
    } finally {
      setFetching(null)
    }
  }

  const crumbs = path ? path.split("/").filter(Boolean) : []

  return (
    <div className="border rounded-md p-2 space-y-2 text-xs" data-testid="remote-source-picker">
      <div className="flex items-center gap-2 flex-wrap">
        <select
          className="rounded border bg-background px-2 py-1 text-xs max-w-[14rem]"
          value={sourceId}
          onChange={(ev) => setSourceId(ev.target.value)}
          data-testid="remote-source-select"
        >
          {sources.map((s) => (
            <option key={s.id} value={s.id}>{s.label || s.id}</option>
          ))}
        </select>
        <Button size="sm" variant="ghost" className="h-6 px-2" onClick={() => void loadBrowse(sourceId, path)} disabled={loading || !sourceId}>
          <RefreshCw className={cn("h-3 w-3", loading && "animate-spin")} />
        </Button>
        <Button size="sm" variant="ghost" className="h-6 px-2 ml-auto" onClick={onClose} data-testid="remote-source-close">
          {tOr("file_tree.remote_close", "Close")}
        </Button>
      </div>
      <div className="flex items-center gap-0.5 flex-wrap text-muted-foreground" data-testid="remote-source-crumbs">
        <button type="button" className="hover:underline" onClick={() => void loadBrowse(sourceId, "")}>/</button>
        {crumbs.map((c, i) => {
          const p = crumbs.slice(0, i + 1).join("/")
          return (
            <span key={p} className="inline-flex items-center">
              <ChevronRight className="h-3 w-3" />
              <button type="button" className="hover:underline font-mono" onClick={() => void loadBrowse(sourceId, p)}>{c}</button>
            </span>
          )
        })}
      </div>
      {error && <p className="text-destructive" data-testid="remote-source-error">{error}</p>}
      <ul className="max-h-48 overflow-auto space-y-0.5 border rounded bg-background" data-testid="remote-source-entries">
        {loading ? (
          <li className="p-2 text-muted-foreground flex items-center gap-1"><Loader2 className="h-3 w-3 animate-spin" />{t("file_tree.refresh")}</li>
        ) : entries.length === 0 ? (
          <li className="p-2 text-muted-foreground">{tOr("file_tree.remote_empty", "No entries")}</li>
        ) : entries.map((e, i) => {
          const folder = entryIsFolder(e)
          const name = entryName(e)
          const p = entryPath(e, path)
          return (
            <li key={`${name}-${i}`} className="flex items-center gap-1 px-2 py-1 hover:bg-muted/50">
              {folder ? <Folder className="h-3 w-3 text-yellow-500 shrink-0" /> : <File className="h-3 w-3 shrink-0" />}
              {folder ? (
                <button type="button" className="font-mono truncate text-left flex-1 hover:underline" onClick={() => void loadBrowse(sourceId, p)}>
                  {name}
                </button>
              ) : (
                <>
                  <span className="font-mono truncate flex-1" title={name}>{name}</span>
                  <Button
                    size="sm"
                    className="h-5 px-1.5 text-[10px]"
                    disabled={!!fetching}
                    onClick={() => { void importEntry(e) }}
                    data-testid="remote-source-import"
                  >
                    {fetching === p || fetching === name
                      ? <Loader2 className="h-3 w-3 animate-spin" />
                      : tOr("file_tree.remote_import", "Import")}
                  </Button>
                </>
              )}
            </li>
          )
        })}
      </ul>
    </div>
  )
}
