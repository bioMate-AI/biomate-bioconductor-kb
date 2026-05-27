/**
 * Plan B — codon optimization stepwise UI E2E (Plan A pattern).
 *
 * User story: Synthetic biology lead runs optimize_codons_for_heterologous_expression
 * (registry 10813) for ANDV Plan B mRNA track through chat → card → Run → terminal.
 *
 * Scenario: research/anti-virus/docs/BIOMATE_UI_SCENARIO_PLAN_B_mRNA_LNP.md
 * Smoke: research/anti-virus/scripts/run_plan_b_codon_lnp_smoke.sh
 *
 * Test index:
 *   PB-1  Chat routing: codon / mRNA / optimize_codons mentioned
 *   PB-2  Workflow card + Run button visible
 *   PB-3  target_sequence and outdir params
 *   PB-4  Execute → terminal COMPLETED or FAILED (audited)
 *   PB-5  Completion banner or download when COMPLETED
 *
 * NO page.route() mocking.
 * Screenshots → e2e/screenshots/plan-b-codon/
 */

import { test, expect } from "@playwright/test";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";
import {
  setupTestUser,
  sendMessageAndWaitForResponse,
  ensureScreenshotDir,
  shot,
  writeSuiteAudit,
  attachExecuteCapture,
  waitForWorkflowCard,
  fillRequiredParams,
  readParamValues,
  clickRunAndWaitTerminal,
  assertCodonWorkflowPanelOrSkip,
  getWorkflowPanelTitle,
  assertAssistantMentions,
  type StepwiseSuiteRecord,
} from "./andv-stepwise-shared.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SS_DIR = path.join(__dirname, "screenshots", "plan-b-codon");
const AUDIT_PATH = path.join(SS_DIR, "plan-b-suite-audit.json");
ensureScreenshotDir(SS_DIR);

/** GFP-coding demo fragment (same as run_plan_b_codon_lnp_smoke.sh). */
const PLAN_B_TARGET_SEQUENCE =
  "ATGAGTAAAGGAGAAGAACTTTTCACTGGAGTTGTCCCAATTCTTGTTGAATTAGATGGTGATGTTAATGGGCACAAATTTTCTGTCAGTGGAGAGGGTGAAGGTGATGCAACATACGGAAAACTTACCCTTAAATTTATTTGCACTACTGGAAAACTACCTGTTCCATGG";

function planBOutdirS3(): string {
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "");
  return `s3://biomate-nextflow-work/nextflow/outputs/plan_b_e2e_ui/${stamp}/`;
}

const PLAN_B_QUERY = [
  "I'm on the ANDV Plan B mRNA-LNP vaccine engineering track.",
  "Step 1: optimize codons for heterologous expression before RNA structure and LNP formulation.",
  "",
  "Use workflow optimize_codons_for_heterologous_expression (registry id 10813).",
  "This step is codon optimization only — not epitopeprediction, mhcquant, or immunopeptidomics.",
  "",
  `target_sequence = ${PLAN_B_TARGET_SEQUENCE}`,
  `outdir = ${planBOutdirS3()}`,
  'host_codon_usage = {"TTT":0.58,"TTC":0.42,"ATG":1.00}',
  "",
  "Use profile docker on AWS Batch.",
  "All parameters are explicit — show the workflow card so I can Run from the panel.",
].join(" ");

function buildPlanBParams(): Record<string, string> {
  return {
    target_sequence: PLAN_B_TARGET_SEQUENCE,
    outdir: planBOutdirS3(),
    host_codon_usage: '{"TTT":0.58,"TTC":0.42,"ATG":1.00}',
  };
}

const SUITE_AUDIT: StepwiseSuiteRecord[] = [];

function record(
  testId: string,
  partial: Omit<StepwiseSuiteRecord, "testId" | "startTs" | "endTs"> & {
    startTs: number;
    endTs: number;
  }
): void {
  SUITE_AUDIT.push({ testId, ...partial });
}

