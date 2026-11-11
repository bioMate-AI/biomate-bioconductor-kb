/**
 * RTL tests for <DataPerception> — the dataset QC card.
 * Presentational: every field the backend profile carries renders through i18n,
 * the Effective-N hint states the REAL reason, and Watch/Blocked list their reasons.
 */
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { DataPerception } from "./data-perception";
import {
  GOOD_TABLE_PROFILE,
  WATCH_JSONL_PROFILE,
  WATCH_LEAKY_PROFILE,
  BLOCKED_PROFILE,
  LEGACY_PROFILE,
  LEGACY_PLAN_IMPACT,
} from "./data-perception.fixtures";

describe("<DataPerception>", () => {
  it("renders shape + quality verdict from the profile", () => {
    render(<DataPerception profile={GOOD_TABLE_PROFILE} datasetName="counts.tsv" />);
    const panel = screen.getByTestId("data-perception");
    expect(panel).toHaveAttribute("data-quality", "good");
    expect(screen.getByTestId("perception-quality-badge")).toHaveTextContent("Good");
    expect(screen.getByText("18,412")).toBeInTheDocument();
    expect(screen.getByTestId("perception-effective-n")).toHaveTextContent("24");
    expect(screen.getByText("counts.tsv")).toBeInTheDocument();
    // Good: no "why" panel, no reason hint (effective N == rows).
    expect(screen.queryByTestId("perception-why")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-effective-n-hint")).not.toBeInTheDocument();
    expect(screen.getByTestId("perception-notes")).toHaveTextContent(
      "24 rows × 18,412 columns; no leakage, imbalance or constant-column issues detected.",
    );
  });

  it("Effective-N hint names duplicate rows when dedup is the reason (no 'correlation' claim)", () => {
    render(<DataPerception profile={WATCH_JSONL_PROFILE} datasetName="epar_study_tables.jsonl" />);
    const hint = screen.getByTestId("perception-effective-n-hint");
    expect(hint).toHaveTextContent("1 duplicate rows are counted once");
    expect(screen.getByTestId("perception-effective-n").textContent).not.toMatch(/correlation|imbalance/i);
  });

  it("Effective-N hint names class imbalance when imbalance binds", () => {
    render(<DataPerception profile={WATCH_LEAKY_PROFILE} />);
    expect(screen.getByTestId("perception-effective-n-hint")).toHaveTextContent(/smallest class \(class imbalance\)/);
  });

  it("explains WHY the verdict is Watch by listing the triggering signals", () => {
    render(<DataPerception profile={WATCH_JSONL_PROFILE} />);
    const why = screen.getByTestId("perception-why");
    expect(why).toHaveTextContent("Why “Watch”");
    expect(why).toHaveTextContent("1 column(s) are near-constant (over 99% a single value): source.");
    // The reason is not repeated in the signal list below it.
    expect(screen.queryByTestId("perception-signal")).not.toBeInTheDocument();
    expect(screen.getByTestId("perception-notes")).toHaveTextContent("2,281 rows × 5 columns.");
  });

  it("lists leakage + imbalance reasons and a localized plan line", () => {
    render(<DataPerception profile={WATCH_LEAKY_PROFILE} planImpact={[{ observed: "xx-legacy", effect: "yy" }]} />);
    const codes = screen.getAllByTestId("perception-why-item").map((el) => el.getAttribute("data-code"));
    expect(codes).toEqual(["minority_class", "batch_confound", "effective_n_imbalance"]);
    const impact = screen.getByTestId("perception-plan-impact");
    expect(impact).toHaveTextContent("“batch”–label confound");
    expect(impact).toHaveTextContent("add “batch” as a covariate before modelling");
    // structured mode ignores the legacy free-text planImpact prop
    expect(impact).not.toHaveTextContent("xx-legacy");
  });

  it("blocked: shows the blocking reason and fabricates no optional sections", () => {
    render(<DataPerception profile={BLOCKED_PROFILE} />);
    expect(screen.getByTestId("data-perception")).toHaveAttribute("data-quality", "blocked");
    expect(screen.getByTestId("perception-why")).toHaveTextContent("No columns could be parsed from the table.");
    expect(screen.queryByTestId("perception-leakage")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-effective-n")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-class-balance")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-plan-impact")).not.toBeInTheDocument();
  });

  it("has no backend-profiler footer", () => {
    render(<DataPerception profile={GOOD_TABLE_PROFILE} />);
    expect(screen.queryByText(/backend profiler/i)).not.toBeInTheDocument();
  });

  it("falls back to free text only for a legacy profile without findings", () => {
    render(<DataPerception profile={LEGACY_PROFILE} planImpact={LEGACY_PLAN_IMPACT} />);
    expect(screen.getByTestId("perception-notes")).toHaveTextContent(/Single-end reads detected/);
    expect(screen.getByTestId("perception-plan-impact")).toHaveTextContent("suggested single-end pipeline");
  });

  it("an unknown finding code renders as its code, never as untranslated prose", () => {
    render(
      <DataPerception
        profile={{ ...GOOD_TABLE_PROFILE, findings: [{ section: "note", code: "future_code", level: "info" }] }}
      />,
    );
    expect(screen.getByTestId("perception-notes")).toHaveTextContent("future_code");
  });
});
