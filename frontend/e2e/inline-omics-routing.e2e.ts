/**
 * Inline Omics Data Routing E2E — UC-1, UC-2, UC-3
 * =====================================================
 * Tests that pasting different inline biological data formats correctly
 * routes to the appropriate workflow family:
 *
 *   UC-1  10x scRNA-seq barcode/gene matrix → Seurat or nf-core/scrnaseq
 *          (must NOT route to bulk differentialabundance)
 *   UC-2  VCF-format variant rows (tab-separated) → sarek/GATK/GWAS
 *   UC-3  SMILES drug candidates → ADMET/drug-property screening pipeline
 *
 * All three trigger the `extractInlineDataWithLLM` path in galaxy-assistant.ts:
 * - SMILES: Gemini LLM extractor returns smiles key in InlineDataMap
 * - Count matrix: tabular regex fallback (≥2 numeric rows) sets count_matrix key
 * - VCF: same tabular regex; QUAL/AF columns are numeric
 *
 * In all cases hasInlineData=true → Galaxy uses "Technical failure" framing
 * (not "Clarification needed") → workflow_ready SSE fires → panel auto-opens.
 *
 * Pattern: DOM-based (same as chat-multiturn-research.e2e.ts).
 * CLAUDE.md rules:
 *  - Single fixture account; login once per file
 *  - No page.route() mocking — all calls hit live dev backend
 *  - 90 s LLM timeout per call
 */

import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

const SS_DIR = path.join("/tmp", "inline-omics-e2e");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

const LLM_TIMEOUT = 90_000;
test.setTimeout(20 * 60_000);

let sharedPage: Page;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

async function ss(page: Page, name: string) {
  await page.screenshot({ path: path.join(SS_DIR, `${name}.png`), fullPage: false });
  console.log(`[SS] ${path.join(SS_DIR, `${name}.png`)}`);
}

async function newSession(page: Page) {
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const newChatBtn = page.locator('[data-testid="button-new-chat"]').first();
  if (await newChatBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await newChatBtn.click();
    await page.waitForTimeout(500);
  }
}

async function sendMessage(page: Page, text: string) {
  const composer = page.locator(
    'textarea, input[placeholder*="Ask"], input[placeholder*="Describe"]'
  ).first();
  await expect(composer).toBeVisible({ timeout: 30_000 });
  await composer.fill(text);
  await composer.press("Enter");
}

async function waitForAssistant(page: Page, timeoutMs = LLM_TIMEOUT) {
  await waitForResponseComplete(page, timeoutMs);
  const el = page.locator('[data-is-latest-assistant="true"]').first();
  await el.waitFor({ state: "attached", timeout: timeoutMs }).catch(() => {});
  return el;
}

/**
 * Assert that the workflow panel opened after an inline-data message.
 * Returns the panel's full text content (for downstream name assertions).
 * Returns null if an infra error (Galaxy backend down) — caller should skip.
 */
async function assertPanelOpened(page: Page, label: string): Promise<string | null> {
  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  const panelVisible = await panel.isVisible({ timeout: 15_000 }).catch(() => false);

  if (!panelVisible) {
    const latestMsg = await page.locator('[data-is-latest-assistant="true"]').first()
      .textContent().catch(() => "");
    console.log(`[${label}] No panel — latest response (first 250): ${latestMsg?.slice(0, 250)}`);

    const isInfra =
      latestMsg?.includes("ECONNREFUSED") ||
      latestMsg?.includes("ENOTFOUND") ||
      latestMsg?.includes("unreachable") ||
      latestMsg?.includes("backend connection") ||
      latestMsg?.includes("AI Assistant not available");

    if (isInfra) {
      console.warn(`[${label}] INFRA-SKIP: Galaxy backend unavailable — skipping test`);
      return null;
    }

    expect(panelVisible,
      `[${label}] Panel did not open. Backend returned needs_input or chat_only instead of ` +
      `workflow_ready. Response: "${latestMsg?.slice(0, 250)}"`
    ).toBe(true);
    return "";
  }

  const panelText = await panel.textContent({ timeout: 5_000 }).catch(() => "") ?? "";
  console.log(`[${label}] Panel opened — content (first 300): ${panelText.slice(0, 300)}`);

  // Confirm chip/card is visible in chat
  const chip = page.locator('[data-testid^="workflow-artifact-anchor-"], .wf-chip').first();
  const chipVisible = await chip.isVisible({ timeout: 5_000 }).catch(() => false);
  console.log(`[${label}] Workflow chip in chat: ${chipVisible}`);

  return panelText;
}

