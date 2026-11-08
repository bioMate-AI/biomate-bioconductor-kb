/**
 * RTL tests for <SkipDependency> — declared-skippable state + the
 * "can't skip — D depends on it" warning. Uses the ported SKIPDEP fixture.
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { SkipDependency } from "./skip-dependency"
import { SKIPDEP_PHASES } from "./gaps-fixtures"

describe("<SkipDependency>", () => {
  it("renders a row per phase with its declared skip param", () => {
    render(<SkipDependency phases={SKIPDEP_PHASES} />)
    for (const p of SKIPDEP_PHASES) {
      expect(screen.getByTestId(`skip-phase-${p.id}`)).toBeInTheDocument()
    }
    expect(screen.getByText("--skip-qc")).toBeInTheDocument()
  })

  it("phase A is not skippable (blocked) — toggle disabled + dependency warning shown", () => {
    render(<SkipDependency phases={SKIPDEP_PHASES} />)
    expect(screen.getByTestId("skip-toggle-A")).toBeDisabled()
    expect(screen.getByTestId("skip-phase-A")).toHaveAttribute("data-skippable", "false")
    const blocked = screen.getByTestId("skip-blocked-A")
    expect(blocked).toHaveTextContent("Can't skip")
    expect(blocked).toHaveTextContent("B and C depend on it")
  })

  it("a declared-skippable phase can be toggled and reports the skip set", async () => {
    const user = userEvent.setup()
    const onToggle = vi.fn()
    render(<SkipDependency phases={SKIPDEP_PHASES} onToggle={onToggle} />)
    await user.click(screen.getByTestId("skip-toggle-B"))
    expect(onToggle).toHaveBeenLastCalledWith(["B"])
    expect(screen.getByTestId("skip-phase-B")).toHaveAttribute("data-skipped", "true")
    // Toggle off again.
    await user.click(screen.getByTestId("skip-toggle-B"))
    expect(onToggle).toHaveBeenLastCalledWith([])
  })

  it("advisory warning ('D has nothing to work on') appears only once C is skipped", async () => {
    const user = userEvent.setup()
    render(<SkipDependency phases={SKIPDEP_PHASES} />)
    expect(screen.queryByTestId("skip-warn-C")).not.toBeInTheDocument()
    await user.click(screen.getByTestId("skip-toggle-C"))
    const warn = screen.getByTestId("skip-warn-C")
    expect(warn).toHaveTextContent("D has nothing to work on without it")
  })

  it("a blocked phase never enters the skip set even if clicked", async () => {
    const user = userEvent.setup()
    const onToggle = vi.fn()
    render(<SkipDependency phases={SKIPDEP_PHASES} onToggle={onToggle} />)
    await user.click(screen.getByTestId("skip-toggle-A"))
    expect(onToggle).not.toHaveBeenCalled()
    expect(screen.getByTestId("skip-phase-A")).toHaveAttribute("data-skipped", "false")
  })
})
