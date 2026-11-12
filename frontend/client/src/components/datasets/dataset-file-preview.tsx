import { useEffect, useState, lazy, Suspense } from "react"
import { FileContentView } from "../file-content-view"
import { t } from "@/lib/i18n"
import { Button } from "@/components/ui/button"
import { Download } from "lucide-react"
import { gunzipPrefix, decompressionAvailable, DecompressionUnavailableError } from "./gzip-text"
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
/** Compressed bytes fetched (Range) for a .gz/.bgz preview — enough for ~256 KiB of text. */
const GZ_RANGE_BYTES = 1024 * 1024

/** An already-localized, user-facing preview failure. */
class PreviewError extends Error {}
// Text-fetchable formats. Broader than the viewer registry's TEXT_EXTS on purpose —
// the Files module previews config/markup/source text too. The specialised viewers
// (structure/vcf/sequence/annotation) are dispatched from the SAME fetched text in
// renderTextContent below, so a .pdb opens in 3D and a .vcf as a variant table
// rather than as a raw dump (the rich viewers the run-output preview already uses).
const TEXT_EXTS = "json|ya?ml|txt|md|csv|tsv|tab|log|xml|html?|py|r|sh|nf|config|toml|ini|fa|fasta|fastq|fq|pdb|cif|mmcif|smi|smiles|vcf|bed|gff|gff3|gtf|sam|narrowpeak|broadpeak|bedgraph|bedpe"
const TEXT = new RegExp(`\\.(${TEXT_EXTS})$`, "i")
// gzip / bgzip-compressed text (.vcf.gz, .fastq.gz, .bed.gz, .bgz …): decoded in the
// browser (gzip-text.ts) and dispatched exactly like the uncompressed extension.
const GZ_TEXT = new RegExp(`\\.(${TEXT_EXTS})\\.(gz|bgz)$`, "i")
// Browsers cannot decode TIFF in <img>; show an honest download state instead.
const TIFF = /\.tiff?$/i
const IMAGE = /\.(png|jpe?g|gif|webp|svg)$/i
const DENSITY = /\.(mrc|mrcs|map|rec)$/i

const previewable = (name: string) =>
  TEXT.test(name) || GZ_TEXT.test(name) || IMAGE.test(name) || DENSITY.test(name) || TIFF.test(name) || /\.pdf$/i.test(name)
/** The name the viewer is chosen by — `x.vcf.gz` previews as `x.vcf`. */
const viewerName = (name: string) => (GZ_TEXT.test(name) ? name.replace(/\.(gz|bgz)$/i, "") : name)

/** Read at most `cap` bytes from a response body; `ended` = the body finished first. */
async function readCapped(body: ReadableStream<Uint8Array>, cap: number): Promise<{ bytes: Uint8Array; ended: boolean }> {
  const reader = body.getReader()
  const parts: Uint8Array[] = []
  let n = 0, ended = false
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) { ended = true; break }
      const take = value.subarray(0, cap - n)
      parts.push(take)
      n += take.length
      if (n >= cap) { await reader.cancel(); break }
    }
  } finally { reader.releaseLock() }
  const bytes = new Uint8Array(n)
  let o = 0
  for (const p of parts) { bytes.set(p, o); o += p.length }
  return { bytes, ended }
}

/** Fetch the compressed prefix with a Range request and decode it. A server that
 *  ignores Range (200) is still capped at GZ_RANGE_BYTES by readCapped. */
async function readGzipPrefix(url: string, signal: AbortSignal): Promise<{ text: string; truncated: boolean }> {
  const content = await fetch(url, { signal, headers: { Range: `bytes=0-${GZ_RANGE_BYTES - 1}` } })
  if (content.status === 416) return { text: "", truncated: false } // empty object: no byte 0
  if (!content.ok) throw new PreviewError(t("dataset_obj.preview_read_error", { status: content.status }))
  if (!content.body) throw new PreviewError(t("dataset_obj.preview_unavailable"))
  const { bytes, ended } = await readCapped(content.body, GZ_RANGE_BYTES)
  // Whole file in hand iff the body ended before the cap (a 206 of the full range may
  // still be followed by more bytes on the server, so exactly-the-cap counts as cut).
  const complete = ended && bytes.length < GZ_RANGE_BYTES
  if (!bytes.length) return { text: "", truncated: false }
  try {
    return await gunzipPrefix(bytes, LIMIT, complete)
  } catch (e) {
    if (e instanceof DecompressionUnavailableError) throw e
    throw new PreviewError(t("dataset_obj.preview_gz_corrupt"))
  }
}