// ---------------------------------------------------------------------------
// Setup / teardown
// ---------------------------------------------------------------------------

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);
  console.log("[Auth] Fixture login complete");
});

test.afterAll(async () => {
  await sharedPage?.close();
});

// ============================================================================
// UC-1 — 10x scRNA-seq barcode/gene matrix → single-cell workflow
// ============================================================================

test("UC-1: 10x scRNA-seq barcode matrix routes to single-cell workflow (not bulk DE)", async () => {
  const page = sharedPage;
  await newSession(page);
  await ss(page, "UC1_00_new_session");

  // 8-barcode × 6-gene matrix — barcodes are the row IDs, genes are columns
  // This is unmistakably single-cell (10x Chromium barcodes, immune marker genes).
  const message = [
    "Cluster these single-cell RNA-seq counts from a 10x Chromium run and generate a UMAP:",
    "barcode,CD3D,CD4,CD8A,MS4A1,CD19,GNLY",
    "AAACCTGAGAAGGCCT,45,32,0,0,0,1",
    "AAACCTGAGACAGACC,0,0,38,0,0,0",
    "AAACCTGAGACTTTCG,0,0,0,87,91,0",
    "AAACCTGAGATCACGG,12,8,0,0,0,0",
    "AAACCTGAGCGATAGC,0,0,0,0,0,112",
    "AAACCTGAGCGCTTAT,22,18,0,0,0,0",
    "AAACCTGAGGCTAGCA,0,0,0,74,82,0",
    "AAACCTGAGTCACGAA,1,0,44,0,0,2",
  ].join("\n");

  await sendMessage(page, message);
  const assistantEl = await waitForAssistant(page, LLM_TIMEOUT);
  await ss(page, "UC1_01_response");

  const responseText = await assistantEl.textContent({ timeout: LLM_TIMEOUT }).catch(() => "");
  console.log("[UC-1] Response length:", responseText?.length);
  console.log("[UC-1] Response (first 200):", responseText?.slice(0, 200));

  const panelText = await assertPanelOpened(page, "UC-1");
  if (panelText === null) return; // infra skip

  // Combined text for assertions
  const combined = ((panelText ?? "") + " " + (responseText ?? "")).toLowerCase();

  // Must NOT route purely to a bulk differential expression pipeline
  const looksLikeBulkDEOnly =
    /differentialabundance/.test(combined) &&
    !/scrna|seurat|scanpy|single.cell|singlecell|sc_rna/.test(combined);
  console.log("[UC-1] Routes to bulk-DE-only:", looksLikeBulkDEOnly);
  expect(looksLikeBulkDEOnly, "10x scRNA matrix must NOT route to a bulk DE pipeline").toBe(false);

  // Response text must acknowledge single-cell analysis
  expect(responseText?.toLowerCase()).toMatch(
    /cluster|umap|dimensionality|cell type|single.cell|scrna|seurat|scanpy/
  );

  await ss(page, "UC1_02_panel_verified");
  console.log("[UC-1] PASS — single-cell workflow routed; bulk-DE routing rejected");
});

// ============================================================================
// UC-2 — Tab-separated VCF variant rows → variant annotation / GWAS workflow
// ============================================================================

