/**
 * StepDetail — RTL coverage for the two load-bearing behaviours of the
 * full-step-view object:
 *   1. the rendered ⇄ raw toggle (raw fetches bytes; rendered delegates to the
 *      shipped evidence-typed viewer, which we stub here)
 *   2. parameter origin badges (default / inherited / override / unknown) plus
 *      the "N not default" count and per-row revert.
 *
 * The evidence-typed viewer (StepOutputPreview) is stubbed — StepDetail's job is
 * to compose provenance + params + the toggle, not to re-implement viewers.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { StepDetail, resolveStepParams } from "./step-detail";

// Stub the shipped evidence-typed viewer — we assert we DELEGATE to it, not that
// we re-render an image/table/etc.
vi.mock("@/components/step-output-preview", () => ({
  StepOutputPreview: ({ file }: any) => (
    <div data-testid="mock-rendered-viewer" data-name={file.name} />
  ),
}));

const runId = "run-abc";

const baseStep = {
  id: "s1",
  name: "salmon_quant",
  processName: "NFCORE_RNASEQ:SALMON_QUANT",
  tool: "salmon",
  toolVersion: "1.10.1",
  duration: "6m 12s",
  inputs: ["reads_R1.fastq.gz", "reads_R2.fastq.gz"],
  parameters: { libType: "A", numBootstraps: 100, threads: 4 },
  outputs: [
    { name: "quant.sf", path: "s1/quant.sf", extension: "tsv" },
    { name: "logs.txt", path: "s1/logs.txt", extension: "txt" },
  ],
};

// Definition supplies defaults so origins resolve: libType default A (→ default),
// numBootstraps default 30 (→ override), threads has no default (→ unknown).
const workflowDefinition = {
  required_params: [{ name: "libType", default: "A" }],
  optional_params: [{ name: "numBootstraps", default: 30 }],
};

function mockRawFetch(text: string) {
  return vi.spyOn(global, "fetch").mockResolvedValue({
    ok: true,
    status: 200,
    text: async () => text,
  } as unknown as Response);
}

beforeEach(() => { vi.restoreAllMocks(); });
afterEach(() => { vi.clearAllMocks(); });

describe("resolveStepParams — origin inference", () => {
  it("tags default / override / unknown correctly", () => {
    const rows = resolveStepParams(baseStep.parameters, workflowDefinition);
    const byName = Object.fromEntries(rows.map(r => [r.name, r]));
    expect(byName.libType.origin).toBe("default");        // A == default A
    expect(byName.numBootstraps.origin).toBe("override");  // 100 != default 30
    expect(byName.threads.origin).toBeUndefined();         // no default known → unknown
  });

  it("tags inherited when the definition marks a project value", () => {
    const rows = resolveStepParams(
      { libType: "ISR" },
      { required_params: [{ name: "libType", default: "A" }], inherited_parameters: { libType: "ISR" } },
    );
    expect(rows[0].origin).toBe("inherited");
  });
});

describe("<StepDetail> — provenance + params", () => {
  it("renders the provenance chain: inputs → tool version → N outputs · duration", () => {
    render(<StepDetail runId={runId} step={baseStep} workflowDefinition={workflowDefinition} onClose={vi.fn()} />);
    const prov = screen.getByTestId("step-provenance");
    expect(prov).toHaveTextContent("reads_R1.fastq.gz");
    expect(prov).toHaveTextContent("salmon");
    expect(prov).toHaveTextContent("1.10.1");
    expect(prov).toHaveTextContent("2 outputs");
    expect(prov).toHaveTextContent("6m 12s");
  });

  it("shows honest empty states when tool version / duration are absent", () => {
    const bare = { ...baseStep, toolVersion: undefined, duration: undefined, inputs: [] };
    render(<StepDetail runId={runId} step={bare} onClose={vi.fn()} />);
    const prov = screen.getByTestId("step-provenance");
    expect(prov).toHaveTextContent("version n/a");
    expect(prov).toHaveTextContent("duration n/a");
    expect(prov).toHaveTextContent("upstream step output");
  });

  it("renders origin badges and the correct 'N not default' count", () => {
    render(<StepDetail runId={runId} step={baseStep} workflowDefinition={workflowDefinition} onClose={vi.fn()} />);
    // libType default, numBootstraps override, threads unknown → 1 not default.
    expect(screen.getByTestId("not-default-count")).toHaveTextContent("1 not default");
    expect(screen.getByTestId("param-row-libType").querySelector('[data-origin="default"]')).toBeTruthy();
    expect(screen.getByTestId("param-row-numBootstraps").querySelector('[data-origin="override"]')).toBeTruthy();
    expect(screen.getByTestId("param-row-threads").querySelector('[data-origin="unknown"]')).toBeTruthy();
  });
});

describe("<StepDetail> — rendered ⇄ raw toggle", () => {
  it("delegates to the shipped viewer for 'rendered' and fetches raw bytes for 'raw'", async () => {
    const fetchSpy = mockRawFetch("Name\tTPM\nGENE1\t42.0\n");
    const user = userEvent.setup();
    render(<StepDetail runId={runId} step={baseStep} workflowDefinition={workflowDefinition} onClose={vi.fn()} />);

    // Default = rendered → delegated viewer present, no fetch yet.
    expect(screen.getByTestId("mock-rendered-viewer")).toBeInTheDocument();
    expect(screen.queryByTestId("raw-view")).not.toBeInTheDocument();
    expect(fetchSpy).not.toHaveBeenCalled();

    // Flip to raw → raw view appears and bytes are fetched from step-file.
    await user.click(screen.getByTestId("toggle-raw"));
    await waitFor(() => expect(screen.getByTestId("raw-view")).toBeInTheDocument());
    expect(screen.queryByTestId("mock-rendered-viewer")).not.toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect((fetchSpy.mock.calls[0][0] as string)).toContain("/step-file?path=");
    await waitFor(() => expect(screen.getByTestId("raw-view")).toHaveTextContent("GENE1"));

    // Flip back to rendered → delegated viewer returns.
    await user.click(screen.getByTestId("toggle-rendered"));
    expect(screen.getByTestId("mock-rendered-viewer")).toBeInTheDocument();
  });

  it("selecting a different output tab resets to rendered and updates the viewer", async () => {
    mockRawFetch("x");
    const user = userEvent.setup();
    render(<StepDetail runId={runId} step={baseStep} workflowDefinition={workflowDefinition} onClose={vi.fn()} />);
    expect(screen.getByTestId("mock-rendered-viewer")).toHaveAttribute("data-name", "quant.sf");
    await user.click(screen.getByTestId("step-output-tab-logs.txt"));
    expect(screen.getByTestId("mock-rendered-viewer")).toHaveAttribute("data-name", "logs.txt");
  });

  it("onOpenOutput fires when an output is selected (claim → output hook)", async () => {
    mockRawFetch("x");
    const onOpenOutput = vi.fn();
    const user = userEvent.setup();
    render(
      <StepDetail runId={runId} step={baseStep} workflowDefinition={workflowDefinition} onClose={vi.fn()} onOpenOutput={onOpenOutput} />,
    );
    await user.click(screen.getByTestId("step-output-tab-logs.txt"));
    expect(onOpenOutput).toHaveBeenCalledWith("s1/logs.txt");
  });
});

// Founder rule (2026-11-12 leak sweep): the step's job id and work directory are infrastructure — a
// storage path on cloud runs — so the full step view shows the recorded failure, never those.
it('renders the actual recorded failure, without job id or work directory', () => {
 render(<StepDetail runId="run" step={{ id: 'failed', name: 'Align', status: 'failed', errorMessage: 'Actual container exit 127 on AWS Batch', jobId: 'job-7', workDir: 's3://biomate-nextflow-work/nextflow/work/u/r/ab12' }} onClose={() => {}} />);
 const details = screen.getByTestId('step-recorded-details');
 expect(details).toHaveTextContent('Actual container exit 127');
 expect(details.textContent).not.toMatch(/job-7|s3:|biomate-nextflow-work|AWS|Batch/);
});

// Live dev 2026-11-11: the full step view titled the step with the raw backend
// label "Download samplesheet and count matrix from S3" and an English status.
describe("StepDetail title — human step name, no infrastructure words", () => {
  it("shows the cleaned step name (process id only as tooltip) and never 'S3'", () => {
    const step = { ...baseStep, name: "Download samplesheet and count matrix from S3", processName: "INPUT_DOWNLOAD", status: "pending" };
    render(<StepDetail runId={runId} step={step as any} onClose={vi.fn()} />);
    const root = screen.getByTestId("step-detail");
    expect(root).toHaveTextContent("Download samplesheet and count matrix");
    expect(root.textContent).not.toMatch(/\bS3\b/);
    expect(screen.getByTitle("INPUT_DOWNLOAD")).toBeInTheDocument();
  });
});
