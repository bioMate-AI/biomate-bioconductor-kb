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
    // Effective N equal to the row count says nothing the row count does not: not shown.
    expect(screen.queryByTestId("perception-effective-n")).not.toBeInTheDocument();
    expect(screen.getByText("counts.tsv")).toBeInTheDocument();
    // Good: no "why" panel, no reason hint (effective N == rows).
    expect(screen.queryByTestId("perception-why")).not.toBeInTheDocument();
    expect(screen.queryByTestId("perception-effective-n-hint")).not.toBeInTheDocument();
    expect(screen.getByTestId("perception-notes")).toHaveTextContent(
      "Rows: 24 · columns: 18,412; groups are balanced, no column gives the group away, and no column is constant.",
    );
  });

  it("Effective-N hint names duplicate rows when dedup is the reason (no 'correlation' claim)", () => {
    render(<DataPerception profile={{ ...WATCH_JSONL_PROFILE, labelColumn: "drug" }} datasetName="epar_study_tables.jsonl" />);
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
    expect(why).toHaveTextContent("Near-constant columns (over 99% a single value): source.");
    // The reason is not repeated in the signal list below it.
    expect(screen.queryByTestId("perception-signal")).not.toBeInTheDocument();
    expect(screen.getByTestId("perception-notes")).toHaveTextContent("Rows: 2,281 · columns: 5.");
  });

  it("lists leakage + imbalance reasons and a localized plan line", () => {
    render(<DataPerception profile={WATCH_LEAKY_PROFILE} planImpact={[{ observed: "xx-legacy", effect: "yy" }]} />);
    const codes = screen.getAllByTestId("perception-why-item").map((el) => el.getAttribute("data-code"));
    expect(codes).toEqual(["minority_class", "batch_confound", "effective_n_imbalance"]);
    const impact = screen.getByTestId("perception-plan-impact");
    expect(impact).toHaveTextContent("“batch” overlaps with the groups");
    expect(impact).toHaveTextContent("include “batch” in the design (e.g. as a covariate) for differential analysis");
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

describe("<DataPerception> — stats per data kind (U2) and copy", () => {
  it("FASTQ shows Reads + Read length from its findings, never Rows/Columns", () => {
    render(<DataPerception datasetName="S1_R1.fastq.gz" profile={{
      shape: { rows: 10000, cols: 151 }, quality: "good", notes: [],
      findings: [{ section: "signal", code: "fastq_reads", level: "info", params: { reads: 10000, at_least: true, mean_len: 151 } }],
    }} />);
    expect(screen.getByTestId("perception-stat-reads")).toHaveTextContent("10,000");
    expect(screen.getByTestId("perception-stat-read_length")).toHaveTextContent("151");
    expect(screen.queryByTestId("perception-stat-rows")).toBeNull();
    // "at least", never a bare "≥" glued to the label.
    const panel = screen.getByTestId("data-perception");
    expect(panel).toHaveTextContent("Reads scanned: at least 10,000");
    expect(panel.textContent).not.toContain("≥");
  });

  it("an image shows no shape stats at all (not '0 rows, 0 columns')", () => {
    render(<DataPerception datasetName="plot.png" kind="image" profile={{
      shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [],
      findings: [{ section: "note", code: "format_identified", level: "info", params: { format: "PNG", size: "1 KB" } }],
    }} />);
    const panel = screen.getByTestId("data-perception");
    expect(panel.querySelectorAll("[data-testid^='perception-stat-']")).toHaveLength(0);
    expect(panel).not.toHaveTextContent(/Rows|Columns/);
    expect(screen.getByTestId("perception-quality-badge")).toHaveTextContent("Not checked");
  });

  it("renders backend stats with their localized labels", () => {
    render(<DataPerception datasetName="calls.vcf" profile={{
      shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "variants",
      stats: [{ code: "variants", value: 1234 }, { code: "samples", value: 3 }],
    }} />);
    expect(screen.getByTestId("perception-stat-variants")).toHaveTextContent("Variants");
    expect(screen.getByTestId("perception-stat-variants")).toHaveTextContent("1,234");
    expect(screen.getByTestId("perception-stat-samples")).toHaveTextContent("3");
  });

  it("Effective N and leakage carry a plain-language gloss", () => {
    render(<DataPerception profile={WATCH_LEAKY_PROFILE} datasetName="leaky.csv" />);
    expect(screen.getByTestId("perception-stat-gloss").getAttribute("title")).toMatch(/independent samples/);
  });

  it("a name/content mismatch finding is explained, not shown as a code", () => {
    render(<DataPerception datasetName="broken.png" profile={{
      shape: { rows: 0, cols: 0 }, quality: "watch", notes: [],
      findings: [{ section: "note", code: "name_content_mismatch", level: "watch", params: { named: "PNG", detected: "plain text" } }],
    }} />);
    expect(screen.getByTestId("perception-why")).toHaveTextContent("Named as PNG, but the content is plain text");
  });
});

describe("<DataPerception> — e2e contract: every rendered finding carries its code", () => {
  it("signal / note / leakage / plan lines are perception-finding[data-code]; why items keep their own testid", () => {
    render(<DataPerception datasetName="t.csv" profile={{
      shape: { rows: 10, cols: 3 }, quality: "watch", notes: [], labelColumn: "label",
      findings: [
        { section: "note", code: "ragged_rows", level: "watch", params: { count: 2, expected: 3 } },
        { section: "signal", code: "table_summary", level: "info", params: { rows: 10, cols: 3 } },
        { section: "note", code: "comment_lines_skipped", level: "info", params: { count: 4 } },
        { section: "leakage", code: "leaked_id", level: "info", params: { column: "id" } },
        { section: "plan", code: "drop_leaky_column", level: "info", params: { column: "id" } },
      ],
    }} />);
    const codes = Array.from(document.querySelectorAll("[data-testid=perception-finding]")).map((e) => e.getAttribute("data-code"));
    expect(codes.sort()).toEqual(["comment_lines_skipped", "drop_leaky_column", "leaked_id", "table_summary"]);
    expect(screen.getByTestId("perception-why-item")).toHaveAttribute("data-code", "ragged_rows");
    expect(screen.getByTestId("perception-why")).toHaveTextContent("Rows whose number of fields differs from the header's (3): 2.");
  });

  it("a backend 'at least' stat reads 'at least N' (QC card)", () => {
    render(<DataPerception datasetName="x.fa" profile={{
      shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "sequences",
      stats: [{ code: "sequences", value: 5000, atLeast: true }, { code: "bases", value: 1200000 }],
    }} />);
    expect(screen.getByTestId("perception-stat-sequences")).toHaveTextContent("at least 5,000");
    expect(screen.getByTestId("perception-stat-sequences")).toHaveAttribute("data-stat", "sequences");
    expect(screen.getByTestId("perception-stat-bases").textContent).not.toContain("at least");
  });

  it("fasta_sequences with at_least qualifies the sequence count, not a prefix glued to the label", () => {
    render(<DataPerception datasetName="x.fa" profile={{
      shape: { rows: 0, cols: 0 }, quality: "good", notes: [],
      findings: [{ section: "signal", code: "fasta_sequences", level: "info",
        params: { sequences: 5000, at_least: true, total: 10, unit: "Mb", mean: 2, min: 1, max: 3, n50: 2 } }],
    }} />);
    expect(screen.getByTestId("perception-signal")).toHaveTextContent("Sequences: at least 5,000; 10 Mb in total");
  });
});
