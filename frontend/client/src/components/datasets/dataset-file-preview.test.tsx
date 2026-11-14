// @vitest-environment jsdom
import { render, screen, waitFor, cleanup, fireEvent } from "@testing-library/react"
import { afterEach, expect, it, vi } from "vitest"
import { gzipSync } from "node:zlib"
import { DatasetFilePreview } from "./dataset-file-preview"

afterEach(() => { cleanup(); vi.unstubAllGlobals() })
function mockFile(text: string | Uint8Array) {
  const value = typeof text === "string" ? new TextEncoder().encode(text) : text
  const read = vi.fn().mockResolvedValueOnce({ value, done: false }).mockResolvedValue({ done: true })
  const cancel = vi.fn().mockResolvedValue(undefined)
  // url → body → any later sibling fetches (e.g. MarkdownReport file list) must stay thenable.
  const fetch = vi.fn()
    .mockResolvedValueOnce({ ok: true, json: async () => ({ url: "https://files.example/test" }) })
    .mockResolvedValueOnce({ ok: true, body: { getReader: () => ({ read, cancel, releaseLock: vi.fn() }) } })
    .mockResolvedValue({ ok: true, json: async () => ({ files: [] }) })
  vi.stubGlobal("fetch", fetch)
  return { fetch, cancel }
}
it("renders JSON content as a structured key/value view through the project permission endpoint", async () => {
  const { fetch } = mockFile('{"sample":"A","value":2}')
  render(<DatasetFilePreview projectId="p" fileId="f" name="data.json" />)
  // Shared FileContentView → structured JSON table (keys + values), not a raw dump.
  const view = await screen.findByTestId("json-preview")
  expect(view).toHaveTextContent("sample")
  expect(view).toHaveTextContent("A")
  expect(view).toHaveTextContent("value")
  expect(fetch.mock.calls[0][0]).toBe("/api/projects/p/files/f/url")
})
it("renders HTML only inside a permission-less sandboxed iframe — never executable (founder: html not visualized)", async () => {
  mockFile('<h1>QC</h1><script>alert(1)</script><img src="x" onerror="alert(2)">')
  const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="report.html" />)
  const frame = await screen.findByTestId("dataset-html-frame")
  expect(frame.getAttribute("sandbox")).toBe("")
  const doc = frame.getAttribute("srcdoc") || ""
  expect(doc).toContain("<h1>QC</h1>")
  expect(doc).not.toMatch(/<script|onerror/i)
  expect(container.querySelector("script")).toBeNull()
  // Source view: the raw text, inert, as before.
  fireEvent.click(screen.getByTestId("html-view-source"))
  await screen.findByTestId("dataset-text-preview")
  expect(container.textContent).toContain("<script>")
})
it("keeps YAML inert, including malformed content", async () => {
  mockFile('key: <script>alert(1)</script>')
  const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="config.yml" />)
  await screen.findByTestId("dataset-text-preview")
  expect(container.querySelector("script")).toBeNull()
})
it("caps large text previews and cancels the response stream", async () => {
  const { cancel } = mockFile("a".repeat(300 * 1024))
  render(<DatasetFilePreview projectId="p" fileId="f" name="large.yml" />)
  await screen.findByText(/Showing the first 256 KiB/)
  expect(cancel).toHaveBeenCalledOnce()
})
it("shows permission errors rather than a blank pane", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 403 }))
  render(<DatasetFilePreview projectId="p" fileId="f" name="private.json" />)
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("403"))
})

it("renders a VCF as a variant table (dispatched to the shared VCF viewer, not a raw dump)", async () => {
  mockFile("##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\nchr1\t100\t.\tA\tG\t50\tPASS\t.")
  render(<DatasetFilePreview projectId="p" fileId="f" name="variants.vcf" />)
  const view = await screen.findByTestId("dataset-text-preview")
  expect(view).toHaveTextContent("CHROM")
  expect(view).toHaveTextContent("chr1")
})

it("renders a FASTA as sequence cards (dispatched to the shared sequence viewer)", async () => {
  mockFile(">seq1 first\nACGTACGT\n>seq2 second\nTTTT\n")
  render(<DatasetFilePreview projectId="p" fileId="f" name="reads.fasta" />)
  const view = await screen.findByTestId("dataset-text-preview")
  expect(view).toHaveTextContent("seq1")
  expect(view).toHaveTextContent("bp")
})

it("renders a BED annotation as a feature table", async () => {
  mockFile("chr1\t10\t50\tfeatA\t0\t+\nchr2\t80\t120\tfeatB\t0\t-\n")
  render(<DatasetFilePreview projectId="p" fileId="f" name="regions.bed" />)
  const view = await screen.findByTestId("dataset-text-preview")
  expect(view).toHaveTextContent("chrom")
  expect(view).toHaveTextContent("featA")
})

