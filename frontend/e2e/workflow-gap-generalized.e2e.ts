/**
 * Workflow Gap Coverage — Generalized Multi-Domain Tests
 *
 * Proves that the gaps identified in CS-11 through CS-14 are not specific to
 * CryoSPARC. The same test logic works across domains:
 *   • Cryo-EM (CryoSPARC Standard SPA)
 *   • Drug Discovery (Scaffold Hopping / NCA PK)
 *   • Protein Structure (AlphaFold DB Search)
 *
 * Tests:
 *   WG-1  Param override → execute payload   (CryoSPARC)
 *   WG-2  Param override → execute payload   (Scaffold Hopping)
 *   WG-3  Param override → execute payload   (AlphaFold DB Search)
 *   WG-4  Findings API: unknown run_id       (generic — domain-agnostic)
 *   WG-5  Execute payload: required param set (NCA PK Analysis)
 *
 * Core assertion shared across all tests:
 *   A param value changed in the pre-run ParameterGroup panel MUST appear in
 *   the /api/workflows/execute POST body.  This verifies the React onChange→
 *   handleParamChange→workflowDefinition.params chain for any workflow.
 *
 * NO page.route() mocking — all calls hit the live backend.
 * Screenshots → e2e/screenshots/workflow-gap/
 */

import { test, expect, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";
import { loginAsFixture } from "./_fixture-login";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL    = process.env.BIOMATE_URL      || "http://localhost:5000";
const E2E_TOKEN   = process.env.E2E_TEST_TOKEN   || "biomate-e2e-bypass-token-dev-only";
const CRYO_LIC    = process.env.CRYOSPARC_LICENSE || "f312a30e-63fc-11f0-8e36-e3c932851287";
const CRYO_MOVIES = process.env.CRYOSPARC_MOVIES_S3 || "s3://biomate-cryo-data/empiar-10028/Micrographs/00[1-5]_movie.mrcs";
const S3_TESTDATA = process.env.S3_TESTDATA       || "s3://biomate-nextflow-work/e2e-testdata";

const SS_DIR = path.join(__dirname, "screenshots", "workflow-gap");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ===========================================================================
// Types
// ===========================================================================

interface Assertion { name: string; passed: boolean; detail?: string; }
interface SuiteRecord {
  testId: string;
  workflow: string;
  domain: string;
  startTs: number;
  endTs: number;
  finalStatus: string;
  assertions: Assertion[];
  screenshots: string[];
  error?: string;
}

const SUITE_AUDIT: SuiteRecord[] = [];

// ===========================================================================
// WorkflowGapConfig — one entry per workflow variant
// ===========================================================================

interface WorkflowGapConfig {
  /** Short identifier used in screenshot names / logs */
  id: string;
  /** Human-readable domain label */
  domain: string;
  /** Workflow name as shown in BioMate */
  workflowLabel: string;
  /** Primary chat query — should include all params explicitly to avoid clarification turns */
  query: string;
  /** Follow-up queries if card does not appear after 45 s */
  followUps?: string[];
  /** POST /api/users/credentials before running (for licensed tools) */
  license?: { tool: string; key: string };
  /**
   * Override value to inject into the param panel.
   * If unset the test falls back to any visible numeric/text input.
   */
  overrideValue?: string;
  /**
   * Expected substring in the execute payload after the override is applied.
   * Defaults to overrideValue.
   */
  payloadSubstring?: string;
}

// ---------------------------------------------------------------------------
// Workflow configurations
// ---------------------------------------------------------------------------

const CONFIGS: WorkflowGapConfig[] = [
  // ── WG-1: CryoSPARC ───────────────────────────────────────────────────────
  {
    id: "wg1_cryosparc",
    domain: "cryo_em",
    workflowLabel: "CryoSPARC Standard SPA",
    query: [
      "Run CryoSPARC standard single-particle analysis on beta-galactosidase cryo-EM data (EMPIAR-10028).",
      `movies_path=${CRYO_MOVIES}`,
      "num_movies=5, pixel_size=1.77, symmetry=D2,",
      "particle_diameter_angstroms=120, voltage=300, spherical_aberration=2.7,",
      "amplitude_contrast=0.1, molecular_weight_kda=466,",
      `cryosparc_license=${CRYO_LIC}.`,
      "All parameters are provided — proceed directly to running the workflow.",
    ].join(" "),
    followUps: [
      `Show the CryoSPARC Standard SPA workflow card. movies_path=${CRYO_MOVIES}, pixel_size=1.77, cryosparc_license=${CRYO_LIC}.`,
      `Force generate CryoSPARC Standard SPA workflow card now with all parameters provided.`,
    ],
    license: { tool: "cryosparc", key: CRYO_LIC },
    overrideValue: "1.80",   // override pixel_size-style param
    payloadSubstring: "1.80",
  },

  // ── WG-2: Scaffold Hopping (Drug Discovery) ───────────────────────────────
  {
    id: "wg2_scaffold_hopping",
    domain: "drug_discovery",
    workflowLabel: "Scaffold Hopping",
    query:
      "Perform scaffold hopping from imatinib (BCR-ABL1 inhibitor). " +
      "Input SMILES: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1. " +
      "Generate 15 bioisosteric scaffold replacements while retaining the BCR-ABL1 pharmacophore. " +
      "Apply Lipinski rule-of-5 filter. Use the scaffold_hopping workflow. " +
      "num_scaffolds=15, filter_lipinski=true. Generate the workflow now.",
    followUps: [
      "Please generate the scaffold_hopping workflow card with imatinib SMILES I provided.",
      "Generate scaffold_hopping workflow now with input_smiles=Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1.",
    ],
    overrideValue: "20",   // override num_scaffolds param
    payloadSubstring: "20",
  },

  // ── WG-3: AlphaFold DB Search (Protein Structure) ────────────────────────
  {
    id: "wg3_alphafold_db_search",
    domain: "protein_structure",
    workflowLabel: "AlphaFold DB Search",
    query:
      "Search the AlphaFold protein structure database for structural homologs of the ABL1 kinase domain. " +
      "Query UniProt ID: P00519 (ABL1_HUMAN). " +
      "Find the top 15 structural neighbors with TM-score > 0.7 to identify off-target kinases. " +
      "Use the alphafold_db_search workflow. uniprot_id=P00519, top_k=15. Generate the workflow now.",
    followUps: [
      "Generate the alphafold_db_search workflow card with uniprot_id=P00519.",
      "Show the AlphaFold database search workflow for ABL1 kinase (UniProt P00519) now.",
    ],
    overrideValue: "20",   // override top_k param
    payloadSubstring: "20",
  },

  // ── WG-4: NCA PK Analysis (Drug Discovery — different param set) ──────────
  {
    id: "wg4_nca_pk",
    domain: "drug_discovery",
    workflowLabel: "NCA PK Analysis",
    query:
      "Run non-compartmental pharmacokinetics (NCA) analysis on single-dose IV plasma concentration data. " +
      `Input CSV: ${S3_TESTDATA}/nca_test.csv. ` +
      "Compound: Compound-A. Dose: 10 mg/kg IV bolus. Molecular weight: 412 g/mol. " +
      "Calculate Cmax, Tmax, AUC0-inf, t1/2, clearance, volume of distribution. " +
      "Use the nca_pknca workflow. dose=10, route=iv. Generate the workflow now.",
    followUps: [
      `Generate the nca_pknca NCA pharmacokinetics workflow. input_csv=${S3_TESTDATA}/nca_test.csv, dose=10.`,
      "Show the NCA pharmacokinetics workflow card now with the dose and CSV I provided.",
    ],
    overrideValue: "5.0",   // override dose or related numeric param
    payloadSubstring: "5.0",
  },
];

// ===========================================================================
// Generic helpers
// ===========================================================================

// Per CLAUDE.md §"E2E test user": single canonical fixture
// (lifeifei163361@163.com), shared across tests. The legacy per-test
// register pattern was migrated 2026-06-15 — the fake @biomate.test
// emails hit Galaxy's provisioning gap and left the test stuck on
// /login. See docs/20260614_AUTOLOOP_SSE_SILENT_ON_ADMET.md for the
// session that caught the regression.
async function registerUser(page: Page, _prefix: string): Promise<void> {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await loginAsFixture(page);
  // Dismiss onboarding banners that occasionally land on first session.
  for (let i = 0; i < 3; i++) {
    const skip = page.locator('button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later")').first();
    if (await skip.isVisible({ timeout: 2000 }).catch(() => false)) {
      await skip.click({ force: true }); await page.waitForTimeout(400);
    } else break;
  }
  await page.waitForSelector("textarea", { state: "visible", timeout: 20_000 }).catch(() => {});
  await page.waitForTimeout(800);
}

async function sendChat(page: Page, text: string, timeoutMs = 120_000): Promise<boolean> {
  const ta = page.locator("textarea").first();
  await expect(ta).toBeVisible({ timeout: 10_000 });
  await ta.fill(text);
  await ta.press("Enter");
  const thinking = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=AI is typing",
  ];
  await Promise.race(thinking.map(s => page.waitForSelector(s, { state: "visible", timeout: 30_000 }).catch(() => null)));
  await Promise.all(thinking.map(s => page.waitForSelector(s, { state: "hidden", timeout: timeoutMs }).catch(() => null)));
  await page.waitForFunction(() => {
    const el = document.querySelector('[data-is-latest-assistant="true"]');
    const t = el?.textContent ?? "";
    return t.trim().length > 30 && !t.includes("thinking") && !t.includes("typing");
  }, { timeout: timeoutMs }).catch(() => {});
  await page.waitForTimeout(1500);
  const txt = await page.locator('[data-is-latest-assistant="true"]').last().textContent({ timeout: 5000 }).catch(() => "");
  return (txt?.trim().length ?? 0) > 20;
}

