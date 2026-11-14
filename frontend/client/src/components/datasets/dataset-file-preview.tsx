import { useEffect, useState, lazy, Suspense } from "react"
import { FileContentView } from "../file-content-view"
import { t } from "@/lib/i18n"
import { fileDownloadUrl, filePreviewPngUrl } from "./datasets-api"
import { isTiff, parseTiffPreviewInfo, tiffCaption, type TiffPreviewInfo } from "./tiff-preview-info"
import { MarkdownReport } from "./markdown-report"
import { HtmlReport } from "./html-report"
import { fileExt, type ViewKind } from "./dataset-view-model"
import type { StructureEvidence } from "@/components/data-perception"
import { Button } from "@/components/ui/button"
import { Download } from "lucide-react"
import { gunzipPrefix, decompressionAvailable, DecompressionUnavailableError } from "./gzip-text"
import {
  resolveViewer,
  resolveViewerFromName,
  InlineStructureViewer,
  InlineVcfViewer,
  InlineSequenceViewer,
  InlineAnnotationViewer,
} from "../viewers/inline-content-viewers"
import { InlineIgvViewer } from "../viewers/inline-igv-viewer"
import { genomicsTrackKind } from "../viewers/genomics-index"

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
// Browsers cannot decode TIFF in <img>: the server renders one plane to PNG (preview.png); when it
// cannot, the honest download state is shown.
const IMAGE = /\.(png|jpe?g|gif|webp|svg)$/i
/** Formats the density viewer reads (MRC / CCP4 maps). `.map` and `.rec` are NOT decided by name:
 *  a PLINK `.map` is a text table and an IMOD `.rec` may be anything — only the profiler's format
 *  (it read the header) says a file is a map. */
const DENSITY_FORMATS = new Set(["mrc", "mrcs", "mrc2014", "ccp4", "map", "rec"])
/** Names that are MRC by convention (used only while no profiler format is known). */
const MRC_NAME = /\.(mrc|mrcs)$/i

const MARKDOWN = /\.(md|markdown)$/i
/** Kinds whose content is text the in-browser viewers read, whatever the file is named
 *  (a FASTQ uploaded as `.txt`, a VCF without its extension). */
const TEXT_KINDS = new Set<string>(["table", "records", "json", "sequences", "reads", "variants", "intervals", "annotation", "molecules", "document"])

type Mode = "text" | "gz" | "tiff" | "image" | "density" | "pdf" | "igv" | "pending" | "none"
/** A cryo-EM density map: an image / structure kind whose format is the MRC family. The format
 *  comes from the profiler; without one, only an unambiguous `.mrc` / `.mrcs` name counts. */
function isDensity(name: string, kind?: string, format?: string): boolean {
  if (kind !== "image" && kind !== "structure") return false
  return format ? DENSITY_FORMATS.has(format.toLowerCase()) : MRC_NAME.test(name)
}

/** BAM or indexed VCF.gz → IGV.js (not the gzip text-table path). */
function isIgvTrack(name: string, kind?: string): boolean {
  if (kind === "alignment") return true
  if (resolveViewerFromName(name) === "igv") return true
  if (kind === "variants" && genomicsTrackKind(name) === "vcf_gz") return true
  return false
}

/** The profiler's format is a text format (it read the bytes as text: `txt`, `csv`, `json`…). */
const TEXT_FORMAT = new RegExp(`^(${TEXT_EXTS})$`, "i")
/** Named as an image / PDF, but the profiler read text: the name is wrong, the content is text. */
function textUnderMediaName(name: string, format?: string): boolean {
  return Boolean(format) && TEXT_FORMAT.test(format!) && (IMAGE.test(name) || isTiff(name) || /\.pdf$/i.test(name))
}

/** Named as an image / TIFF / PDF: a name the profiler can overturn (it read text, not pixels). */
const MEDIA_NAME = (name: string) => IMAGE.test(name) || isTiff(name) || /\.pdf$/i.test(name)

/** How a file is previewed: by its content kind when the profiler read it, else by its name.
 *  While the profile is still coming, a media name is not trusted yet: "pending" fetches nothing,
 *  so a "fake.png" holding text never first loads as a (broken) image and then flips to text —
 *  the browser cached the image request without CORS headers and the text fetch of the same URL
 *  then failed ("file content unavailable"). */
