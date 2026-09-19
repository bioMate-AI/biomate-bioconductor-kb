import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";
import { SingleCellSummaryPanel } from "./single-cell-summary";

const SUMMARY = {
  n_cells: 12345,
  n_genes: 20000,
  clusters: [
    { label: "CD4 T", n: 3200 },
    { label: "B cell", n: 1800 },
  ],
  umap: { points: [[1.0, 2.0, "CD4 T"], [-1.0, 0.5, "B cell"]] as Array<[number, number, string]> },
  markers: [{ cluster: "CD4 T", genes: ["IL7R", "CCR7", "TCF7"] }],
};

describe("SingleCellSummaryPanel", () => {
  beforeEach(() => { vi.restoreAllMocks(); });
  afterEach(() => { vi.clearAllMocks(); });

  it("renders UMAP, clusters and markers from the sidecar", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true, status: 200, json: async () => SUMMARY,
    } as Response);

    render(<SingleCellSummaryPanel runId="r1" file={{ name: "annotated.h5ad", path: "s3/x/annotated.h5ad" }} />);

    await waitFor(() => expect(screen.getByTestId("single-cell-summary")).toBeInTheDocument());
    expect(screen.getByTestId("single-cell-umap")).toBeInTheDocument();
    const clusters = screen.getByTestId("single-cell-clusters");
    expect(within(clusters).getByText("CD4 T")).toBeInTheDocument();
    expect(within(clusters).getByText("B cell")).toBeInTheDocument();
    expect(screen.getByText(/12,345/)).toBeInTheDocument();
    expect(screen.getByText(/IL7R/)).toBeInTheDocument();
  });

  it("fetches the .summary.json sibling of the h5ad", async () => {
    const f = vi.spyOn(global, "fetch").mockResolvedValue({ ok: true, status: 200, json: async () => SUMMARY } as Response);
    render(<SingleCellSummaryPanel runId="r1" file={{ name: "annotated.h5ad", path: "s3/x/annotated.h5ad" }} />);
    await waitFor(() => expect(f).toHaveBeenCalled());
    const url = String((f.mock.calls[0] as any)[0]);
    expect(url).toContain("step-file");
    expect(decodeURIComponent(url)).toContain("annotated.h5ad.summary.json");
  });

  it("calls onAbsent and renders nothing when there is no sidecar", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({ ok: false, status: 404, json: async () => ({}) } as Response);
    const onAbsent = vi.fn();
    const { container } = render(
      <SingleCellSummaryPanel runId="r1" file={{ name: "x.h5ad", path: "s3/x.h5ad" }} onAbsent={onAbsent} />,
    );
    await waitFor(() => expect(onAbsent).toHaveBeenCalledTimes(1));
    expect(screen.queryByTestId("single-cell-summary")).toBeNull();
    expect(container.querySelector('[data-testid="single-cell-umap"]')).toBeNull();
  });

  it("treats an empty summary as absent (no fabricated plot)", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({ ok: true, status: 200, json: async () => ({ n_cells: 0 }) } as Response);
    const onAbsent = vi.fn();
    render(<SingleCellSummaryPanel runId="r1" file={{ name: "x.h5ad", path: "s3/x.h5ad" }} onAbsent={onAbsent} />);
    await waitFor(() => expect(onAbsent).toHaveBeenCalled());
    expect(screen.queryByTestId("single-cell-summary")).toBeNull();
  });
});
