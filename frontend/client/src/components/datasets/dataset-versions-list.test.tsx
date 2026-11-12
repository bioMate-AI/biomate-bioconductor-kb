/**
 * Versions tab rows (audit R13, client side; live evidence: "v1 — fd5a73ac-87df-…", Compare "r2 · dose"
 * for the third data row).
 *
 * - the author is the server's display name; a raw user id is never printed;
 * - an automatic note that only repeats the label ("v1") is not shown;
 * - each version shows its own time;
 * - Compare numbers changed rows from 1 (the diff API reports a 0-based data-row index).
 */
import { describe, it, expect } from "vitest"
import { render, screen, fireEvent } from "@testing-library/react"
import { DatasetVersionsList, authorLabel, diffRowNumber, type VersionRow } from "./dataset-versions-list"

const UID = "fd5a73ac-87df-4850-b8ff-6d768c1b47fb"
const base = {
  usedByCount: 0, versionable: true, error: null, diffFor: null, diffData: null, diffLoading: false,
  restoringVersion: null, onCompare: () => {}, onRestore: () => {},
}

describe("DatasetVersionsList", () => {
  it("shows the author's display name and never a raw user id", () => {
    const versions: VersionRow[] = [
      { version: "3", label: "v3", current: true, createdAt: "2026-11-12T05:36:04Z", note: null, author: null },
      { version: "2", label: "v2", current: false, createdAt: "2026-11-12T05:31:00Z", note: "v2", author: UID, authorName: "Ada Lovelace" },
      { version: "1", label: "v1", current: false, createdAt: "2026-11-12T05:29:01Z", note: "v1", author: UID },
    ]
    render(<DatasetVersionsList {...base} versions={versions} />)
    expect(document.body.textContent).not.toContain(UID)
    expect(document.body.textContent).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-/)
    expect(screen.getByTestId("dataset-version-author-2")).toHaveTextContent("Ada Lovelace")
    // id only, no display name → no author line; the auto note "v1" is not repeated either
    expect(screen.queryByTestId("dataset-version-author-1")).toBeNull()
    expect(screen.queryByTestId("dataset-version-meta-1")).toBeNull()
  })

  it("each version shows its own time", () => {
    const versions: VersionRow[] = [
      { version: "2", label: "v2", current: true, createdAt: "2026-11-12T05:36:04Z" },
      { version: "1", label: "v1", current: false, createdAt: "2026-11-12T05:29:01Z" },
    ]
    render(<DatasetVersionsList {...base} versions={versions} />)
    const t2 = screen.getByTestId("dataset-version-time-2").textContent
    const t1 = screen.getByTestId("dataset-version-time-1").textContent
    expect(t2).toBe(new Date("2026-11-12T05:36:04Z").toLocaleString("en-US"))
    expect(t1).toBe(new Date("2026-11-12T05:29:01Z").toLocaleString("en-US"))
  })

  it("a user-written note is kept, with the author", () => {
    render(<DatasetVersionsList {...base} versions={[
      { version: "1", label: "v1", current: false, createdAt: null, note: "re-derived after QC fix", author: "Grace Hopper" },
    ]} />)
    expect(screen.getByTestId("dataset-version-meta-1")).toHaveTextContent("re-derived after QC fix")
    expect(screen.getByTestId("dataset-version-author-1")).toHaveTextContent("Grace Hopper")
  })

  it("Compare numbers changed rows from 1", () => {
    const calls: string[] = []
    render(<DatasetVersionsList
      {...base}
      onCompare={(v) => calls.push(v)}
      diffFor="1"
      diffData={{ changedCells: [{ row: 2, col: "dose", from: "50", to: "75" }, { row: 0, col: "note", from: "", to: "x" }] }}
      versions={[
        { version: "2", label: "v2", current: true, createdAt: null },
        { version: "1", label: "v1", current: false, createdAt: null },
      ]}
    />)
    const where = screen.getAllByTestId("dataset-diff-cell-where").map((e) => e.textContent)
    expect(where[0]).toMatch(/Row 3 · dose/)
    expect(where[1]).toMatch(/Row 1 · note/)
    expect(screen.getAllByTestId("dataset-diff-cell")[1]).toHaveTextContent("(empty)")
    fireEvent.click(screen.getByTestId("dataset-version-compare-1"))
    expect(calls).toEqual(["1"])
  })

  it("helpers: ids are not names; a server-sent 1-based rowNumber is used as is", () => {
    expect(authorLabel({ author: UID })).toBeNull()
    expect(authorLabel({ author: "42" })).toBeNull()
    expect(authorLabel({ author: UID, authorName: "  " })).toBeNull()
    expect(authorLabel({ author: UID, authorName: "Ada" })).toBe("Ada")
    expect(diffRowNumber({ row: 0 })).toBe(1)
    expect(diffRowNumber({ row: 0, rowNumber: 7 })).toBe(7)
  })
})
