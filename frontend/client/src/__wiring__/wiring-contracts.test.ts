/**
 * Wiring / no-dead-affordance + trust-boundary contract tests.
 *
 * SOURCE-LEVEL (read files with fs, like server/project-routes.test.ts).
 * These are CI regression guards for the exact bug class the audit kept
 * finding: a component is *built* but silently gets un-wired, a control
 * renders without the availability gate that makes it honest, one prop is
 * dropped so a feature goes dead, cost estimation creeps back in, or a
 * private-notes trust boundary is removed.
 *
 * Each assertion is grounded in code verified at authoring time; the
 * file:line references live in the coverage ledger
 * (docs/user-manual/coverage-ledger.md). We assert on the source TEXT so
 * that deleting/renaming/un-passing the wiring makes the test go red —
 * which a render-only "it mounts" test would not catch.
 *
 * We do NOT edit source or existing tests, and we do NOT assert on
 * step-output-preview *behavior* (a change is in flight there); we only
 * READ it to confirm the interactive-tools availability gate is referenced.
 */
import { describe, it, expect, vi } from "vitest";
import * as fs from "fs";
import React from "react";
import { render } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { DatasetObject } from "../components/datasets/dataset-object";
import * as path from "path";

// ── source loader ──────────────────────────────────────────────────────────
const read = (rel: string): string => {
  const abs = path.join(__dirname, rel);
  if (!fs.existsSync(abs)) {
    throw new Error(`wiring-contracts: expected source file is missing: ${rel} (${abs})`);
  }
  return fs.readFileSync(abs, "utf-8");
};

