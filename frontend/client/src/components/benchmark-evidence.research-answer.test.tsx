import React from "react";
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { ResearchResponseDisplay, type ResearchResponseData } from "./benchmark-evidence";

const base: ResearchResponseData = {
  answer: "Pathway Y is upregulated under treatment X in most reported systems.",
  citations: [{ title: "A study", authors: ["Doe J"], year: 2024, doi: "10.1/x" }],
  confidence: 0.8,
};

// Founder decision (2026-11-10): a research/literature answer renders its
// sources and follow-ups only — no "Boundary:" caveat banner, no "Save to
// project" button, and no "Plan analysis with my data" exit.
describe("ResearchResponseDisplay — no clutter under a research answer", () => {
  it("does not render the Boundary banner, even when the server sends a boundary", () => {
    const withBoundary = { ...base, boundary: "Not evidence for dosing in humans." } as ResearchResponseData;
    const { container } = render(<ResearchResponseDisplay response={withBoundary} />);
    expect(screen.queryByTestId("research-answer-boundary")).toBeNull();
    expect(container.textContent).not.toMatch(/Boundary:/);
    expect(container.textContent).not.toContain("Not evidence for dosing in humans.");
    expect(container.textContent).not.toMatch(/not validated against your project/i);
  });

  it("does not render a Save to project button", () => {
    render(<ResearchResponseDisplay response={base} />);
    expect(screen.queryByTestId("research-answer-save")).toBeNull();
    expect(screen.queryByRole("button", { name: /save to project/i })).toBeNull();
  });

  it("does not render a Plan analysis with my data button", () => {
    render(<ResearchResponseDisplay response={base} />);
    expect(screen.queryByTestId("research-answer-check-data")).toBeNull();
    expect(screen.queryByRole("button", { name: /plan analysis with my data|规划我的数据分析/i })).toBeNull();
  });

  it("still renders follow-up questions", () => {
    render(<ResearchResponseDisplay response={{ ...base, follow_up_questions: ["What about Z?"] }} />);
    expect(screen.getByRole("button", { name: /What about Z\?/ })).toBeInTheDocument();
  });
});