/** Dispatch already-fetched text to the matching rich viewer by file type, with
 *  FileContentView (structured table / inert text) as the fallback. HTML stays
 *  inert (never an iframe) — same security choice this component has always made. */
function renderTextContent(fileName: string, text: string, maxHClass: string) {
  const name = viewerName(fileName)
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
  const [state, setState] = useState<{ url?: string; text?: string; truncated?: boolean; compressed?: boolean; error?: string; noDecompress?: boolean }>({})
  useEffect(() => {
    const abort = new AbortController()
    setState({})
    ;(async () => {
      if (!previewable(name)) return
      const gz = GZ_TEXT.test(name)
      if (gz && !decompressionAvailable()) { setState({ noDecompress: true }); return }
      const response = await fetch(`/api/projects/${encodeURIComponent(projectId)}/files/${encodeURIComponent(fileId)}/url`, {
        credentials: "include", signal: abort.signal,
      })
      if (!response.ok) throw new PreviewError(t("dataset_obj.preview_access_error", { status: response.status }))
      const { url } = await response.json()
      if (typeof url !== "string" || !/^https?:\/\//.test(url)) throw new PreviewError(t("dataset_obj.preview_unavailable"))
      if (gz) {
        const { text, truncated } = await readGzipPrefix(url, abort.signal)
        if (!abort.signal.aborted) setState({ text, truncated, compressed: true })
        return
      }
      if (!TEXT.test(name)) { setState({ url }); return }
      const content = await fetch(url, { signal: abort.signal })
      if (!content.ok) throw new PreviewError(t("dataset_obj.preview_read_error", { status: content.status }))
      if (!content.body) throw new PreviewError(t("dataset_obj.preview_unavailable"))
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
    // Our own errors are already localized; a raw network/stream error is not shown verbatim.
    })().catch(error => {
      if (abort.signal.aborted) return
      if (error instanceof DecompressionUnavailableError) { setState({ noDecompress: true }); return }
      setState({ error: error instanceof PreviewError ? error.message : t("dataset_obj.preview_unavailable") })
    })
    return () => abort.abort()
  }, [projectId, fileId, name])
  if (!previewable(name)) return (
    <p className="text-muted-foreground">{t("dataset_obj.preview_unsupported")}</p>
  )
  if (state.noDecompress) return (
    <p className="text-muted-foreground" data-testid="dataset-preview-no-decompress">{t("dataset_obj.preview_gz_unavailable")}</p>
  )
  if (state.error) return <p role="alert" className="text-destructive">{state.error}</p>
  if (state.text !== undefined) return <div className="min-w-0 space-y-2" data-testid="dataset-text-preview">
    {/* Files module: a tall, scrollable reading pane (not the compact run-output height). */}
    {state.text ? renderTextContent(name, state.text, "max-h-[60vh]") : <p className="text-muted-foreground">{t("dataset_obj.preview_empty")}</p>}
    {state.truncated && <p className="text-muted-foreground">{t(state.compressed ? "dataset_obj.preview_truncated_gz" : "dataset_obj.preview_truncated")}</p>}
  </div>
  if (state.url && TIFF.test(name)) return (
    <div className="space-y-2" data-testid="dataset-preview-tiff">
      <p className="text-muted-foreground">{t("dataset_obj.preview_tiff")}</p>
      <Button asChild variant="outline" size="sm" className="gap-1.5">
        <a href={state.url} download={name} data-testid="dataset-preview-tiff-download">
          <Download className="h-3.5 w-3.5" />{t("dataset_obj.preview_download")}
        </a>
      </Button>
    </div>
  )
  if (state.url && IMAGE.test(name)) return <img src={state.url} alt={name} className="max-h-[60vh] max-w-full object-contain" />
  if (state.url && DENSITY.test(name)) return (
    <Suspense fallback={<p role="status" className="text-muted-foreground">{t("dataset_obj.preview_loading_density")}</p>}>
      <DensityMapViewer src={state.url} name={name} />
    </Suspense>
  )
  if (state.url) return <iframe title={name} src={state.url} className="h-[60vh] w-full rounded-md border" />
  return <p role="status" className="text-muted-foreground">{t("dataset_obj.preview_loading")}</p>
}
