import { describe, it, expect } from "vitest"
import { render, screen } from "@testing-library/react"
import { ProposalRankingNotice } from "./drug-discovery-auto-retrain"

const discrimination = {
  can_discriminate: false,
  max_pairwise_order_probability: 0.6811,
  threshold: 0.95,
  reason: "no candidate pair is ordered with P >= 0.95",
}

describe("ProposalRankingNotice", () => {
  it("says the proposal cannot be ranked when the surrogate cannot discriminate", () => {
    render(<ProposalRankingNotice canDiscriminate={false} nTrain={3} discrimination={discrimination} />)
    const notice = screen.getByTestId("proposal-cannot-rank")
    expect(notice.textContent).toMatch(/Too few data to rank/)
    expect(notice.textContent).toMatch(/best pairwise confidence 68%/)
    expect(notice.textContent).toMatch(/trained on 3 measured compounds/)
  })

  it("renders nothing when candidates are discriminated or the flag predates recording", () => {
    const { container: a } = render(<ProposalRankingNotice canDiscriminate={true} />)
    const { container: b } = render(<ProposalRankingNotice canDiscriminate={null} />)
    const { container: c } = render(<ProposalRankingNotice />)
    expect(a.innerHTML + b.innerHTML + c.innerHTML).toBe("")
  })
})
