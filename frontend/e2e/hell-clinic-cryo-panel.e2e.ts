/**
 * Focused cryo panel screenshot: wait for Movies Path + settings without cs_image.
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), "execshots", "hell-clinic-20261113");
fs.mkdirSync(OUT, { recursive: true });

test("cryo panel settled: Movies Path + no Cs Image", async ({ page }) => {
  test.setTimeout(6 * 60_000);
  await loginAsFixture(page);
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
  const newChat = page.getByTestId("button-new-chat");
  if ((await newChat.count().catch(() => 0)) > 0) {
    await newChat.first().click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(1500);
  }

  const input = page.getByTestId("chat-input");
  await input.fill(
    "Open cryosparc_standard_spa (CryoSPARC Standard SPA) in the right panel. Do not run.",
  );
  await page.locator('[data-testid="chat-send-button"]:not([disabled])').click();

  // Wait until chat mentions Movies Path (settled response)
  await page.getByText(/Movies Path/i).first().waitFor({ timeout: 220_000 });
  await page.waitForTimeout(5000);

  // Open right panel / settings if needed
  const openPanel = page.getByRole("button", { name: /open.*panel|in panel|configure|Confirm and configure/i });
  if ((await openPanel.count()) > 0) {
    await openPanel.first().click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(2000);
  }
  const settings = page.getByRole("button", { name: /settings|parameters|edit params/i });
  if ((await settings.count()) > 0) {
    await settings.first().click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1500);
  }

  await page.screenshot({ path: path.join(OUT, "01b-cryo-settled.png"), fullPage: true });
  const panel = page.getByTestId("workflow-right-panel");
  if ((await panel.count()) > 0) {
    await panel.first().screenshot({ path: path.join(OUT, "01b-cryo-panel.png") }).catch(() => {});
  }

  const body = (await page.locator("body").innerText()) || "";
  fs.writeFileSync(path.join(OUT, "01b-cryo-settled.txt"), body.slice(0, 16000));

  expect(body).toMatch(/Movies Path/i);
  expect(body).not.toMatch(/\bCs Image\b/i);
  expect(body).not.toMatch(/dkr\.ecr\./i);
  expect(body).not.toMatch(/\bcs_image\b/i);

  // Confirm button should not launch when movies empty — prefer disabled or Fix now
  const confirm = page.getByRole("button", { name: /confirm\s*&?\s*run/i });
  if ((await confirm.count()) > 0) {
    const disabled =
      (await confirm.first().isDisabled().catch(() => false)) ||
      (await confirm.first().getAttribute("aria-disabled")) === "true";
    const api = await page.request.post(`${BASE_URL}/api/workflows/execute`, {
      data: {
        workflowDefinition: {
          name: "CryoSPARC Standard SPA",
          nextflow_path:
            "biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf",
          required_params: [{ name: "movies_path", type: "file", required: true, value: null }],
          optional_params: [],
        },
        params: {},
      },
    });
    const j = await api.json();
    expect(api.status()).toBe(400);
    expect(JSON.stringify(j)).toMatch(/movies_path/);
    console.log("[cryo] confirmDisabled=", disabled, "apiBlocks=", true);
  }
});
