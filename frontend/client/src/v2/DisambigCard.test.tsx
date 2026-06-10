/**
 * v2/DisambigCard — RTL coverage for the production-quality TS port of the
 * Bioconductor handoff §3.5 disambiguation card.
 *
 * Covers the design surfaces the v1 WorkflowDisambiguationCard was missing:
 *   - Score column rendered right-aligned monospace
 *   - "recommended" badge on the highest-score option
 *   - Optional detail line under sub
 *   - Optional countdown auto-select after N seconds
 *   - Manual Select clicks during a countdown cancel the auto-select
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, act } from "@testing-library/react";
import { DisambigCard, type DisambigOption } from "./DisambigCard";

const OPTIONS: DisambigOption[] = [
  {
    id: "bulk_rnaseq_de_analysis",
    label: "Standard DE Analysis",
    sub: "6 steps · starts from a count matrix",
    detail: "DESeq2 → apeglm → clusterProfiler → EnhancedVolcano",
    score: "0.71",
    badge: "top match",
    recommended: true,
  },
  {
    id: "bp4_rnaseq_best_practices_pipeline",
    label: "Best-Practices Pipeline (BP4)",
    sub: "9 steps · starts from raw FASTQ",
    detail: "STAR → featureCounts → DESeq2 → fgsea",
    score: "0.66",
    badge: "fuller run",
  },
];

beforeEach(() => {
  vi.useFakeTimers();
});
afterEach(() => {
  vi.useRealTimers();
});

describe("v2/DisambigCard", () => {
  it("renders prompt + both options with score / badge / detail", () => {
    const onSelect = vi.fn();
    render(<DisambigCard prompt="Two workflows matched." options={OPTIONS} onSelect={onSelect} />);
    expect(screen.getByTestId("disambig-card")).toBeInTheDocument();
    expect(screen.getByText("Two workflows matched.")).toBeInTheDocument();
    // both options present
    expect(screen.getByTestId("disambig-option-bulk_rnaseq_de_analysis")).toBeInTheDocument();
    expect(screen.getByTestId("disambig-option-bp4_rnaseq_best_practices_pipeline")).toBeInTheDocument();
    // scores
    expect(screen.getByTestId("disambig-score-bulk_rnaseq_de_analysis")).toHaveTextContent("0.71");
    expect(screen.getByTestId("disambig-score-bp4_rnaseq_best_practices_pipeline")).toHaveTextContent("0.66");
    // badges
    expect(screen.getByTestId("disambig-badge-bulk_rnaseq_de_analysis")).toHaveTextContent("top match");
    expect(screen.getByTestId("disambig-badge-bp4_rnaseq_best_practices_pipeline")).toHaveTextContent("fuller run");
    // detail rows
    expect(screen.getByText(/DESeq2 → apeglm/)).toBeInTheDocument();
    expect(screen.getByText(/STAR → featureCounts/)).toBeInTheDocument();
  });

  it("renders a default prompt when none provided", () => {
    render(<DisambigCard options={OPTIONS} onSelect={() => {}} />);
    expect(screen.getByText(/Multiple workflows matched your request/)).toBeInTheDocument();
  });

  it("calls onSelect with the clicked option when a Select button is clicked", () => {
    const onSelect = vi.fn();
    render(<DisambigCard options={OPTIONS} onSelect={onSelect} />);
    fireEvent.click(screen.getByTestId("disambig-select-bp4_rnaseq_best_practices_pipeline"));
    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect.mock.calls[0][0].id).toBe("bp4_rnaseq_best_practices_pipeline");
  });

  it("does NOT show countdown footer when countdownSeconds is omitted", () => {
    render(<DisambigCard options={OPTIONS} onSelect={() => {}} />);
    expect(screen.queryByTestId("disambig-countdown-ring")).toBeNull();
    expect(screen.getByTestId("disambig-footer")).toHaveTextContent(/ranked by KB match score/);
  });

  it("shows countdown footer + ring when countdownSeconds is set", () => {
    render(<DisambigCard options={OPTIONS} onSelect={() => {}} countdownSeconds={10} />);
    expect(screen.getByTestId("disambig-countdown-ring")).toBeInTheDocument();
    expect(screen.getByTestId("disambig-footer")).toHaveTextContent(/Defaults to .* in 10s/);
  });

  it("auto-selects the recommended option after the countdown elapses", () => {
    const onSelect = vi.fn();
    render(<DisambigCard options={OPTIONS} onSelect={onSelect} countdownSeconds={3} />);
    expect(onSelect).not.toHaveBeenCalled();
    // tick 3 seconds
    act(() => { vi.advanceTimersByTime(3000); });
    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect.mock.calls[0][0].id).toBe("bulk_rnaseq_de_analysis"); // the recommended one
  });

  it("manual Select during countdown cancels the auto-select (no double-fire)", () => {
    const onSelect = vi.fn();
    render(<DisambigCard options={OPTIONS} onSelect={onSelect} countdownSeconds={10} />);
    // click the non-recommended option mid-countdown
    fireEvent.click(screen.getByTestId("disambig-select-bp4_rnaseq_best_practices_pipeline"));
    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect.mock.calls[0][0].id).toBe("bp4_rnaseq_best_practices_pipeline");
    // run out the countdown — should NOT fire again
    act(() => { vi.advanceTimersByTime(15_000); });
    expect(onSelect).toHaveBeenCalledTimes(1);
  });

  it("falls back to options[0] when no option is marked recommended", () => {
    const noRec: DisambigOption[] = OPTIONS.map(o => ({ ...o, recommended: false }));
    const onSelect = vi.fn();
    render(<DisambigCard options={noRec} onSelect={onSelect} countdownSeconds={2} />);
    act(() => { vi.advanceTimersByTime(2000); });
    expect(onSelect).toHaveBeenCalledTimes(1);
    expect(onSelect.mock.calls[0][0].id).toBe("bulk_rnaseq_de_analysis"); // first option
  });
});
