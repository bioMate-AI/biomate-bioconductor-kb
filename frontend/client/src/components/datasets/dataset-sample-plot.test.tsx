import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { DatasetSamplePlot, numericColumnIndices, hasNumericColumns, histogramBins } from "./dataset-sample-plot";

const COLS = ["gene", "count", "pvalue"];
const ROWS = [
  ["ACTB", "2003", "0.01"],
  ["B2M", "540", "0.2"],
  ["C3", "1151", "0.004"],
  ["C1QA", "147", "0.9"],
];

describe("dataset-sample-plot helpers", () => {
  it("detects numeric columns from the sample, skips the label column", () => {
    const idx = numericColumnIndices(COLS, ROWS);
    expect(idx).toEqual([1, 2]); // count, pvalue — not the gene names
    expect(hasNumericColumns(COLS, ROWS)).toBe(true);
  });

  it("reports no numeric columns for a text-only sample", () => {
    const idx = numericColumnIndices(["a", "b"], [["x", "y"], ["p", "q"]]);
    expect(idx).toEqual([]);
    expect(hasNumericColumns(["a", "b"], [["x", "y"], ["p", "q"]])).toBe(false);
  });
});

describe("DatasetSamplePlot render", () => {
  it("renders the plot container when a numeric column exists", () => {
    const { queryByTestId } = render(<DatasetSamplePlot columns={COLS} sampleRows={ROWS} />);
    expect(queryByTestId("dataset-sample-plot")).not.toBeNull();
  });

  it("renders nothing (caller shows fallback) when no numeric columns", () => {
    const { container } = render(
      <DatasetSamplePlot columns={["a", "b"]} sampleRows={[["x", "y"], ["p", "q"]]} />,
    );
    expect(container.firstChild).toBeNull();
  });
});

describe("histogram axis labels are human numbers (U7)", () => {
  // The founder's sample: values ~1,840–2,160 rendered as "1.84e+3 … 2.16e+3".
  const vals = Array.from({ length: 500 }, (_, i) => 1840 + ((i * 37) % 321))

  it("never scientific notation; thousands separators; nice aligned edges", () => {
    const bins = histogramBins(vals, 12, "en-US")
    for (const b of bins) expect(b.bin).not.toMatch(/e[+-]/i)
    expect(bins[0].bin).toBe("1,800")
    expect(bins[1].bin).toBe("1,850")
    expect(bins.reduce((n, b) => n + b.count, 0)).toBe(500)
  })

  it("every bin has a range label in the same format", () => {
    const bins = histogramBins(vals, 12, "en-US")
    expect(bins[0].range).toBe("1,800 – 1,850")
  })

  it("consistent precision for small values (every tick has the same decimals)", () => {
    const bins = histogramBins([0.01, 0.2, 0.004, 0.9, 0.33, 0.5], 12, "en-US")
    const decimals = new Set(bins.map((b) => (b.bin.split(".")[1] ?? "").length))
    expect(decimals.size).toBe(1)
    expect(bins[0].bin).toBe("0.0")
    expect(bins[1].bin).toBe("0.1")
  })

  it("large values use compact notation in the UI locale", () => {
    expect(histogramBins([1_000_000, 5_000_000, 9_000_000], 4, "en-US")[0].bin).toBe("0")
    expect(histogramBins([1_200_000, 5_000_000, 9_000_000], 4, "en-US")[1].bin).toBe("2M")
    expect(histogramBins([1_200_000, 5_000_000, 9_000_000], 4, "zh-CN")[1].bin).toBe("200万")
  })
})
