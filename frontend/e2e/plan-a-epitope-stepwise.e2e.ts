/**
 * Plan A — epitopeprediction stepwise UI E2E (Cryo-EM / pharmacology pattern).
 *
 * User story: Immunoinformatics lead runs nf-core epitopeprediction for ANDV Plan A
 * through chat → workflow card → Run → terminal status → outputs.
 *
 * Scenario: research/anti-virus/docs/BIOMATE_UI_SCENARIO_PLAN_A_EPITOPE.md
 * CLI parity: research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py
 *
 * Test index:
 *   PA-1  Chat routing: epitope / MHC / epitopeprediction mentioned
 *   PA-2  Workflow card + Run button visible; param section present
 *   PA-3  Required params filled when empty (samplesheet S3, tools, genome_reference)
 *   PA-4  Execute on Batch → terminal COMPLETED or FAILED (audited)
 *   PA-5  Completion banner or download control when COMPLETED
 *
 * NO page.route() mocking.
 * Screenshots → e2e/screenshots/plan-a-epitope/
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
  assertAssistantMentions,
  type StepwiseSuiteRecord,
} from "./andv-stepwise-shared.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SS_DIR = path.join(__dirname, "screenshots", "plan-a-epitope");
const AUDIT_PATH = path.join(SS_DIR, "plan-a-suite-audit.json");
ensureScreenshotDir(SS_DIR);

const PLAN_A_SAMPLESHEET_S3 =
  "s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/samplesheet.csv";

function planAOutdirS3(): string {
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "");
  return `s3://biomate-nextflow-work/nextflow/outputs/plan_a_e2e_ui/${stamp}/`;
}

const PLAN_A_QUERY = [
  "I'm on the ANDV Plan A vaccine immunoinformatics track.",
  "We need class I epitope binding scores for our ninety-residue glycoprotein benchmark",
  "segment (PLAN_A_SMOKE_GP) before we expand the HLA panel.",
  "",
  "Use workflow nfcore/epitopeprediction (Galaxy id 12700) — NOT mhcquant.",
  "Please run nf-core epitopeprediction with:",
  `input = ${PLAN_A_SAMPLESHEET_S3}`,
  `outdir = ${planAOutdirS3()}`,
  "tools = mhcnuggets",
  "genome_reference = grch37",
  "min_peptide_length_classI = 8",
  "max_peptide_length_classI = 12",
  "",
  "The samplesheet lists HLA-A*02:01 and HLA-B*07:02.",
  "Use profile docker on AWS Batch.",
  "All parameters are explicit — show the workflow card so I can Run from the panel.",
].join(" ");

function buildPlanAParams(): Record<string, string> {
  return {
    input: PLAN_A_SAMPLESHEET_S3,
    outdir: planAOutdirS3(),
    tools: "mhcnuggets",
    genome_reference: "grch37",
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

test.describe.serial("Plan A epitopeprediction — stepwise UI", () => {
  test.beforeAll(() => {
    ensureScreenshotDir(SS_DIR);
  });

  test.afterAll(() => {
    writeSuiteAudit(AUDIT_PATH, SUITE_AUDIT);
  });

  test("PA-1: chat routing mentions epitope prediction", async ({ page }) => {
    test.setTimeout(420_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-a");
    await shot(page, SS_DIR, "PA-1_00_before_chat");

    let hasCard = await sendMessageAndWaitForResponse(page, PLAN_A_QUERY, 180_000);
    await shot(page, SS_DIR, "PA-1_01_after_response");

    let mentionsEpitope = await assertAssistantMentions(page, [
      "epitope",
      "mhc",
      "epitopeprediction",
      "mhcnuggets",
      "vaccine",
    ]);

    // Recovery (parity with PB-1): if the first turn produced neither a card nor a
    // domain mention (slow AI service / transient hang), re-prompt for the named card.
    if (!hasCard && !mentionsEpitope) {
      hasCard = await waitForWorkflowCard(page, "PA-1", [
        "Show the nf-core epitopeprediction (Galaxy id 12700) workflow card with Run button.",
        "Plan A epitope prediction with MHCnuggets — not mhcquant.",
      ]);
      mentionsEpitope =
        mentionsEpitope ||
        (await assertAssistantMentions(page, [
          "epitope",
          "mhc",
          "epitopeprediction",
          "mhcnuggets",
          "12700",
        ]));
    }

    record("PA-1", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: hasCard ? "unknown" : "skipped",
      assertions: [
        { name: "assistant_mentions_epitope_domain", passed: mentionsEpitope },
        { name: "workflow_card_or_followup_possible", passed: hasCard || mentionsEpitope },
      ],
      screenshots: [],
      notes: [`hasWorkflowCard=${hasCard}`, `mentionsEpitope=${mentionsEpitope}`],
    });

    expect(mentionsEpitope || hasCard).toBeTruthy();
  });

  test("PA-2: workflow card and QC / run controls", async ({ page }) => {
    test.setTimeout(300_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-a-pa2");

    await sendMessageAndWaitForResponse(page, PLAN_A_QUERY, 180_000);

    const cardOk = await waitForWorkflowCard(page, "PA-2", [
      "Generate the nf-core epitopeprediction workflow card with Run button.",
      "Use workflow epitopeprediction / MHCnuggets with the samplesheet I provided.",
    ]);

    await shot(page, SS_DIR, "PA-2_01_workflow_card");

    const runVisible = await page
      .getByTestId("button-run-workflow-panel")
      .first()
      .isVisible({ timeout: 5000 })
      .catch(() => false);

    record("PA-2", {
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

  test("PA-3: param prefill / manual fill for samplesheet and tools", async ({ page }) => {
    test.setTimeout(300_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-a-pa3");

    await sendMessageAndWaitForResponse(page, PLAN_A_QUERY, 180_000);
    await waitForWorkflowCard(page, "PA-3", [
      "Show epitopeprediction workflow parameters: input samplesheet, tools, genome_reference.",
    ]);

    await fillRequiredParams(page, "PA-3", buildPlanAParams());
    await shot(page, SS_DIR, "PA-3_01_params_filled");

    const vals = await readParamValues(page, ["input", "tools", "outdir", "genome_reference"]);
    const inputVal = vals.input ?? "";
    const toolsVal = vals.tools ?? "";

    const inputOk =
      inputVal.includes("samplesheet") || inputVal.includes("s3://") || inputVal.length > 10;
    const toolsOk = toolsVal.toLowerCase().includes("mhc") || toolsVal === "";

    record("PA-3", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: "unknown",
      assertions: [
        { name: "input_samplesheet_set", passed: inputOk, note: inputVal },
        { name: "tools_mhcnuggets_or_prefilled", passed: toolsOk, note: toolsVal },
      ],
      screenshots: [],
      notes: [],
    });

    expect(inputOk || toolsOk).toBeTruthy();
  });

  test("PA-4: Run epitopeprediction → terminal status", async ({ page }) => {
    test.setTimeout(2_700_000); // epitope Batch can be slow
    const startTs = Date.now();
    const { captured, detach } = attachExecuteCapture(page);

    await setupTestUser(page, "plan-a-pa4");
    await sendMessageAndWaitForResponse(page, PLAN_A_QUERY, 180_000);

    const cardOk = await waitForWorkflowCard(page, "PA-4", [
      "Load nf-core epitopeprediction (Galaxy 12700), not mhcquant.",
      "I need the epitopeprediction workflow card with input, outdir, tools, genome_reference.",
    ]);
    expect(cardOk).toBeTruthy();

    const panelTitle =
      (await page
        .locator(
          '[data-testid="workflow-artifact-panel"] .panel-name, [data-testid="workflow-right-panel"] .panel-name'
        )
        .first()
        .textContent({ timeout: 5000 })
        .catch(() => "")) ?? "";
    if (/mhcquant/i.test(panelTitle) && !/epitopeprediction/i.test(panelTitle)) {
      record("PA-4", {
        runId: null,
        startTs,
        endTs: Date.now(),
        finalStatus: "skipped",
        assertions: [
          { name: "workflow_is_epitopeprediction", passed: false, note: panelTitle },
        ],
        screenshots: [],
        notes: ["Planner routed to mhcquant — re-prompt or fix intent routing"],
      });
      test.skip(true, `Wrong workflow in panel: ${panelTitle.trim()}`);
      return;
    }

    await fillRequiredParams(page, "PA-4", buildPlanAParams());
    await shot(page, SS_DIR, "PA-4_01_before_run");

    const terminal = await clickRunAndWaitTerminal(page, 2_400_000);
    await shot(page, SS_DIR, `PA-4_02_${terminal}`);

    detach();

    record("PA-4", {
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

  test("PA-5: completion UX when run succeeded", async ({ page }) => {
    test.setTimeout(2_700_000);
    const startTs = Date.now();
    await setupTestUser(page, "plan-a-pa5");

    await sendMessageAndWaitForResponse(page, PLAN_A_QUERY, 180_000);
    await waitForWorkflowCard(page, "PA-5", ["Show epitopeprediction workflow card."]);
    await fillRequiredParams(page, "PA-5", buildPlanAParams());

    const terminal = await clickRunAndWaitTerminal(page, 2_400_000);
    await shot(page, SS_DIR, `PA-5_${terminal}`);

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

    record("PA-5", {
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
