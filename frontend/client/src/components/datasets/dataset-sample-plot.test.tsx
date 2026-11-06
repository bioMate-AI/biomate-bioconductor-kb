import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { DatasetSamplePlot, numericColumnIndices, hasNumericColumns } from "./dataset-sample-plot";

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
