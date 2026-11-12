// @vitest-environment jsdom
/**
 * N3 (2026-11-12 walkthrough): "fake.png" (20 bytes of text) first loaded as an image by its name,
 * then — when the profile said "text" — flipped to text mode and fetched the same signed URL again.
 * The browser had cached the <img> response without CORS headers, so the text fetch failed:
 * "Loading preview…" / "文件内容不可用。" before (or instead of) the text.
 *
 * While the profile is pending, a media name fetches nothing; once the profile decides, the file
 * is fetched once, in its final mode.
 */
import { render, screen, cleanup } from "@testing-library/react"
import { afterEach, expect, it, vi, describe } from "vitest"
import { DatasetFilePreview, previewMode } from "./dataset-file-preview"

afterEach(() => { cleanup(); vi.unstubAllGlobals() })

function stubText(text: string) {
  const value = new TextEncoder().encode(text)
  const read = vi.fn().mockResolvedValueOnce({ value, done: false }).mockResolvedValue({ done: true })
  const fetch = vi.fn(async (u: string) => u.startsWith("/api/")
    ? { ok: true, json: async () => ({ url: "https://files.example/fake.png" }) }
    : { ok: true, body: { getReader: () => ({ read, cancel: vi.fn(), releaseLock: vi.fn() }) } })
  vi.stubGlobal("fetch", fetch)
  return fetch
}

describe("fake.png — the mode is decided once, after the profile", () => {
  it("while the profile is pending: a loading state, no fetch, no <img>", () => {
    const fetch = stubText("this is not a png!!")
    const { container } = render(<DatasetFilePreview projectId="p" fileId="f" name="fake.png" kind="image" profilePending />)
    expect(screen.getByTestId("dataset-file-preview-loading")).toBeInTheDocument()
    expect(container.querySelector("img")).toBeNull()
    expect(fetch).not.toHaveBeenCalled()
  })

  it("then the profile says text: the text is fetched once and shown — never an image first", async () => {
    const fetch = stubText("this is not a png!!")
    const { rerender, container } = render(<DatasetFilePreview projectId="p" fileId="f" name="fake.png" kind="image" profilePending />)
    rerender(<DatasetFilePreview projectId="p" fileId="f" name="fake.png" kind="document" format="txt" profilePending={false} />)
    const view = await screen.findByTestId("dataset-text-preview")
    expect(view).toHaveTextContent("this is not a png!!")
    expect(container.querySelector("img")).toBeNull()
    // One signed-URL request, one content request.
    expect(fetch.mock.calls.map((c) => String(c[0]))).toEqual(["/api/projects/p/files/f/url", "https://files.example/fake.png"])
  })

  it("previewMode: pending only for a media name with no profile format yet", () => {
    expect(previewMode("fake.png", "image", undefined, true)).toBe("pending")
    expect(previewMode("scan.tiff", "image", undefined, true)).toBe("pending")
    expect(previewMode("fake.png", "document", "txt", false)).toBe("text")
    expect(previewMode("real.png", "image", "png", false)).toBe("image")
    // A text name is fetched as text straight away (the profile only refines its viewer).
    expect(previewMode("counts.tsv", "table", undefined, true)).toBe("text")
    // No profile coming (another caller): the name decides, as before.
    expect(previewMode("fake.png", "image", undefined, false)).toBe("image")
  })
})
