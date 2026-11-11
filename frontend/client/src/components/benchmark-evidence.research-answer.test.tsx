import React from "react";
import { describe, it, expect, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { ResearchResponseDisplay, toEvidenceCitations, type ResearchResponseData } from "./benchmark-evidence";

const base: ResearchResponseData = {
  answer: "Pathway Y is upregulated under treatment X in most reported systems.",
  citations: [{ title: "A study", authors: ["Doe J"], year: 2024, journal: "Cell", doi: "10.1/x" }],
  confidence: 0.8,
};

describe("ResearchResponseDisplay — research answer under the chat reply", () => {
  it("renders NO boundary banner, even when the response supplies one (founder review 2026-11-10)", () => {
    render(<ResearchResponseDisplay response={{ ...base, boundary: "Not evidence for dosing in humans." }} />);
    expect(screen.queryByTestId("research-answer-boundary")).toBeNull();
    expect(screen.queryByText(/Boundary:/)).toBeNull();
    expect(screen.queryByText(/not validated against your project/i)).toBeNull();
    expect(screen.queryByText("Not evidence for dosing in humans.")).toBeNull();
  });

  it("has NO second button row: no 'Save to project' and no 'Plan analysis with my data' (founder review 2026-11-10)", () => {
    render(<ResearchResponseDisplay response={base} onFollowUpClick={vi.fn()} />);
    expect(screen.queryByTestId("research-answer-save")).toBeNull();
    expect(screen.queryByTestId("research-answer-check-data")).toBeNull();
    expect(screen.queryByText(/save to project/i)).toBeNull();
    expect(screen.queryByText(/plan analysis/i)).toBeNull();
    expect(screen.queryByText(/规划我的数据分析/)).toBeNull();
  });

  it("collapses the sources by default to one quiet 'N sources' line", () => {
    render(<ResearchResponseDisplay response={base} />);
    const toggle = screen.getByTestId("citations-toggle");
    expect(toggle).toHaveTextContent("1 sources");
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByTestId("reference-list")).toBeNull();
    fireEvent.click(toggle);
    expect(screen.getByTestId("reference-list")).toHaveTextContent("A study · Cell · 2024");
  });

  it("follow-up questions fire the handler (pre-fill), and are hidden when there is no handler", () => {
    const withFollowUps = { ...base, follow_up_questions: ["What about Z?"] };
    const { rerender } = render(<ResearchResponseDisplay response={withFollowUps} />);
    expect(screen.queryByTestId("research-follow-ups")).toBeNull();
    const onFollow = vi.fn();
    rerender(<ResearchResponseDisplay response={withFollowUps} onFollowUpClick={onFollow} />);
    fireEvent.click(screen.getByText("What about Z?"));
    expect(onFollow).toHaveBeenCalledWith("What about Z?");
  });

  it("toEvidenceCitations carries every id the reader needs (doi, pmid, pmcid, url)", () => {
    const [c] = toEvidenceCitations([{ title: "T", doi: "10.1/x", pmid: "123", pmcid: "PMC9", url: "https://x.org/a", abstract: "abs" }]);
    expect(c).toMatchObject({ doi: "10.1/x", pmid: "123", pmcid: "PMC9", url: "https://x.org/a", abstract: "abs", title: "T" });
  });
});