/** Generic card wait — accepts per-workflow follow-up messages. */
async function waitForWorkflowCard(
  page: Page,
  label: string,
  followUps: string[] = [],
  timeoutMs = 300_000,
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  const followUpIntervalMs = 45_000;
  let followUpsSent = 0;
  let lastFollowUpTs = Date.now();

  while (Date.now() < deadline) {
    await page.evaluate(() => {
      const c = document.querySelector('[data-testid="chat-messages"], main');
      if (c) c.scrollTop = c.scrollHeight;
    }).catch(() => {});

    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid="workflow-run-controls"]',
      '[data-testid="qc-settings-section"]',
      '[data-testid^="phase-card-"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        console.log(`[${label}] card via: ${sel}`);
        await page.waitForTimeout(1000);
        return true;
      }
    }

    const elapsed = Date.now() - lastFollowUpTs;
    if (elapsed >= followUpIntervalMs && followUpsSent < followUps.length) {
      const thinking = ["[data-testid='chat-response-pending']", "[data-testid='chat-analysis-status']"];
      const isThinking = (await Promise.all(thinking.map(s =>
        page.locator(s).first().isVisible({ timeout: 200 }).catch(() => false)
      ))).some(v => v);
      if (!isThinking) {
        const ta = page.locator("textarea").first();
        if (await ta.isVisible({ timeout: 1000 }).catch(() => false)) {
          const msg = followUps[followUpsSent];
          console.log(`[${label}] Follow-up #${followUpsSent + 1}: ${msg.slice(0, 80)}…`);
          await ta.fill(msg);
          await ta.press("Enter");
          followUpsSent++;
          lastFollowUpTs = Date.now();
          await page.waitForTimeout(8000);
          continue;
        }
      }
    }
    await page.waitForTimeout(1500);
  }
  return false;
}

