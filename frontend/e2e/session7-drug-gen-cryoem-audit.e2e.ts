/**
 * session7-drug-gen-cryoem-audit.e2e.ts
 *
 * Session 7 E2E tests: de novo drug generation (REINVENT4) and cryo-EM
 * knowledge system validation (RAG context → LLM response, QC thresholds,
 * best practices panel).
 *
 * All tests hit the live backend — no API mocking.
 * Drug generation: validates REINVENT4 routing + drug-likeness knowledge.
 * Cryo-EM: validates the two-path knowledge system (BGE RAG + expert JSON).
 */

import { test, expect, Page } from "@playwright/test";
import { setupTestUser } from "./helpers.js";
import {
  SimulatedUser,
  SIMULATED_USER_SCENARIOS,
} from "./helpers/simulated-user.js";

// ---------------------------------------------------------------------------
// Timeout constants (match existing suite conventions)
// ---------------------------------------------------------------------------
const SIMPLE_TIMEOUT = 10 * 60 * 1000;  // 10 min — drug gen routing
const MEDIUM_TIMEOUT = 25 * 60 * 1000;  // 25 min — cryo-EM knowledge

// ---------------------------------------------------------------------------
// Helper: check if page text contains any of the given terms
// ---------------------------------------------------------------------------
function bodyContainsAny(pageText: string, terms: string[]): { found: boolean; match: string | null } {
  const lower = pageText.toLowerCase();
  for (const term of terms) {
    if (lower.includes(term.toLowerCase())) {
      return { found: true, match: term };
    }
  }
  return { found: false, match: null };
}

// ============================================================================
// DRUG GENERATION TESTS — REINVENT4 De Novo
// ============================================================================

test.describe("Session 7 — De Novo Drug Generation (REINVENT4)", () => {

  test("DD-S7-1: De novo drug generation routes to REINVENT4 workflow", async ({ page }) => {
    test.setTimeout(SIMPLE_TIMEOUT);
    await setupTestUser(page, "dd-s7-1-denovo");

    const user = new SimulatedUser(page, SIMULATED_USER_SCENARIOS.de_novo_drug_generation);
    await user.reachWorkflowCard({ maxRounds: 4, requireWorkflowCard: true });

    console.log(`DD-S7-1 clarification rounds: ${user.getClarificationRoundsUsed()}`);
    console.log(`DD-S7-1 history:\n${user.getConversationHistory().join("\n---\n")}`);

    const pageText = (await page.textContent("body")) ?? "";
    const check = bodyContainsAny(pageText, [
      "reinvent", "generative", "scaffold", "de novo", "molecule generation",
      "lead optimization", "drug design", "compound generation",
    ]);
    console.log(`DD-S7-1 generative content found: ${check.found} (matched: "${check.match}")`);
    expect(check.found).toBe(true);

    // Run button must be reachable
    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    await expect(runBtn).toBeVisible({ timeout: 10_000 });
  });

  test("DD-S7-2: Drug generation response mentions drug-likeness / QED / Lipinski", async ({ page }) => {
    test.setTimeout(SIMPLE_TIMEOUT);
    await setupTestUser(page, "dd-s7-2-qed-check");

    const user = new SimulatedUser(page, SIMULATED_USER_SCENARIOS.de_novo_drug_generation);
    await user.reachWorkflowCard({ maxRounds: 4, requireWorkflowCard: true });

    console.log(`DD-S7-2 clarification rounds: ${user.getClarificationRoundsUsed()}`);

    const pageText = (await page.textContent("body")) ?? "";
    const check = bodyContainsAny(pageText, [
      "qed", "drug-likeness", "drug likeness", "lipinski",
      "rule of five", "ro5", "molecular weight", "logp",
      "mw ", "bioavailability", "oral availability",
    ]);
    console.log(`DD-S7-2 drug-likeness mention: ${check.found} (matched: "${check.match}")`);
    // Log page snippet for audit
    console.log(`DD-S7-2 page snippet: ${pageText.slice(0, 600)}`);

    expect(check.found).toBe(true);

    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    await expect(runBtn).toBeVisible({ timeout: 10_000 });
  });
});

// ============================================================================
// CRYO-EM KNOWLEDGE VALIDATION TESTS
// ============================================================================

