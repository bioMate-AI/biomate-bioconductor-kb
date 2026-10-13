/**
 * Companion to domain-e2e-capture.e2e.ts. Captures the COMPLETED-panel and
 * merged-RESULTS stills for each gap domain by RE-USING the already-dispatched
 * Batch run (discovered from the runs API by workflow-name + recency) — so it
 * adds ZERO Batch spend. Run it AFTER domain-e2e-capture has dispatched the
 * runs and they have reached a terminal state.
 *
 *   domain-<key>-completed.png  /debug/viewer/:runId  (panel: phase cards + footer)
 *   domain-<key>-results.png    /debug/afterrun/:runId (merged Results: findings + inline outputs)
 *
 * Discovery: GET /api/workflows/runs, newest run whose workflowName matches the
 * domain pattern. A run must be terminal (completed/failed) or it is skipped
 * (an in-flight run has no outputs → empty figure). Honest: captures whatever
 * the real completed run produced; nothing mocked.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/domain-results-capture.e2e.ts --project=chromium --retries=0
 *
 * Override a single domain's runId explicitly (skips discovery):
 *   DOMAIN_RUN_metabolomics=<uuid> ... (env var per domain key, '-' → '_')
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");

interface DomainRun {
  key: string;
  /** workflowName pattern the dispatched run should match. */
  wf: RegExp;
}
const DOMAINS: DomainRun[] = [
  { key: "metabolomics", wf: /metabo/i },
  { key: "epigenomics", wf: /chip|macs|peak/i },
  { key: "proteomics", wf: /proteom|pulldown|pull-down|lfq|chemoproteomic/i },
  { key: "crispr", wf: /crispr|mageck/i },
  { key: "single-cell", wf: /scrna|single.?cell|scdownstream|seurat|scanpy|cellranger|alevin|starsolo/i },
  { key: "variant-calling", wf: /sarek|variant|haplotype|strelka|deepvariant|mutect|germline|somatic/i },
];

const TERMINAL = /^(completed|failed|succeeded|error|ok|ok_warnings|cancelled)$/i;

test("capture completed + merged-results for gap domains from dispatched runs", async ({ page }) => {
  test.setTimeout(30 * 60 * 1000);
  await loginAsFixture(page);
  const log: string[] = [];

  // Pull the fixture's recent runs once (Playwright HTTP stack carries the
  // context Authorization header set by loginAsFixture).
  const resp = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=60`);
  if (!resp.ok()) throw new Error(`/api/workflows/runs → ${resp.status()}`);
  const body = await resp.json();
  const runs: any[] = Array.isArray(body) ? body : body.runs ?? [];
  const byRecency = [...runs].sort(
    (a, b) => new Date(b.createdAt ?? b.created_at ?? 0).getTime() - new Date(a.createdAt ?? a.created_at ?? 0).getTime(),
  );

  const shot = async (name: string, el?: import("@playwright/test").Locator) => {
    await (el ?? page).screenshot({ path: path.join(ASSETS, name) });
    log.push(`OK   ${name}`);
  };

  for (const d of DOMAINS) {
    const envKey = `DOMAIN_RUN_${d.key.replace(/-/g, "_")}`;
    let runId: string | undefined = process.env[envKey];
    let match: any;
    if (!runId) {
      match = byRecency.find((r) => d.wf.test(String(r.workflowName ?? r.workflow_name ?? r.name ?? "")));
      runId = match?.id ?? match?.runId;
    }
    if (!runId) { log.push(`SKIP ${d.key} — no dispatched run matches ${d.wf}`); continue; }
    log.push(`${d.key} → run ${runId} (${match?.workflowName ?? "env-override"})`);

    // Poll the run to a terminal state (up to 20 min) so outputs/findings exist.
    let status = String(match?.status ?? match?.realExecStatus ?? "").toLowerCase();
    const deadline = Date.now() + 20 * 60 * 1000;
    while (!TERMINAL.test(status) && Date.now() < deadline) {
      await page.waitForTimeout(20_000);
      const sr = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`).catch(() => null);
      if (sr?.ok()) {
        const sj = await sr.json().catch(() => ({}));
        status = String(sj.status ?? sj.state ?? sj.realExecStatus ?? status).toLowerCase();
      }
    }
    log.push(`${d.key} status=${status || "unknown"}`);
    if (!TERMINAL.test(status)) { log.push(`SKIP ${d.key} completed/results — run not terminal in 20min (status=${status})`); continue; }

    // completed panel (hardcoded-completed debug viewer, real steps/outputs fetched by runId)
    try {
      await page.goto(BASE_URL + `/debug/viewer/${runId}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
      await page.waitForTimeout(6000);
      await shot(`domain-${d.key}-completed.png`);
    } catch (e: any) { log.push(`FAIL ${d.key} completed — ${e?.message?.split("\n")[0] ?? e}`); }

    // merged Results view (findings banner + inline outputs gallery)
    try {
      await page.goto(BASE_URL + `/debug/afterrun/${runId}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
      await page.waitForTimeout(6000);
      await shot(`domain-${d.key}-results.png`);
    } catch (e: any) { log.push(`FAIL ${d.key} results — ${e?.message?.split("\n")[0] ?? e}`); }
  }

  // eslint-disable-next-line no-console
  console.log("\n[domain-results-capture]\n" + log.join("\n") + "\n");
  expect(log.some((l) => l.startsWith("OK"))).toBe(true);
});
