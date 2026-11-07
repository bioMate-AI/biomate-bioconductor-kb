import { useEffect, useState, lazy, Suspense } from "react"
import { FileContentView } from "../file-content-view"
import {
  resolveViewer,
  InlineStructureViewer,
  InlineVcfViewer,
  InlineSequenceViewer,
  InlineAnnotationViewer,
} from "../viewers/inline-content-viewers"

// Reuse the run-output 3-axis density viewer for cryo-EM map datasets — it takes
// a direct `src` URL, so the dataset's own presigned URL drives it (no runId /
// step-file coupling). Lazy so its ~binary-parsing code stays out of the main bundle.
const DensityMapViewer = lazy(() =>
  import("../viewers/density-map-viewer").then((m) => ({ default: m.DensityMapViewer })),
)

const LIMIT = 256 * 1024
// Text-fetchable formats. Broader than the viewer registry's TEXT_EXTS on purpose —
// the Files module previews config/markup/source text too. The specialised viewers
// (structure/vcf/sequence/annotation) are dispatched from the SAME fetched text in
// renderTextContent below, so a .pdb opens in 3D and a .vcf as a variant table
// rather than as a raw dump (the rich viewers the run-output preview already uses).
const TEXT = /\.(json|ya?ml|txt|md|csv|tsv|tab|log|xml|html?|py|r|sh|nf|config|toml|ini|fa|fasta|fastq|fq|pdb|cif|mmcif|smi|smiles|vcf|bed|gff|gff3|gtf|sam)$/i
const IMAGE = /\.(png|jpe?g|gif|webp|svg)$/i
const DENSITY = /\.(mrc|mrcs|map|rec)$/i

/** Dispatch already-fetched text to the matching rich viewer by file type, with
 *  FileContentView (structured table / inert text) as the fallback. HTML stays
 *  inert (never an iframe) — same security choice this component has always made. */
function renderTextContent(name: string, text: string, maxHClass: string) {
  const ext = (name.split(".").pop() || "").toLowerCase()
  const kind = resolveViewer(ext)
  if (kind === "structure") return <InlineStructureViewer text={text} ext={ext} />
  if (kind === "vcf") return <InlineVcfViewer text={text} />
  if (kind === "sequence") return <InlineSequenceViewer text={text} />
  if (kind === "annotation") return <InlineAnnotationViewer text={text} ext={ext} />
  // table (csv/tsv/json/star) → structured grid; html/text/other → inert text.
  return <FileContentView name={name} text={text} maxHClass={maxHClass} />
}

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
      // JSON / CSV / TSV / STAR, structures, VCF, sequences and annotations are
      // rendered by the shared rich viewers (renderTextContent) — pass raw text.
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
    {state.text ? renderTextContent(name, state.text, "max-h-[60vh]") : <p className="text-muted-foreground">This file is empty.</p>}
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
