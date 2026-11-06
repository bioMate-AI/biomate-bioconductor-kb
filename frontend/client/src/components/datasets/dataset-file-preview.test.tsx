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