it("renders YAML config as readable inert text", async () => {
  mockFile('sample: tumor\nreplicates: 3\nnote: "<script>alert(1)</script>"')
  const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="protocol.yml" />)
  const preview = await screen.findByTestId("dataset-text-preview")
  expect(preview).toHaveTextContent("sample: tumor")
  expect(preview).toHaveTextContent("replicates: 3")
  expect(container.querySelector("script")).toBeNull()
})

const VCF = "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\nchr7\t55191822\trs1\tT\tG\t60\tPASS\tDP=40\n"

it("routes indexed .vcf.gz to the IGV preview slot (not the gzip text / VCF table path)", async () => {
  const { fetch } = mockFile(new Uint8Array(gzipSync(VCF)))
  render(<DatasetFilePreview projectId="p" fileId="f" name="calls.vcf.gz" />)
  expect(await screen.findByTestId("dataset-igv-preview")).toBeInTheDocument()
  expect(await screen.findByTestId("inline-igv-viewer")).toBeInTheDocument()
  // Signed URL only — no gzip Range body fetch into the VCF table path.
  expect(fetch.mock.calls[0][0]).toBe("/api/projects/p/files/f/url")
  expect(fetch.mock.calls.some((c) => c[1]?.headers?.Range === "bytes=0-1048575")).toBe(false)
  expect(screen.queryByTestId("dataset-text-preview")).toBeNull()
})

it("previews .fastq.gz as sequence cards", async () => {
  mockFile(new Uint8Array(gzipSync("@read1\nACGTN\n+\nIIIII\n")))
  render(<DatasetFilePreview projectId="p" fileId="f" name="R1.fastq.gz" />)
  const view = await screen.findByTestId("dataset-text-preview")
  expect(view).toHaveTextContent("read1")
  expect(view).toHaveTextContent("5 bp")
})

it("says so honestly when the browser has no DecompressionStream", async () => {
  vi.stubGlobal("DecompressionStream", undefined)
  const { fetch } = mockFile(new Uint8Array(gzipSync("@read1\nACGTN\n+\nIIIII\n")))
  render(<DatasetFilePreview projectId="p" fileId="f" name="R1.fastq.gz" />)
  expect(await screen.findByTestId("dataset-preview-no-decompress")).toHaveTextContent("cannot decompress")
  expect(fetch).not.toHaveBeenCalled()
})

it("reports an undecodable .gz instead of a blank pane", async () => {
  mockFile("this is not gzip")
  render(<DatasetFilePreview projectId="p" fileId="f" name="broken.bed.gz" />)
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("could not be decoded"))
})

it("renders a narrowPeak with the ENCODE peak columns", async () => {
  mockFile("chr1\t9980\t10480\tpeak1\t1000\t.\t12.5\t8.1\t6.2\t250\n")
  render(<DatasetFilePreview projectId="p" fileId="f" name="sample_peaks.narrowPeak" />)
  const view = await screen.findByTestId("dataset-text-preview")
  const headers = Array.from(view.querySelectorAll("th")).map((th) => th.textContent)
  expect(headers).toEqual(["chrom", "start", "end", "name", "score", "strand", "signalValue", "pValue", "qValue", "peak"])
  expect(view).toHaveTextContent("peak1")
})

it("renders a bedGraph as chrom/start/end/value, skipping the track line", async () => {
  mockFile("track type=bedGraph\nchr1\t0\t100\t3.5\n")
  render(<DatasetFilePreview projectId="p" fileId="f" name="cov.bedgraph" />)
  const view = await screen.findByTestId("dataset-text-preview")
  expect(Array.from(view.querySelectorAll("th")).map((th) => th.textContent)).toEqual(["chrom", "start", "end", "value"])
  expect(view).not.toHaveTextContent("track type")
})

// TIFF: rendered by the server (GET …/preview.png → PNG + X-Preview-Info), never fetched raw.
const TIFF_INFO = { seriesCount: 1, series: 0, planeCount: 3, plane: 0, axes: "QYX", shape: [3, 20, 24], dtype: "uint16",
  channels: 1, channelsShown: 1, level: 0, levelCount: 1, width: 24, height: 20,
  stretch: { percentiles: [0.5, 99.5], low: [10], high: [3990] }, constant: false, notes: [] }
function mockPng(info: unknown = TIFF_INFO) {
  const fetch = vi.fn().mockResolvedValue({
    ok: true, status: 200,
    headers: new Headers({ "content-type": "image/png", "x-preview-info": JSON.stringify(info) }),
    blob: async () => new Blob([new Uint8Array([0x89, 0x50, 0x4e, 0x47])], { type: "image/png" }),
  })
  vi.stubGlobal("fetch", fetch)
  const create = vi.fn(() => "blob:preview-1"), revoke = vi.fn()
  Object.assign(URL, { createObjectURL: create, revokeObjectURL: revoke })
  return { fetch, create, revoke }
}
function mockRefusal(status: number, body: unknown) {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
    ok: false, status, headers: new Headers({ "content-type": "application/json" }), json: async () => body,
  }))
}

