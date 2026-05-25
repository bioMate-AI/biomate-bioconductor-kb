/**
 * ANDV inhibitor — UI chained manifest E2E (CLI parity).
 *
 * Runs pocket → pharmacophore → ADMET → docking in one serial session, recording a
 * pipeline_manifest-shaped JSON audit (run_id + terminal status per step).
 *
 * CLI reference: research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py
 * Evidence manifest: runs/andv_nf_pipeline_20260513T032000Z/pipeline_manifest.json
 *
 * Test index:
 *   INH-C1  Pocket → terminal
 *   INH-C2  Pharmacophore → terminal (manifest handoff to step 3)
 *   INH-C3  ADMET → terminal
 *   INH-C4  Docking Vina → terminal + write inhibitor-chained-manifest.json
 *
 * NO page.route() mocking.
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
  attachExecuteCapture,
  waitForWorkflowCard,
  fillRequiredParams,
  clickRunAndWaitTerminal,
  writeChainedManifest,
  getWorkflowPanelTitle,
  type ChainedManifestStep,
} from "./andv-stepwise-shared.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SS_DIR = path.join(__dirname, "screenshots", "andv-inhibitor-chained");
const MANIFEST_PATH = path.join(SS_DIR, "inhibitor-chained-manifest.json");
ensureScreenshotDir(SS_DIR);

const DEMO_ACTIVES_S3 =
  "s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi";
const DEMO_LIBRARY_S3 =
  "s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi";

const POCKET_QUERY = [
  "ANDV inhibitor chained UI test — step 1 pocket detection and druggability.",
  "pdb_input = 1IEP, min_druggability = 0.35, min_volume = 200.",
  "Show the workflow card so I can Run.",
].join(" ");

const PHARM_QUERY = [
  "ANDV inhibitor chained UI test — step 2 pharmacophore screening.",
  `reference_actives = ${DEMO_ACTIVES_S3}`,
  `compound_library = ${DEMO_LIBRARY_S3}`,
  "Show pharmacophore filtering workflow card.",
].join(" ");

const ADMET_QUERY = [
  "ANDV inhibitor chained UI test — step 3 ADMET on pharmacophore-filtered hits.",
  "Use predict ADMET properties workflow. Use compounds from the prior pharmacophore step when available.",
  "Show workflow card.",
].join(" ");

const DOCKING_QUERY = [
  "ANDV inhibitor chained UI test — step 4 AutoDock Vina docking.",
  "Use top pocket from step 1 for the docking box when available. pdb_input = 1IEP.",
  "Show AutoDock Vina workflow card.",
].join(" ");

const CHAINED_STEPS: ChainedManifestStep[] = [];

async function runChainedStep(
  page: import("@playwright/test").Page,
  opts: {
    key: string;
    title: string;
    query: string;
    params: Record<string, string>;
    label: string;
    runTimeoutMs: number;
    panelMustMatch?: RegExp;
    panelMustNotMatch?: RegExp;
  }
): Promise<ChainedManifestStep> {
  const { captured, detach } = attachExecuteCapture(page);
  await sendMessageAndWaitForResponse(page, opts.query, 180_000);

  const cardOk = await waitForWorkflowCard(page, opts.label, [
    `Show ${opts.title} workflow card with Run button.`,
  ]);
  const panelTitle = await getWorkflowPanelTitle(page);

  if (!cardOk) {
    detach();
    return {
      key: opts.key,
      title: opts.title,
      runId: null,
      status: "skipped",
      panelTitle,
      notes: ["No workflow card"],
    };
  }

  if (opts.panelMustNotMatch && opts.panelMustNotMatch.test(panelTitle)) {
    detach();
    return {
      key: opts.key,
      title: opts.title,
      runId: null,
      status: "skipped",
      panelTitle,
      notes: ["Wrong workflow in panel"],
    };
  }

  if (opts.panelMustMatch && !opts.panelMustMatch.test(panelTitle)) {
    detach();
    return {
      key: opts.key,
      title: opts.title,
      runId: null,
      status: "skipped",
      panelTitle,
      notes: [`Panel title did not match ${opts.panelMustMatch}`],
    };
  }

  await fillRequiredParams(page, opts.label, opts.params);
  await shot(page, SS_DIR, `${opts.label}_before_run`);

  const terminal = await clickRunAndWaitTerminal(page, opts.runTimeoutMs);
  await shot(page, SS_DIR, `${opts.label}_${terminal}`);
  detach();

  return {
    key: opts.key,
    title: opts.title,
    runId: captured.runId ?? null,
    status: terminal,
    panelTitle,
    notes: [`executeUrl=${captured.executeUrl ?? "?"}`],
  };
}

test.describe.serial("ANDV inhibitor — UI chained manifest", () => {
  test.afterAll(() => {
    writeChainedManifest(MANIFEST_PATH, CHAINED_STEPS);
  });

  test("INH-C1: manifest step 1 — pocket", async ({ page }) => {
    test.setTimeout(900_000);
    await setupTestUser(page, "inh-chain-c1");
    const step = await runChainedStep(page, {
      key: "pocket",
      title: "Pocket detection + druggability",
      query: POCKET_QUERY,
      params: { pdb_input: "1IEP" },
      label: "INH-C1",
      runTimeoutMs: 780_000,
      panelMustMatch: /pocket|druggability|fpocket/i,
    });
    CHAINED_STEPS.push(step);
    expect(step.status === "completed" || step.status === "failed").toBeTruthy();
  });

  test("INH-C2: manifest step 2 — pharmacophore", async ({ page }) => {
    test.setTimeout(1_200_000);
    await setupTestUser(page, "inh-chain-c2");
    const step = await runChainedStep(page, {
      key: "pharmacophore",
      title: "Pharmacophore library filtering",
      query: PHARM_QUERY,
      params: {
        reference_actives: DEMO_ACTIVES_S3,
        compound_library: DEMO_LIBRARY_S3,
      },
      label: "INH-C2",
      runTimeoutMs: 1_080_000,
      panelMustMatch: /pharmacophore|screen/i,
    });
    CHAINED_STEPS.push(step);
    expect(step.status === "completed" || step.status === "failed").toBeTruthy();
  });

  test("INH-C3: manifest step 3 — ADMET", async ({ page }) => {
    test.setTimeout(1_200_000);
    await setupTestUser(page, "inh-chain-c3");
    const step = await runChainedStep(page, {
      key: "admet",
      title: "Predict ADMET properties",
      query: ADMET_QUERY,
      params: {},
      label: "INH-C3",
      runTimeoutMs: 1_080_000,
      panelMustMatch: /admet|predict/i,
    });
    CHAINED_STEPS.push(step);
    expect(step.status === "completed" || step.status === "failed").toBeTruthy();
  });

  test("INH-C4: manifest step 4 — docking + write manifest", async ({ page }) => {
    test.setTimeout(1_200_000);
    await setupTestUser(page, "inh-chain-c4");
    const step = await runChainedStep(page, {
      key: "docking_vina",
      title: "AutoDock Vina docking",
      query: DOCKING_QUERY,
      params: { pdb_input: "1IEP" },
      label: "INH-C4",
      runTimeoutMs: 1_080_000,
      panelMustMatch: /vina|dock/i,
    });
    CHAINED_STEPS.push(step);

    const succeeded = CHAINED_STEPS.filter((s) => s.status === "completed").length;
    const recorded = CHAINED_STEPS.filter((s) => s.runId).length;
    console.log(
      `[INH-CMAN] manifest steps=${CHAINED_STEPS.length} with_run_id=${recorded} completed=${succeeded}`
    );

    expect(CHAINED_STEPS.length).toBe(4);
    expect(recorded).toBeGreaterThanOrEqual(2);
    expect(step.status === "completed" || step.status === "failed").toBeTruthy();
  });
});
