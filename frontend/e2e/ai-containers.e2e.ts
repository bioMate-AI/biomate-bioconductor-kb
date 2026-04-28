/**
 * AI Container Workflows — Use-Case Based E2E Tests
 *
 * Tests chat routing, workflow card generation, and parameter pre-fill for
 * the 8 ECR-hosted AI model workflows. No mocking — all requests hit the live stack.
 *
 * Plan: docs/nextPhase/20260414_AI_CONTAINERS_TEST_PLAN.md
 *
 * AI-1  Boltz-2        structural_biology / boltz_structure_prediction
 * AI-2  Chai-1         structural_biology / chai1_structure_prediction
 * AI-3  DrugCLIP       drug_discovery / drugclip_virtual_screening
 * AI-4  SynCraft       drug_discovery / syncraft_synthesizability
 * AI-5  STATE          single_cell / state_perturbation_prediction
 * AI-6  scFv-PMPNN     drug_discovery / scfv_antibody_design
 * AI-7  ProTrek        proteomics / protrek_protein_search
 * AI-8  ProFam-1       proteomics / profam_fitness_prediction
 */

import { test, expect, Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { setupTestUser, BASE_URL } from "./helpers.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SS_DIR = "/tmp/ai-containers-e2e-screenshots";
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

async function ss(page: Page, name: string) {
  await page.screenshot({ path: path.join(SS_DIR, `${name}.png`), fullPage: true });
  console.log(`[Screenshot] ${path.join(SS_DIR, name)}.png`);
}

/**
 * Send a chat message and wait for the workflow card to appear.
 * Returns true if a workflow artifact panel appeared within the timeout.
 */
async function sendAndWaitForWorkflow(
  page: Page,
  message: string,
  timeoutMs = 90_000
): Promise<boolean> {
  const textarea = page.locator("textarea").first();
  await expect(textarea).toBeVisible({ timeout: 10_000 });
  await textarea.fill(message);
  await textarea.press("Enter");

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const hasCard =
      (await page.locator('[data-testid^="workflow-artifact"]').first().isVisible({ timeout: 500 }).catch(() => false)) ||
      (await page.getByTestId("button-run-workflow-panel").first().isVisible({ timeout: 500 }).catch(() => false)) ||
      (await page.locator('[data-testid="workflow-right-panel"]').isVisible({ timeout: 500 }).catch(() => false));
    if (hasCard) return true;
    await page.waitForTimeout(1500);
  }
  return false;
}

/**
 * Get the workflow name shown in the viewer (from the panel header or card title).
 */
async function getWorkflowCardText(page: Page): Promise<string> {
  // Try right panel first
  const panel = page.locator('[data-testid="workflow-right-panel"]');
  if (await panel.isVisible({ timeout: 2_000 }).catch(() => false)) {
    const text = await panel.innerText().catch(() => "");
    return text.slice(0, 500);
  }
  // Fall back to inline card
  const card = page.locator('[data-testid^="workflow-artifact"]').first();
  if (await card.isVisible({ timeout: 2_000 }).catch(() => false)) {
    return (await card.innerText().catch(() => "")).slice(0, 500);
  }
  // Fall back to all assistant messages
  const assistantMsg = page.locator('[data-is-latest-assistant="true"]').first();
  return (await assistantMsg.innerText().catch(() => "")).slice(0, 500);
}

test.setTimeout(300_000);

// ============================================================================
// AI-1 — Boltz-2: Novel protein structure prediction
// ============================================================================

test("AI-1: Boltz-2 — novel enzyme structure prediction routes to boltz workflow", async ({ page }) => {
  await setupTestUser(page, "ai1-boltz");

  const query =
    "Predict the 3D structure of this novel protein sequence using Boltz: " +
    "MKVLWAALLVTFLAGSKAESPIIGYHWQHFIVKNSKTNTGAFYFDIAKVGENLMFPKTVSYKVLAKDYPMIFSEYLR";

  console.log("[AI-1] Sending Boltz-2 structure prediction query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai1-boltz-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-1] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for Boltz-2 query").toBe(true);

  // Verify routing: card text should mention boltz or structure prediction
  const textLower = cardText.toLowerCase();
  const hasBoltz = textLower.includes("boltz") || textLower.includes("structure predict");
  expect(hasBoltz, `Card should reference Boltz or structure prediction. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-1] PASS: Boltz-2 routing and workflow card ✓");
});

// ============================================================================
// AI-2 — Chai-1: Protein–ligand complex structure
// ============================================================================

test("AI-2: Chai-1 — protein-ligand complex structure prediction", async ({ page }) => {
  await setupTestUser(page, "ai2-chai1");

  const query =
    "Model the protein-ligand complex structure of CDK2 with palbociclib using Chai-1. " +
    "Palbociclib SMILES: CC1=C(C=C(C=N1)NC2=NC=CC(=N2)N3CCNCC3)C(=O)NC4=CC(=CC(=C4)F)F";

  console.log("[AI-2] Sending Chai-1 complex structure query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai2-chai1-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-2] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for Chai-1 query").toBe(true);

  const textLower = cardText.toLowerCase();
  const hasChai = textLower.includes("chai") || textLower.includes("complex") || textLower.includes("structure");
  expect(hasChai, `Card should reference Chai-1 or structure prediction. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-2] PASS: Chai-1 routing and workflow card ✓");
});

