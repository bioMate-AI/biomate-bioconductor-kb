import React from "react";
import { describe, it, expect, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { ResearchResponseDisplay, type ResearchResponseData } from "./benchmark-evidence";

const base: ResearchResponseData = {
  answer: "Pathway Y is upregulated under treatment X in most reported systems.",
  citations: [{ title: "A study", authors: ["Doe J"], year: 2024, doi: "10.1/x" }],
  confidence: 0.8,
};

describe("ResearchResponseDisplay — evidence answer as an object (L1)", () => {
  it("ALWAYS renders a boundary, even when the response supplies none", () => {
    render(<ResearchResponseDisplay response={base} />);
    const b = screen.getByTestId("research-answer-boundary");
    expect(b).toBeInTheDocument();
    // Falls back to an honest standing caveat, not an empty element.
    expect(b.textContent).toMatch(/not validated against your project/i);
  });

  it("shows the response's specific boundary when provided", () => {
    render(<ResearchResponseDisplay response={{ ...base, boundary: "Not evidence for dosing in humans." }} />);
    expect(screen.getByTestId("research-answer-boundary").textContent).toContain("Not evidence for dosing in humans.");
  });

  it("offers Save to project, disabled when there is no active project", () => {
    render(<ResearchResponseDisplay response={base} />);
    const save = screen.getByTestId("research-answer-save");
    expect(save).toBeInTheDocument();
    // No ActiveProjectProvider in the test → useActiveProjectIdSafe() is null →
    // the save is honestly disabled rather than silently no-op.
    expect(save).toBeDisabled();
  });

  it('only renders "Check against our data" when a handler is supplied, and fires it with the answer', () => {
    const { rerender } = render(<ResearchResponseDisplay response={base} />);
    expect(screen.queryByTestId("research-answer-check-data")).toBeNull();

    const onCheck = vi.fn();
    rerender(<ResearchResponseDisplay response={base} onCheckAgainstData={onCheck} />);
    const btn = screen.getByTestId("research-answer-check-data");
    fireEvent.click(btn);
    expect(onCheck).toHaveBeenCalledWith(base.answer);
  });
});