// Strip full-line JS/TS `//` comments AND `/* … */` block comments so
// "is this affordance ACTIVELY rendered" assertions don't get fooled by a
// commented-out block. (Line-level heuristic: good enough for source-text
// contracts; string literals containing `//` are not a concern here.)
const stripComments = (src: string): string => {
  const noBlock = src.replace(/\/\*[\s\S]*?\*\//g, "");
  return noBlock
    .split("\n")
    .filter((line) => !/^\s*\/\//.test(line))
    .join("\n");
};

const BENCH = read("../components/benchmark-evidence.tsx");
const CHAT_MSG = read("../components/chat-message.tsx");
const AFTER_RUN = read("../v2/AfterRunReport.tsx");
const STEP_PREVIEW = read("../components/step-output-preview.tsx");
const LAUNCHER = read("../components/interactive-launcher.tsx");
const DATASET_OBJ = read("../components/datasets/dataset-object.tsx");
const WF_VIEWER = read("../components/nextflow-workflow-viewer.tsx");
const MEMORY_INTEGRATION = read("../../../server/memory-integration.ts");

// ─────────────────────────────────────────────────────────────────────────
// 1. CitationPanel is mounted in the live chat answer (not orphaned).
//    Regression guard: CitationPanel was built but not rendered anywhere.
// ─────────────────────────────────────────────────────────────────────────
describe("1. CitationPanel is wired into the live chat answer", () => {
  const active = stripComments(BENCH);

  it("benchmark-evidence imports CitationPanel", () => {
    expect(active).toMatch(/import\s*\{\s*CitationPanel\s*\}\s*from\s*["']@\/components\/citation-panel["']/);
  });

  it("benchmark-evidence actually renders <CitationPanel …> (not just imports it)", () => {
    expect(active).toMatch(/<CitationPanel\b/);
  });

  it("CitationPanel is fed retrieval + conflicts + answerText (rich panel, not a bare list)", () => {
    // Isolate the JSX for the CitationPanel element so the props are its own.
    const el = active.slice(active.indexOf("<CitationPanel"), active.indexOf("<CitationPanel") + 400);
    expect(el).toMatch(/citations=\{/);
    expect(el).toMatch(/retrieval=\{response\.retrieval\}/);
    expect(el).toMatch(/conflicts=\{response\.conflicts\}/);
    expect(el).toMatch(/answerText=\{response\.answer\}/);
  });

  it("the panel is reachable from the LIVE chat answer (ResearchResponseDisplay is rendered in chat-message)", () => {
    const chat = stripComments(CHAT_MSG);
    expect(chat).toMatch(/import\s*\{[^}]*ResearchResponseDisplay[^}]*\}\s*from\s*["']\.\/benchmark-evidence["']/);
    expect(chat).toMatch(/<ResearchResponseDisplay\b/);
  });
});

// ─────────────────────────────────────────────────────────────────────────
// 2. After-run = Summary · Outputs · Report (accepted design). FindingsCard
//    (informational banner) sits in the Summary tab; the outputs gallery is its
//    own Outputs tab. (The earlier merged "Results" tab was split per decision.)
// ─────────────────────────────────────────────────────────────────────────
describe("2. FindingsCard (Summary) and OutputsTab (Outputs) are mounted in the split after-run tabs", () => {
  const active = stripComments(AFTER_RUN);

  it("AfterRunReport imports FindingsCard", () => {
    expect(active).toMatch(/import\s*\{\s*FindingsCard\s*\}\s*from\s*["']@\/components\/findings-card["']/);
  });

  it("the Summary tab holds the findings banner and the Outputs tab holds the gallery", () => {
    // Summary and Outputs are separate tabs (no merged "results" tab).
    expect(active).toMatch(/data-testid="after-summary-tab"/);
    expect(active).toMatch(/data-testid="after-outputs-tab"/);
    expect(active).toMatch(/\["summary",\s*tOr\('afterrun\.tab\.summary'/);
    expect(active).toMatch(/\["outputs",\s*tOr\('afterrun\.tab\.outputs'/);
    expect(active).toMatch(/\["report",\s*tOr\('afterrun\.tab\.report'/);
    // FindingsCard (banner) and OutputsTab (gallery) are both mounted.
    expect(active).toMatch(/<FindingsCard\b/);
    expect(active).toMatch(/<OutputsTab\b/);
  });
});

// ─────────────────────────────────────────────────────────────────────────
// 3. Interactive-tool launches are availability-gated EVERYWHERE they render.
//    Regression guard: InteractiveToolsRow (and per-viewer buttons) rendered
//    ungated → dead 400 launches when tools aren't provisioned.
// ─────────────────────────────────────────────────────────────────────────
describe("3. Interactive-tool affordances are availability-gated at every render site", () => {
  it("step-output-preview references useInteractiveToolsAvailable (R-object + single-cell previews)", () => {
    const active = stripComments(STEP_PREVIEW);
    expect(active).toMatch(/useInteractiveToolsAvailable/);
    // Both preview code paths derive availability from the probe.
    expect(active).toMatch(/itAvail\.tools\.rstudio/);   // RObjectPreview → RStudio
    expect(active).toMatch(/itAvail\.tools\.cellxgene/); // single-cell preview → CellxGene
  });

  it("AfterRunReport InteractiveToolsRow references useInteractiveToolsAvailable and hides when none provisioned", () => {
    const active = stripComments(AFTER_RUN);
    expect(active).toMatch(/function InteractiveToolsRow\b/);
    // The hook is used inside the row (not merely imported).
    const rowStart = active.indexOf("function InteractiveToolsRow");
    const rowBody = active.slice(rowStart, rowStart + 2000);
    expect(rowBody).toMatch(/useInteractiveToolsAvailable\(\)/);
    // Row returns null when availability is known and nothing is provisioned.
    expect(rowBody).toMatch(/return null/);
    // And the row IS actually mounted (dead-affordance guard for the row itself).
    expect(active).toMatch(/<InteractiveToolsRow\b/);
  });

  it("the launcher DISABLES its launch button when the selected tool is known-unavailable", () => {
    const active = stripComments(LAUNCHER);
    expect(active).toMatch(/useInteractiveToolsAvailable/);
    // Availability derived from the probe for the selected tool …
    expect(active).toMatch(/const\s+selectedToolAvailable\s*=/);
    // … and the launch Button is disabled on it (no dead launch).
    expect(active).toMatch(/disabled=\{[^}]*!selectedToolAvailable[^}]*\}/);
  });
});

// ─────────────────────────────────────────────────────────────────────────
// 4. Dataset-object header shows the quality pill + version chip.
//    Regression guard: object identity (quality/versions) got buried behind
//    tabs instead of surfacing on the header.
// ─────────────────────────────────────────────────────────────────────────
describe("4. Dataset-object header surfaces the quality pill + version chip", () => {
  const active = stripComments(DATASET_OBJ);

  // Behavioural (was a source regex on `profile?.quality`, which broke when the verdict began to
  // go through effectiveQuality): the pill shows the PROFILE's verdict, whatever it is.
  it("the header renders the quality pill from the perception profile", async () => {
    for (const [quality, label] of [["blocked", "Blocked"], ["good", "Good"], ["watch", "Watch"]] as const) {
      const profile = { shape: { rows: 2, cols: 2 }, quality, notes: [], findings: [
        { section: "note", code: "ragged_rows", level: quality === "good" ? "info" : quality, params: { count: 1, expected: 2 } },
      ] };
      globalThis.fetch = vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        const body = url.includes("/api/perception/profile") ? profile : {};
        return { ok: !url.includes("/rows"), status: url.includes("/rows") ? 415 : 200, json: async () => body, text: async () => "" } as unknown as Response;
      }) as unknown as typeof fetch;
      const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
      const view = render(React.createElement(QueryClientProvider, { client: qc },
        React.createElement(DatasetObject, {
          projectId: "p1", onDownload: () => {}, onRunQC: () => {},
          dataset: { id: `f-${quality}`, name: "t.csv", ref: "projects/p1/inputs/t.csv", size: 10, source: "upload" },
        })));
      const pill = await view.findByTestId("dataset-header-quality");
      expect(pill).toHaveAttribute("data-quality", quality);
      expect(pill).toHaveTextContent(label);
      view.unmount();
    }
  });

  it("the quality pill is in the dataset-object source (not only in a tab)", () => {
    expect(active).toMatch(/data-testid="dataset-header-quality"/);
  });

  it("the header renders the v{N} version chip derived from dataset.versions", () => {
    // Design §4.3.1: the header shows the current version (v2), not a count.
    expect(active).toMatch(/data-testid="dataset-header-version"/);
    // propVersions feeds currentVersionLabel and derives from dataset.versions.
    expect(active).toMatch(/const\s+propVersions\s*=\s*dataset\.versions/);
  });

  it("both live in the CardHeader (identity on the header, not only in a tab)", () => {
    const headStart = active.indexOf("<CardHeader");
    const headEnd = active.indexOf("</CardHeader>");
    expect(headStart).toBeGreaterThan(-1);
    expect(headEnd).toBeGreaterThan(headStart);
    const header = active.slice(headStart, headEnd);
    expect(header).toMatch(/data-testid="dataset-header-quality"/);
    expect(header).toMatch(/data-testid="dataset-header-version"/);
  });
});

// ─────────────────────────────────────────────────────────────────────────
// 5. No cost estimation in the UI — CostEstimateBadge / dg-cost stay REMOVED.
//    Regression guard: static per-run cost estimates were removed as
//    inaccurate; they must not be re-rendered.
// ─────────────────────────────────────────────────────────────────────────
describe("5. No active cost-estimation render (CostEstimateBadge / dg-cost stay removed)", () => {
  it("nextflow-workflow-viewer has NO active CostEstimateBadge render", () => {
    const active = stripComments(WF_VIEWER);
    // The whole component is commented out today; after stripping comments the
    // symbol must not appear at all (no active definition, no active render).
    expect(active).not.toMatch(/CostEstimateBadge/);
    expect(active).not.toMatch(/<CostEstimateBadge\b/);
  });

  it("no active cost-estimate affordance anywhere in the wired surfaces we assert on", () => {
    for (const [name, src] of Object.entries({
      WF_VIEWER, AFTER_RUN, STEP_PREVIEW, DATASET_OBJ, BENCH, CHAT_MSG,
    })) {
      const active = stripComments(src);
      expect(active, `${name} should not render a cost-estimate badge`).not.toMatch(/data-testid="cost-estimate-badge"/);
      expect(active, `${name} should not reference dg-cost`).not.toMatch(/dg-cost/);
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────
// 6. Trust boundary (runtime complement to memory-knowledge-filter.test.ts):
//    the memory-HINT path in memory-integration.ts must route project
//    knowledge THROUGH filterModelVisibleKnowledge, so a user_notes /
//    notes_synthesis row can never surface in a "[Memory: …]" hint.
//    Regression guard: the boundary being silently removed from the hint path.
// ─────────────────────────────────────────────────────────────────────────
describe("6. memory-integration hint path routes knowledge through filterModelVisibleKnowledge", () => {
  const active = stripComments(MEMORY_INTEGRATION);

  it("imports the filter from memory-knowledge-filter", () => {
    expect(active).toMatch(/import\s*\{\s*filterModelVisibleKnowledge\s*\}\s*from\s*["']\.\/memory-knowledge-filter["']/);
  });

  it("addMemoryHints derives its knowledge hints from filterModelVisibleKnowledge(knowledge) — unfiltered rows never reach a hint", () => {
    // Anchor on the METHOD DEFINITION, not the call site (`this.addMemoryHints(`).
    const start = active.indexOf("private addMemoryHints(");
    expect(start).toBeGreaterThan(-1);
    // Bound the scan to the addMemoryHints method body.
    const body = active.slice(start, start + 2500);
    // The knowledge hint MUST be built from the filtered list.
    expect(body).toMatch(/filterModelVisibleKnowledge\(\s*knowledge\s*\)/);
    // And the "Project knowledge" hint is emitted from THAT filtered list,
    // not from the raw `knowledge` array.
    const filterIdx = body.indexOf("filterModelVisibleKnowledge(");
    const knowledgeHintIdx = body.indexOf("Project knowledge");
    expect(filterIdx).toBeGreaterThan(-1);
    expect(knowledgeHintIdx).toBeGreaterThan(-1);
    expect(filterIdx).toBeLessThan(knowledgeHintIdx);
    // Guard against reintroducing a raw-knowledge slice that bypasses the filter:
    // there must be no `knowledge.slice(` feeding the hint (the filtered var is used instead).
    expect(body).not.toMatch(/[^e]knowledge\.slice\(/);
  });
});
