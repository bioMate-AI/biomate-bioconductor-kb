/**
 * Unit coverage for buildFiguresFromKeyResults — the TS projection that gives the
 * Node (Gemini) findings path illustration figures, matching the Python analyzer.
 * Verifies: qc pair detection, composition grouping, bars fallback, source_file
 * propagation, and the never-fabricate guarantee (no numbers -> no figures).
 */
import { describe, it, expect } from "vitest";
import { buildFiguresFromKeyResults } from "./findings-figures";

describe("buildFiguresFromKeyResults", () => {
  it("returns [] when there are no parseable numbers (never fabricates)", () => {
    expect(buildFiguresFromKeyResults([])).toEqual([]);
    expect(buildFiguresFromKeyResults([{ metric: "Quality", value: "good", interpretation: "ok" }])).toEqual([]);
  });

  it("builds a qc figure from a kept/total pair and carries the shared source_file", () => {
    const figs = buildFiguresFromKeyResults([
      { metric: "Total variants", value: "1,000", source_file: "variants.csv" },
      { metric: "PASS variants", value: "850", source_file: "variants.csv" },
    ]);
    const qc = figs.find(f => f.kind === "qc");
    expect(qc).toBeTruthy();
    expect(qc.kept).toBe(850);
    expect(qc.total).toBe(1000);
    expect(qc.source_file).toBe("variants.csv");
  });

  it("omits source_file when contributing metrics disagree on the source", () => {
    const figs = buildFiguresFromKeyResults([
      { metric: "Total reads", value: "100", source_file: "a.csv" },
      { metric: "Passing reads", value: "80", source_file: "b.csv" },
    ]);
    expect(figs.find(f => f.kind === "qc").source_file).toBeUndefined();
  });

  it("builds a composition figure from metrics sharing a trailing word", () => {
    const figs = buildFiguresFromKeyResults([
      { metric: "HIGH impact", value: "3" },
      { metric: "MODERATE impact", value: "12" },
      { metric: "LOW impact", value: "40" },
    ]);
    const comp = figs.find(f => f.kind === "composition");
    expect(comp).toBeTruthy();
    expect(comp.data.length).toBe(3);
    expect(comp.data).toContainEqual(["HIGH impact", 3]);
  });

  it("falls back to a bars figure for >=2 unrelated numeric metrics", () => {
    const figs = buildFiguresFromKeyResults([
      { metric: "Dispersion estimate", value: "0.21" },
      { metric: "Size factor median", value: "1.04" },
    ]);
    const bars = figs.find(f => f.kind === "bars");
    expect(bars).toBeTruthy();
    expect(bars.data.length).toBe(2);
  });

  it("parses scientific notation and percentages", () => {
    const figs = buildFiguresFromKeyResults([
      { metric: "Adjusted p value", value: "2.3e-5" },
      { metric: "Fraction retained", value: "92%" },
    ]);
    const bars = figs.find(f => f.kind === "bars");
    expect(bars.data).toContainEqual(["Adjusted p value", 0.000023]);
    expect(bars.data).toContainEqual(["Fraction retained", 92]);
  });
});
