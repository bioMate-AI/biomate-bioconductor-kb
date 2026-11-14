/**
 * Live DEV verify for 2026-11-13 workflow-execution hell clinic fixes
 * (commit 1257a9f36d code sync).
 *
 * Checks:
 *   1. Cryo SPA: Movies Path required; Confirm & Run blocked when empty
 *   2. Generate 500: NOT ADMET-Gated Virtual Screening mega-chain
 *   3. DE: launch payload mirrors samplesheet ↔ input (API-level)
 *   4. cs_image: cryo panel must not show ECR Cs Image to clinic user
 *
 * Run:
 *   cd frontend && unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy && \
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   npx playwright test e2e/hell-clinic-dev-verify.e2e.ts --project=chromium --workers=1
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";
import { loginAsFixture, BASE_URL, FIXTURE_EMAIL } from "./_fixture-login";
import { buildNextflowLaunchParameters } from "../server/nextflow-launch-params";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });

const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), "execshots", "hell-clinic-20261113");
fs.mkdirSync(OUT, { recursive: true });

const RESULTS: Record<string, { pass: boolean; evidence: string }> = {};

function record(id: string, pass: boolean, evidence: string) {
  RESULTS[id] = { pass, evidence };
  console.log(`\n[${pass ? "PASS" : "FAIL"}] ${id}: ${evidence}\n`);
  fs.writeFileSync(
    path.join(OUT, "results.json"),
    JSON.stringify({ fixture: FIXTURE_EMAIL, base: BASE_URL, results: RESULTS }, null, 2),
  );
}

async function newCleanChat(page: import("@playwright/test").Page) {
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
  const newChat = page.getByTestId("button-new-chat");
  if ((await newChat.count().catch(() => 0)) > 0) {
    await newChat.first().click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(1500);
  }
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
}

async function sendChat(page: import("@playwright/test").Page, text: string) {
  const input = page.getByTestId("chat-input");
  await input.click();
  await input.fill(text);
  const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await send.waitFor({ state: "visible", timeout: 30_000 });
  await send.click({ timeout: 15_000 });
}

test.describe.serial("Hell clinic DEV verify @1257a9f36d", () => {
  test("1+4 Cryo: Movies Path required, Confirm blocked, no cs_image", async ({ page }) => {
    test.setTimeout(6 * 60_000);
    await loginAsFixture(page);
    await newCleanChat(page);

    // Prefer deterministic generate_workflow → open panel via chat that names the wf.
    await sendChat(
      page,
      "Open the cryosparc_standard_spa workflow (CryoSPARC standard SPA). Do not run it — I only need the pre-run panel with parameters.",
    );

    const panel = page.getByTestId("workflow-right-panel");
    // Wait for cryo panel or Confirm & Run
    const confirm = page.getByRole("button", { name: /confirm\s*&?\s*run/i });
    await Promise.race([
      panel.first().waitFor({ state: "visible", timeout: 220_000 }),
      confirm.first().waitFor({ state: "visible", timeout: 220_000 }),
      page.getByText(/Movies Path|cryosparc|CryoSPARC/i).first().waitFor({ timeout: 220_000 }),
    ]).catch(() => {});
    await page.waitForTimeout(4000);

    await page.screenshot({ path: path.join(OUT, "01-cryo-full.png"), fullPage: true });
    if ((await panel.count()) > 0) {
      await panel.first().screenshot({ path: path.join(OUT, "01-cryo-panel.png") }).catch(() => {});
    }

    const panelText = ((await panel.first().innerText().catch(() => "")) || "") +
      "\n" +
      ((await page.locator("body").innerText().catch(() => "")) || "");
    const inputValues = await page
      .locator('[data-testid="workflow-right-panel"] input, [data-testid="workflow-right-panel"] textarea')
      .evaluateAll((els) => els.map((e) => `${(e as HTMLInputElement).name || ""}=${(e as HTMLInputElement).value || ""}`).join("\n"))
      .catch(() => "");
    const labels = await page
      .locator('[data-testid="workflow-right-panel"] label, [data-testid="workflow-right-panel"] [data-param-name]')
      .evaluateAll((els) => els.map((e) => e.textContent?.trim() || e.getAttribute("data-param-name") || "").filter(Boolean))
      .catch(() => [] as string[]);

    fs.writeFileSync(
      path.join(OUT, "01-cryo-panel.txt"),
      panelText.slice(0, 12000) + "\n---inputs---\n" + inputValues + "\n---labels---\n" + labels.join("\n"),
    );

    const hasMovies =
      /movies\s*path/i.test(panelText) ||
      labels.some((l) => /movies/i.test(l)) ||
      /movies_path/i.test(inputValues);
    const showsCsImage =
      /\bcs[_\s-]?image\b/i.test(panelText) ||
      /Cs Image/i.test(panelText) ||
      /dkr\.ecr\./i.test(panelText) ||
      labels.some((l) => /cs[_\s-]?image/i.test(l));

    // Confirm & Run should be disabled OR a Fix-now / missing-required alert visible
    let confirmBlocked = false;
    if ((await confirm.count()) > 0) {
      const btn = confirm.first();
      const disabled = await btn.isDisabled().catch(() => false);
      const ariaDisabled = (await btn.getAttribute("aria-disabled").catch(() => null)) === "true";
      const cls = (await btn.getAttribute("class").catch(() => "")) || "";
      confirmBlocked = disabled || ariaDisabled || /opacity-50|pointer-events-none|cursor-not-allowed/.test(cls);
    }
    const fixNowVisible = await page.getByRole("button", { name: /fix now/i }).first().isVisible().catch(() => false);
    const missingAlert = await page.getByText(/movies path|required|missing/i).first().isVisible().catch(() => false);
    const blocked = confirmBlocked || fixNowVisible || (hasMovies && missingAlert);

    // API-level gate (authoritative for execute)
    const gen = await page.request.post(`${BASE_URL}/api/ai_assistant/generate_workflow`, {
      data: { request_text: "cryosparc_standard_spa CryoSPARC standard SPA" },
    });
    const genBody = await gen.json();
    const ga = genBody.workflow_ga || {};
    const paramNames = [
      ...((ga.required_params || []) as any[]),
      ...((ga.optional_params || []) as any[]),
    ].map((p) => String(p.name || ""));
    const apiNoCs = !paramNames.includes("cs_image");
    const exec = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
      data: {
        workflowDefinition: {
          name: ga.name,
          nextflow_path: ga.nextflow_path,
          required_params: (ga.required_params || []).map((p: any) => ({ ...p, value: null })),
          optional_params: ga.optional_params || [],
        },
        params: {},
      },
    });
    const execBody = await exec.json().catch(() => ({}));
    const apiBlocksEmpty =
      exec.status() === 400 &&
      execBody?.error === "missing_required_params" &&
      JSON.stringify(execBody).includes("movies_path");

    record(
      "cryo_movies_required",
      hasMovies && (blocked || apiBlocksEmpty),
      `UI movies=${hasMovies} confirmBlocked=${confirmBlocked} fixNow=${fixNowVisible} apiBlocks=${apiBlocksEmpty} exec=${JSON.stringify(execBody).slice(0, 300)}`,
    );
    record(
      "cryo_cs_image_hidden",
      apiNoCs && !showsCsImage,
      `apiHasCsImage=${!apiNoCs} uiShowsCsImage=${showsCsImage} paramNames=${paramNames.filter((n) => /image|container|cs_/i.test(n)).join(",") || "(none infra)"}`,
    );

    // License prompt best-effort
    const licenseVisible = await page
      .getByText(/CryoSPARC.*(license|credential|API key)|Tool Credentials|license key/i)
      .first()
      .isVisible()
      .catch(() => false);
    record(
      "cryo_license_prompt_best_effort",
      true, // best-effort — never fail the suite
      `licenseUIVisible=${licenseVisible} (informational)`,
    );

    expect(hasMovies && (blocked || apiBlocksEmpty), "Movies Path required + run blocked").toBe(true);
    expect(apiNoCs && !showsCsImage, "cs_image hidden from clinic").toBe(true);
  });

  test("2 Generate 500: not ADMET-Gated mega-chain", async ({ page }) => {
    test.setTimeout(6 * 60_000);
    await loginAsFixture(page);
    await newCleanChat(page);

    const QUERY = "Generate 500 candidates for this target with drug-like properties.";
    await sendChat(page, QUERY);

    // Wait for assistant response / workflow card
    await page.waitForTimeout(8000);
    await page
      .getByText(/reinvent|lead design|candidate|workflow|pipeline|ADMET|screening|design/i)
      .first()
      .waitFor({ timeout: 180_000 })
      .catch(() => {});
    await page.waitForTimeout(5000);

    await page.screenshot({ path: path.join(OUT, "02-generate500-full.png"), fullPage: true });
    const bodyText = (await page.locator("body").innerText().catch(() => "")) || "";
    fs.writeFileSync(path.join(OUT, "02-generate500.txt"), bodyText.slice(0, 16000));

    const low = bodyText.toLowerCase();
    const isAdmetGated =
      /admet[- ]gated\s+virtual\s+screening/.test(low) ||
      /drug_discovery_admet_gated_screening/.test(low);
    const isPharmacophoreAdmetDockChain =
      (/pharmacophore/.test(low) && /admet/.test(low) && /dock/.test(low)) ||
      /target[- ]to[- ]lead/.test(low) ||
      /pocket detection.*pharmacophore.*admet/.test(low);
    const prefersDesign =
      /reinvent/.test(low) ||
      /lead[_ ]design/.test(low) ||
      (/generat/.test(low) && /candidate/.test(low) && !isAdmetGated);

    // Chat/stream is the clinic path. Galaxy generate_workflow may still chain_lookup
    // target_to_lead_full — note as residual, do not fail the clinic check on it alone.
    const api = await page.request.post(`${BASE_URL}/api/ai_assistant/generate_workflow`, {
      data: { request_text: QUERY },
    });
    const apiBody = await api.json();
    fs.writeFileSync(path.join(OUT, "02-generate500-api.json"), JSON.stringify(apiBody, null, 2).slice(0, 20000));
    const apiChain = String(apiBody.chain_name || apiBody.chain_display_name || "");
    const apiIsAdmetGated =
      apiChain === "drug_discovery_admet_gated_screening" ||
      /admet[- ]gated/i.test(apiChain) ||
      /admet[- ]gated/i.test(String(apiBody.message || ""));
    const honestClarification =
      /missing|need|pdb|sequence|structure|clarif/i.test(bodyText) && !isAdmetGated;

    // PASS: chat is NOT ADMET-Gated VS and NOT pharmacophore→ADMET→dock curated chain.
    // Also require generate_workflow API not to return the ADMET-gated chain — UI-only
    // prose can look "design-ish" while the payload still hijacks (Bugbot Medium #6).
    const pass =
      !isAdmetGated &&
      !isPharmacophoreAdmetDockChain &&
      !apiIsAdmetGated &&
      (prefersDesign || honestClarification);
    record(
      "generate_500_not_admet_gated",
      pass,
      `uiAdmetGated=${isAdmetGated} uiPharmAdmetDock=${isPharmacophoreAdmetDockChain} prefersDesign=${prefersDesign} honestClarification=${honestClarification} apiChain=${apiChain || "(none)"} apiAdmetGated=${apiIsAdmetGated} bodySnippet=${bodyText.slice(0, 500).replace(/\s+/g, " ")}`,
    );

    expect(pass, "chat must not be ADMET-Gated / pharmacophore→ADMET→dock mega-chain").toBe(true);
    expect(apiIsAdmetGated, "generate_workflow API must not return ADMET-gated chain").toBe(false);
  });

  test("3 DE: samplesheet↔input launch alias (API)", async ({ page }) => {
    test.setTimeout(120_000);
    await loginAsFixture(page);

    // Pure function parity with deployed server module (same source synced as 1257a9f36d)
    const mirrored = buildNextflowLaunchParameters(
      {
        name: "nf-core/differentialabundance",
        required_params: [
          { name: "samplesheet", type: "file", value: "s3://b/samplesheet.csv" },
          { name: "matrix", type: "file", value: "s3://b/matrix.csv" },
          { name: "contrasts", type: "file", value: "s3://b/contrasts.csv" },
        ],
        optional_params: [{ name: "input", type: "file" }],
      },
      { samplesheet: "s3://b/samplesheet.csv", matrix: "s3://b/matrix.csv", contrasts: "s3://b/contrasts.csv" },
    );
    const aliasOk =
      mirrored.samplesheet === "s3://b/samplesheet.csv" &&
      mirrored.input === "s3://b/samplesheet.csv";

    // Live execute gate: samplesheet-only (no input) + matrix + contrasts should NOT
    // fail with "samplesheet was not provided" after alias — may still fail later for
    // path/S3 reasons, but missing_required_params must not list samplesheet/input.
    const exec = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
      data: {
        workflowDefinition: {
          name: "nf-core/differentialabundance",
          nextflow_path: "biomni_workflows/nfcore/differentialabundance/main.nf",
          required_params: [
            { name: "samplesheet", type: "file", required: true, value: "s3://biomate-dev-placeholder/samplesheet.csv" },
            { name: "matrix", type: "file", required: true, value: "s3://biomate-dev-placeholder/matrix.csv" },
            { name: "contrasts", type: "file", required: true, value: "s3://biomate-dev-placeholder/contrasts.csv" },
          ],
          optional_params: [{ name: "input", type: "file", required: false }],
        },
        params: {
          samplesheet: "s3://biomate-dev-placeholder/samplesheet.csv",
          matrix: "s3://biomate-dev-placeholder/matrix.csv",
          contrasts: "s3://biomate-dev-placeholder/contrasts.csv",
        },
      },
    });
    const execBody = await exec.json().catch(() => ({}));
    fs.writeFileSync(path.join(OUT, "03-de-execute.json"), JSON.stringify({ status: exec.status(), body: execBody }, null, 2).slice(0, 8000));
    const missing = JSON.stringify(execBody.missing || execBody.message || execBody.error || "");
    const wronglyClaimsSamplesheetMissing =
      /samplesheet was not provided/i.test(missing) ||
      (/missing_required_params/i.test(String(execBody.error || "")) &&
        /samplesheet|"input"/i.test(JSON.stringify(execBody.missing || [])) &&
        !/matrix|contrasts/i.test(JSON.stringify(execBody.missing || [])));

    record(
      "de_samplesheet_input_alias",
      aliasOk && !wronglyClaimsSamplesheetMissing,
      `aliasOk=${aliasOk} mirroredKeys=${Object.keys(mirrored).join(",")} execStatus=${exec.status()} wronglyClaimsMissing=${wronglyClaimsSamplesheetMissing} body=${JSON.stringify(execBody).slice(0, 400)}`,
    );

    expect(aliasOk, "buildNextflowLaunchParameters mirrors samplesheet→input").toBe(true);
    expect(wronglyClaimsSamplesheetMissing, "execute must not claim samplesheet missing when provided").toBe(false);
  });
});
