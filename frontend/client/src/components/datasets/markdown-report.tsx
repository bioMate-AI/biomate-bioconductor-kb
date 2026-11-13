import { useEffect, useState } from "react"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import { t } from "@/lib/i18n"
import { fileDownloadUrl } from "./datasets-api"

/** True when `src` is a bare relative path we can map onto a project file (not http(s)/data/#/root). */
export function isRelativeImageSrc(src: string): boolean {
  const raw = String(src || "").trim()
  return Boolean(raw) && !/^(?:[a-z][a-z0-9+.-]*:|\/|#)/i.test(raw)
}

/** Resolve a Markdown image `src` relative to the report's own stored path ("<folder>/report.md").
 *  Only bare relative links are resolved; absolute, root and data/http URLs are left alone. */
export function resolveSiblingImage(src: string, reportName: string, files: Array<{ id: string; name: string }>): string | null {
  const raw = String(src || "").trim()
  if (!isRelativeImageSrc(raw)) return null
  let decoded = raw
  try { decoded = decodeURIComponent(raw) } catch { /* keep raw */ }
  const dir = reportName.includes("/") ? reportName.slice(0, reportName.lastIndexOf("/")) : ""
  const parts = [...(dir ? dir.split("/") : []), ...decoded.replace(/^\.\//, "").split("/")]
  const out: string[] = []
  for (const p of parts) { if (p === "..") out.pop(); else if (p && p !== ".") out.push(p) }
  const wanted = out.join("/")
  const exact = files.find((f) => f.name === wanted)
  if (exact) return exact.id
  // A report that links "fig.png" while its figure sits in the same chat folder under a version.
  const base = out[out.length - 1]
  if (!base) return null
  const sameDir = files.find((f) => f.name === (dir ? `${dir}/${base}` : base))
  if (sameDir) return sameDir.id
  // Live dig (2026-11-13): panel breadcrumb may show "分析结果/<chat · time>/…" while stored
  // names omit that tree prefix (or the reverse). Prefer a sibling under the report's leaf
  // folder; else any basename match (reportName may be basename-only).
  const reportLeafDir = dir.includes("/") ? dir.slice(dir.lastIndexOf("/") + 1) : dir
  if (reportLeafDir) {
    const underLeaf = files.find((f) => {
      const n = f.name
      return n === `${reportLeafDir}/${base}` || n.endsWith(`/${reportLeafDir}/${base}`)
    })
    if (underLeaf) return underLeaf.id
  }
  const byBase = files.find((f) => f.name === base || f.name.endsWith(`/${base}`))
  return byBase ? byBase.id : null
}

/** A Markdown report with its figures: relative image links are served from the sibling project
 *  files (founder 2026-11-12: "md report no figures"). Raw HTML is still not interpreted. */
export function MarkdownReport({ text, projectId, reportName }: { text: string; projectId?: string; reportName?: string }) {
  const [files, setFiles] = useState<Array<{ id: string; name: string }> | null>(null)
  // Always load the project file list when we can resolve siblings. Do not gate on a regex over
  // `text`: reference-style images (`![alt][id]` + `[id]: fig.png`) still become <img> nodes but
  // miss the inline `![](…)` pattern, which left `files` null forever and showed "未找到图片".
  useEffect(() => {
    if (!projectId) return
    let alive = true
    fetch(`/api/projects/${encodeURIComponent(projectId)}/files`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => {
        const list = Array.isArray(j) ? j : Array.isArray(j?.files) ? j.files : []
        if (alive) setFiles(list.map((f: any) => ({ id: String(f.id), name: String(f.name) })))
      })
      .catch(() => { if (alive) setFiles([]) })
    return () => { alive = false }
  }, [projectId])
  return (
    <div className="prose prose-sm dark:prose-invert max-w-none max-h-[60vh] overflow-auto rounded-md border p-3" data-testid="dataset-markdown">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          img: ({ src, alt }) => {
            const s = String(src || "")
            const relative = isRelativeImageSrc(s)
            // Wait for the file list before declaring a relative figure missing.
            if (relative && projectId && files === null) {
              return <span className="text-xs text-muted-foreground">{t("dataset_obj.figure_loading")}</span>
            }
            const id = projectId && reportName && files ? resolveSiblingImage(s, reportName, files) : null
            if (id) return <img src={fileDownloadUrl(projectId!, id)} alt={alt || ""} loading="lazy" className="max-w-full rounded border" data-testid="markdown-figure" />
            if (/^(?:https?:|data:image\/)/i.test(s)) return <img src={s} alt={alt || ""} loading="lazy" className="max-w-full" />
            return <span className="text-xs text-muted-foreground" data-testid="markdown-figure-missing">{t("dataset_obj.figure_missing", { name: s })}</span>
          },
        }}
      >
        {text}
      </ReactMarkdown>
    </div>
  )
}
