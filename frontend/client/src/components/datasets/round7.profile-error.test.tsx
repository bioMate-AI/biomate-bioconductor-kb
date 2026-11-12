/**
 * Audit round 7 (dev 72e21ca3): a profile REQUEST that failed (a 502 from the backend proxy while
 * dev was busy) was shown as "the profiler could not read this dataset" — a claim about the file,
 * with no way to try again. A failed request is not an unreadable file:
 *  - network errors and 502/503/504 are retried (read-only request), 4xx never;
 *  - still failing → "Couldn't reach the profiler" + Try again (refetches);
 *  - 403 → no access; no claim about the file's content.
 * The same holds for the folder profile.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject, type DatasetRef } from "./dataset-object"
import { FolderProfileView } from "./folder-profile-view"

let profileStatuses: number[] = []
let profileCalls = 0
let folderStatuses: number[] = []
let folderCalls = 0
const PROFILE = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["a", "b"], sampleRows: [["1", "2"]], findings: [] }

beforeEach(() => {
  profileStatuses = []; profileCalls = 0; folderStatuses = []; folderCalls = 0
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = new URL(String(input), "http://x")
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    if (url.pathname === "/api/perception/profile") {
      const s = profileStatuses[Math.min(profileCalls++, profileStatuses.length - 1)]
      if (s === 0) throw new TypeError("Failed to fetch")
      return s === 200 ? res(200, PROFILE) : res(s, { error: "DL surface proxy error" })
    }
    if (url.pathname.includes("/folders/profile")) {
      const s = folderStatuses[Math.min(folderCalls++, folderStatuses.length - 1)]
      return res(s, { error: "x" })
    }
    if (url.pathname.endsWith("/versions")) return res(200, { versions: [] })
    return res(200, {})
  }) as unknown as typeof fetch
})

const ds: DatasetRef = { id: "id-a", name: "a.tsv", ref: "projects/p1/inputs/a.tsv", size: 10, source: "upload" }
function renderObj() {
  const client = new QueryClient({ defaultOptions: { queries: { gcTime: 0 } } })
  return render(
    <QueryClientProvider client={client}>
      <DatasetObject projectId="p1" dataset={ds} onRunQC={() => {}} onDownload={() => {}} />
    </QueryClientProvider>,
  )
}
const LONG = { timeout: 6000 }

describe("dataset profile: a failed request is not an unreadable file", () => {
  it("a transient 502 is retried and the profile shows", async () => {
    profileStatuses = [502, 200]
    renderObj()
    await waitFor(() => expect(screen.getByTestId("data-perception")).toBeInTheDocument(), LONG)
    expect(profileCalls).toBe(2)
    expect(screen.queryByTestId("dataset-quality-error")).toBeNull()
  })

  it("still failing (network / 503): 'Couldn't reach the profiler' + Try again, never 'could not read'", async () => {
    profileStatuses = [0, 503, 503, 200]
    renderObj()
    const err = await screen.findByTestId("dataset-quality-error", {}, LONG)
    expect(err).toHaveAttribute("data-reason", "unreachable")
    expect(err).toHaveTextContent("Couldn't reach the profiler")
    expect(err).not.toHaveTextContent(/could not read/i)
    expect(profileCalls).toBe(3) // first try + 2 retries
    fireEvent.click(screen.getByTestId("dataset-quality-retry"))
    await waitFor(() => expect(screen.getByTestId("data-perception")).toBeInTheDocument(), LONG)
  }, 15000)

  it("403: no access, not retried, no claim about the file", async () => {
    profileStatuses = [403]
    renderObj()
    const err = await screen.findByTestId("dataset-quality-error", {}, LONG)
    expect(err).toHaveAttribute("data-reason", "forbidden")
    expect(err).not.toHaveTextContent(/could not read/i)
    expect(screen.queryByTestId("dataset-quality-retry")).toBeNull()
    expect(profileCalls).toBe(1)
  })
})

describe("folder profile: the same rules", () => {
  it("a 502 is retried; still failing → Try again", async () => {
    folderStatuses = [502]
    const client = new QueryClient({ defaultOptions: { queries: { gcTime: 0 } } })
    render(
      <QueryClientProvider client={client}>
        <FolderProfileView projectId="p1" path="inputs" />
      </QueryClientProvider>,
    )
    const err = await screen.findByTestId("folder-profile-error", {}, LONG)
    expect(err).toHaveAttribute("data-reason", "unreachable")
    expect(folderCalls).toBe(3)
    expect(screen.getByTestId("folder-profile-retry")).toBeInTheDocument()
  }, 15000)
})
