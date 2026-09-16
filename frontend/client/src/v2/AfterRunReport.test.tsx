/**
 * v2/AfterRunReport — first RTL coverage for the v2 directory.
 *
 * Focus: the rich QcAuditTab (just ported from v2/Modals.tsx legacy JSX
 * into the proper TS pipeline). Covers the three design surfaces the
 * old bare table was missing:
 *   1. 4-stat header (Gates evaluated / Passed / Auto-corrected / Manual)
 *   2. Audit log with PASS / FAIL → loop styling + action column
 *   3. Chain-of-custody block + hide-when-empty e-signature
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, within, fireEvent } from "@testing-library/react";

// QcAuditTab isn't exported; test it through the wrapper that ARR uses.
// To keep the test surface focused, expose QcAuditTab via a tiny stub that
// re-imports from the source module's lexical scope using vite-friendly trick:
// we directly import the source and rely on its internal QcAuditTab being
// invoked via the AfterRunReport tab switching. Easier: render the helper
// inline since it's a pure presentational component. We test it as if it
// were exported by creating a thin module that re-exports through dynamic
// import — but vite/vitest treats the module identically.
//
// Practical approach: re-construct an equivalent QcEvent[] payload, mount
// AfterRunReport with all other tabs empty so QC audit auto-activates, and
// assert against the rendered DOM via the data-testid hooks added to the
// rich panel.

import { AfterRunReport } from "./AfterRunReport";

// Block the fetch calls AfterRunReport makes on mount.
beforeEach(() => {
  vi.restoreAllMocks();
  vi.spyOn(global, "fetch").mockImplementation(async (input) => {
    const url = String(input);
    // Return qc-events shaped data for the qc fetch; empty for everything else.
    if (url.includes("qc-events")) {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          events: [
            { ts: "2026-06-10 12:14:21Z", gate: "fsc_resolution", status: "pass",
              measured: "3.21 Å", threshold: "≤ 3.5 Å", message: "" },
            { ts: "2026-06-10 12:18:33Z", gate: "ctf_quality", status: "fail",
              measured: "0.22", threshold: "≥ 0.30", message: "below threshold; auto-loop fired" },
            { ts: "2026-06-10 12:25:10Z", gate: "particle_count", status: "pass",
              measured: "1.24M", threshold: "≥ 500k", message: "" },
          ],
        }),
        text: async () => "",
      } as Response;
    }
    return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
  });
});
afterEach(() => { vi.clearAllMocks(); });

const baseProps = {
  runId: "run-qc-test",
  invocationId: "inv-qc-test",
  workflowName: "test workflow",
  parameters: {},
  executionStatus: "completed" as const,
  errorMessage: undefined,
};

async function openQcTab() {
  // QC report is now a collapsible section inside the "Reproducibility record"
  // top-level tab. Open that tab; jsdom renders <details> children into the DOM
  // regardless of the open state, so the QC panel is queryable once mounted.
  const recordTabBtn = await screen.findByTestId("after-tab-record", {}, { timeout: 5000 });
  fireEvent.click(recordTabBtn);
  await screen.findByTestId("record-section-qc", {}, { timeout: 5000 });
}

describe("v2/AfterRunReport — FindingsFiguresPanel (data-driven figures)", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    // Mock the findings job pipeline: enqueue → state-ready → artifact returns FindingsData
    const findingsArtifact = {
      status: "ok",
      summary: "DESeq2 found 2,841 differentially expressed genes.",
      figures: [
        { kind: "bars", title: "Top GO terms", unit: "−log₁₀ adj. p",
          highlight: "apoptotic process",
          data: [["apoptotic process", 10.7], ["immune response", 8.4]] },
        { kind: "composition", title: "DE direction",
          data: [["Up", 1612], ["Down", 1229]] },
        { kind: "qc", title: "Gene filtering", unit: "genes retained",
          kept: 14203, total: 18421 },
      ],
    };
    vi.spyOn(global, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      const method = (init?.method ?? "GET").toUpperCase();
      if (url.endsWith("/api/jobs") && method === "POST") {
        return { ok: true, status: 200,
          json: async () => ({ jobId: "job-1", state: "ready" }),
          text: async () => "" } as Response;
      }
      if (url === "/api/jobs/job-1/artifact") {
        return { ok: true, status: 200,
          json: async () => findingsArtifact, text: async () => "" } as Response;
      }
      if (url.startsWith("/api/jobs/job-1")) {
        return { ok: true, status: 200,
          json: async () => ({ state: "ready" }), text: async () => "" } as Response;
      }
      if (url.includes("qc-events")) {
        return { ok: true, status: 200, json: async () => ({ events: [] }),
          text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
  });

  it("renders all 3 figure kinds when findings.figures is populated", async () => {
    render(<AfterRunReport {...baseProps} />);
    // Findings now live on the Summary tab, which is the default landing tab —
    // no click needed.
    const panel = await screen.findByTestId("findings-figures-panel", {}, { timeout: 5000 });
    expect(within(panel).getByTestId("finding-fig-bars")).toBeInTheDocument();
    expect(within(panel).getByTestId("finding-fig-composition")).toBeInTheDocument();
    expect(within(panel).getByTestId("finding-fig-qc")).toBeInTheDocument();
  });

  it("highlights the row matching figure.highlight in FigBars", async () => {
    render(<AfterRunReport {...baseProps} />);
    const hl = await screen.findByTestId("finding-fig-bars-row-highlight", {}, { timeout: 5000 });
    expect(hl).toHaveTextContent(/apoptotic process/);
  });

  it("renders the manifest contract note at the Summary-tab footer (post-A1 hoist)", async () => {
    // 2026-06-11 audit A1: the note was hoisted out of FindingsFiguresPanel
    // so it always renders on the Summary tab, even when figures are absent.
    render(<AfterRunReport {...baseProps} />);
    // Wait for the figures panel to mount so we know findings finished loading
    await screen.findByTestId("findings-figures-panel", {}, { timeout: 5000 });
    const note = screen.getByTestId("findings-manifest-note");
    expect(note).toHaveTextContent(/Findings are generated directly from the run manifest/i);
    expect(note).toHaveTextContent(/Numbers and figures in this section come from the workflow outputs/i);
    // The note must NOT contain the old defensive wording.
    expect(note).not.toHaveTextContent(/not from the LLM/i);
  });

  it("hides the figures panel entirely when findings.figures is undefined (hide-when-empty)", async () => {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      const method = (init?.method ?? "GET").toUpperCase();
      if (url.endsWith("/api/jobs") && method === "POST") {
        return { ok: true, status: 200,
          json: async () => ({ jobId: "j2", state: "ready" }), text: async () => "" } as Response;
      }
      if (url === "/api/jobs/j2/artifact") {
        // No `figures` key → panel should not mount
        return { ok: true, status: 200,
          json: async () => ({ status: "ok", summary: "no figures here" }),
          text: async () => "" } as Response;
      }
      if (url.startsWith("/api/jobs/j2")) {
        return { ok: true, status: 200, json: async () => ({ state: "ready" }),
          text: async () => "" } as Response;
      }
      if (url.includes("qc-events")) {
        return { ok: true, status: 200, json: async () => ({ events: [] }),
          text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
    render(<AfterRunReport {...baseProps} />);
    await new Promise(r => setTimeout(r, 200));
    expect(screen.queryByTestId("findings-figures-panel")).toBeNull();
  });
});

describe("v2/AfterRunReport — MethodsTab editable report (Spec 12 increment)", () => {
  // A non-stub methods report: >200 chars and no "No QC events recorded".
  const METHODS_MD = [
    "## Methods",
    "",
    "Reads were quantified with salmon v1.10.1 against the GRCh38 transcriptome.",
    "Differential expression was assessed with DESeq2 v1.42, applying an",
    "apeglm log-fold-change shrinkage estimator. Multiple testing was controlled",
    "at a 5% false discovery rate using the Benjamini-Hochberg procedure.",
    "",
    "### Tool versions",
    "salmon 1.10.1 · DESeq2 1.42 · nf-core/rnaseq 3.14.0",
  ].join("\n");

  function mockMethodsPipeline() {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      const method = (init?.method ?? "GET").toUpperCase();
      // Methods report job pipeline.
      if (url.endsWith("/api/jobs") && method === "POST") {
        const body = JSON.parse(String(init?.body ?? "{}"));
        if (body.kind === "methods_report") {
          return { ok: true, status: 200,
            json: async () => ({ jobId: "mjob-1", state: "ready" }),
            text: async () => "" } as Response;
        }
        // Findings job (mounted by the Findings tab / download prep) — return a
        // benign ready job with no methods content.
        return { ok: true, status: 200,
          json: async () => ({ jobId: "fjob-1", state: "ready" }),
          text: async () => "" } as Response;
      }
      if (url === "/api/jobs/mjob-1/artifact") {
        return { ok: true, status: 200, json: async () => ({}),
          text: async () => METHODS_MD } as Response;
      }
      if (url.startsWith("/api/jobs/mjob-1")) {
        return { ok: true, status: 200, json: async () => ({ state: "ready" }),
          text: async () => "" } as Response;
      }
      if (url === "/api/jobs/fjob-1/artifact") {
        return { ok: true, status: 200,
          json: async () => ({ status: "ok", summary: "" }), text: async () => "" } as Response;
      }
      if (url.startsWith("/api/jobs/fjob-1")) {
        return { ok: true, status: 200, json: async () => ({ state: "ready" }),
          text: async () => "" } as Response;
      }
      if (url.includes("qc-events")) {
        return { ok: true, status: 200, json: async () => ({ events: [] }),
          text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
  }

  beforeEach(() => { mockMethodsPipeline(); });
  afterEach(() => { vi.clearAllMocks(); });

  async function openMethodsTab() {
    // Methods is now a section inside the Reproducibility record tab.
    const recordTab = await screen.findByTestId("after-tab-record", {}, { timeout: 5000 });
    fireEvent.click(recordTab);
    await screen.findByTestId("record-section-methods", {}, { timeout: 5000 });
    return recordTab;
  }

  it("renders the Methods section inside the record tab once a non-stub report loads", async () => {
    render(<AfterRunReport {...baseProps} workflowName="nf-core/rnaseq" />);
    fireEvent.click(await screen.findByTestId("after-tab-record", {}, { timeout: 5000 }));
    // The Methods section is always present; its body renders the report when
    // methods.hasRealContent is true.
    expect(await screen.findByTestId("record-section-methods", {}, { timeout: 5000 })).toBeInTheDocument();
    expect(await screen.findByTestId("methods-tab", {}, { timeout: 5000 })).toBeInTheDocument();
  });

  it("renders the report read-only by default with an Edit toggle (no editor yet)", async () => {
    render(<AfterRunReport {...baseProps} workflowName="nf-core/rnaseq" />);
    await openMethodsTab();
    const ro = await screen.findByTestId("methods-readonly", {}, { timeout: 5000 });
    expect(ro).toHaveTextContent(/salmon v1\.10\.1/);
    expect(screen.getByTestId("methods-edit-toggle")).toBeInTheDocument();
    // Editor must NOT be mounted until Edit is clicked.
    expect(screen.queryByTestId("methods-editor")).toBeNull();
    expect(screen.queryByTestId("methods-save-edited")).toBeNull();
  });

  it("clicking Edit opens the TipTap editor and swaps out the read-only view", async () => {
    render(<AfterRunReport {...baseProps} workflowName="nf-core/rnaseq" />);
    await openMethodsTab();
    fireEvent.click(await screen.findByTestId("methods-edit-toggle", {}, { timeout: 5000 }));
    // Editor mounts; read-only <pre> is gone; Save + Done controls appear.
    expect(await screen.findByTestId("methods-editor", {}, { timeout: 5000 })).toBeInTheDocument();
    expect(screen.queryByTestId("methods-readonly")).toBeNull();
    expect(screen.getByTestId("methods-save-edited")).toBeInTheDocument();
    expect(screen.getByTestId("methods-done-editing")).toBeInTheDocument();
  });

  it("Save edited version triggers a markdown download and shows a confirmation toast", async () => {
    // Stub the DOM download machinery so the click doesn't navigate jsdom.
    const clickSpy = vi.fn();
    const origCreate = document.createElement.bind(document);
    vi.spyOn(document, "createElement").mockImplementation((tag: string) => {
      const el = origCreate(tag) as HTMLElement;
      if (tag === "a") (el as HTMLAnchorElement).click = clickSpy;
      return el as any;
    });
    const createURL = vi.fn(() => "blob:mock");
    const revokeURL = vi.fn();
    (URL as any).createObjectURL = createURL;
    (URL as any).revokeObjectURL = revokeURL;

    render(<AfterRunReport {...baseProps} workflowName="nf-core/rnaseq" />);
    await openMethodsTab();
    fireEvent.click(await screen.findByTestId("methods-edit-toggle", {}, { timeout: 5000 }));
    await screen.findByTestId("methods-editor", {}, { timeout: 5000 });
    fireEvent.click(screen.getByTestId("methods-save-edited"));

    expect(createURL).toHaveBeenCalledTimes(1);
    expect(clickSpy).toHaveBeenCalledTimes(1);
    const toast = await screen.findByTestId("methods-save-toast", {}, { timeout: 5000 });
    expect(toast).toHaveTextContent(/Edited methods report downloaded/i);

    vi.mocked(document.createElement).mockRestore();
  });

  it("Done editing returns to the read-only report view", async () => {
    render(<AfterRunReport {...baseProps} workflowName="nf-core/rnaseq" />);
    await openMethodsTab();
    fireEvent.click(await screen.findByTestId("methods-edit-toggle", {}, { timeout: 5000 }));
    await screen.findByTestId("methods-editor", {}, { timeout: 5000 });
    fireEvent.click(screen.getByTestId("methods-done-editing"));
    expect(await screen.findByTestId("methods-readonly", {}, { timeout: 5000 })).toBeInTheDocument();
    expect(screen.queryByTestId("methods-editor")).toBeNull();
  });
});

describe("v2/AfterRunReport — QcAuditTab (rich panel)", () => {
  it("renders 4-stat summary with correct counts", async () => {
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    const audit = await screen.findByTestId("qc-audit-tab", {}, { timeout: 5000 });
    const summary = within(audit).getByTestId("qc-summary");
    // 3 gates total: 2 passed (fsc + particle_count), 1 fail→auto-loop (ctf_quality)
    expect(within(summary).getByTestId("qc-stat-evaluated")).toHaveTextContent("3");
    expect(within(summary).getByTestId("qc-stat-passed")).toHaveTextContent("2");
    expect(within(summary).getByTestId("qc-stat-autoloop")).toHaveTextContent("1");
    expect(within(summary).getByTestId("qc-stat-manual")).toHaveTextContent("0");
  });

  it("renders audit log table with the design column order", async () => {
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    const log = await screen.findByTestId("qc-audit-log");
    const headers = within(log).getAllByRole("columnheader").map(h => h.textContent);
    expect(headers).toEqual([
      "Timestamp (UTC)", "Gate", "Threshold", "Observed", "Result", "Action",
    ]);
  });

  it("shows ✓ PASS for passing gates and ↻ FAIL → loop for failing ones", async () => {
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    await screen.findByTestId("qc-audit-log");
    expect(screen.getByTestId("qc-row-0-result")).toHaveTextContent("✓ PASS");
    expect(screen.getByTestId("qc-row-1-result")).toHaveTextContent("↻ FAIL → loop");
    expect(screen.getByTestId("qc-row-2-result")).toHaveTextContent("✓ PASS");
  });

  it("renders Chain-of-custody block when events exist", async () => {
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    const chain = await screen.findByTestId("qc-chain-of-custody");
    expect(chain).toHaveTextContent(/Chain of custody/);
    expect(chain).toHaveTextContent(/No human override modified this run/);
  });

  it("honesty fix (#25): does NOT assert content-addressed/tamper-evident storage when no output carries a sha256", async () => {
    // The record tab passes outputs={[]} to QcAuditTab, so no checksums are
    // known. The copy must fall back to the honest "computed on demand / not
    // yet hashed" wording and must NOT claim a guarantee the data can't back.
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    const copy = await screen.findByTestId("qc-custody-copy");
    expect(copy).toHaveTextContent(/computed on demand/i);
    expect(copy).toHaveTextContent(/not yet hashed/i);
    // The blanket "content-addressed … tamper-evident" claim must be absent.
    expect(copy).not.toHaveTextContent(/are content-addressed by SHA-256 checksum/i);
  });

  it("hides e-signature block when backend provides no signing record (hide-when-empty)", async () => {
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    await screen.findByTestId("qc-audit-log");
    expect(screen.queryByTestId("qc-e-signature")).toBeNull();
  });

  it("auto-corrected count tracks fail/loop keywords; manual is the leftover", async () => {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("qc-events")) {
        return { ok: true, status: 200, json: async () => ({
          events: [
            { ts: "t1", gate: "g1", status: "pass", measured: "1", threshold: "≥1" },
            { ts: "t2", gate: "g2", status: "blocked", measured: "0", threshold: "≥1",
              message: "manual review required" },
          ],
        }), text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    const summary = await screen.findByTestId("qc-summary");
    expect(within(summary).getByTestId("qc-stat-evaluated")).toHaveTextContent("2");
    expect(within(summary).getByTestId("qc-stat-passed")).toHaveTextContent("1");
    expect(within(summary).getByTestId("qc-stat-autoloop")).toHaveTextContent("0");
    expect(within(summary).getByTestId("qc-stat-manual")).toHaveTextContent("1");
  });

  it("renders em-dash placeholders when event fields are missing (partial backend payload)", async () => {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("qc-events")) {
        return { ok: true, status: 200, json: async () => ({ events: [{}] }),
          text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    const row = await screen.findByTestId("qc-row-0");
    expect(within(row).getAllByText("—").length).toBeGreaterThanOrEqual(4);
    expect(screen.getByTestId("qc-row-0-result")).toHaveTextContent("✓ PASS");
  });

  it("shows the 'all quality gates passed' empty state when qcEvents is [] (QC tab always visible)", async () => {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("qc-events")) {
        return { ok: true, status: 200, json: async () => ({ events: [] }),
                 text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
    render(<AfterRunReport {...baseProps} />);
    // The QC tab is ALWAYS visible (not hidden-when-empty). Open it and assert
    // the real empty state — "all quality gates passed" — rather than asserting
    // the tab is absent (which only passed because the default tab is Outputs).
    await openQcTab();
    const audit = await screen.findByTestId("qc-audit-tab");
    expect(within(audit).getByTestId("qc-all-passed")).toHaveTextContent(/all quality gates passed/i);
    // The audit-log table (which needs events) is NOT rendered in the empty state.
    expect(within(audit).queryByTestId("qc-audit-log")).toBeNull();
  });
});

describe("v2/AfterRunReport — Reproducibility tab (Phase 2)", () => {
  const RECORD = {
    recordVersion: "1.0",
    runId: "run-repro",
    workflowName: "bulk RNA-seq DE",
    status: "ok",
    createdAt: "2026-09-14T00:00:00.000Z",
    completedAt: "2026-09-14T00:10:00.000Z",
    parameters: { fdr: 0.05, contrast: "treated_vs_control" },
    inputBindings: [{ stepId: "0", datasetId: "ds-a", name: "counts.csv" }],
    outputs: [{ id: "o1", name: "results.csv", fileType: "csv", sizeBytes: 2048, sha256: "abc123def456ghij789zzz" }],
    outputCount: 1,
  };

  beforeEach(() => {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("reproducibility-record")) {
        return { ok: true, status: 200, json: async () => RECORD, text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
  });
  afterEach(() => { vi.clearAllMocks(); });

  it("renders the unified record: identity, parameters, input bindings, outputs", async () => {
    render(<AfterRunReport {...baseProps} runId="run-repro" />);
    // Reproducibility record is now the (default-open) first section inside the
    // "Reproducibility record" top-level tab.
    fireEvent.click(await screen.findByTestId("after-tab-record", {}, { timeout: 5000 }));
    const tab = await screen.findByTestId("repro-tab", {}, { timeout: 5000 });
    expect(within(tab).getByText("bulk RNA-seq DE")).toBeTruthy();     // identity from record
    expect(within(tab).getByText("fdr")).toBeTruthy();                 // parameter key
    expect(within(tab).getByText(/Parameters \(2\)/)).toBeTruthy();
    expect(within(tab).getByText("counts.csv")).toBeTruthy();          // input binding
    expect(within(tab).getByText(/Outputs \(1\)/)).toBeTruthy();
    expect(within(tab).getByText("results.csv")).toBeTruthy();         // output name
    expect(within(tab).getByText(/abc123def456ghij/)).toBeTruthy();    // truncated sha256
    expect(within(tab).getByTestId("repro-download-json")).toBeTruthy();
  });

  it("shows an honest error state when the record is unavailable", async () => {
    vi.spyOn(global, "fetch").mockImplementation(async () =>
      ({ ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response));
    render(<AfterRunReport {...baseProps} runId="run-missing" />);
    fireEvent.click(await screen.findByTestId("after-tab-record", {}, { timeout: 5000 }));
    expect(await screen.findByTestId("repro-error", {}, { timeout: 5000 })).toBeTruthy();
  });
});

describe("v2/AfterRunReport — three-tab consolidation (accepted design)", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    // Every fetch 404s so all tabs render their honest empty states; keeps the
    // structural assertions independent of any tab's data pipeline.
    vi.spyOn(global, "fetch").mockImplementation(async () =>
      ({ ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response));
  });
  afterEach(() => { vi.clearAllMocks(); });

  it("renders exactly three top-level tabs — Summary, Outputs, Reproducibility record", () => {
    render(<AfterRunReport {...baseProps} />);
    const tablist = screen.getByRole("tablist");
    const tabs = within(tablist).getAllByRole("tab");
    expect(tabs.map(t => t.textContent)).toEqual([
      "Summary", "Outputs", "Reproducibility record",
    ]);
    // The former peer tabs must NOT be top-level anymore.
    expect(screen.queryByTestId("after-tab-findings")).toBeNull();
    expect(screen.queryByTestId("after-tab-qc")).toBeNull();
    expect(screen.queryByTestId("after-tab-methods")).toBeNull();
    expect(screen.queryByTestId("after-tab-params")).toBeNull();
    expect(screen.queryByTestId("after-tab-software")).toBeNull();
    expect(screen.queryByTestId("after-tab-citations")).toBeNull();
    expect(screen.queryByTestId("after-tab-trajectory")).toBeNull();
    expect(screen.queryByTestId("after-tab-reproducibility")).toBeNull();
  });

  it("opens on the Summary tab and marks the run original", () => {
    render(<AfterRunReport {...baseProps} />);
    // Summary is selected by default.
    expect(screen.getByTestId("after-tab-summary")).toHaveAttribute("aria-selected", "true");
    expect(screen.getByTestId("after-tab-outputs")).toHaveAttribute("aria-selected", "false");
    expect(screen.getByTestId("after-tab-record")).toHaveAttribute("aria-selected", "false");
    // Summary tab body + "run original" badge are visible without any click.
    expect(screen.getByTestId("after-summary-tab")).toBeInTheDocument();
    expect(screen.getByTestId("after-run-original-badge")).toHaveTextContent(/run original/i);
  });

  it("folds Methods, Parameters, Software, Citations, QC report and Trajectory as sections inside the record tab", () => {
    render(<AfterRunReport {...baseProps} />);
    fireEvent.click(screen.getByTestId("after-tab-record"));
    const record = screen.getByTestId("after-record-tab");
    // Intro line ("nothing is hidden or discarded").
    expect(within(record).getByTestId("record-intro")).toHaveTextContent(/nothing is hidden or discarded/i);
    // All former peer tabs are present as expandable sections.
    for (const id of [
      "record-section-record",
      "record-section-params",
      "record-section-methods",
      "record-section-software",
      "record-section-citations",
      "record-section-qc",
      "record-section-trajectory",
    ]) {
      expect(within(record).getByTestId(id)).toBeInTheDocument();
    }
  });
});
