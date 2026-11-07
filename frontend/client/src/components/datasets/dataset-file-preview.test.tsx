// @vitest-environment jsdom
import { render, screen, waitFor, cleanup } from "@testing-library/react"
import { afterEach, expect, it, vi } from "vitest"
import { DatasetFilePreview } from "./dataset-file-preview"

afterEach(() => { cleanup(); vi.unstubAllGlobals() })
function mockFile(text: string) {
  const read = vi.fn().mockResolvedValueOnce({ value: new TextEncoder().encode(text), done: false }).mockResolvedValue({ done: true })
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
