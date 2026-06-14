/**
 * RTL tests for <WhyAnchor> — the (why?) bioc hover.
 * Covers visibility rules + hover-fetch + citation render.
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { WhyAnchor, type Rationale } from "./why-anchor"

const BULK_NORM_RATIONALE: Rationale = {
  workflow_id: 35,
  phase_id: "B_norm",
  rationale_text:
    "After normalisation, counts + metadata + size factors fold into a single DESeqDataSet.",
  citation: { doi: "10.1186/s13059-014-0550-8", title: "Love MI et al. 2014" },
  qc_gate_name: "deseq2_negative_binomial_fit",
  last_curated_at: 1718360000,
}

describe("<WhyAnchor>", () => {
  it("renders nothing when workflowName is missing", () => {
    const { container } = render(<WhyAnchor workflowName={null} phaseId="A" />)
    expect(container.firstChild).toBeNull()
  })

  it("renders nothing when phaseId is missing", () => {
    const { container } = render(<WhyAnchor workflowName="bulk_rnaseq_consensus_de_bioc" phaseId={null} />)
    expect(container.firstChild).toBeNull()
  })

  it("renders the anchor button when both name + phaseId provided", () => {
    render(
      <WhyAnchor workflowName="bulk_rnaseq_consensus_de_bioc" phaseId="B_norm" />,
    )
    expect(screen.getByTestId("why-anchor-B_norm")).toBeInTheDocument()
    expect(screen.getByText("(why?)")).toBeInTheDocument()
  })

  it("hides itself after lazy fetch returns null (no curated row)", async () => {
    const fetchFn = vi.fn().mockResolvedValue(null)
    const user = userEvent.setup()
    render(
      <WhyAnchor
        workflowName="unknown_chain"
        phaseId="Z"
        fetchFn={fetchFn}
      />,
    )
    const btn = screen.getByTestId("why-anchor-Z")
    await user.click(btn)
    await waitFor(() => expect(fetchFn).toHaveBeenCalledTimes(1))
    await waitFor(() => expect(screen.queryByTestId("why-anchor-Z")).not.toBeInTheDocument())
  })

  it("renders rationale text + clickable DOI on first hover", async () => {
    const fetchFn = vi.fn().mockResolvedValue(BULK_NORM_RATIONALE)
    const user = userEvent.setup()
    render(
      <WhyAnchor
        workflowName="bulk_rnaseq_consensus_de_bioc"
        phaseId="B_norm"
        fetchFn={fetchFn}
      />,
    )
    await user.click(screen.getByTestId("why-anchor-B_norm"))
    await waitFor(() => expect(fetchFn).toHaveBeenCalledTimes(1))
    expect(await screen.findByText(/DESeqDataSet/)).toBeInTheDocument()
    const link = screen.getByRole("link", { name: /Love MI/ })
    expect(link).toHaveAttribute("href", "https://doi.org/10.1186/s13059-014-0550-8")
  })

  it("does not refetch on second open (lazy + cached)", async () => {
    const fetchFn = vi.fn().mockResolvedValue(BULK_NORM_RATIONALE)
    const user = userEvent.setup()
    render(
      <WhyAnchor
        workflowName="bulk_rnaseq_consensus_de_bioc"
        phaseId="B_norm"
        fetchFn={fetchFn}
      />,
    )
    const btn = screen.getByTestId("why-anchor-B_norm")
    await user.click(btn)
    await waitFor(() => expect(fetchFn).toHaveBeenCalledTimes(1))
    // close + reopen
    await user.keyboard("{Escape}")
    await user.click(btn)
    expect(fetchFn).toHaveBeenCalledTimes(1) // no second fetch
  })

  it("accepts a pre-loaded rationale prop and skips fetch", async () => {
    const fetchFn = vi.fn()
    const user = userEvent.setup()
    render(
      <WhyAnchor
        workflowName="bulk_rnaseq_consensus_de_bioc"
        phaseId="B_norm"
        rationale={BULK_NORM_RATIONALE}
        fetchFn={fetchFn}
      />,
    )
    await user.click(screen.getByTestId("why-anchor-B_norm"))
    expect(fetchFn).not.toHaveBeenCalled()
    expect(await screen.findByText(/DESeqDataSet/)).toBeInTheDocument()
  })
})