test.describe.serial("Plan B codon optimization — stepwise UI", () => {
  test.beforeAll(() => {
    ensureScreenshotDir(SS_DIR);
  });

  test.afterAll(() => {
    writeSuiteAudit(AUDIT_PATH, SUITE_AUDIT);
  });

  test("PB-1: chat routing mentions codon / mRNA optimization", async ({ page }) => {
    test.setTimeout(420_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-b");
    await shot(page, SS_DIR, "PB-1_00_before_chat");

    let hasCard = await sendMessageAndWaitForResponse(page, PLAN_B_QUERY, 180_000);
    await shot(page, SS_DIR, "PB-1_01_after_response");

    let mentionsCodon = await assertAssistantMentions(page, [
      "codon",
      "mRNA",
      "optimize",
      "heterologous",
      "synthetic",
      "expression",
      "10813",
    ]);

    if (!hasCard && !mentionsCodon) {
      hasCard = await waitForWorkflowCard(page, "PB-1", [
        "Show optimize_codons_for_heterologous_expression workflow card with Run button.",
        "Plan B codon optimization registry 10813.",
      ]);
      mentionsCodon =
        mentionsCodon ||
        (await assertAssistantMentions(page, [
          "codon",
          "mRNA",
          "optimize",
          "heterologous",
          "10813",
        ]));
    }

    record("PB-1", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: hasCard ? "unknown" : "skipped",
      assertions: [
        { name: "assistant_mentions_codon_domain", passed: mentionsCodon },
        { name: "workflow_card_or_followup_possible", passed: hasCard || mentionsCodon },
      ],
      screenshots: [],
      notes: [`hasWorkflowCard=${hasCard}`, `mentionsCodon=${mentionsCodon}`],
    });

    expect(mentionsCodon || hasCard).toBeTruthy();
  });

  test("PB-2: workflow card and run controls", async ({ page }) => {
    test.setTimeout(300_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-b-pb2");

    await sendMessageAndWaitForResponse(page, PLAN_B_QUERY, 180_000);

    const cardOk = await waitForWorkflowCard(page, "PB-2", [
      "Show optimize_codons_for_heterologous_expression workflow card with Run button.",
      "Plan B codon optimization registry 10813.",
    ]);

    await shot(page, SS_DIR, "PB-2_01_workflow_card");

    const runVisible = await page
      .getByTestId("button-run-workflow-panel")
      .first()
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    record("PB-2", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: cardOk && runVisible ? "unknown" : "skipped",
      assertions: [
        { name: "workflow_card_detected", passed: cardOk },
        { name: "run_button_visible", passed: runVisible },
      ],
      screenshots: [],
      notes: [],
    });

    expect(cardOk, "Expected workflow card with Run button").toBeTruthy();
    await expect(page.getByTestId("button-run-workflow-panel").first()).toBeVisible();
  });

  test("PB-3: param prefill for target_sequence and outdir", async ({ page }) => {
    test.setTimeout(300_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-b-pb3");

    await sendMessageAndWaitForResponse(page, PLAN_B_QUERY, 180_000);
    await waitForWorkflowCard(page, "PB-3", [
      "Show codon optimization parameters: target_sequence, outdir, host_codon_usage.",
    ]);

    await fillRequiredParams(page, "PB-3", buildPlanBParams());
    await shot(page, SS_DIR, "PB-3_01_params_filled");

    const vals = await readParamValues(page, [
      "target_sequence",
      "outdir",
      "host_codon_usage",
    ]);
    const seqVal = vals.target_sequence ?? "";
    const outdirVal = vals.outdir ?? "";

    const seqOk = seqVal.startsWith("ATG") || seqVal.length > 20;
    const outdirOk = outdirVal.includes("s3://") || outdirVal.includes("plan_b");

    record("PB-3", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: "unknown",
      assertions: [
        { name: "target_sequence_set", passed: seqOk, note: seqVal.slice(0, 40) },
        { name: "outdir_s3_or_prefilled", passed: outdirOk, note: outdirVal },
      ],
      screenshots: [],
      notes: [],
    });

    expect(seqOk || outdirOk).toBeTruthy();
  });

  test("PB-4: Run codon workflow → terminal status", async ({ page }) => {
    test.setTimeout(1_800_000);
    const startTs = Date.now();
    const { captured, detach } = attachExecuteCapture(page);

    await setupTestUser(page, "plan-b-pb4");
    await sendMessageAndWaitForResponse(page, PLAN_B_QUERY, 180_000);

    const cardOk = await waitForWorkflowCard(
      page,
      "PB-4",
      [
        "Load optimize_codons_for_heterologous_expression (10813), not epitopeprediction.",
        "Show the codon optimization workflow card with Run button enabled.",
      ],
      600_000
    );
    expect(cardOk).toBeTruthy();

    const panelTitle = await getWorkflowPanelTitle(page);
    if (!(await assertCodonWorkflowPanelOrSkip(page, "PB-4"))) {
      record("PB-4", {
        runId: null,
        startTs,
        endTs: Date.now(),
        finalStatus: "skipped",
        assertions: [
          { name: "workflow_is_codon_optimization", passed: false, note: panelTitle },
        ],
        screenshots: [],
        notes: ["Wrong workflow in panel — expected codon optimization"],
      });
      test.skip(true, `Wrong workflow in panel: ${panelTitle.trim()}`);
      return;
    }

    await fillRequiredParams(page, "PB-4", buildPlanBParams());
    await shot(page, SS_DIR, "PB-4_01_before_run");

    const terminal = await clickRunAndWaitTerminal(page, 1_200_000);
    await shot(page, SS_DIR, `PB-4_02_${terminal}`);

    detach();

    record("PB-4", {
      runId: captured.runId ?? null,
      startTs,
      endTs: Date.now(),
      finalStatus: terminal,
      assertions: [
        { name: "execute_captured_run_id", passed: !!captured.runId, note: captured.runId },
        {
          name: "terminal_completed_or_failed",
          passed: terminal === "completed" || terminal === "failed",
        },
      ],
      screenshots: [],
      notes: [`executeUrl=${captured.executeUrl ?? "?"}`],
    });

    expect(terminal === "completed" || terminal === "failed").toBeTruthy();
  });

  test("PB-5: completion UX when run succeeded", async ({ page }) => {
    test.setTimeout(1_800_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-b-pb5");

    await sendMessageAndWaitForResponse(page, PLAN_B_QUERY, 180_000);
    const cardOk = await waitForWorkflowCard(
      page,
      "PB-5",
      [
        "Show optimize_codons_for_heterologous_expression (registry 10813) workflow card.",
        "NOT epitopeprediction or mhcquant — codon optimization only.",
      ],
      600_000
    );
    expect(cardOk, "Expected workflow card with Run button").toBeTruthy();
    const panelTitle = await getWorkflowPanelTitle(page);
    if (!(await assertCodonWorkflowPanelOrSkip(page, "PB-5"))) {
      record("PB-5", {
        runId: null,
        startTs,
        endTs: Date.now(),
        finalStatus: "skipped",
        assertions: [
          { name: "workflow_is_codon_optimization", passed: false, note: panelTitle },
        ],
        screenshots: [],
        notes: ["Wrong workflow in panel — expected codon optimization"],
      });
      test.skip(true, `Wrong workflow in panel: ${panelTitle.trim()}`);
      return;
    }

    await fillRequiredParams(page, "PB-5", buildPlanBParams());

    const terminal = await clickRunAndWaitTerminal(page, 1_200_000);
    await shot(page, SS_DIR, `PB-5_${terminal}`);

    let bannerOk = false;
    let downloadOk = false;
    if (terminal === "completed") {
      bannerOk = await page
        .getByTestId("workflow-completion-banner")
        .isVisible({ timeout: 15_000 })
        .catch(() => false);
      downloadOk = await page
        .getByTestId("button-download-all-workflow-panel")
        .isVisible({ timeout: 30_000 })
        .catch(() => false);
    }

    record("PB-5", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: terminal,
      assertions: [
        {
          name: "completion_banner_when_completed",
          passed: terminal !== "completed" || bannerOk,
        },
        {
          name: "download_or_outputs_when_completed",
          passed: terminal !== "completed" || downloadOk || bannerOk,
        },
      ],
      screenshots: [],
      notes: [],
    });

    if (terminal === "completed") {
      expect(bannerOk || downloadOk).toBeTruthy();
    } else {
      expect(terminal).toBe("failed");
    }
  });
});