export function previewMode(name: string, kind?: string, format?: string, profilePending = false): Mode {
  if (profilePending && !format && MEDIA_NAME(name)) return "pending"
  // A "fake.png" that holds text is shown as the text it is (the QC card says so).
  if (textUnderMediaName(name, format)) return "text"
  // Indexed genomics tracks before the generic .gz text decoder.
  if (isIgvTrack(name, kind)) return "igv"
  if (GZ_TEXT.test(name)) return "gz"
  if (isTiff(name, format)) return "tiff"
  // A cryo-EM map is an image kind (the profiler's vocabulary) drawn by the density viewer —
  // never by <img>, which cannot decode MRC.
  if (isDensity(name, kind, format)) return "density"
  if (IMAGE.test(name) || kind === "image") return "image"
  if (/\.pdf$/i.test(name)) return "pdf"
  if (TEXT.test(name) || (kind && TEXT_KINDS.has(kind))) return "text"
  return "none"
}
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
function renderTextContent(fileName: string, text: string, maxHClass: string, dataKind?: string, structure?: StructureEvidence | null, projectId?: string) {
  const name = viewerName(fileName)
  const ext = (name.split(".").pop() || "").toLowerCase()
  const byName = resolveViewer(ext)
  // The content kind (what the bytes are) wins over the name (what the file is called).
  if (dataKind === "structure" || (!dataKind && byName === "structure")) return <InlineStructureViewer text={text} ext={byName === "structure" ? ext : "pdb"} structure={structure} />
  if (dataKind === "variants" || (!dataKind && byName === "vcf")) return <InlineVcfViewer text={text} />
  if (dataKind === "reads" || dataKind === "sequences" || (!dataKind && byName === "sequence")) return <InlineSequenceViewer text={text} />
  if (dataKind === "intervals" || dataKind === "annotation" || (!dataKind && byName === "annotation"))
    return <InlineAnnotationViewer text={text} ext={byName === "annotation" ? ext : dataKind === "annotation" ? "gff" : "bed"} />
  if (MARKDOWN.test(name)) return <MarkdownReport text={text} projectId={projectId} reportName={fileName} />
  if (/\.html?$/i.test(name)) return <HtmlReport text={text} projectId={projectId} reportName={fileName} maxHClass={maxHClass} />
  // table (csv/tsv/json/star) → structured grid; html/text/other → inert text.
  return <FileContentView name={name} text={text} maxHClass={maxHClass} />
}

/** An image the browser cannot decode (a file named .png that holds something else) says so,
 *  instead of a broken-image icon. A decoded image shows its pixel size and fits the frame (a tiny
 *  image is enlarged, crisp; a large one shrunk), with a toggle to its actual size. */
function ImagePreview({ url, name, broken, onBroken }: { url: string; name: string; broken: boolean; onBroken: () => void }) {
  const [dims, setDims] = useState<{ w: number; h: number } | null>(null)
  const [actual, setActual] = useState(false)
  if (broken) return (
    <p role="alert" className="text-muted-foreground" data-testid="dataset-preview-image-invalid">
      {t("dataset_obj.image_invalid", { format: fileExt(name).toUpperCase() || "—" })}
    </p>
  )
  const small = dims != null && dims.w < 256 && dims.h < 256
  return (
    <div className="space-y-1.5" data-testid="dataset-preview-image-frame" data-zoom={actual ? "actual" : "fit"}>
      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        {dims && <span data-testid="dataset-preview-image-dims">{t("dataset_obj.image_dims", { w: dims.w.toLocaleString(), h: dims.h.toLocaleString() })}</span>}
        <button
          type="button"
          className="rounded border px-1.5 py-0.5 hover:bg-muted"
          aria-pressed={actual}
          data-testid="dataset-preview-image-zoom"
          onClick={() => setActual((a) => !a)}
        >{actual ? t("dataset_obj.image_fit") : t("dataset_obj.image_actual")}</button>
      </div>
      <div className={`rounded border bg-muted/20 ${actual ? "max-h-[60vh] overflow-auto" : "flex h-[min(60vh,28rem)] items-center justify-center overflow-hidden"}`}>
        <img
          src={url}
          alt={name}
          className={actual ? "max-w-none" : "h-full w-full object-contain"}
          style={small && !actual ? { imageRendering: "pixelated" } : undefined}
          data-testid="dataset-preview-image"
          onLoad={(e) => { const el = e.currentTarget; if (el.naturalWidth) setDims({ w: el.naturalWidth, h: el.naturalHeight }) }}
          onError={onBroken}
        />
      </div>
    </div>
  )
}

