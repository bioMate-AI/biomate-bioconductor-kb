/**
 * RTL tests for <TrajectoryView> — decisions / tool calls / answers / notes,
 * with kind filtering. Uses the ported TRAJ fixture.
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { TrajectoryView } from "./trajectory-view"
import { TRAJ_ROWS } from "./gaps-fixtures"

describe("<TrajectoryView>", () => {
  it("renders all rows by default with timing meta", () => {
    render(<TrajectoryView rows={TRAJ_ROWS} />)
    const rows = screen.getByTestId("trajectory-rows")
    // 8 fixture rows, all visible under 'all'.
    expect(rows.querySelectorAll('[data-testid^="trajectory-row-"]').length).toBe(TRAJ_ROWS.length)
    expect(screen.getByText("Routing decision")).toBeInTheDocument()
    expect(screen.getByText("0.4s")).toBeInTheDocument()
    expect(screen.getByText("resolve_project_files")).toBeInTheDocument()
  })

  it("filters to tool calls only", async () => {
    const user = userEvent.setup()
    render(<TrajectoryView rows={TRAJ_ROWS} />)
    await user.click(screen.getByTestId("trajectory-filter-tool"))
    const rows = screen.getByTestId("trajectory-rows")
    const shown = rows.querySelectorAll('[data-testid="trajectory-row-tool"]')
    expect(shown.length).toBe(2)
    expect(rows.querySelectorAll('[data-testid="trajectory-row-route"]').length).toBe(0)
  })

  it("'Decisions' filter also includes gate rows", async () => {
    const user = userEvent.setup()
    render(<TrajectoryView rows={TRAJ_ROWS} />)
    await user.click(screen.getByTestId("trajectory-filter-route"))
    expect(screen.getByText("Routing decision")).toBeInTheDocument()
    expect(screen.getByText("Quality gate halted phase B")).toBeInTheDocument()
    // A tool call must not show.
    expect(screen.queryByText("resolve_project_files")).not.toBeInTheDocument()
  })

  it("shows the two narration notes under 'What it told you'", async () => {
    const user = userEvent.setup()
    render(<TrajectoryView rows={TRAJ_ROWS} />)
    await user.click(screen.getByTestId("trajectory-filter-note"))
    const rows = screen.getByTestId("trajectory-rows")
    expect(rows.querySelectorAll('[data-testid="trajectory-row-note"]').length).toBe(2)
  })

  it("shows an empty state when a filter matches nothing", async () => {
    const user = userEvent.setup()
    render(<TrajectoryView rows={TRAJ_ROWS.filter((r) => r.kind !== "clarify")} />)
    await user.click(screen.getByTestId("trajectory-filter-clarify"))
    expect(screen.getByTestId("trajectory-empty")).toBeInTheDocument()
  })

  it("shows the export link only when onExport is provided", async () => {
    const user = userEvent.setup()
    const onExport = vi.fn()
    const { rerender } = render(<TrajectoryView rows={TRAJ_ROWS} />)
    expect(screen.queryByTestId("trajectory-export")).not.toBeInTheDocument()
    rerender(<TrajectoryView rows={TRAJ_ROWS} onExport={onExport} />)
    await user.click(screen.getByTestId("trajectory-export"))
    expect(onExport).toHaveBeenCalledTimes(1)
  })
})