test("UC-2: tab-separated VCF variants route to variant analysis workflow", async () => {
  const page = sharedPage;
  await newSession(page);
  await ss(page, "UC2_00_new_session");

  // Tab-separated: CHROM, POS, ID, REF, ALT, QUAL (numeric), AF (numeric)
  // The tabular regex fires on QUAL/AF columns → count_matrix in inlineDataMap
  const message = [
    "Annotate and filter these germline variants for a population study:",
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tAF",
    "1\t752566\trs3094315\tG\tA\t60\t0.42",
    "1\t776546\trs12124819\tA\tG\t55\t0.31",
    "1\t798959\trs11240777\tG\tA\t71\t0.18",
    "1\t800007\trs6681049\tC\tT\t80\t0.09",
    "1\t838555\trs4970383\tC\tT\t63\t0.24",
    "1\t846808\trs4475691\tC\tT\t58\t0.37",
    "1\t854250\trs7537756\tA\tG\t74\t0.11",
  ].join("\n");

  await sendMessage(page, message);
  const assistantEl = await waitForAssistant(page, LLM_TIMEOUT);
  await ss(page, "UC2_01_response");

  const responseText = await assistantEl.textContent({ timeout: LLM_TIMEOUT }).catch(() => "");
  console.log("[UC-2] Response length:", responseText?.length);
  console.log("[UC-2] Response (first 200):", responseText?.slice(0, 200));

  const panelText = await assertPanelOpened(page, "UC-2");
  if (panelText === null) return; // infra skip

  // Workflow must be variant/GWAS family
  const combined = ((panelText ?? "") + " " + (responseText ?? "")).toLowerCase();
  const isVariantWorkflow =
    /sarek|gatk|plink|regenie|variant|annotate|gwas|vep|snp|vcf|population/.test(combined);
  console.log("[UC-2] Variant workflow detected in panel+response:", isVariantWorkflow);
  expect(isVariantWorkflow, "must route to a variant annotation or GWAS pipeline").toBe(true);

  // Response must NOT re-ask for the data we already provided
  expect(responseText).not.toMatch(
    /please provide|can you share|need.*file|upload.*vcf|attach.*variant/i
  );

  await ss(page, "UC2_02_panel_verified");
  console.log("[UC-2] PASS — variant workflow routed; AI did not re-request provided data");
});

// ============================================================================
// UC-3 — Multi-compound SMILES → ADMET / drug-property screening workflow
// ============================================================================

test("UC-3: SMILES drug candidates route to ADMET screening workflow", async () => {
  const page = sharedPage;
  await newSession(page);
  await ss(page, "UC3_00_new_session");

  // 5 SMILES strings — LLM extractor (Gemini) should detect these as smiles type
  // (they don't have ≥2 numeric columns, so the tabular regex won't fire)
  const message = [
    "Run full ADMET profiling on these five drug candidates and flag any hERG or CYP3A4 liabilities:",
    "CC(=O)Oc1ccccc1C(=O)O",
    "CN1CCC[C@H]1c2cccnc2",
    "CC12CCC3C(C1CCC2O)CCC4=CC(=O)CCC34C",
    "c1ccc2c(c1)cc1ccccc1n2",
    "COc1cc2c(cc1OC)C(=O)c1ccccc1C2=O",
  ].join("\n");

  await sendMessage(page, message);
  const assistantEl = await waitForAssistant(page, LLM_TIMEOUT);
  await ss(page, "UC3_01_response");

  const responseText = await assistantEl.textContent({ timeout: LLM_TIMEOUT }).catch(() => "");
  console.log("[UC-3] Response length:", responseText?.length);
  console.log("[UC-3] Response (first 200):", responseText?.slice(0, 200));

  const panelText = await assertPanelOpened(page, "UC-3");
  if (panelText === null) return; // infra skip

  // Workflow must be ADMET / drug-property family
  const combined = ((panelText ?? "") + " " + (responseText ?? "")).toLowerCase();
  const isAdmetWorkflow =
    /admet|drug|pkpd|tox|property|screen|herg|cyp|absorption|pharmacokinet/.test(combined);
  console.log("[UC-3] ADMET/drug workflow detected:", isAdmetWorkflow);
  expect(isAdmetWorkflow, "must route to an ADMET or drug-property pipeline").toBe(true);

  // Response text must acknowledge ADMET concepts
  expect(responseText?.toLowerCase()).toMatch(
    /admet|herg|cyp|absorption|toxicit|pharmacokinet|bioavail/
  );

  // Assistant must NOT re-ask for the SMILES the user already provided.
  // Failure here means inlineDataMap was empty (e.g. Gemini returned an array that
  // got dropped before the extractInlineDataWithLLM fix) so the LLM didn't know
  // the compounds were already in the message.
  expect(responseText, "must not re-request already-provided SMILES").not.toMatch(
    /please provide|can you (share|give|send|paste)|need.*smiles|upload.*sdf|attach.*compound|what (molecule|compound|structure)/i
  );

  await ss(page, "UC3_02_panel_verified");
  console.log("[UC-3] PASS — ADMET workflow routed; response mentions drug properties");
});

