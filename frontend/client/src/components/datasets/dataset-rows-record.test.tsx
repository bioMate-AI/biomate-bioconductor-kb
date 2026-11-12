/**
 * JSONL nested cells → record view (audit U9, founder screenshot jsonl_noPreview.png).
 *
 * The "list · 11" / "table 4×11" chips were inert spans (no keyboard, no role), and the record
 * opened BELOW the 60vh table box — off-screen. Now each chip is a button that opens the record
 * in a dialog over the table, focused on the field that was clicked.
 */
import { describe, it, expect, afterEach } from "vitest"
import { render, screen, within, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { DatasetRowsTable } from "./dataset-rows-table"

const cell = (v: unknown) => JSON.stringify(v)
const columns = ["source", "drug", "page", "headers", "rows", "meta"]
const record = (page: number) => [
  "epar_table", "pluvicto", String(page),
  cell(["Study identifier", "Phase", "N"]),
  cell([["VISION", "3", "831"], ["PSMAfore", "3", "468"]]),
  cell({ lab: { site: "A" }, doses: [1, 3] }),
]
const props = { columns, rows: [record(30), record(31)], total: 2, loading: false, error: null, onNeedMore: () => {} }

const origScrollIntoView = Element.prototype.scrollIntoView
afterEach(() => { Element.prototype.scrollIntoView = origScrollIntoView })

describe("nested JSONL chips are real controls (U9)", () => {
  it("each chip is a button named by record and field", () => {
    render(<DatasetRowsTable {...props} />)
    const chip = screen.getByRole("button", { name: /Record 2 · rows:/ })
    expect(chip.tagName).toBe("BUTTON")
    expect(chip).toHaveAttribute("data-testid", "dataset-nested-cell")
    expect(chip).toHaveAttribute("aria-haspopup", "dialog")
  })

  it("keyboard: Tab to a chip and press Enter opens that record in a dialog, focused on the field", async () => {
    const scrolled: Element[] = []
    Element.prototype.scrollIntoView = function (this: Element) { scrolled.push(this) }
    const user = userEvent.setup()
    render(<DatasetRowsTable {...props} />)
    const chip = screen.getByRole("button", { name: /Record 2 · meta:/ })
    chip.focus()
    expect(document.activeElement).toBe(chip)
    await user.keyboard("{Enter}")

    // opens where the user is looking: a modal dialog, not a block below the table
    const dialog = await screen.findByRole("dialog")
    const view = within(dialog).getByTestId("dataset-record-view")
    expect(view.textContent).toContain("Record 2")
    expect(screen.getByTestId("dataset-preview-table").contains(view)).toBe(false)

    const field = within(dialog).getByTestId("dataset-record-field-meta")
    expect(field).toHaveAttribute("data-focused", "true")
    await waitFor(() => expect(document.activeElement).toBe(field))
    expect(scrolled).toContain(field)
  })

  it("Space on a table chip focuses the embedded table it belongs to; Esc closes and returns focus", async () => {
    const user = userEvent.setup()
    render(<DatasetRowsTable {...props} />)
    const chip = screen.getByRole("button", { name: /Record 1 · rows:/ })
    chip.focus()
    await user.keyboard(" ")
    const dialog = await screen.findByRole("dialog")
    const table = within(dialog).getByTestId("dataset-record-table")
    expect(table).toHaveAttribute("data-focused", "true")
    expect(table.querySelectorAll("tbody tr")).toHaveLength(2)

    await user.keyboard("{Escape}")
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull())
    expect(screen.queryByTestId("dataset-record-view")).toBeNull()
    await waitFor(() => expect(document.activeElement).toBe(chip))
  })

  it("a mouse click on the chip opens the record once (the row handler does not re-open it unfocused)", async () => {
    const user = userEvent.setup()
    render(<DatasetRowsTable {...props} />)
    await user.click(screen.getByRole("button", { name: /Record 1 · headers:/ }))
    const dialog = await screen.findByRole("dialog")
    // headers feed the embedded table (header list + rows matrix) → that table is the focus
    expect(within(dialog).getByTestId("dataset-record-table")).toHaveAttribute("data-focused", "true")
    expect(screen.getAllByTestId("dataset-record-view")).toHaveLength(1)
  })
})
