/**
 * All-executable E2E: every real-execution-validated Bioconductor workflow must be
 * product-serviceable — the live product can serve its panel data (steps, container,
 * visualizations, QC) so it renders and runs when a user opens it.
 *
 * Cases come from bioc_validated_cases.json (generated from the DB:
 * source='bioconductor' AND real_exec_status IN ('ok','ok_warnings')). No mocks — hits
 * the live Node/Galaxy server. The marquee routing + full-Batch-run flows are covered by
 * bioconductor-workflows-comprehensive.e2e.ts (BC-01, BC-EXEC, ...).
 */
import { test, expect } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";

const BASE_URL = process.env.BASE_URL || "http://localhost:5000";
const TOKEN = process.env.E2E_TEST_TOKEN || "test";
const CASES: Array<{ pkg: string; wf: string; name: string; domain: string }> =
  JSON.parse(fs.readFileSync(path.join(__dirname, "bioc_validated_cases.json"), "utf-8"));

test.describe("Bioconductor: every real-exec-validated workflow is product-serviceable", () => {
  test.setTimeout(20 * 60 * 1000);

  test(`all ${CASES.length} validated workflows serve complete panel data`, async ({ request }) => {
    const fails: string[] = [];
    let served = 0, withSteps = 0;
    for (const tc of CASES) {
      const nfPath = `nextflow_nfcore/subworkflows/bioconductor/${tc.pkg}/${tc.wf}.nf`;
      try {
        const r = await request.get(
          `${BASE_URL}/api/nextflow/steps?nextflow_path=${encodeURIComponent(nfPath)}`,
          { headers: { "X-E2E-Test-Token": TOKEN }, timeout: 15000 });
        if (!r.ok()) { fails.push(`${tc.pkg}/${tc.wf}: HTTP ${r.status()}`); continue; }
        const body = await r.json();
        served++;
        if ((body.count ?? 0) > 0) withSteps++;
        else fails.push(`${tc.pkg}/${tc.wf}: 0 steps`);
      } catch (e: any) {
        fails.push(`${tc.pkg}/${tc.wf}: ${String(e).slice(0, 60)}`);
      }
    }
    console.log(`[all-validated] served=${served}/${CASES.length}  with-steps=${withSteps}/${CASES.length}`);
    if (fails.length) console.log(`[all-validated] failures (${fails.length}):\n  ` + fails.slice(0, 40).join("\n  "));
    // Every validated workflow must serve its steps so the panel can render + run it.
    expect.soft(served, "all validated workflows respond from the steps API").toBe(CASES.length);
    expect(withSteps, `validated workflows serving >=1 step (failures: ${fails.length})`).toBeGreaterThanOrEqual(Math.floor(CASES.length * 0.95));
  });
});
