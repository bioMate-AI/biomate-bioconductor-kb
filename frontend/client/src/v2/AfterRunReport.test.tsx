/**
 * v2/AfterRunReport — first RTL coverage for the v2 directory.
 *
 * Focus: the rich QcAuditTab (just ported from v2/Modals.tsx legacy JSX
 * into the proper TS pipeline). Covers the three design surfaces the
 * old bare table was missing:
 *   1. 4-stat header (Gates recorded / Passed / Flagged / Advisory or unavailable)
 *   2. Audit log with recorded outcomes and explicit actions
 *   3. Chain-of-custody block + hide-when-empty e-signature
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, within, fireEvent, waitFor } from "@testing-library/react";

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

import { AfterRunReport, isRunMetadataFile } from "./AfterRunReport";

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
  // QC report is now a collapsible section folded inside the "Report" top-level
  // tab (below the report document). Open that tab; jsdom renders <details>
  // children into the DOM regardless of the open state, so the QC panel is
  // queryable once mounted.
  const reportTabBtn = await screen.findByTestId("after-tab-report", {}, { timeout: 5000 });
  fireEvent.click(reportTabBtn);
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

  it("does NOT render the manifest contract note (removed 2026-11-01 to match the design)", async () => {
    // The italic "findings generated from the run manifest" meta-sentence was
    // removed — the design's after-run strip goes straight to the findings card,
    // whose header already conveys provenance.
    render(<AfterRunReport {...baseProps} />);
    await screen.findByTestId("findings-figures-panel", {}, { timeout: 5000 });
    expect(screen.queryByTestId("findings-manifest-note")).toBeNull();
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

describe.skip("v2/AfterRunReport — MethodsTab editable report (Spec 12 increment)", () => {
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

  function mockMethodsPipeline(opts: { acceptVersionPost?: boolean } = {}) {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      const method = (init?.method ?? "GET").toUpperCase();
      // Report versions (#22). Default: reject so Save falls back to a local
      // download. With acceptVersionPost, the POST succeeds (server-first path).
      if (url.includes("/report/versions")) {
        if (method === "POST" && opts.acceptVersionPost) {
          return { ok: true, status: 200,
            json: async () => ({ version: { version: 1 } }), text: async () => "" } as Response;
        }
        if (method === "GET" && opts.acceptVersionPost) {
          return { ok: true, status: 200,
            json: async () => ({ versions: [] }), text: async () => "" } as Response;
        }
        return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
      }
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
    // Methods is now a section folded inside the Report tab.
    const reportTab = await screen.findByTestId("after-tab-report", {}, { timeout: 5000 });
    fireEvent.click(reportTab);
    await screen.findByTestId("record-section-methods", {}, { timeout: 5000 });
    return reportTab;
  }

  it("renders the Methods section inside the record tab once a non-stub report loads", async () => {
    render(<AfterRunReport {...baseProps} workflowName="nf-core/rnaseq" />);
    fireEvent.click(await screen.findByTestId("after-tab-report", {}, { timeout: 5000 }));
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

  it("Save falls back to a local markdown download when the server is unavailable", async () => {
    // Save is now server-first (#22): it POSTs the edit to /report/versions and
    // only downloads locally if that fails. The default fetch mock returns 404
    // for /report/versions, so this exercises the fallback path. Because the
    // download happens AFTER the awaited fetch, assertions use waitFor.
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

    await waitFor(() => expect(createURL).toHaveBeenCalledTimes(1));
    expect(clickSpy).toHaveBeenCalledTimes(1);
    const toast = await screen.findByTestId("methods-save-toast", {}, { timeout: 5000 });
    expect(toast).toHaveTextContent(/Server unavailable.*downloaded locally/i);

    vi.mocked(document.createElement).mockRestore();
  });

  it("Save persists a server version (no local download) when the endpoint accepts it", async () => {
    // Server-success path: POST /report/versions returns a version → MethodsTab
    // shows a "Saved as version" toast and does NOT fall back to a download.
    // Re-arm the pipeline mock to accept the version POST (keeps the methods
    // pipeline handlers the tab needs to render).
    mockMethodsPipeline({ acceptVersionPost: true });
    const clickSpy = vi.fn();
    const origCreate = document.createElement.bind(document);
    vi.spyOn(document, "createElement").mockImplementation((tag: string) => {
      const el = origCreate(tag) as HTMLElement;
      if (tag === "a") (el as HTMLAnchorElement).click = clickSpy;
      return el as any;
    });
    const createURL = vi.fn(() => "blob:mock");
    (URL as any).createObjectURL = createURL;
    (URL as any).revokeObjectURL = vi.fn();

    render(<AfterRunReport {...baseProps} workflowName="nf-core/rnaseq" />);
    await openMethodsTab();
    fireEvent.click(await screen.findByTestId("methods-edit-toggle", {}, { timeout: 5000 }));
    await screen.findByTestId("methods-editor", {}, { timeout: 5000 });
    fireEvent.click(screen.getByTestId("methods-save-edited"));

    const toast = await screen.findByTestId("methods-save-toast", {}, { timeout: 5000 });
    expect(toast).toHaveTextContent(/Saved as version v1/i);
    expect(clickSpy).not.toHaveBeenCalled(); // no local download on the success path

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

describe.skip("v2/AfterRunReport — QcAuditTab (rich panel)", () => {
  it("presents completed checks as findings without remediation controls", async () => {
    render(<AfterRunReport {...baseProps} />);
    const findings = await screen.findByTestId('completed-qc-findings');
    expect(findings).toHaveTextContent('ctf_quality');
    expect(findings).toHaveTextContent('0.22');
    expect(findings).toHaveTextContent('FAIL');
    expect(within(findings).queryByRole('button')).toBeNull();
    expect(findings).not.toHaveTextContent(/paused|adjusting parameters|resume/i);
  });

  it("renders 4-stat summary with correct counts", async () => {
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    const audit = await screen.findByTestId("qc-audit-tab", {}, { timeout: 5000 });
    const summary = within(audit).getByTestId("qc-summary");
    // 3 recorded checks: 2 passed, 1 failed; no retry execution is inferred.
    expect(within(summary).getByTestId("qc-stat-evaluated")).toHaveTextContent("3");
    expect(within(summary).getByTestId("qc-stat-passed")).toHaveTextContent("2");
    expect(within(summary).getByTestId("qc-stat-failed")).toHaveTextContent("1");
    expect(within(summary).getByTestId("qc-stat-other")).toHaveTextContent("0");
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

  it("shows actual results without claiming automatic remediation", async () => {
    render(<AfterRunReport {...baseProps} />);
    await openQcTab();
    await screen.findByTestId("qc-audit-log");
    expect(screen.getByTestId("qc-row-0-result")).toHaveTextContent("PASS");
    expect(screen.getByTestId("qc-row-1-result")).toHaveTextContent("FAIL");
    expect(screen.getByTestId("qc-row-2-result")).toHaveTextContent("PASS");
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

  it("blocked checks count as failures without inventing a retry", async () => {
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
    expect(within(summary).getByTestId("qc-stat-failed")).toHaveTextContent("1");
    expect(within(summary).getByTestId("qc-stat-other")).toHaveTextContent("0");
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
    expect(screen.getByTestId("qc-row-0-result")).toHaveTextContent("NOT EVALUATED");
  });

  it("shows unavailable instead of inventing an all-pass result when qcEvents is [] (QC tab always visible)", async () => {
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
    expect(within(audit).getByTestId("qc-unavailable")).toHaveTextContent(/QC results unavailable/i);
    // The audit-log table (which needs events) is NOT rendered in the empty state.
    expect(within(audit).queryByTestId("qc-audit-log")).toBeNull();
  });
});

describe.skip("v2/AfterRunReport — Reproducibility tab (Phase 2)", () => {
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
    fireEvent.click(await screen.findByTestId("after-tab-report", {}, { timeout: 5000 }));
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
    fireEvent.click(await screen.findByTestId("after-tab-report", {}, { timeout: 5000 }));
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

  it("renders exactly three top-level tabs — Summary, Outputs, Report", () => {
    render(<AfterRunReport {...baseProps} />);
    const tablist = screen.getByRole("tablist");
    const tabs = within(tablist).getAllByRole("tab");
    expect(tabs.map(t => t.textContent)).toEqual([
      "Summary", "Outputs", "Report",
    ]);
    // Summary / Outputs / Report are the three real top-level tabs.
    expect(screen.getByTestId("after-tab-summary")).toBeInTheDocument();
    expect(screen.getByTestId("after-tab-outputs")).toBeInTheDocument();
    expect(screen.getByTestId("after-tab-report")).toBeInTheDocument();
    // The former peer tabs (and the removed Results/Record tabs) fold into
    // Report and must NOT be top-level.
    expect(screen.queryByTestId("after-tab-results")).toBeNull();
    expect(screen.queryByTestId("after-tab-record")).toBeNull();
    expect(screen.queryByTestId("after-tab-findings")).toBeNull();
    expect(screen.queryByTestId("after-tab-qc")).toBeNull();
    expect(screen.queryByTestId("after-tab-methods")).toBeNull();
    expect(screen.queryByTestId("after-tab-params")).toBeNull();
    expect(screen.queryByTestId("after-tab-software")).toBeNull();
    expect(screen.queryByTestId("after-tab-citations")).toBeNull();
    expect(screen.queryByTestId("after-tab-trajectory")).toBeNull();
  });

  it("opens on the Summary tab and marks the run original", () => {
    render(<AfterRunReport {...baseProps} />);
    // Summary is selected by default.
    expect(screen.getByTestId("after-tab-summary")).toHaveAttribute("aria-selected", "true");
    expect(screen.getByTestId("after-tab-outputs")).toHaveAttribute("aria-selected", "false");
    expect(screen.getByTestId("after-tab-report")).toHaveAttribute("aria-selected", "false");
    // Summary tab body (findings banner) is visible without any click. The
    // "RUN ORIGINAL" badge was removed 2026-11-01 to match the design's clean
    // after-run strip, so it is intentionally no longer asserted / present.
    expect(screen.getByTestId("after-summary-tab")).toBeInTheDocument();
    expect(screen.queryByTestId("after-run-original-badge")).toBeNull();
  });

  it.skip("folds Methods, Parameters, Software, Citations and QC report as sections inside the Report tab (record commented out 2026-10-28; QC relocating to data panel)", () => {
    render(<AfterRunReport {...baseProps} />);
    fireEvent.click(screen.getByTestId("after-tab-report"));
    const report = screen.getByTestId("after-report-tab");
    // The reproducibility record folds in below the report document.
    const record = within(report).getByTestId("after-record-tab");
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
    ]) {
      expect(within(record).getByTestId(id)).toBeInTheDocument();
    }
    // Trajectory section removed (item 17) — no backend endpoint; the step view
    // is the trajectory. It must NOT appear.
    expect(within(record).queryByTestId("record-section-trajectory")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// FIX #9 — after-run UX bugs on failed / partial runs.
// ---------------------------------------------------------------------------

describe("v2/AfterRunReport — isRunMetadataFile (FIX #9.1 classification)", () => {
  it("classifies Nextflow pipeline_info / execution bookkeeping as metadata", () => {
    const meta = [
      { path: "work/pipeline_info/execution_report_2026-11-04.html", name: "execution_report_2026-11-04.html" },
      { path: "pipeline_info/execution_timeline_2026-11-04.html", name: "execution_timeline_2026-11-04.html" },
      { path: "pipeline_info/execution_trace_2026-11-04.txt", name: "execution_trace_2026-11-04.txt" },
      { path: "out/pipeline_info/dag.html", name: "dag.html" },
      { path: "run/dag.html", name: "dag.html" },
      { path: "run/report.html", name: "report.html" },
      { path: "run/timeline.html", name: "timeline.html" },
      { path: "run/trace.txt", name: "trace.txt" },
      { path: "logs/.nextflow.log", name: ".nextflow.log" },
      { path: "logs/.nextflow.log.3", name: ".nextflow.log.3" },
    ];
    for (const f of meta) expect(isRunMetadataFile(f)).toBe(true);
  });

  it("does NOT classify genuine scientific outputs as metadata", () => {
    const sci = [
      { path: "deseq2/results.tsv", name: "results.tsv" },
      { path: "multiqc/multiqc_report.html", name: "multiqc_report.html" },
      { path: "plots/volcano.png", name: "volcano.png" },
      { path: "admet/predictions.csv", name: "predictions.csv" },
      { path: "variants/sample.vcf", name: "sample.vcf" },
    ];
    for (const f of sci) expect(isRunMetadataFile(f)).toBe(false);
  });
});

describe("v2/AfterRunReport — Outputs tab metadata split + failed-run report (FIX #9)", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    // OutputsTab only fetches when the outputs prop is empty; we pass outputs
    // directly, so a blanket 404 keeps the other tab hooks quiet.
    vi.spyOn(global, "fetch").mockImplementation(async () =>
      ({ ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response),
    );
  });
  afterEach(() => { vi.clearAllMocks(); });

  const mixedOutputs = [
    { step: "deseq2", name: "results.tsv", path: "deseq2/results.tsv", ext: "tsv" },
    { step: "", name: "dag.html", path: "pipeline_info/dag.html", ext: "html" },
    { step: "", name: "execution_trace_2026-11-04.txt", path: "pipeline_info/execution_trace_2026-11-04.txt", ext: "txt" },
    { step: "", name: ".nextflow.log", path: "logs/.nextflow.log", ext: "log" },
  ];

  it("labels directory-derived groups once instead of repeating a supposed step on each file", async () => {
    render(<AfterRunReport {...baseProps} outputs={[
      { step: 'custom_thresholds', name: 'sample-a.bin', path: '02_quality_control/custom_thresholds/sample-a.bin', ext: 'bin' },
      { step: 'custom_thresholds', name: 'sample-b.bin', path: '02_quality_control/custom_thresholds/sample-b.bin', ext: 'bin' },
    ]} />);
    fireEvent.click(await screen.findByTestId('after-tab-outputs'));
    expect(screen.getAllByTestId('output-step-group')).toHaveLength(1);
    expect(screen.getByTestId('output-step-group')).toHaveTextContent('Output group: Quality control · custom thresholds');
    for (const card of screen.getAllByTestId('output-card')) {
      expect(card).not.toHaveTextContent('custom_thresholds');
    }
  });

  it("opens a single-identity view without download controls and closes with Escape", async () => {
    render(<AfterRunReport {...baseProps} outputs={[
      { step: 'custom_thresholds', name: 'quality.png', path: 'custom_thresholds/quality.png', ext: 'png' },
    ]} />);
    fireEvent.click(await screen.findByTestId('after-tab-outputs'));
    const card = screen.getByTestId('output-card');
    expect(within(card).getAllByText('quality.png')).toHaveLength(1);
    expect(within(card).getAllByRole('button', { name: 'Download quality.png' })).toHaveLength(1);
    fireEvent.click(within(card).getByRole('button', { name: 'view' }));
    const dialog = screen.getByRole('dialog', { name: 'quality.png' });
    expect(within(dialog).getAllByText('quality.png')).toHaveLength(1);
    expect(within(dialog).queryByRole('button', { name: /Download/ })).toBeNull();
    expect(within(dialog).getByRole('button', { name: 'Close' })).toBeInTheDocument();
    fireEvent.keyDown(dialog, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it.each(['completed', 'failed'])("keeps run metadata visible when a %s run has no scientific outputs", async status => {
    render(<AfterRunReport {...baseProps} executionStatus={status as any} outputs={mixedOutputs.slice(1) as any} />);
    fireEvent.click(await screen.findByTestId('after-tab-outputs'));
    const section = await screen.findByTestId('run-metadata-section');
    expect(within(section).getByText('dag.html')).toBeInTheDocument();
    expect(screen.queryByText(/Download output files \(3\)/)).toBeNull();
  });

  it("does not repeat the parent After run heading when embedded", async () => {
    render(<AfterRunReport {...baseProps} embedded executionStatus="failed" outputs={[]} />);
    expect(await screen.findByTestId('after-tab-summary')).toBeInTheDocument();
    expect(screen.queryByText('After run')).toBeNull();
    expect(screen.getByTestId('afterrun-no-report')).toBeInTheDocument();
  });

  it("does not advertise generated findings for a failed run with only diagnostic files", async () => {
    render(<AfterRunReport {...baseProps} executionStatus="failed" outputs={mixedOutputs.slice(1) as any} />);
    const summary = await screen.findByTestId('after-summary-tab');
    expect(summary).not.toHaveTextContent('generated from outputs');
    expect(summary).not.toHaveTextContent('Download findings');
    expect(screen.getByTestId('afterrun-no-report')).toBeInTheDocument();
    expect(vi.mocked(fetch).mock.calls.some(([url, init]) =>
      String(url) === '/api/jobs' && String(init?.body).includes('findings_analysis'))).toBe(false);
  });

  it("Download-all count excludes pipeline_info/metadata files", async () => {
    render(
      <AfterRunReport
        {...baseProps}
        executionStatus={"completed" as any}
        outputs={mixedOutputs as any}
      />,
    );
    // Outputs live under the Outputs tab (component lands on Summary).
    fireEvent.click(await screen.findByTestId("after-tab-outputs"));
    // 1 scientific output of 4 total → "Download all (1)", never (4).
    expect(await screen.findByText(/Download output files \(1\) · ZIP/)).toBeInTheDocument();
    expect(screen.queryByText(/Download output files \(4\)/)).toBeNull();
  });

  it("groups Nextflow bookkeeping under a 'Run metadata' section (not Outputs)", async () => {
    render(
      <AfterRunReport
        {...baseProps}
        executionStatus={"completed" as any}
        outputs={mixedOutputs as any}
      />,
    );
    // Outputs live under the Outputs tab (component lands on Summary).
    fireEvent.click(await screen.findByTestId("after-tab-outputs"));
    const section = await screen.findByTestId("run-metadata-section");
    expect(section).toBeInTheDocument();
    // 3 of the 4 files are metadata.
    expect(within(section).getByText(/Run metadata \(Nextflow\) · 3/)).toBeInTheDocument();
    expect(within(section).getByText("dag.html")).toBeInTheDocument();
  });

  it("offers 'Open as dataset' on a dataset-typed output, deep-linking the one Files object", async () => {
    // Run outputs register into project_files; the card resolves name→id and links
    // into /files?file=<id> (spec 04 §4.5.3/§4.7) — no second dataset panel here.
    vi.spyOn(global, "fetch").mockImplementation(async (input: any) => {
      const url = String(input);
      if (url.includes("/api/projects/proj-x/files")) {
        return { ok: true, status: 200, json: async () => ([
          { id: "ds-1", name: "results.tsv", source: "run_output", run_id: "r" },
        ]), text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
    render(
      <AfterRunReport
        {...baseProps}
        executionStatus={"completed" as any}
        outputs={[{ step: "deseq2", name: "results.tsv", path: "deseq2/results.tsv", ext: "tsv" }] as any}
        projectId={"proj-x" as any}
      />,
    );
    fireEvent.click(await screen.findByTestId("after-tab-outputs"));
    const link = await screen.findByTestId("output-open-as-dataset");
    expect(link).toHaveAttribute("href", "/files?file=ds-1");
  });

  it("shows a 'No report' note instead of the Download-report button on a failed run", async () => {
    render(
      <AfterRunReport
        {...baseProps}
        executionStatus={"failed" as any}
        errorMessage="DESeq2 exited with code 1"
      />,
    );
    expect(await screen.findByTestId("afterrun-no-report")).toHaveTextContent(
      /No report — the run did not complete/,
    );
    expect(screen.queryByTestId("afterrun-download-report")).toBeNull();
  });

  it("keeps the download affordance on a completed run", async () => {
    // The completed-run download UI is a menu behind an always-visible toggle
    // (Markdown report + PPTX deck); the per-item afterrun-download-report lives
    // inside that collapsed menu. Assert the toggle is present and no no-report note.
    render(<AfterRunReport {...baseProps} executionStatus={"completed" as any} />);
    expect(await screen.findByTestId("afterrun-download-toggle")).toBeInTheDocument();
    expect(screen.queryByTestId("afterrun-no-report")).toBeNull();
  });
});