it("TIFF: the server-rendered plane is drawn with a caption saying what it shows (ready)", async () => {
  const { fetch, revoke } = mockPng()
  const onStatus = vi.fn()
  const { unmount } = render(<DatasetFilePreview projectId="p" fileId="f" name="imgs/stack.tif" kind="image" format="tiff" onStatus={onStatus} />)
  const img = await screen.findByTestId("dataset-preview-image")
  expect(img).toHaveAttribute("src", "blob:preview-1")
  expect(img).toHaveAttribute("alt", "Preview of stack.tif")
  expect(screen.getByTestId("dataset-preview-tiff-caption")).toHaveTextContent("first of 3 pages · 16-bit, contrast stretched · 24 × 20 px")
  expect(fetch).toHaveBeenCalledOnce()
  expect(fetch.mock.calls[0][0]).toBe("/api/projects/p/files/f/preview.png")
  expect(fetch.mock.calls[0][1]).toMatchObject({ credentials: "include" })
  await waitFor(() => expect(onStatus).toHaveBeenLastCalledWith("ready"))
  expect(screen.queryByTestId("dataset-preview-tiff")).toBeNull()
  unmount()
  expect(revoke).toHaveBeenCalledWith("blob:preview-1")
})

it("TIFF the server refuses: the honest download state with the reason, reported as none, no <img>", async () => {
  mockRefusal(413, { error: "too_large", reason: "the image plane is 50000 × 50000 px (2 GiB decoded)" })
  const onStatus = vi.fn()
  const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="scan.tif" onStatus={onStatus} />)
  const state = await screen.findByTestId("dataset-preview-tiff")
  expect(state).toHaveTextContent("This TIFF image cannot be drawn here")
  expect(screen.getByTestId("dataset-preview-tiff-why")).toHaveTextContent("too large to preview: the image plane is 50000 × 50000 px")
  expect(screen.getByTestId("dataset-preview-tiff-download")).toHaveAttribute("href", "/api/projects/p/files/f/url?redirect=1")
  expect(container.querySelector("img")).toBeNull()
  await waitFor(() => expect(onStatus).toHaveBeenLastCalledWith("none"))
})

it("an image the browser cannot decode says so instead of a broken icon (U6)", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ url: "https://files.example/broken.png" }) }))
  render(<DatasetFilePreview projectId="p" fileId="f" name="broken.png" />)
  const img = await screen.findByTestId("dataset-preview-image")
  fireEvent.error(img)
  expect(await screen.findByTestId("dataset-preview-image-invalid")).toHaveTextContent("This file is not a valid image")
  expect(screen.queryByTestId("dataset-preview-image")).toBeNull()
})

it("Markdown is rendered as a document (headings, emphasis), and raw HTML in it stays inert (U11)", async () => {
  mockFile("# Study notes\n\nThis is a **markdown** note.\n\n<img src=x onerror=alert(1)>\n")
  const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="notes.md" />)
  const doc = await screen.findByTestId("dataset-markdown")
  expect(doc.querySelector("h1")).toHaveTextContent("Study notes")
  expect(doc.querySelector("strong")).toHaveTextContent("markdown")
  expect(doc).not.toHaveTextContent("# Study notes")
  expect(container.querySelector("img")).toBeNull()
})

it("FASTQ is shown as reads with '@' ids and base quality, never as FASTA '>' records (U11)", async () => {
  mockFile("@read1 extra\nACGTACGTAC\n+\nIIIIIIIIII\n@read2\nGGGG\n+\n!!!!\n")
  render(<DatasetFilePreview projectId="p" fileId="f" name="S1_R1.fastq" />)
  const view = await screen.findByTestId("inline-fastq-viewer")
  expect(view).toHaveTextContent("@read1")
  expect(view.textContent).not.toContain(">read1")
  expect(screen.getAllByTestId("inline-fastq-read")).toHaveLength(2)
  // 'I' = Phred 40, '!' = Phred 0
  expect(screen.getAllByTestId("inline-fastq-meta")[0]).toHaveTextContent("mean quality Phred 40.0")
  expect(screen.getAllByTestId("inline-fastq-meta")[1]).toHaveTextContent("mean quality Phred 0.0")
})

it("content kind wins over the name: reads uploaded as .txt open in the reads viewer", async () => {
  mockFile("@r1\nACGT\n+\nIIII\n")
  render(<DatasetFilePreview projectId="p" fileId="f" name="reads.txt" kind="reads" />)
  expect(await screen.findByTestId("inline-fastq-viewer")).toHaveTextContent("@r1")
})

