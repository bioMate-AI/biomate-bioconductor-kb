/**
 * StepOutputPreview — RTL coverage for the 8 viewer code paths.
 *
 * Until now this 700-LOC component had zero unit tests. The viewer chosen
 * by file extension is the user-visible payload of every workflow run, so
 * any regression here breaks the "see your results" UX. Tests verify
 * extension → viewer selection and the basic content rendering for each
 * type. Heavy viewers (DensityMapViewer, 3Dmol structure, CryoEM charts)
 * are mocked — those have their own integration coverage elsewhere.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { StepOutputPreview } from "./step-output-preview";

// Stub heavy viewers — we're testing routing + content rendering, not the
// 3Dmol/density/chart internals.
vi.mock("./viewers/density-map-viewer", () => ({
  DensityMapViewer: ({ url }: any) => <div data-testid="mock-density-viewer" data-url={url} />,
}));
vi.mock("./viewers/fsc-curve-chart", () => ({
  FscCurveChart: () => <div data-testid="mock-fsc-chart" />,
}));
vi.mock("./viewers/motion-histogram-chart", () => ({
  MotionHistogramChart: () => <div data-testid="mock-motion-chart" />,
}));
vi.mock("./viewers/ctf-quality-chart", () => ({
  CtfQualityChart: () => <div data-testid="mock-ctf-chart" />,
}));
vi.mock("./interactive-launcher", () => ({
  InteractiveLauncher: ({ open }: any) =>
    open ? <div data-testid="mock-interactive-launcher" /> : null,
}));

const runId = "run-1";
const onClose = vi.fn();

function mockFetch(body: string | object, contentType = "text/plain", ok = true, status = 200) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  const blob = new Blob([text], { type: contentType });
  return vi.spyOn(global, "fetch").mockResolvedValue({
    ok,
    status,
    headers: { get: (k: string) => (k.toLowerCase() === "content-type" ? contentType : null) },
    text: async () => text,
    json: async () => (typeof body === "string" ? JSON.parse(text) : body),
    blob: async () => blob,
  } as unknown as Response);
}

beforeEach(() => {
  vi.restoreAllMocks();
  (global as any).URL.createObjectURL = vi.fn(() => "blob:mock-url");
  (global as any).URL.revokeObjectURL = vi.fn();
});
afterEach(() => { vi.clearAllMocks(); });

describe("StepOutputPreview — viewer routing by extension", () => {
  it("routes .png to image viewer with blob URL", async () => {
    mockFetch("binary", "image/png");
    render(<StepOutputPreview runId={runId} file={{ name: "plot.png", path: "/p", extension: "png" }} onClose={onClose} />);
    await waitFor(() => {
      const img = screen.getByRole("img");
      expect(img).toHaveAttribute("src", "blob:mock-url");
    });
  });

  it("routes .tsv to table viewer and renders first row as header", async () => {
    mockFetch("gene\tlog2FC\tpvalue\nTP53\t2.4\t0.001\nMYC\t-1.1\t0.05", "text/tab-separated-values");
    render(<StepOutputPreview runId={runId} file={{ name: "de.tsv", path: "/p", extension: "tsv" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByText("gene")).toBeInTheDocument();
      expect(screen.getByText("TP53")).toBeInTheDocument();
    });
  });

  it("routes .fasta to sequence viewer and renders record header", async () => {
    mockFetch(">contig_1\nATGCATGCATGCATGC\n>contig_2\nGGGGCCCCAAAATTTT", "text/plain");
    render(<StepOutputPreview runId={runId} file={{ name: "out.fasta", path: "/p", extension: "fasta" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByText(/contig_1/)).toBeInTheDocument();
    });
  });

  it("routes .vcf to variant table", async () => {
    const vcf = "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\nchr1\t100\trs1\tA\tG\t99\tPASS\t.";
    mockFetch(vcf, "text/plain");
    render(<StepOutputPreview runId={runId} file={{ name: "v.vcf", path: "/p", extension: "vcf" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByText("rs1")).toBeInTheDocument();
    });
  });

  it("routes .bed to annotation table", async () => {
    mockFetch("chr1\t100\t200\tpeak_1\t500\nchr2\t300\t400\tpeak_2\t900", "text/plain");
    render(<StepOutputPreview runId={runId} file={{ name: "peaks.bed", path: "/p", extension: "bed" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByText("peak_1")).toBeInTheDocument();
    });
  });

  it("routes .rds to RObjectPreview with 'Open in RStudio' CTA (no fetch fired)", () => {
    const fetchSpy = vi.spyOn(global, "fetch");
    render(<StepOutputPreview runId={runId} file={{ name: "dds.rds", path: "/p", extension: "rds" }} onClose={onClose} />);
    expect(screen.getByRole("button", { name: /Open in RStudio/i })).toBeInTheDocument();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("routes .mrc to density viewer (no inline fetch, viewer handles it)", () => {
    render(<StepOutputPreview runId={runId} file={{ name: "map.mrc", path: "/p", extension: "mrc" }} onClose={onClose} />);
    expect(screen.getByTestId("mock-density-viewer")).toBeInTheDocument();
  });

  it("routes CryoEM fsc_curve.json to FscCurveChart", async () => {
    mockFetch({ resolution_a: [10, 8, 6, 4], fsc: [1, 0.9, 0.5, 0.143] }, "application/json");
    render(<StepOutputPreview runId={runId} file={{ name: "fsc_validation_report.json", path: "/p", extension: "json" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByTestId("mock-fsc-chart")).toBeInTheDocument();
    });
  });

  it("falls back to download for unknown binary extensions", async () => {
    mockFetch("garbage", "application/octet-stream");
    render(<StepOutputPreview runId={runId} file={{ name: "data.cs", path: "/p", extension: "cs" }} onClose={onClose} />);
    // .cs is registered in CRYO_BINARY_EXTS → viewer='download', shows a download link
    await waitFor(() => {
      const dl = screen.getAllByRole("link").find(a => a.getAttribute("href") === "blob:mock-url");
      expect(dl).toBeTruthy();
    });
  });

  it("renders error message on 404 fetch failure", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: false,
      status: 404,
      headers: { get: () => "text/plain" },
      text: async () => "Not Found",
    } as unknown as Response);
    render(<StepOutputPreview runId={runId} file={{ name: "missing.tsv", path: "/p", extension: "tsv" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByText(/Failed to load file/)).toBeInTheDocument();
      expect(screen.getByText(/HTTP 404/)).toBeInTheDocument();
    });
  });
});
