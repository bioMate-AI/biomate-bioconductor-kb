/**
 * RTL tests for <DataPerception> (gap 9 perception-at-ingest read surface).
 * Pure presentational: assert every prop-driven field renders, and that
 * absent optional fields render nothing (no fabrication).
 */
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { DataPerception } from "./data-perception";
import {
  GOOD_RNASEQ_PROFILE,
  GOOD_RNASEQ_PLAN_IMPACT,
  WATCH_LEAKY_PROFILE,
  WATCH_LEAKY_PLAN_IMPACT,
  BLOCKED_PROFILE,
} from "./data-perception.fixtures";

describe("<DataPerception>", () => {
  it("renders shape + quality verdict from the profile", () => {
    render(<DataPerception profile={GOOD_RNASEQ_PROFILE} datasetName="counts.tsv" />);
    const panel = screen.getByTestId("data-perception");
    expect(panel).toHaveAttribute("data-quality", "good");
    expect(screen.getByTestId("perception-quality-badge")).toHaveTextContent("Good");
    // Rows=24 and Effective N=24 both render "24"; scope to the columns count.
    expect(screen.getByText("18,412")).toBeInTheDocument();
    expect(screen.getAllByText("24").length).toBeGreaterThanOrEqual(1);
    expect(screen.getByTestId("perception-effective-n")).toHaveTextContent("24");
    expect(screen.getByText("counts.tsv")).toBeInTheDocument();
  });

  it("renders class balance, signal summary, and notes", () => {
    render(<DataPerception profile={GOOD_RNASEQ_PROFILE} />);
    expect(screen.getByTestId("perception-class-balance")).toBeInTheDocument();
    expect(screen.getByText("control")).toBeInTheDocument();
    expect(screen.getByText("treated")).toBeInTheDocument();
    expect(screen.getByTestId("perception-signal")).toHaveTextContent(/PC1 42% variance/);
    expect(screen.getByTestId("perception-notes")).toHaveTextContent(/Single-end reads detected/);
  });

  it("renders the 'how it shaped the plan' lines when planImpact is given", () => {
    render(
      <DataPerception profile={GOOD_RNASEQ_PROFILE} planImpact={GOOD_RNASEQ_PLAN_IMPACT} />,
    );
    const impact = screen.getByTestId("perception-plan-impact");
    expect(impact).toHaveTextContent("single-end detected");
    expect(impact).toHaveTextContent("suggested single-end pipeline");
  });

  it("surfaces a leakage finding and effective-N discount on a watch profile", () => {
    render(<DataPerception profile={WATCH_LEAKY_PROFILE} planImpact={WATCH_LEAKY_PLAN_IMPACT} />);
    expect(screen.getByTestId("data-perception")).toHaveAttribute("data-quality", "watch");
    expect(screen.getByTestId("perception-leakage")).toHaveTextContent(
      /processing batch is perfectly correlated/,
    );
    const effN = screen.getByTestId("perception-effective-n");
    expect(effN).toHaveTextContent("41");
    // effectiveN (41) < rows (300) → discount hint shown
    expect(effN).toHaveTextContent(/discounted it/);
  });

  it("does not fabricate optional sections when the profile omits them", () => {
    render(<DataPerception profile={BLOCKED_PROFILE} />);
    expect(screen.getByTestId("data-perception")).toHaveAttribute("data-quality", "blocked");
    expect(screen.queryByTestId("perception-leakage")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-effective-n")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-class-balance")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-signal")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-plan-impact")).not.toBeInTheDocument();
    // notes are always present on this fixture
    expect(screen.getByTestId("perception-notes")).toHaveTextContent(/0 rows/);
  });

  it("notes the backend profiler produces the data (read surface)", () => {
    render(<DataPerception profile={GOOD_RNASEQ_PROFILE} />);
    expect(screen.getByText(/backend profiler/i)).toBeInTheDocument();
  });
});