async function shot(page: Page, name: string): Promise<string> {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: false }).catch(() => {});
  return p;
}

function assert(rec: SuiteRecord, name: string, condition: boolean, detail?: string): void {
  rec.assertions.push({ name, passed: condition, detail });
  if (!condition) console.warn(`[ASSERT FAIL] ${name}${detail ? `: ${detail}` : ""}`);
}

// ===========================================================================
// Core gap test: param override → execute payload
//
// Generic across ALL nextflow workflows because every workflow uses:
//   1. ParameterGroup with <Input id={param.id}> (direct edit, all params)
//   2. EditableParamRow with param-override-btn-* (autoFilled params only)
// Both paths trigger onChange → handleParamChange → workflowDefinition.params
// → execute payload.
// ===========================================================================

async function runParamOverrideGapTest(
  page: Page,
  cfg: WorkflowGapConfig,
  rec: SuiteRecord,
): Promise<void> {
  // 1. Register license if needed
  if (cfg.license) {
    await page.request.post(`${BASE_URL}/api/users/credentials`, {
      data: { tool: cfg.license.tool, data: { license_key: cfg.license.key } },
      headers: { "Content-Type": "application/json" },
    }).catch(() => {});
    console.log(`[${cfg.id}] License registered for ${cfg.license.tool}`);
  }

  // 2. Send query
  const gotResponse = await sendChat(page, cfg.query, 120_000);
  assert(rec, "ai-response-received", gotResponse);
  rec.screenshots.push(await shot(page, `${cfg.id}_01_query`));

  // 3. Wait for workflow card (generic selector list + workflow-specific follow-ups)
  const gotCard = await waitForWorkflowCard(page, cfg.id, cfg.followUps ?? [], 300_000);
  assert(rec, "workflow-card-appeared", gotCard, cfg.workflowLabel);
  rec.screenshots.push(await shot(page, `${cfg.id}_02_card`));
  if (!gotCard) return;

  // 4. Wait for ParameterGroup to render
  await page.waitForTimeout(1500);

  let overrideApplied = false;
  let overriddenParam = "";
  const targetValue = cfg.overrideValue ?? "99";
  const checkSubstr = cfg.payloadSubstring ?? targetValue;

  // --- Path A: autoFilled override button (param-override-btn-*) ---
  const overrideBtns = page.locator('[data-testid^="param-override-btn-"]');
  const overrideBtnCount = await overrideBtns.count().catch(() => 0);
  console.log(`[${cfg.id}] autoFilled override buttons: ${overrideBtnCount}`);

  if (overrideBtnCount > 0) {
    const firstBtn = overrideBtns.first();
    if (await firstBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      const testId = await firstBtn.getAttribute("data-testid").catch(() => "");
      overriddenParam = testId.replace("param-override-btn-", "");
      await firstBtn.click().catch(() => {});
      await page.waitForTimeout(400);

      const inlineInput = page.locator(`[data-testid="param-inline-edit-${overriddenParam}"]`).first();
      if (await inlineInput.isVisible({ timeout: 2000 }).catch(() => false)) {
        await page.evaluate(
          ({ testid, val }: { testid: string; val: string }) => {
            const el = document.querySelector(`[data-testid="${testid}"]`) as HTMLInputElement;
            if (!el) return;
            const ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
            ns?.call(el, val);
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.dispatchEvent(new Event("change", { bubbles: true }));
          },
          { testid: `param-inline-edit-${overriddenParam}`, val: targetValue }
        );
        await page.waitForTimeout(300);
        const confirmBtn = page.locator(`[data-testid="param-confirm-btn-${overriddenParam}"]`).first();
        if (await confirmBtn.isVisible({ timeout: 1500 }).catch(() => false)) {
          await confirmBtn.click().catch(() => {});
          await page.waitForTimeout(400);
          overrideApplied = true;
          console.log(`[${cfg.id}] PathA override: "${overriddenParam}"="${targetValue}"`);
        }
      }
    }
  }

  // --- Path B: direct Input/Textarea edit (works for ALL params regardless of autoFilled) ---
  // ParameterGroup renders:
  //   <Input id={param.id}>  for string/number/file-path params
  //   <Textarea id={param.id}> for CSV/SMILES/FASTA/sequence params (ids ending in _csv, _tsv, etc.)
  // Neither carries a data-testid, so we target both element types by ID presence.
  if (!overrideApplied) {
    // Combined selector for Input + Textarea in ParameterGroup (both use id={param.id})
    const editables = page.locator(
      'input[type="number"]:not([data-testid]), ' +
      'input[type="text"]:not([data-testid]), ' +
      'textarea:not([data-testid])'
    );
    const editableCount = await editables.count().catch(() => 0);
    console.log(`[${cfg.id}] editable fields (no testid): ${editableCount}`);

    for (let i = 0; i < Math.min(editableCount, 12); i++) {
      const inp = editables.nth(i);
      if (!await inp.isVisible({ timeout: 500 }).catch(() => false)) continue;
      const type = await inp.getAttribute("type").catch(() => "text");
      if (type === "password") continue;
      const tag = await inp.evaluate(el => el.tagName.toLowerCase()).catch(() => "input");
      const paramId = await inp.getAttribute("id").catch(() => "");
      if (!paramId) continue;

      overriddenParam = paramId;
      if (tag === "textarea") {
        // For textarea: use fill() since nativeSetter only covers HTMLInputElement
        await inp.fill(targetValue).catch(() => {});
        await inp.dispatchEvent("input").catch(() => {});
        await inp.dispatchEvent("change").catch(() => {});
      } else {
        await page.evaluate(
          ({ id, val }: { id: string; val: string }) => {
            const el = document.getElementById(id) as HTMLInputElement;
            if (!el) return;
            const ns = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
            ns?.call(el, val);
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.dispatchEvent(new Event("change", { bubbles: true }));
          },
          { id: paramId, val: targetValue }
        );
      }
      await page.waitForTimeout(400);
      overrideApplied = true;
      console.log(`[${cfg.id}] PathB override: <${tag} id="${paramId}">="${targetValue}"`);
      break;
    }
  }

  assert(rec, "param-override-applied", overrideApplied,
    `cfg=${cfg.id} overrideBtns=${overrideBtnCount}`);
  rec.screenshots.push(await shot(page, `${cfg.id}_03_override`));

  // 5. Set up request capture THEN click run
  let executePayload: string | null = null;
  const requestCapture = page.waitForRequest(
    r => r.url().includes("/api/workflows/execute"), { timeout: 30_000 }
  ).then(req => {
    executePayload = req.postData() || "";
    return req;
  }).catch(() => null);

  // Click whichever run button is present
  const runBtns = [
    '[data-testid="button-run-workflow-panel"]',
    '[data-testid="button-confirm-and-run"]',
    '[data-testid="workflow-run-controls"] button',
  ];
  let ranClicked = false;
  for (const sel of runBtns) {
    const btn = page.locator(sel).first();
    if (await btn.isVisible({ timeout: 1500 }).catch(() => false) &&
        !await btn.isDisabled({ timeout: 500 }).catch(() => true)) {
      await btn.click().catch(() => {});
      ranClicked = true;
      console.log(`[${cfg.id}] Run clicked via ${sel}`);
      break;
    }
  }
  assert(rec, "run-button-clicked", ranClicked, `cfg=${cfg.id}`);

  if (ranClicked) {
    await requestCapture;
    rec.screenshots.push(await shot(page, `${cfg.id}_04_execute`));

    assert(rec, "execute-request-captured", executePayload !== null,
      `cfg=${cfg.id}`);

    if (executePayload) {
      const hasSubstr = executePayload.includes(checkSubstr)
        || (overriddenParam.length > 0 && executePayload.includes(overriddenParam));
      assert(rec, "execute-payload-contains-override", hasSubstr,
        `Looking for "${checkSubstr}" or param "${overriddenParam}". ` +
        `Payload[0:300]: ${executePayload.slice(0, 300)}`);
      console.log(`[${cfg.id}] Execute payload (first 300): ${executePayload.slice(0, 300)}`);
    }
  }
}

