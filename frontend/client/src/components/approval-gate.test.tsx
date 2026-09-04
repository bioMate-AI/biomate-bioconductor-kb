/**
 * RTL tests for <ApprovalGate> — human approval in measured·threshold·verdict
 * grammar. Uses the ported APPROVAL fixture.
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { ApprovalGate, type ApprovalRecord } from "./approval-gate"
import { APPROVAL_DATA } from "./gaps-fixtures"

describe("<ApprovalGate>", () => {
  it("renders what / why / cost and every measured row", () => {
    render(<ApprovalGate data={APPROVAL_DATA} onResolve={() => {}} />)
    expect(screen.getByText("Write this run's outputs into the project record")).toBeInTheDocument()
    expect(screen.getByText(/Phase D publishes counts.tsv v4/)).toBeInTheDocument()
    expect(screen.getByText(/reversible for 24 h/)).toBeInTheDocument()
    for (const m of APPROVAL_DATA.measured) {
      expect(screen.getByTestId(`approval-measured-${m.key}`)).toBeInTheDocument()
    }
  })

  it("renders the correct verdict chips (needs approval vs pass)", () => {
    render(<ApprovalGate data={APPROVAL_DATA} onResolve={() => {}} />)
    expect(screen.getByTestId("verdict-needs approval")).toBeInTheDocument()
    expect(screen.getAllByTestId("verdict-pass").length).toBe(2)
  })

  it("shows who / policy", () => {
    render(<ApprovalGate data={APPROVAL_DATA} onResolve={() => {}} />)
    expect(screen.getByText(/you own this project/)).toBeInTheDocument()
    expect(screen.getByText(/requires an owner/)).toBeInTheDocument()
  })

  it("records who / when / decision / reason on approve", async () => {
    const user = userEvent.setup()
    const onResolve = vi.fn<[ApprovalRecord], void>()
    render(<ApprovalGate data={APPROVAL_DATA} onResolve={onResolve} actor="lifeifei" />)
    await user.click(screen.getByTestId("approval-approve"))
    const rec = onResolve.mock.calls[0][0]
    expect(rec.decision).toBe("approve")
    expect(rec.who).toBe("lifeifei")
    expect(rec.reason).toBe(APPROVAL_DATA.why)
    expect(rec.at).toBeInstanceOf(Date)
  })

  it("records deny and delegate decisions", async () => {
    const user = userEvent.setup()
    const onResolve = vi.fn<[ApprovalRecord], void>()
    render(<ApprovalGate data={APPROVAL_DATA} onResolve={onResolve} />)
    await user.click(screen.getByTestId("approval-deny"))
    expect(onResolve.mock.calls[0][0].decision).toBe("deny")
    await user.click(screen.getByTestId("approval-delegate"))
    expect(onResolve.mock.calls[1][0].decision).toBe("delegate")
  })
})