/** The rendered TIFF plane with its caption (what was drawn: page / series / bit depth / stretch). */
function TiffImage({ src, name, info, onBroken }: { src: string; name: string; info: TiffPreviewInfo | null; onBroken: () => void }) {
  const caption = tiffCaption(info)
  // A tiny image (a 32 × 32 test plane) is enlarged by a whole factor with crisp pixels, not blurred.
  const w = Number(info?.width) || 0, h = Number(info?.height) || 0
  const zoom = w && h && Math.max(w, h) < 256 ? Math.floor(256 / Math.max(w, h)) : 1
  return (
    <figure className="space-y-1.5" data-testid="dataset-preview-tiff-image">
      <img src={src} alt={t("dataset_obj.preview_tiff_alt", { name: name.split("/").pop() || name })}
        className={`max-h-[60vh] max-w-full rounded-md border bg-black/5 object-contain${zoom > 1 ? " [image-rendering:pixelated]" : ""}`}
        style={zoom > 1 ? { width: w * zoom, height: h * zoom } : undefined}
        data-testid="dataset-preview-image" onError={onBroken} />
      {caption && <figcaption className="text-xs text-muted-foreground" data-testid="dataset-preview-tiff-caption">{caption}</figcaption>}
    </figure>
  )
}

/** Why the server could not draw a TIFF (its refusal code), as a localized line; null if unknown. */
function tiffWhy(code: string | undefined, reason: string | undefined): string | null {
  switch (code) {
    case "too_large": return t("dataset_obj.preview_tiff_why_too_large", { reason: reason || "—" })
    case "not_tiff": case "empty_image": case "unreadable": case "preview_unavailable": case "not_previewable": case "decode":
      return t(`dataset_obj.preview_tiff_why_${code}`)
    default: return null
  }
}

/**
 * What the preview is showing, for the dataset object (its `data-preview-kind` / `aria-busy`):
 * `loading` while it fetches, `ready` when the content is drawn, `error` for a failure the user
 * sees, `none` when nothing of the content can be shown here (unsupported, empty, a TIFF the
 * server could not render, no decompressor).
 */
export type FilePreviewStatus = "loading" | "ready" | "error" | "none"