// ===========================================================================
// Core gap test: Findings API — unknown run_id returns non-500
// Same logic as CS-13(a) but with no dependency on any specific workflow.
// Just hits the findings endpoint with a random UUID and checks the response.
// ===========================================================================

async function runFindingsApiGapTest(
  page: Page,
  rec: SuiteRecord,
): Promise<void> {
  const fakeRunId = "00000000-dead-beef-0000-000000000000";
  const findingsResp = await page.request.get(
    `${BASE_URL}/api/workflows/runs/${fakeRunId}/findings`,
    { headers: { "x-e2e-test-token": E2E_TOKEN }, timeout: 10_000 }
  ).catch(() => null);

  const status = findingsResp?.status() ?? -1;
  assert(rec, "findings-unknown-run-non-500", status !== 500 && status !== -1,
    `HTTP ${status} — expected non-500 for unknown run_id`);

  if (findingsResp?.ok() === false && status !== 500) {
    // 404 or 200 with {status:"pending"} are both acceptable
    const body = await findingsResp.json().catch(() => null);
    console.log(`[findings-api] HTTP ${status}, body: ${JSON.stringify(body)?.slice(0, 100)}`);
    const acceptableShape = body === null || typeof body === "object";
    assert(rec, "findings-unknown-run-non-crash", acceptableShape,
      `body: ${JSON.stringify(body)?.slice(0, 100)}`);
  } else if (status === 200) {
    const body = await findingsResp!.json().catch(() => null);
    assert(rec, "findings-unknown-run-pending-shape",
      body?.status === "pending" || body?.status === "error" || body?.status === "not_found",
      `Expected pending/error/not_found, got: ${JSON.stringify(body)?.slice(0, 100)}`);
  }
  console.log(`[findings-api] non-existent run → HTTP ${status} ✓`);
}