test.describe("Session 7 — Cryo-EM Knowledge System Validation", () => {

  test("CE-S7-3: Cryo-EM knowledge — RAG context shapes LLM response (param table + GPCR/saposin)", async ({ page }) => {
    test.setTimeout(MEDIUM_TIMEOUT);
    await setupTestUser(page, "ce-s7-3-rag-validate");

    const user = new SimulatedUser(page, SIMULATED_USER_SCENARIOS.cryoem_knowledge_validation);
    await user.reachWorkflowCard({ maxRounds: 3, requireWorkflowCard: true });

    console.log(`CE-S7-3 clarification rounds: ${user.getClarificationRoundsUsed()}`);
    console.log(`CE-S7-3 history:\n${user.getConversationHistory().join("\n---\n")}`);

    const pageText = (await page.textContent("body")) ?? "";

    // RAG parameter table injected → LLM should reference pixel size or defocus
    const paramCheck = bodyContainsAny(pageText, [
      "pixel size", "0.83", "defocus", "ctf", "motion correction", "å/pixel", "angstrom",
    ]);
    // Sample-class RAG hit → GPCR / saposin / nanodisc content
    const sampleCheck = bodyContainsAny(pageText, [
      "gpcr", "saposin", "nanodisc", "g protein", "membrane protein", "lipid",
    ]);

    console.log(`CE-S7-3 param context: ${paramCheck.found} (matched: "${paramCheck.match}")`);
    console.log(`CE-S7-3 sample context: ${sampleCheck.found} (matched: "${sampleCheck.match}")`);
    console.log(`CE-S7-3 page snippet: ${pageText.slice(0, 800)}`);

    // At least one of the two RAG paths must have reached the LLM response
    expect(paramCheck.found || sampleCheck.found).toBe(true);

    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    await expect(runBtn).toBeVisible({ timeout: 10_000 });
  });

  test("CE-S7-4: Cryo-EM knowledge panel — best practices or knowledge block visible in UI", async ({ page }) => {
    test.setTimeout(MEDIUM_TIMEOUT);
    await setupTestUser(page, "ce-s7-4-panel-check");

    const user = new SimulatedUser(page, SIMULATED_USER_SCENARIOS.cryoem_knowledge_validation);
    await user.reachWorkflowCard({ maxRounds: 3, requireWorkflowCard: true });

    console.log(`CE-S7-4 clarification rounds: ${user.getClarificationRoundsUsed()}`);

    // Check for dedicated knowledge panel
    const knowledgePanelVisible = await page
      .getByTestId("knowledge-highlights-panel")
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    const workflowPanelVisible = await page
      .getByTestId("workflow-artifact-panel")
      .isVisible({ timeout: 5_000 })
      .catch(() => false);

    console.log(`CE-S7-4 knowledge-highlights-panel: ${knowledgePanelVisible}`);
    console.log(`CE-S7-4 workflow-artifact-panel: ${workflowPanelVisible}`);

    const pageText = (await page.textContent("body")) ?? "";
    const textCheck = bodyContainsAny(pageText, [
      "fsc", "gold-standard", "gold standard", "best practice",
      "pixel size", "cryosparc", "recommended", "protocol",
    ]);
    console.log(`CE-S7-4 best-practices text: ${textCheck.found} (matched: "${textCheck.match}")`);

    // Pass if ANY of: dedicated panel, workflow panel, or knowledge text in body
    expect(knowledgePanelVisible || workflowPanelVisible || textCheck.found).toBe(true);
  });

  test("CE-S7-5: Cryo-EM QC — gold-standard FSC threshold or resolution criterion visible", async ({ page }) => {
    test.setTimeout(MEDIUM_TIMEOUT);
    await setupTestUser(page, "ce-s7-5-qc-threshold");

    const user = new SimulatedUser(page, SIMULATED_USER_SCENARIOS.cryoem_knowledge_validation);
    await user.reachWorkflowCard({ maxRounds: 3, requireWorkflowCard: true });

    console.log(`CE-S7-5 clarification rounds: ${user.getClarificationRoundsUsed()}`);

    const pageText = (await page.textContent("body")) ?? "";
    const qcCheck = bodyContainsAny(pageText, [
      "0.143",        // gold-standard FSC criterion
      "half-map",     // half-map FSC
      "b-factor",     // B-factor sharpening
      "resolution",   // general resolution mention
      "signal-to-noise",
      "snr",
      "fsc",
      "molprobity",
    ]);
    console.log(`CE-S7-5 QC threshold found: ${qcCheck.found} (matched: "${qcCheck.match}")`);
    console.log(`CE-S7-5 page snippet: ${pageText.slice(0, 800)}`);

    expect(qcCheck.found).toBe(true);

    const runBtn = page.getByTestId("button-run-workflow-panel").first();
    await expect(runBtn).toBeVisible({ timeout: 10_000 });
  });
});
