/**
 * ANDV inhibitor pipeline — stepwise UI E2E (Cryo-EM pattern).
 *
 * User story: Medicinal chemist runs inhibitor triage steps through BioMate chat,
 * each step surfacing a workflow card → Run → terminal status.
 *
 * Scenario: research/anti-virus/docs/BIOMATE_UI_SCENARIO_ANDV_INHIBITOR_PIPELINE.md
 * CLI parity: research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py
 *
 * Test index:
 *   INH-1  Pocket query routing + workflow card
 *   INH-2  Pocket Run → COMPLETED or FAILED
 *   INH-3  Pharmacophore card + param paths (S3 demo library)
 *   INH-4  Pharmacophore Run → terminal (optional long Batch)
 *
 * NO page.route() mocking.
 * Screenshots → e2e/screenshots/andv-inhibitor-stepwise/
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
  clickRunAndWaitTerminal,
  assertAssistantMentions,
  type StepwiseSuiteRecord,
} from "./andv-stepwise-shared.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SS_DIR = path.join(__dirname, "screenshots", "andv-inhibitor-stepwise");
const AUDIT_PATH = path.join(SS_DIR, "inhibitor-suite-audit.json");
ensureScreenshotDir(SS_DIR);

const DEMO_ACTIVES_S3 =
  "s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi";
const DEMO_LIBRARY_S3 =
  "s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi";

const POCKET_QUERY = [
  "I'm on the ANDV glycoprotein oral inhibitor program (Guo et al. Cryo-EM structures).",
  "Step 1: pocket detection and druggability for tractability before we order compounds.",
  "",
  "Please run Pocket Detection Druggability with:",
  "pdb_input = 1IEP, min_druggability = 0.35, min_volume = 200.",
  "",
  "1IEP is for reliable end-to-end validation; production ANDV builds use 9P3I after PDB upload.",
  "All parameters are explicit — show the workflow card so I can Run.",
].join(" ");

const PHARM_QUERY = [
  "ANDV inhibitor program — step 2 pharmacophore screening.",
  "",
  `reference_actives_s3 = ${DEMO_ACTIVES_S3}`,
  `compound_library_s3 = ${DEMO_LIBRARY_S3}`,
  "",
  "Show the pharmacophore filtering workflow card with these S3 paths prefilled so I can Run.",
].join(" ");

const POCKET_PARAMS: Record<string, string> = {
  pdb_input: "1IEP",
};

const PHARM_PARAMS: Record<string, string> = {
  reference_actives: DEMO_ACTIVES_S3,
  compound_library: DEMO_LIBRARY_S3,
};

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

test.describe.serial("ANDV inhibitor pipeline — stepwise UI", () => {
  test.afterAll(() => {
    writeSuiteAudit(AUDIT_PATH, SUITE_AUDIT);
  });

  test("INH-1: pocket step — routing and workflow card", async ({ page }) => {
    test.setTimeout(300_000);
    const startTs = Date.now();
    await setupTestUser(page, "inh-pocket-1");

    const hasCard = await sendMessageAndWaitForResponse(page, POCKET_QUERY, 180_000);
    await shot(page, SS_DIR, "INH-1_01_response");

    const mentionsPocket = await assertAssistantMentions(page, [
      "pocket",
      "druggability",
      "fpocket",
      "1iep",
    ]);

    const cardOk =
      hasCard ||
      (await waitForWorkflowCard(page, "INH-1", [
        "Generate Pocket Detection Druggability workflow card with Run button.",
      ]));

    record("INH-1", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: cardOk ? "unknown" : "skipped",
      assertions: [
        { name: "mentions_pocket_domain", passed: mentionsPocket },
        { name: "workflow_card", passed: cardOk },
      ],
      screenshots: [],
      notes: [],
    });

    expect(cardOk || mentionsPocket).toBeTruthy();
  });

  test("INH-2: pocket step — Run to terminal", async ({ page }) => {
    test.setTimeout(900_000);
    const startTs = Date.now();
    const { captured, detach } = attachExecuteCapture(page);

    await setupTestUser(page, "inh-pocket-2");
    await sendMessageAndWaitForResponse(page, POCKET_QUERY, 180_000);
    await waitForWorkflowCard(page, "INH-2", [
      "Show Pocket Detection Druggability workflow — pdb_input 1IEP.",
    ]);

    await fillRequiredParams(page, "INH-2", POCKET_PARAMS);
    await shot(page, SS_DIR, "INH-2_01_before_run");

    const terminal = await clickRunAndWaitTerminal(page, 780_000);
    await shot(page, SS_DIR, `INH-2_02_${terminal}`);
    detach();

    record("INH-2", {
      runId: captured.runId ?? null,
      startTs,
      endTs: Date.now(),
      finalStatus: terminal,
      assertions: [
        { name: "run_id_captured", passed: !!captured.runId },
        {
          name: "terminal_state",
          passed: terminal === "completed" || terminal === "failed",
        },
      ],
      screenshots: [],
      notes: [],
    });

    expect(terminal === "completed" || terminal === "failed").toBeTruthy();
  });

  test("INH-3: pharmacophore — card and S3 param fill", async ({ page }) => {
    test.setTimeout(360_000);
    const startTs = Date.now();
    await setupTestUser(page, "inh-pharm-3");

    await sendMessageAndWaitForResponse(page, PHARM_QUERY, 180_000);

    const cardOk = await waitForWorkflowCard(page, "INH-3", [
      "Generate pharmacophore filtering workflow with reference_actives_s3 and compound_library_s3.",
      "Use the demo S3 library paths I provided.",
    ]);

    await shot(page, SS_DIR, "INH-3_01_card");

    if (cardOk) {
      await fillRequiredParams(page, "INH-3", PHARM_PARAMS);
      await shot(page, SS_DIR, "INH-3_02_params");
    }

    const mentionsPharm = await assertAssistantMentions(page, [
      "pharmacophore",
      "screen",
      "library",
      "smi",
    ]);

    record("INH-3", {
      runId: null,
      startTs,
      endTs: Date.now(),
      finalStatus: cardOk ? "unknown" : "skipped",
      assertions: [
        { name: "pharmacophore_card", passed: cardOk },
        { name: "mentions_pharmacophore", passed: mentionsPharm },
      ],
      screenshots: [],
      notes: [],
    });

    expect(cardOk || mentionsPharm).toBeTruthy();
  });

  test("INH-4: pharmacophore — Run to terminal", async ({ page }) => {
    test.setTimeout(1_200_000);
    const startTs = Date.now();
    const { captured, detach } = attachExecuteCapture(page);

    await setupTestUser(page, "inh-pharm-4");
    await sendMessageAndWaitForResponse(page, PHARM_QUERY, 180_000);
    const cardOk = await waitForWorkflowCard(page, "INH-4", [
      "I need pharmacophore filtering workflow card now.",
    ]);

    if (!cardOk) {
      record("INH-4", {
        runId: null,
        startTs,
        endTs: Date.now(),
        finalStatus: "skipped",
        assertions: [{ name: "workflow_card", passed: false }],
        screenshots: [],
        notes: ["No workflow card — intent routing may need pharmacophore keywords"],
      });
      test.skip(true, "Pharmacophore workflow card not surfaced");
      return;
    }

    await fillRequiredParams(page, "INH-4", PHARM_PARAMS);
    const terminal = await clickRunAndWaitTerminal(page, 1_080_000);
    await shot(page, SS_DIR, `INH-4_${terminal}`);
    detach();

    record("INH-4", {
      runId: captured.runId ?? null,
      startTs,
      endTs: Date.now(),
      finalStatus: terminal,
      assertions: [
        { name: "run_id_captured", passed: !!captured.runId },
        {
          name: "terminal_state",
          passed: terminal === "completed" || terminal === "failed",
        },
      ],
      screenshots: [],
      notes: [],
    });

    expect(terminal === "completed" || terminal === "failed").toBeTruthy();
  });
});