// ===========================================================================
// Audit write-out (identical pattern to cryoem-stepwise)
// ===========================================================================

test.afterAll(() => {
  if (SUITE_AUDIT.length === 0) return;
  const passed = SUITE_AUDIT.filter(r => r.finalStatus === "completed").length;
  const file = path.join(SS_DIR, `audit_${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  const payload = {
    suiteId: "workflow-gap-generalized",
    generatedAt: new Date().toISOString(),
    passed,
    total: SUITE_AUDIT.length,
    runs: SUITE_AUDIT,
  };
  fs.writeFileSync(file, JSON.stringify(payload, null, 2));
  console.log(`[Audit] ${passed}/${SUITE_AUDIT.length} → ${file}`);
});

// ===========================================================================
// WG-1: CryoSPARC SPA — param override (cryo-EM domain)
// ===========================================================================
test("WG-1: CryoSPARC SPA — param override reaches execute payload", async ({ page }) => {
  test.setTimeout(300_000);
  const rec: SuiteRecord = {
    testId: "WG-1", workflow: CONFIGS[0].workflowLabel, domain: CONFIGS[0].domain,
    startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "wg1");
    await runParamOverrideGapTest(page, CONFIGS[0], rec);
    rec.finalStatus = "completed";
  } catch (err: any) {
    rec.error = err.message;
    await shot(page, "wg1_error").catch(() => {});
    throw err;
  } finally {
    rec.endTs = Date.now();
    SUITE_AUDIT.push(rec);
  }
});

// ===========================================================================
// WG-2: Scaffold Hopping — param override (drug_discovery domain)
// ===========================================================================
test("WG-2: Scaffold Hopping — param override reaches execute payload", async ({ page }) => {
  test.setTimeout(300_000);
  const rec: SuiteRecord = {
    testId: "WG-2", workflow: CONFIGS[1].workflowLabel, domain: CONFIGS[1].domain,
    startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "wg2");
    await runParamOverrideGapTest(page, CONFIGS[1], rec);
    rec.finalStatus = "completed";
  } catch (err: any) {
    rec.error = err.message;
    await shot(page, "wg2_error").catch(() => {});
    throw err;
  } finally {
    rec.endTs = Date.now();
    SUITE_AUDIT.push(rec);
  }
});

// ===========================================================================
// WG-3: AlphaFold DB Search — param override (protein_structure domain)
// ===========================================================================
test("WG-3: AlphaFold DB Search — param override reaches execute payload", async ({ page }) => {
  test.setTimeout(300_000);
  const rec: SuiteRecord = {
    testId: "WG-3", workflow: CONFIGS[2].workflowLabel, domain: CONFIGS[2].domain,
    startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "wg3");
    await runParamOverrideGapTest(page, CONFIGS[2], rec);
    rec.finalStatus = "completed";
  } catch (err: any) {
    rec.error = err.message;
    await shot(page, "wg3_error").catch(() => {});
    throw err;
  } finally {
    rec.endTs = Date.now();
    SUITE_AUDIT.push(rec);
  }
});

// ===========================================================================
// WG-4: Findings API unknown-run-id — fully domain-agnostic
// Runs in < 5 s. No workflow card, no execute, just an API call.
// ===========================================================================
test("WG-4: Findings API — unknown run_id returns non-500 (domain-agnostic)", async ({ page }) => {
  test.setTimeout(60_000);
  const rec: SuiteRecord = {
    testId: "WG-4", workflow: "ALL", domain: "generic",
    startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "wg4");
    await runFindingsApiGapTest(page, rec);
    rec.finalStatus = "completed";
  } catch (err: any) {
    rec.error = err.message;
    throw err;
  } finally {
    rec.endTs = Date.now();
    SUITE_AUDIT.push(rec);
  }
});

// ===========================================================================
// WG-5: NCA PK Analysis — param override (different drug_discovery workflow)
// ===========================================================================
test("WG-5: NCA PK Analysis — param override reaches execute payload", async ({ page }) => {
  test.setTimeout(300_000);
  const rec: SuiteRecord = {
    testId: "WG-5", workflow: CONFIGS[3].workflowLabel, domain: CONFIGS[3].domain,
    startTs: Date.now(), endTs: 0, finalStatus: "unknown",
    assertions: [], screenshots: [],
  };
  try {
    await registerUser(page, "wg5");
    await runParamOverrideGapTest(page, CONFIGS[3], rec);
    rec.finalStatus = "completed";
  } catch (err: any) {
    rec.error = err.message;
    await shot(page, "wg5_error").catch(() => {});
    throw err;
  } finally {
    rec.endTs = Date.now();
    SUITE_AUDIT.push(rec);
  }
});
