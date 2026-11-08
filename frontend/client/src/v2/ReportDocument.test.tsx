import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ReportDocument } from "./ReportDocument";

describe("read-only report document", () => {
  it("renders semantic headings, real GFM tables and lists from actual report markdown", () => {
    render(<ReportDocument markdown={`# BioMate Run Report

## Dataset

| Field | Reference |
| --- | --- |
| input | counts.csv |

## Findings

- **Recorded metric**: 12

[Artifact](/api/owned-output)
`} />);
    expect(screen.getByRole("heading", { level: 1, name: "BioMate Run Report" })).toBeTruthy();
    expect(screen.getByRole("heading", { level: 2, name: "Dataset" })).toBeTruthy();
    const table = screen.getByRole("table");
    expect(within(table).getByRole("columnheader", { name: "Reference" })).toBeTruthy();
    expect(within(table).getByRole("cell", { name: "counts.csv" })).toBeTruthy();
    expect(screen.getByRole("region", { name: "Report table" }).contains(table)).toBe(true);
    expect(screen.getByRole("listitem").textContent).toContain("Recorded metric");
    expect(screen.getByRole("link", { name: "Artifact" }).getAttribute("href")).toBe("/api/owned-output");
    expect(screen.getByTestId("after-report-doc").tagName).toBe("ARTICLE");
    expect(screen.getByTestId("after-report-doc").style.maxHeight).toBe("");
  });

  it("never executes raw HTML or manufactures figures from absent report content", () => {
    const { container } = render(<ReportDocument markdown={'## Results\n\nNo figures recorded.\n\n<script>window.bad=true</script>'} />);
    expect(container.querySelector("script")).toBeNull();
    expect(container.querySelector("img")).toBeNull();
    expect(screen.queryByRole("textbox")).toBeNull();
  });
});