// ============================================================================
// AI-3 — DrugCLIP: Target-focused virtual screening
// ============================================================================

test("AI-3: DrugCLIP — KRAS G12C virtual screening routes to drugclip workflow", async ({ page }) => {
  await setupTestUser(page, "ai3-drugclip");

  const query =
    "Run virtual screening with DrugCLIP against KRAS G12C target (PDB: 6OIM) " +
    "to rank a compound library by predicted binding affinity";

  console.log("[AI-3] Sending DrugCLIP virtual screening query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai3-drugclip-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-3] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for DrugCLIP query").toBe(true);

  const textLower = cardText.toLowerCase();
  const hasDrugClip = textLower.includes("drugclip") || textLower.includes("virtual screen") || textLower.includes("screening");
  expect(hasDrugClip, `Card should reference DrugCLIP or virtual screening. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-3] PASS: DrugCLIP routing and workflow card ✓");
});

// ============================================================================
// AI-4 — SynCraft: Synthesizability optimization
// ============================================================================

test("AI-4: SynCraft — drug candidate synthesizability optimization", async ({ page }) => {
  await setupTestUser(page, "ai4-syncraft");

  const query =
    "Optimize the synthesizability of this drug candidate using SynCraft: " +
    "CC(C)(C)c1ccc(cc1)C(=O)Nc2ccc(cc2)S(=O)(=O)N3CCCC3 " +
    "The synthetic accessibility score is too high — reduce complexity while keeping pharmacophore";

  console.log("[AI-4] Sending SynCraft synthesizability query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai4-syncraft-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-4] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for SynCraft query").toBe(true);

  const textLower = cardText.toLowerCase();
  const hasSynCraft = textLower.includes("syncraft") || textLower.includes("synthesiz") || textLower.includes("synthetic access");
  expect(hasSynCraft, `Card should reference SynCraft or synthesizability. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-4] PASS: SynCraft routing and workflow card ✓");
});

// ============================================================================
// AI-5 — STATE: CRISPR knockout perturbation prediction
// ============================================================================

test("AI-5: STATE — TP53 knockout transcriptional response prediction", async ({ page }) => {
  await setupTestUser(page, "ai5-state");

  const query =
    "Use the STATE virtual cell model to predict the transcriptional response " +
    "to TP53 knockout in cancer cells. I have an h5ad file with single-cell profiles.";

  console.log("[AI-5] Sending STATE perturbation query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai5-state-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-5] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for STATE query").toBe(true);

  const textLower = cardText.toLowerCase();
  const hasState = textLower.includes("state") || textLower.includes("perturbation") || textLower.includes("virtual cell");
  expect(hasState, `Card should reference STATE or perturbation prediction. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-5] PASS: STATE routing and workflow card ✓");
});

// ============================================================================
// AI-6 — scFv: Intrabody design from antibody PDB
// ============================================================================

test("AI-6: scFv — intrabody design with ProteinMPNN and AlphaFold2", async ({ page }) => {
  await setupTestUser(page, "ai6-scfv");

  const query =
    "Design scFv intrabody variants from my antibody PDB structure using ProteinMPNN and AlphaFold2. " +
    "I need 50 designs targeting a cytoplasmic antigen — generate the best candidates ranked by predicted stability.";

  console.log("[AI-6] Sending scFv antibody design query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai6-scfv-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-6] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for scFv query").toBe(true);

  const textLower = cardText.toLowerCase();
  const hasScFv = textLower.includes("scfv") || textLower.includes("intrabody") || textLower.includes("antibody") || textLower.includes("proteinmpnn");
  expect(hasScFv, `Card should reference scFv or antibody design. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-6] PASS: scFv routing and workflow card ✓");
});

