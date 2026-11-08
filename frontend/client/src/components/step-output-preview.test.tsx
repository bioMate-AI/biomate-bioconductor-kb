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
import { StepOutputPreview, parsePlddtFromPdb } from "./step-output-preview";

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

  it("routes .rds to RObjectPreview: tries the sidecar, falls back to 'Open in RStudio' when absent", async () => {
    // Sidecar absent → fetch 404s → RStudio launcher remains the CTA.
    mockFetch("not found", "text/plain", false, 404);
    const fetchSpy = vi.spyOn(global, "fetch");
    render(<StepOutputPreview runId={runId} file={{ name: "dds.rds", path: "/p", extension: "rds" }} onClose={onClose} />);
    expect(screen.getByRole("button", { name: /Open in RStudio/i })).toBeInTheDocument();
    // It probes for the <name>.rds.json sidecar (graceful enhancement).
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        expect.stringContaining("dds.rds.json"),
      );
    });
  });

  it("routes .rds to RObjectPreview: renders the object summary inline when the sidecar exists", async () => {
    mockFetch(JSON.stringify({ class: "DESeqDataSet", dim: [20000, 12], assays: ["counts"] }), "application/json");
    render(<StepOutputPreview runId={runId} file={{ name: "dds.rds", path: "/p", extension: "rds" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByText("DESeqDataSet")).toBeInTheDocument();
    });
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
      expect(screen.getByRole("link", { name: "Download data.cs" })).toBeInTheDocument();
    });
  });

  it("routes .html to an 'Open in new tab' affordance, not a blank sandboxed iframe (FIX #9.3)", async () => {
    mockFetch("<html><body><script>render()</script></body></html>", "text/html");
    const { container } = render(
      <StepOutputPreview runId={runId} file={{ name: "report.html", path: "/pipeline_info/report.html", extension: "html" }} onClose={onClose} />,
    );
    const link = await screen.findByRole("link", { name: /Open full report in a new tab/i });
    // Navigate through the authenticated endpoint so its CSP sandbox survives.
    // A same-origin blob would discard those headers, even with noopener.
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(link.getAttribute('href')).toContain(`/api/workflows/runs/${runId}/step-file?`);
    expect(link.getAttribute('href')).not.toMatch(/^blob:/);
    // The blank 256px sandboxed iframe must be gone.
    expect(container.querySelector("iframe")).toBeNull();
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

  // DL-domain JSON sidecars → the ported evidence viewers (Spec 08 §8.5).
  it("routes a *_seqtracks.json output to SeqTracks with its flagged intervals", async () => {
    mockFetch(
      {
        locus: "chr7:5,527,100–5,530,600",
        bp: 3500,
        tracks: [{ kind: "line", name: "conservation", values: [10, 40, 80, 60] }],
        flagged: [{ start: 120, end: 145, context: "splice donor", why: "predicted loss-of-function" }],
      },
      "application/json",
    );
    render(<StepOutputPreview runId={runId} file={{ name: "variant_seqtracks.json", path: "/p", extension: "json" }} onClose={onClose} />);
    await waitFor(() => {
      // The DL preview wrapper mounts and the SeqTracks flagged output is the actionable payload.
      expect(screen.getByTestId("dl-json-preview")).toBeInTheDocument();
      expect(screen.getByText(/predicted loss-of-function/)).toBeInTheDocument();
    });
  });

  it("routes a *_hits.json output to HitGrid and keeps a held hit unscored (null, not 0)", async () => {
    mockFetch(
      {
        modelName: "admet-herg v3",
        hits: [
          { id: "cand-1", smiles: "CCO", score: 0.82, confidence: "in-domain", verdict: "accepted" },
          { id: "cand-2", smiles: "c1ccccc1", verdict: "held", confidence: "out-of-domain" },
        ],
      },
      "application/json",
    );
    render(<StepOutputPreview runId={runId} file={{ name: "triage_hits.json", path: "/p", extension: "json" }} onClose={onClose} />);
    await waitFor(() => {
      expect(screen.getByTestId("dl-json-preview")).toBeInTheDocument();
      // HitGrid renders the ranked-hits card; the held candidate id must still appear.
      expect(screen.getByText("cand-2")).toBeInTheDocument();
    });
  });

  it("does NOT route a plain report.json to a DL viewer (unknown JSON → table)", async () => {
    mockFetch({ summary: "ok", value: 42 }, "application/json");
    render(<StepOutputPreview runId={runId} file={{ name: "report.json", path: "/p", extension: "json" }} onClose={onClose} />);
    await waitFor(() => {
      // No DL wrapper — falls through to the generic JSON table path.
      expect(screen.queryByTestId("dl-json-preview")).not.toBeInTheDocument();
    });
  });

  it("renders a JSON object as a readable key/value view, not comma-split CSV rows", async () => {
    mockFetch({ dili_probability: 0.875, dili_probability_threshold: 0.5, admet_dili_probability_passes: false, citation: "Redfern 2003, Kazius 2005" }, "application/json");
    render(<StepOutputPreview runId={runId} file={{ name: "qc_metrics.json", path: "/p", extension: "json" }} onClose={onClose} />);
    const preview = await screen.findByTestId("json-preview");
    // Keys and scalar values are present as a structured view.
    expect(preview.textContent).toContain("admet_dili_probability_passes");
    expect(preview.textContent).toContain("false");
    // The citation stays a single value cell, not split across CSV columns.
    const citationCell = Array.from(preview.querySelectorAll("td")).find((td) => td.textContent?.includes("Redfern 2003"));
    expect(citationCell?.textContent).toContain("Redfern 2003, Kazius 2005");
  });

  it("shows a multi-line string field of a JSON object with its line breaks", async () => {
    mockFetch({ success: true, result: "Compound: CCO\n  hERG inhibition : 0.003\n  DILI probability : 0.855" }, "application/json");
    render(<StepOutputPreview runId={runId} file={{ name: "predict_admet_properties_results.json", path: "/p", extension: "json" }} onClose={onClose} />);
    const preview = await screen.findByTestId("json-preview");
    // The multi-line "result" value is rendered in its own cell with line breaks intact.
    const resultCell = Array.from(preview.querySelectorAll("td")).find((td) => td.textContent?.includes("hERG inhibition"));
    expect(resultCell?.textContent).toContain("Compound: CCO");
    expect(resultCell?.textContent).toContain("hERG inhibition : 0.003");
    expect(resultCell?.textContent).toContain("DILI probability : 0.855");
  });

  it("keeps an array of records as a table", async () => {
    mockFetch([{ smiles: "CCO", score: 0.1 }, { smiles: "CCN", score: 0.2 }], "application/json");
    render(<StepOutputPreview runId={runId} file={{ name: "scores.json", path: "/p", extension: "json" }} onClose={onClose} />);
    await screen.findByText("CCN");
    expect(screen.queryByTestId("json-preview")).not.toBeInTheDocument();
  });
});