// ── Status for the dataset object (data-preview-kind / aria-busy), audit 2026-11-12 seams ──
it("reports loading → ready, and marks its loading line with a *-loading testid + aria-busy", async () => {
  mockFile('{"a":1}')
  const onStatus = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="data.json" onStatus={onStatus} />)
  const loading = screen.getByTestId("dataset-file-preview-loading")
  expect(loading).toHaveAttribute("aria-busy", "true")
  await screen.findByTestId("json-preview")
  expect(onStatus.mock.calls.map((c) => c[0])).toEqual(["loading", "ready"])
})
it("reports error for a failure the user sees and none for content it cannot show", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 403 }))
  const onError = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="private.json" onStatus={onError} />)
  await waitFor(() => expect(onError).toHaveBeenLastCalledWith("error"))
  cleanup()
  const onNone = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="blob.xyz" onStatus={onNone} />)
  await waitFor(() => expect(onNone).toHaveBeenLastCalledWith("none"))
})
it("an MRC map (viewKind image) goes to the density viewer, never <img>", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ url: "https://files.example/map.mrc" }) }))
  const onStatus = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="map.mrc" kind="image" onStatus={onStatus} />)
  await waitFor(() => expect(onStatus).toHaveBeenLastCalledWith("ready"))
  expect(screen.queryByTestId("dataset-preview-image")).toBeNull()
})
it("a TIFF whose rendered PNG fails to decode falls back to the honest state (none)", async () => {
  mockPng()
  const onStatus = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="x.tiff" kind="image" onStatus={onStatus} />)
  fireEvent.error(await screen.findByTestId("dataset-preview-image"))
  expect(await screen.findByTestId("dataset-preview-tiff")).toBeInTheDocument()
  expect(screen.getByTestId("dataset-preview-tiff-why")).toHaveAttribute("data-code", "decode")
  expect(screen.queryByTestId("dataset-preview-image")).toBeNull()
  await waitFor(() => expect(onStatus).toHaveBeenLastCalledWith("none"))
})
it("the profiler's format decides TIFF: an OME-TIFF without a .tif name is rendered; a .tif that is a PNG is not", async () => {
  const { fetch } = mockPng()
  render(<DatasetFilePreview projectId="p" fileId="f" name="upload.bin" kind="image" format="ome.tiff" />)
  await screen.findByTestId("dataset-preview-tiff-image")
  expect(fetch.mock.calls[0][0]).toBe("/api/projects/p/files/f/preview.png")
  cleanup()
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ url: "https://files.example/a.tif" }) }))
  render(<DatasetFilePreview projectId="p" fileId="f" name="a.tif" kind="image" format="png" />)
  expect(await screen.findByTestId("dataset-preview-image")).toHaveAttribute("src", "https://files.example/a.tif")
})
it("a renderer that is not installed (503) or a network failure is the honest state, not an error", async () => {
  mockRefusal(503, { error: "preview_unavailable", reason: "TIFF rendering is not installed on this server" })
  const onStatus = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="x.tif" onStatus={onStatus} />)
  expect(await screen.findByTestId("dataset-preview-tiff-why")).toHaveTextContent("not available on this server")
  await waitFor(() => expect(onStatus).toHaveBeenLastCalledWith("none"))
  cleanup()
  vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")))
  render(<DatasetFilePreview projectId="p" fileId="f" name="x.tif" />)
  expect(await screen.findByTestId("dataset-preview-tiff")).toBeInTheDocument()
  expect(screen.queryByTestId("dataset-file-preview-error")).toBeNull()
})
it("a PLINK .map (a text table per the profile) is NOT routed to the density viewer by its extension", async () => {
  mockFile("1\trs123\t0\t752566\n1\trs456\t0\t798959\n")
  const onStatus = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="chr1.map" kind="table" format="tabular" onStatus={onStatus} />)
  const view = await screen.findByTestId("dataset-text-preview")
  expect(view).toHaveTextContent("rs123")
  expect(screen.queryByTestId("dataset-file-preview-loading")).toBeNull()
  expect(onStatus).toHaveBeenLastCalledWith("ready")
})
it("a .map the profiler identified as an MRC map (image + mrc format) goes to the density viewer", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ url: "https://files.example/emd.map" }) }))
  const onStatus = vi.fn()
  render(<DatasetFilePreview projectId="p" fileId="f" name="emd_1234.map" kind="image" format="mrc" onStatus={onStatus} />)
  await waitFor(() => expect(onStatus).toHaveBeenLastCalledWith("ready"))
  expect(screen.queryByTestId("dataset-preview-image")).toBeNull()
  expect(screen.queryByTestId("dataset-text-preview")).toBeNull()
})
