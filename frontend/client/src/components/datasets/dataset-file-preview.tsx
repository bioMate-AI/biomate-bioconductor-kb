import { useEffect, useState, lazy, Suspense } from "react"
import { FileContentView } from "../file-content-view"

// Reuse the run-output 3-axis density viewer for cryo-EM map datasets — it takes
// a direct `src` URL, so the dataset's own presigned URL drives it (no runId /
// step-file coupling). Lazy so its ~binary-parsing code stays out of the main bundle.
const DensityMapViewer = lazy(() =>
  import("../viewers/density-map-viewer").then((m) => ({ default: m.DensityMapViewer })),
)

const LIMIT = 256 * 1024
const TEXT = /\.(json|ya?ml|txt|md|csv|tsv|log|xml|html?|py|r|sh|nf|config|toml|ini|fa|fasta|pdb|smi|smiles|vcf)$/i
const IMAGE = /\.(png|jpe?g|gif|webp)$/i
const DENSITY = /\.(mrc|mrcs|map|rec)$/i

/** Uses the same permission-checked signed URL as Download. HTML stays inert text. */
export function DatasetFilePreview({ projectId, fileId, name }: {
  projectId: string; fileId: string; name: string
}) {
  const [state, setState] = useState<{ url?: string; text?: string; truncated?: boolean; error?: string }>({})
  useEffect(() => {
    const abort = new AbortController()
    setState({})
    ;(async () => {
      if (!TEXT.test(name) && !IMAGE.test(name) && !DENSITY.test(name) && !/\.pdf$/i.test(name)) return
      const response = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(fileId)}/url`, {
        credentials: "include", signal: abort.signal,
      })
      if (!response.ok) throw new Error(`Cannot access file (${response.status}).`)
      const { url } = await response.json()
      if (typeof url !== "string" || !/^https?:\/\//.test(url)) throw new Error("File URL is unavailable.")
      if (!TEXT.test(name)) { setState({ url }); return }
      const content = await fetch(url, { signal: abort.signal })
      if (!content.ok) throw new Error(`Cannot read file (${content.status}).`)
      if (!content.body) throw new Error("File content is unavailable.")
      const reader = content.body.getReader()
      const decoder = new TextDecoder()
      let text = "", bytes = 0, truncated = false
      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          const remaining = LIMIT - bytes
          text += decoder.decode(value.subarray(0, remaining), { stream: true })
          bytes += value.length
          if (bytes >= LIMIT) { truncated = true; await reader.cancel(); break }
        }
        text += decoder.decode()
      } finally { reader.releaseLock() }
      // JSON / CSV / TSV / STAR and other formats are rendered structurally by
      // FileContentView (shared with the run-output preview) — pass raw text.
      if (!abort.signal.aborted) setState({ text, truncated })
    })().catch(error => { if (!abort.signal.aborted) setState({ error: error.message }) })
    return () => abort.abort()
  }, [projectId, fileId, name])
  if (!TEXT.test(name) && !IMAGE.test(name) && !DENSITY.test(name) && !/\.pdf$/i.test(name)) return (
    <p className="text-muted-foreground">Content preview is not available for this format. Download the file to open it in a compatible application.</p>
  )
  if (state.error) return <p role="alert" className="text-destructive">{state.error}</p>
  if (state.text !== undefined) return <div className="min-w-0 space-y-2" data-testid="dataset-text-preview">
    {/* Files module: a tall, scrollable reading pane (not the compact run-output height). */}
    {state.text ? <FileContentView name={name} text={state.text} maxHClass="max-h-[60vh]" /> : <p className="text-muted-foreground">This file is empty.</p>}
    {state.truncated && <p className="text-muted-foreground">Showing the first 256 KiB. Download for the complete file.</p>}
  </div>
  if (state.url && IMAGE.test(name)) return <img src={state.url} alt={name} className="max-h-[60vh] max-w-full object-contain" />
  if (state.url && DENSITY.test(name)) return (
    <Suspense fallback={<p role="status" className="text-muted-foreground">Loading density viewer…</p>}>
      <DensityMapViewer src={state.url} name={name} />
    </Suspense>
  )
  if (state.url) return <iframe title={name} src={state.url} className="h-[60vh] w-full rounded-md border" />
  return <p role="status" className="text-muted-foreground">Loading preview…</p>
}