/** Uses the same permission-checked signed URL as Download. HTML stays inert text. */
export function DatasetFilePreview({ projectId, fileId, name, kind, format, structure, onStatus, profilePending }: {
  projectId: string; fileId: string; name: string
  /** The content kind from the dataset view model (DatasetObject passes it). */
  kind?: ViewKind
  /** The profiler's format extension (DataProfile.format.ext; DatasetObject passes it). */
  format?: string
  /** The profiler's structure evidence (DataProfile.structure; DatasetObject passes it). */
  structure?: StructureEvidence | null
  /** Told every status change (DatasetObject passes it). */
  onStatus?: (status: FilePreviewStatus) => void
  /** The profile (kind + format) is still being read (DatasetObject passes it). */
  profilePending?: boolean
}) {
  const [state, setState] = useState<{
    url?: string; text?: string; truncated?: boolean; compressed?: boolean; error?: string; noDecompress?: boolean; broken?: boolean
    /** TIFF: an object URL of the rendered PNG + what it shows, or why it could not be drawn. */
    png?: string; pngInfo?: TiffPreviewInfo | null; tiffFallback?: { code?: string; reason?: string }
  }>({})
  const mode = previewMode(name, kind, format, Boolean(profilePending))
  const status: FilePreviewStatus =
    mode === "none" || state.noDecompress ? "none"
    : state.error || state.broken ? "error"
    : state.text !== undefined ? (state.text ? "ready" : "none")
    : state.tiffFallback ? "none"
    : state.png || state.url ? "ready"
    : "loading"
  useEffect(() => { onStatus?.(status) }, [status, onStatus])
  useEffect(() => {
    const abort = new AbortController()
    let objectUrl: string | null = null
    setState({})
    ;(async () => {
      if (mode === "none" || mode === "pending") return
      const gz = mode === "gz"
      if (gz && !decompressionAvailable()) { setState({ noDecompress: true }); return }
      if (mode === "tiff") {
        // Rendered on the server (same owner/member check as Download); the header says what it shows.
        const r = await fetch(filePreviewPngUrl(projectId, fileId), { credentials: "include", signal: abort.signal })
        if (!r.ok || !(r.headers.get("content-type") || "").startsWith("image/png")) {
          const body: any = await r.json().catch(() => null)
          if (!abort.signal.aborted) setState({ tiffFallback: { code: typeof body?.error === "string" ? body.error : undefined, reason: typeof body?.reason === "string" ? body.reason : undefined } })
          return
        }
        const info = parseTiffPreviewInfo(r.headers.get("x-preview-info"))
        const blob = await r.blob()
        if (abort.signal.aborted) return
        objectUrl = URL.createObjectURL(blob)
        setState({ png: objectUrl, pngInfo: info })
        return
      }
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
      if (mode !== "text") { setState({ url }); return }
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
      if (mode === "tiff") { setState({ tiffFallback: {} }); return }
      setState({ error: error instanceof PreviewError ? error.message : t("dataset_obj.preview_unavailable") })
    })
    return () => { abort.abort(); if (objectUrl) URL.revokeObjectURL(objectUrl) }
  }, [projectId, fileId, name, mode])
  if (mode === "none") return (
    <p className="text-muted-foreground" data-testid="dataset-file-preview-unsupported">{t("dataset_obj.preview_unsupported")}</p>
  )
  if (state.noDecompress) return (
    <p className="text-muted-foreground" data-testid="dataset-preview-no-decompress">{t("dataset_obj.preview_gz_unavailable")}</p>
  )
  if (state.error) return <p role="alert" className="text-destructive" data-testid="dataset-file-preview-error">{state.error}</p>
  if (state.text !== undefined) return <div className="min-w-0 space-y-2" data-testid="dataset-text-preview">
    {textUnderMediaName(name, format) && (
      <p className="text-muted-foreground" data-testid="dataset-preview-name-mismatch">
        {t("dataset_obj.preview_text_under_name", { format: fileExt(name).toUpperCase() || "—" })}
      </p>
    )}
    {/* Files module: a tall, scrollable reading pane (not the compact run-output height). */}
    {state.text ? renderTextContent(name, state.text, "max-h-[60vh]", kind, structure, projectId) : <p className="text-muted-foreground">{t("dataset_obj.preview_empty")}</p>}
    {state.truncated && <p className="text-muted-foreground">{t(state.compressed ? "dataset_obj.preview_truncated_gz" : "dataset_obj.preview_truncated")}</p>}
  </div>
  if (state.png && mode === "tiff") return (
    <TiffImage src={state.png} name={name} info={state.pngInfo ?? null}
      onBroken={() => setState((s) => ({ ...s, png: undefined, tiffFallback: { code: "decode" } }))} />
  )
  if (state.tiffFallback && mode === "tiff") return (
    <div className="space-y-2" data-testid="dataset-preview-tiff">
      <p className="text-muted-foreground">{t("dataset_obj.preview_tiff")}</p>
      {tiffWhy(state.tiffFallback.code, state.tiffFallback.reason) && (
        <p className="text-xs text-muted-foreground" data-testid="dataset-preview-tiff-why" data-code={state.tiffFallback.code}>
          {tiffWhy(state.tiffFallback.code, state.tiffFallback.reason)}
        </p>
      )}
      <Button asChild variant="outline" size="sm" className="gap-1.5">
        {/* Same-origin redirect: saved under the display name, the tab never opens the storage URL. */}
        <a href={fileDownloadUrl(projectId, fileId)} download={name.split("/").pop() || name} data-testid="dataset-preview-tiff-download">
          <Download className="h-3.5 w-3.5" />{t("dataset_obj.preview_download")}
        </a>
      </Button>
    </div>
  )
  if (state.url && mode === "image") return (
    <ImagePreview url={state.url} name={name} broken={Boolean(state.broken)} onBroken={() => setState((s) => ({ ...s, broken: true }))} />
  )
  if (state.url && mode === "density") return (
    <Suspense fallback={<p role="status" aria-busy="true" className="text-muted-foreground" data-testid="dataset-file-preview-loading">{t("dataset_obj.preview_loading_density")}</p>}>
      <DensityMapViewer src={state.url} name={name} />
    </Suspense>
  )
  if (state.url && mode === "igv") return (
    <div data-testid="dataset-igv-preview">
      <InlineIgvViewer
        url={state.url}
        name={name}
        downloadUrl={fileDownloadUrl(projectId, fileId)}
      />
    </div>
  )
  if (state.url) return <iframe title={name} src={state.url} className="h-[60vh] w-full rounded-md border" />
  return <p role="status" aria-busy="true" className="text-muted-foreground" data-testid="dataset-file-preview-loading">{t(mode === "tiff" ? "dataset_obj.preview_tiff_loading" : "dataset_obj.preview_loading")}</p>
}