// ============================================================================
// UC-6 — Compound table (name + SMILES column) without explicit ADMET keywords
// ============================================================================
//
// Why this test exists:
//   UC-3 uses the ADMET+SMILES fast path (message contains "hERG"/"ADMET") so
//   needsWorkflowGeneration is forced true even if inlineDataMap is empty.
//   UC-6 uses a physicochemical-properties request with NO ADMET keywords, so
//   the routing relies on extractInlineDataWithLLM correctly surfacing the SMILES
//   table in inlineDataMap.  If Gemini returns an array that was previously
//   dropped (pre-fix), inlineDataMap is empty, the LLM has no "data already
//   provided" context, and may re-ask — failing the not.toMatch assertion below.

test("UC-6: compound name+SMILES table routes to property workflow without re-asking for structures", async () => {
  const page = sharedPage;
  await newSession(page);
  await ss(page, "UC6_00_new_session");

  // CSV table: compound name column + SMILES column.
  // No ADMET/hERG keywords → ADMET fast path is NOT triggered.
  // Routing must come from inlineDataMap populated by extractInlineDataWithLLM.
  const message = [
    "Calculate the molecular weight, LogP, and number of hydrogen bond donors/acceptors for each of these compounds:",
    "compound_name,smiles",
    "aspirin,CC(=O)Oc1ccccc1C(=O)O",
    "caffeine,Cn1cnc2c1c(=O)n(C)c(=O)n2C",
    "ibuprofen,CC(C)Cc1ccc(cc1)C(C)C(=O)O",
    "paracetamol,CC(=O)Nc1ccc(O)cc1",
    "metformin,CN(C)C(=N)NC(=N)N",
  ].join("\n");

  await sendMessage(page, message);
  const assistantEl = await waitForAssistant(page, LLM_TIMEOUT);
  await ss(page, "UC6_01_response");

  const responseText = await assistantEl.textContent({ timeout: LLM_TIMEOUT }).catch(() => "");
  console.log("[UC-6] Response length:", responseText?.length);
  console.log("[UC-6] Response (first 300):", responseText?.slice(0, 300));

  // Must be a substantive response
  expect(responseText?.trim().length ?? 0, "response must be non-empty").toBeGreaterThan(50);

  // Critical assertion: assistant must NOT ask for the structures the user already pasted.
  // This fails if inlineDataMap was empty (arrays dropped) because the system prompt
  // would lack the "these values are already provided" context block.
  expect(responseText, "must not re-request already-provided SMILES/structures").not.toMatch(
    /please provide|can you (share|give|send|paste)|need.*smiles|upload.*sdf|attach.*compound|what (molecule|compound|structure)|provide.*structure|share.*smiles/i
  );

  // Response should engage with the physicochemical request
  expect(responseText?.toLowerCase()).toMatch(
    /molecular weight|logp|hydrogen bond|mw|donor|acceptor|property|properties|lipinski|aspirin|caffeine|ibuprofen/i
  );

  // No workflow card expected (property calculation may return chat-only or workflow)
  const cardCount = await page.locator('[data-testid^="workflow-artifact-anchor-"]').count();
  console.log("[UC-6] Workflow cards found:", cardCount);

  await ss(page, "UC6_02_verified");
  console.log("[UC-6] PASS — compound table processed; assistant did not re-request structures");
});
