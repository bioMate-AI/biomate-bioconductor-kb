import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * COVERAGE GUARD for the output-requirements chokepoint.
 *
 * Output-format requirements (project Instructions → Output formats) must be applied
 * to EVERY deliverable generator through ONE mechanism — the `applyOutputRequirements`
 * chokepoint (LLM generators) or the structured `parseOutputRequirements` object
 * (non-LLM generators) — never a hand-rolled per-generator concat.
 *
 * This is a source-scan rather than an endpoint harness because routes.ts registers a
 * full Express app with heavy deps; the scan is what fails CI when a NEW deliverable
 * generator forgets to route through the chokepoint. Each row names a generator and the
 * marker proving it reads the requirements through the one mechanism.
 */
// vitest runs with cwd = the frontend package root.
const ROUTES_SRC = readFileSync(resolve(process.cwd(), "server/routes.ts"), "utf8");

describe("output-requirements application is ONE chokepoint across every deliverable generator", () => {
  const generators: Array<{ name: string; markers: RegExp[] }> = [
    {
      name: "methods-report (LLM) → applyOutputRequirements('report')",
      markers: [/applyOutputRequirements\(\s*USER\s*,[^)]*,\s*['"]report['"]\s*\)/],
    },
    {
      name: "findings summary (LLM) → applyOutputRequirements('findings-summary')",
      markers: [/applyOutputRequirements\([^)]*,\s*['"]findings-summary['"]\s*\)/],
    },
    {
      name: "QC HTML (non-LLM) → buildQCReportHtml reads structured requirements",
      markers: [
        /function buildQCReportHtml\([^)]*reqs\??:\s*OutputRequirements/,
        /buildQCReportHtml\(\s*run\s*,\s*invocationId\s*,\s*_qcReqs\s*\)/,
      ],
    },
    // NOTE: IND report is PAUSED (IND_REPORT_ENABLED off) and its generator runs in the
    // Galaxy backend, so it is intentionally NOT wired into the chokepoint — no coverage row.
  ];

  it.each(generators)("$name", ({ markers }) => {
    for (const marker of markers) {
      expect(ROUTES_SRC).toMatch(marker);
    }
  });

  it("the chat path keeps its dedupe-aware helper (the one intentional non-chokepoint path)", () => {
    // Chat must dedupe against a browser-threaded composerInstructions copy — a concern
    // the deliverable generators don't have — so it uses appendProjectOutputRequirements.
    expect(ROUTES_SRC).toMatch(/appendProjectOutputRequirements\(/);
  });

  it("no generator hand-rolls the requirements directive literal anymore (it lives in the chokepoint composer)", () => {
    // The '=== PROJECT OUTPUT REQUIREMENTS ... ===' directive text now lives ONLY in
    // appendOutputRequirementsBlock (chat-context.ts). If it reappears in routes.ts, a
    // generator has re-introduced an ad-hoc concat — the exact regression this refactor removes.
    expect(ROUTES_SRC).not.toMatch(/===\s*PROJECT OUTPUT REQUIREMENTS/);
  });

  it("each LLM deliverable runs the non-blocking conformance check", () => {
    // checkOutputConformance must be invoked after both LLM deliverables (report + findings).
    const invocations = ROUTES_SRC.match(/checkOutputConformance\(/g) ?? [];
    expect(invocations.length).toBeGreaterThanOrEqual(2);
  });
});
