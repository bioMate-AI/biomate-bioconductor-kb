// @vitest-environment jsdom
import { render, screen, waitFor, cleanup } from "@testing-library/react"
import { afterEach, expect, it, vi } from "vitest"
import { gzipSync } from "node:zlib"
import { DatasetFilePreview } from "./dataset-file-preview"

afterEach(() => { cleanup(); vi.unstubAllGlobals() })
function mockFile(text: string | Uint8Array) {
  const value = typeof text === "string" ? new TextEncoder().encode(text) : text
  const read = vi.fn().mockResolvedValueOnce({ value, done: false }).mockResolvedValue({ done: true })
  const cancel = vi.fn().mockResolvedValue(undefined)
  const fetch = vi.fn().mockResolvedValueOnce({ ok: true, json: async () => ({ url: "https://files.example/test" }) })
    .mockResolvedValueOnce({ ok: true, body: { getReader: () => ({ read, cancel, releaseLock: vi.fn() }) } })
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
it("keeps YAML and HTML inert, including malformed content", async () => {
  mockFile('<script>alert(1)</script>')
  const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="report.html" />)
  await screen.findByTestId("dataset-text-preview")
  expect(container.querySelector("script")).toBeNull()
  expect(container.textContent).toContain("<script>")
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

it("decompresses a .vcf.gz in the browser (Range request) and dispatches it to the VCF viewer", async () => {
  const gz = new Uint8Array(Buffer.concat([gzipSync(VCF.slice(0, 40)), gzipSync(VCF.slice(40))]))  // two members
  const { fetch } = mockFile(gz)
  render(<DatasetFilePreview projectId="p" fileId="f" name="calls.vcf.gz" />)
  const view = await screen.findByTestId("dataset-text-preview")
  // Variant table: header from #CHROM, the record split into columns (not a raw dump).
  expect(view.querySelector("th")?.textContent).toBe("CHROM")
  expect(view).toHaveTextContent("55191822")
  expect(view).not.toHaveTextContent("##fileformat")
  expect(fetch.mock.calls[1][1].headers.Range).toBe("bytes=0-1048575")
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
  const { fetch } = mockFile(new Uint8Array(gzipSync(VCF)))
  render(<DatasetFilePreview projectId="p" fileId="f" name="calls.vcf.gz" />)
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

it("TIFF: an honest no-preview state with a Download link, never a broken <img>", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ url: "https://files.example/scan.tif" }) }))
  const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="scan.tif" />)
  const state = await screen.findByTestId("dataset-preview-tiff")
  expect(state).toHaveTextContent("TIFF images cannot be displayed in the browser")
  expect(screen.getByTestId("dataset-preview-tiff-download")).toHaveAttribute("href", "https://files.example/scan.tif")
  expect(container.querySelector("img")).toBeNull()
})
