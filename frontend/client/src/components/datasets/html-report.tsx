import { useEffect, useMemo, useState } from "react"
import { t } from "@/lib/i18n"
import { FileContentView } from "../file-content-view"
import { resolveSiblingImage } from "./markdown-report"

/** HTML stripped of anything that could act: scripts, <base>, meta refresh, inline event handlers.
 *  The iframe is sandboxed with NO permissions anyway (no scripts, opaque origin, no forms, no
 *  top navigation) — this is belt and braces, and keeps the srcdoc readable. */
export function inertHtml(html: string): Document {
  const doc = new DOMParser().parseFromString(String(html || ""), "text/html")
  doc.querySelectorAll("script, base, meta[http-equiv], iframe, object, embed").forEach((el) => el.remove())
  doc.querySelectorAll("*").forEach((el) => {
    for (const a of Array.from(el.attributes)) if (/^on/i.test(a.name)) el.removeAttribute(a.name)
  })
  return doc
}

/** An HTML report, rendered (founder 2026-11-12: generated HTML showed as source). Rendered in a
 *  fully sandboxed iframe; relative <img> links resolve to the sibling project files (same rule as
 *  Markdown reports) through short-lived signed URLs. "Source" shows the raw text, as before. */
export function HtmlReport({ text, projectId, reportName, maxHClass }: { text: string; projectId?: string; reportName?: string; maxHClass: string }) {
  const [view, setView] = useState<"rendered" | "source">("rendered")
  const [srcdoc, setSrcdoc] = useState<string | null>(null)
  const relImgs = useMemo(() => {
    const doc = inertHtml(text)
    return Array.from(doc.querySelectorAll("img")).map((i) => i.getAttribute("src") || "").filter((s) => s && !/^(?:[a-z][a-z0-9+.-]*:|\/|#)/i.test(s))
  }, [text])
  useEffect(() => {
    let alive = true
    ;(async () => {
      const doc = inertHtml(text)
      if (relImgs.length && projectId && reportName) {
        try {
          const r = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files`, { credentials: "include" })
          const j = r.ok ? await r.json() : null
          const files = (Array.isArray(j?.files) ? j.files : []).map((f: any) => ({ id: String(f.id), name: String(f.name) }))
          for (const img of Array.from(doc.querySelectorAll("img"))) {
            const id = resolveSiblingImage(img.getAttribute("src") || "", reportName, files)
            if (!id) continue
            const u = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(id)}/url`, { credentials: "include" })
            const uj = u.ok ? await u.json() : null
            if (uj?.url) img.setAttribute("src", String(uj.url))
          }
        } catch { /* figures stay unresolved; the text still renders */ }
      }
      if (alive) setSrcdoc("<!doctype html>" + doc.documentElement.outerHTML)
    })()
    return () => { alive = false }
  }, [text, projectId, reportName, relImgs.length])
  return (
    <div className="space-y-2" data-testid="dataset-html">
      <div className="flex gap-1 text-xs" role="tablist">
        {(["rendered", "source"] as const).map((v) => (
          <button key={v} type="button" role="tab" aria-selected={view === v} onClick={() => setView(v)}
            className={"rounded px-2 py-0.5 " + (view === v ? "bg-muted font-medium" : "text-muted-foreground hover:text-foreground")}
            data-testid={`html-view-${v}`}>
            {v === "rendered" ? t("dataset_obj.html_rendered") : t("dataset_obj.html_source")}
          </button>
        ))}
      </div>
      {view === "source" ? (
        <FileContentView name={reportName || "report.html"} text={text} maxHClass={maxHClass} />
      ) : srcdoc == null ? (
        <p className="text-xs text-muted-foreground" role="status">{t("dataset_obj.preview_loading")}</p>
      ) : (
        <iframe
          title={reportName || "HTML report"}
          sandbox=""
          srcDoc={srcdoc}
          referrerPolicy="no-referrer"
          className="h-[60vh] w-full rounded-md border bg-white"
          data-testid="dataset-html-frame"
        />
      )}
    </div>
  )
}
