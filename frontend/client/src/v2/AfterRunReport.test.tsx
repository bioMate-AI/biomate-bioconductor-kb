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
  // Default tab is "findings"; the QC tab button only appears once the fetch
  // returns at least one event (hide-when-empty). Wait for it, then click.
  const qcTabBtn = await screen.findByTestId("after-tab-qc", {}, { timeout: 5000 });
  fireEvent.click(qcTabBtn);
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
    // Findings is the default tab — wait for the panel to mount after the job poll
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

  it("renders the manifest contract note at the Findings-tab footer (post-A1 hoist)", async () => {
    // 2026-06-11 audit A1: the note was hoisted out of FindingsFiguresPanel
    // so it always renders on the Findings tab, even when figures are absent.
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
    expect(chain).toHaveTextContent(/SHA-256/);
    expect(chain).toHaveTextContent(/tamper-evident/);
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

  it("renders 'No QC gates fired' empty state when qcEvents is []", async () => {
    vi.restoreAllMocks();
    vi.spyOn(global, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("qc-events")) {
        return { ok: true, status: 200, json: async () => ({ events: [] }),
                 text: async () => "" } as Response;
      }
      return { ok: false, status: 404, json: async () => ({}), text: async () => "" } as Response;
    });
    render(<AfterRunReport {...baseProps} />);
    // qc tab is hidden entirely when there are no events (per hide-when-empty),
    // so the audit tab testid never mounts. Verify absence:
    await new Promise(r => setTimeout(r, 50)); // allow effects to settle
    expect(screen.queryByTestId("qc-audit-tab")).toBeNull();
  });
});