// ---------------------------------------------------------------------------
// pLDDT parser — the honest companion to a predicted-structure 3D view.
// Spec 14 §14.2: "pLDDT in the B-factor column". Spec 08 §8.5: a predicted
// structure opens the 3D view WITH its per-residue confidence chart.
// ---------------------------------------------------------------------------
describe("parsePlddtFromPdb", () => {
  // Minimal PDB: one CA per residue with the B-factor (cols 61-66) as pLDDT.
  // Columns are 1-based in the PDB spec; slice offsets in the parser are 0-based.
  const pdbLine = (resSeq: number, bfac: number) =>
    `ATOM  ${String(resSeq * 5).padStart(5)}  CA  ALA A${String(resSeq).padStart(4)}    ` +
    `  10.000  10.000  10.000  1.00${bfac.toFixed(2).padStart(6)}           C`;

  it("reads one per-residue confidence value per CA atom, in residue order", () => {
    const pdb = [pdbLine(1, 95.2), pdbLine(2, 72.0), pdbLine(3, 40.5)].join("\n");
    expect(parsePlddtFromPdb(pdb)).toEqual([95.2, 72.0, 40.5]);
  });

  it("returns [] when there are no CA atoms", () => {
    const pdb = "ATOM      1  N   ALA A   1      10.0  10.0  10.0  1.00 88.00           N";
    expect(parsePlddtFromPdb(pdb)).toEqual([]);
  });

  it("returns [] for a real crystal structure whose B-factors exceed the pLDDT 0–100 band", () => {
    // Real temperature factors routinely run 120+ Å² — not a confidence column.
    const pdb = [pdbLine(1, 145.0), pdbLine(2, 210.0)].join("\n");
    expect(parsePlddtFromPdb(pdb)).toEqual([]);
  });
});

describe('embedded output preview', () => {
  it('omits duplicate filename and close controls when its parent owns the modal header', async () => {
    mockFetch('preview text', 'text/plain');
    render(<StepOutputPreview embedded runId={runId} file={{name:'one-name.txt',path:'/owned/one-name.txt',extension:'txt'}} onClose={onClose}/>);
    await waitFor(()=>expect(screen.getByText('preview text')).toBeInTheDocument());
    expect(screen.queryByTitle('one-name.txt')).not.toBeInTheDocument();
    expect(screen.queryByRole('button',{name:/close/i})).not.toBeInTheDocument();
  });
});

it('shows an enlarged image directly in the parent view panel without another click', async()=>{
  mockFetch('image bytes','image/png');
  render(<StepOutputPreview expanded embedded runId={runId} file={{name:'large.png',path:'/owned/large.png',extension:'png'}} onClose={onClose}/>);
  expect(await screen.findByTestId('expanded-output-image')).toHaveAttribute('alt','large.png');
  expect(screen.queryByRole('button',{name:/download/i})).not.toBeInTheDocument();
  expect(screen.queryByRole('button',{name:/close/i})).not.toBeInTheDocument();
});

it.each([
  ['fsc_validation_report.json', {frequencies:[0.1],fsc:[0.5]}],
  ['triage_hits.json', {hits:[]}],
])('omits the nested %s header in a parent-owned file panel',async(name,data)=>{
  mockFetch(data,'application/json');
  render(<StepOutputPreview embedded runId={runId} file={{name,path:'/owned/'+name,extension:'json'}} onClose={onClose}/>);
  await waitFor(()=>expect(global.fetch).toHaveBeenCalled());
  expect(screen.queryByText(name)).not.toBeInTheDocument();
  expect(screen.queryByRole('button',{name:/close/i})).not.toBeInTheDocument();
});