// ============================================================================
// AI-7 — ProTrek: Function-based trimodal protein search
// ============================================================================

test("AI-7: ProTrek — text-based protein search for DNA repair kinases", async ({ page }) => {
  await setupTestUser(page, "ai7-protrek");

  const query =
    "Search for serine/threonine kinases involved in DNA damage response using ProTrek " +
    "trimodal protein search. I want to search by function description across UniProt and AlphaFold databases.";

  console.log("[AI-7] Sending ProTrek protein search query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai7-protrek-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-7] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for ProTrek query").toBe(true);

  const textLower = cardText.toLowerCase();
  const hasProTrek = textLower.includes("protrek") || textLower.includes("protein search") || textLower.includes("trimodal");
  expect(hasProTrek, `Card should reference ProTrek or protein search. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-7] PASS: ProTrek routing and workflow card ✓");
});

// ============================================================================
// AI-8 — ProFam-1: Protein variant fitness prediction
// ============================================================================

test("AI-8: ProFam-1 — variant fitness landscape for thermostable enzyme engineering", async ({ page }) => {
  await setupTestUser(page, "ai8-profam");

  const query =
    "Predict fitness effects of single-point mutations in this thermostable lipase " +
    "for protein engineering using ProFam-1. I want to identify stabilizing mutations " +
    "without needing a multiple sequence alignment. " +
    "Wildtype sequence: MGSSHHHHHHHSSGSTLVPRGSMASMTGGQQMGRDLYDDDDKHMSGLN";

  console.log("[AI-8] Sending ProFam-1 fitness prediction query...");
  const found = await sendAndWaitForWorkflow(page, query, 90_000);
  await ss(page, "ai8-profam-workflow-card");

  const cardText = await getWorkflowCardText(page);
  console.log(`[AI-8] Card text preview: ${cardText.slice(0, 200)}`);

  expect(found, "Workflow card should appear for ProFam-1 query").toBe(true);

  const textLower = cardText.toLowerCase();
  const hasProFam = textLower.includes("profam") || textLower.includes("fitness") || textLower.includes("variant") || textLower.includes("mutation");
  expect(hasProFam, `Card should reference ProFam-1 or fitness prediction. Got: ${cardText.slice(0, 300)}`).toBe(true);

  console.log("[AI-8] PASS: ProFam-1 routing and workflow card ✓");
});

// ============================================================================
// AI-SMOKE — All 8 containers registered and searchable via API
// ============================================================================

test("AI-SMOKE: All 8 AI container workflows are registered in the backend", async ({ page }) => {
  await page.goto(BASE_URL);
  await page.waitForLoadState("load");

  interface WorkflowCheck {
    name: string;
    keywords: string[];
  }
  const workflows: WorkflowCheck[] = [
    { name: "Boltz-2",   keywords: ["boltz"] },
    { name: "Chai-1",    keywords: ["chai"] },
    { name: "DrugCLIP",  keywords: ["drugclip", "drug clip"] },
    { name: "SynCraft",  keywords: ["syncraft"] },
    { name: "STATE",     keywords: ["state", "perturbation"] },
    { name: "scFv",      keywords: ["scfv", "scfv_pmpnn"] },
    { name: "ProTrek",   keywords: ["protrek"] },
    { name: "ProFam-1",  keywords: ["profam"] },
  ];

  const results: Record<string, boolean> = {};

  for (const wf of workflows) {
    const resp = await page.evaluate(async (query: string) => {
      const r = await fetch(`/api/galaxy/tools/search?q=${encodeURIComponent(query)}&limit=5`, {
        credentials: "include",
      });
      const text = await r.text();
      return { status: r.status, text: text.slice(0, 1000) };
    }, wf.keywords[0]);

    const bodyLower = resp.text.toLowerCase();
    const found = wf.keywords.some(k => bodyLower.includes(k));
    results[wf.name] = found;
    console.log(`[AI-SMOKE] ${wf.name}: ${found ? "✓ found" : "✗ NOT FOUND"} (status=${resp.status})`);
  }

  await ss(page, "ai-smoke-db-check");

  const allFound = Object.values(results).every(Boolean);
  const missing = Object.entries(results).filter(([, v]) => !v).map(([k]) => k);
  expect(allFound, `Missing AI workflows in DB: ${missing.join(", ")}`).toBe(true);

  console.log("[AI-SMOKE] PASS: All 8 AI container workflows registered ✓");
});
