/**
 * RTL tests for <BlockRenderer> — verifies the composition walker dispatches each
 * block kind to a rendered element, reuses existing primitives, carries structural
 * data, and flags blocks whose design primitive does not exist yet. The heavy
 * StepOutputPreview is stubbed (it pulls 3D/chart deps); we only assert the walker
 * routes an `outputRef` block to it with the right file.
 */
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";

vi.mock("@/components/step-output-preview", () => ({
  StepOutputPreview: ({ file }: { file: { name: string } }) => (
    <div data-testid="stub-step-output-preview">{file.name}</div>
  ),
}));

import { BlockRenderer } from "./BlockRenderer";
import type { Block } from "./types";

const BLOCKS: Block[] = [
  { kind: "prose", markdown: "Screened **two** compounds." },
  { kind: "keyResult", entity: "terfenadine", metric: "hERG IC50", value: "0.012 µM", interpretation: "HALT", source: { source_file: "qc_metrics.json" } },
  { kind: "outputRef", file: { name: "qc_metrics.json", path: "out/qc_metrics.json", extension: "json" } },
  { kind: "table", columns: ["Compound", "hERG"], rows: [["aspirin", "safe"], ["terfenadine", "HALT"]] },
  { kind: "figure", figureKind: "bars", title: "Endpoints", data: [["hERG", 0.012]] },
  { kind: "callout", severity: "halt", title: "GOLD hERG gate halted", body: "0.012 µM < 1.0 µM" },
  { kind: "citation", title: "Sanguinetti 2006", id: "PMID:16556864", url: "https://pubmed.ncbi.nlm.nih.gov/16556864/" },
];

describe("BlockRenderer", () => {
  it("renders every block kind with its data-block-kind marker", () => {
    const { container } = render(<BlockRenderer blocks={BLOCKS} runId="run-1" />);
    for (const kind of ["prose", "keyResult", "outputRef", "table", "figure", "callout", "citation"]) {
      expect(container.querySelector(`[data-block-kind="${kind}"]`)).toBeTruthy();
    }
  });

  it("carries real entity identity on a keyResult (never 'Compound N')", () => {
    const { container } = render(<BlockRenderer blocks={BLOCKS} runId="run-1" />);
    const kr = container.querySelector('[data-block-kind="keyResult"]');
    expect(kr?.querySelector('[data-block-field="entity"]')?.textContent).toBe("terfenadine");
    expect(kr?.querySelector('[data-block-field="value"]')?.textContent).toBe("0.012 µM");
  });

  it("routes an outputRef through the (stubbed) StepOutputPreview resolver", () => {
    render(<BlockRenderer blocks={BLOCKS} runId="run-1" />);
    expect(screen.getByTestId("stub-step-output-preview")).toHaveTextContent("qc_metrics.json");
  });

  it("flags a block whose design primitive is not built yet (callout)", () => {
    const { container } = render(<BlockRenderer blocks={BLOCKS} runId="run-1" />);
    const callout = container.querySelector('[data-block-kind="callout"]');
    expect(callout?.getAttribute("data-design-primitive")).toBe("needed");
  });

  it("does not flag a block that maps to a built primitive (outputRef)", () => {
    const { container } = render(<BlockRenderer blocks={BLOCKS} runId="run-1" />);
    const ref = container.querySelector('[data-block-kind="outputRef"]');
    expect(ref?.getAttribute("data-design-primitive")).toBeNull();
  });
});
