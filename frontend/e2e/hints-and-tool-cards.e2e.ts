/**
 * E2E (dev, live, no mocks, zh UI): hover hints + chat tool cards + "no backend name in output".
 *
 * Founder 2026-11-12:
 *   - "add hint text hover for each element in the side bar, each tab in each panel"
 *   - screenshots of an image-QC chat: a Read File card showing {"galaxy_dataset_id":"<uuid>"},
 *     a clipped code preview, and an answer that was only "现在让我生成可视化的 QC 报告："
 *   - "there should not have galaxy in output!!!!"
 *
 * Flow A (one login, one chat):
 *   1. Sidebar items open their zh hint on keyboard focus; no native `title` remains.
 *   2. Models page tabs: hint opens AND the selected tab keeps data-state="active".
 *   3. Image-QC chat with a real uploaded PNG: no "galaxy", UUID or s3 anywhere in the chat
 *      (collapsed + expanded tool cards included); collapsed code preview shows whole lines;
 *      the turn ends with an answer, not a promise of one.
 *
 * Run: E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/hints-and-tool-cards.e2e.ts
 */
import { test, expect, type Page } from "@playwright/test";
import fs from "fs";
import path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import zh from "../client/src/locales/zh/common.json";

test.use({ locale: "zh-CN" });
const SHOTS = "e2e/screenshots/hints-and-tool-cards";
const UUID_RE = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i;

async function setZh(page: Page) {
  await page.addInitScript(() => {
    try {
      const raw = localStorage.getItem("biomate-user-settings");
      const s = raw ? JSON.parse(raw) : {};
      localStorage.setItem("biomate-user-settings", JSON.stringify({ ...s, language: "zh" }));
    } catch { /* ignore */ }
  });
}

async function tooltipFor(page: Page, testId: string): Promise<string> {
  const el = page.getByTestId(testId).first();
  await el.focus();
  const tip = page.getByRole("tooltip").first();
  await tip.waitFor({ state: "attached", timeout: 5000 });
  const text = (await tip.textContent()) || "";
  await page.keyboard.press("Escape");
  await el.blur().catch(() => {});
  await page.waitForTimeout(150);
  return text.trim();
}

test("zh: hover hints, tool cards, no backend name in output", async ({ page }) => {
  test.setTimeout(9 * 60 * 1000);
  fs.mkdirSync(SHOTS, { recursive: true });
  await setZh(page);
  await loginAsFixture(page);
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });

  // ── 1. Sidebar hints ───────────────────────────────────────────────────────
  const nav: Array<[string, string]> = [
    ["button-data-nav", zh.hint.nav.data],
    ["button-workflows-nav", zh.hint.nav.workflows],
    ["button-models-nav", zh.hint.nav.models],
    ["button-projects-section", zh.hint.nav.projects],
    ["button-settings-sidebar", zh.hint.nav.settings],
    ["button-logout", zh.hint.nav.sign_out],
  ];
  for (const [id, want] of nav) {
    expect(await page.getByTestId(id).first().getAttribute("title"), `${id} native title`).toBeNull();
    expect(await tooltipFor(page, id), `${id} hint`).toBe(want);
  }
  await page.getByTestId("button-data-nav").first().focus();
  await page.getByRole("tooltip").first().waitFor({ state: "visible" });
  await page.screenshot({ path: `${SHOTS}/1-sidebar-hint.png` });
  await page.keyboard.press("Escape");

  // ── 2. Models tabs: hint + active state survives ──────────────────────────
  await page.getByTestId("button-models-nav").first().click();
  await page.getByTestId("models-track-0").waitFor({ state: "visible", timeout: 30_000 });
  expect(await page.getByTestId("models-track-0").getAttribute("data-state")).toBe("active");
  expect(await tooltipFor(page, "models-track-1")).toBe(zh.hint.models.library);
  await page.getByTestId("models-track-1").click();
  await expect(page.getByTestId("models-track-1")).toHaveAttribute("data-state", "active");
  await expect(page.getByTestId("models-track-0")).toHaveAttribute("data-state", "inactive");
  await page.getByTestId("models-track-1").hover();
  await page.getByRole("tooltip").first().waitFor({ state: "visible" });
  await page.screenshot({ path: `${SHOTS}/2-models-tab-hint.png` });

  // ── 3. Image-QC chat ───────────────────────────────────────────────────────
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
  const nc = page.getByTestId("button-new-chat");
  if ((await nc.count().catch(() => 0)) > 0) { await nc.first().click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1500); }
  const png = fs.readFileSync(path.resolve("client/public/biomate-logo.png"));
  await page.locator('[data-testid="chat-attach-file-input"]').setInputFiles([{ name: "qc_image.png", mimeType: "image/png", buffer: png }]);
  await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 30_000 }).catch(() => {});
  const input = page.getByTestId("chat-input");
  await input.click();
  await input.fill("请对这张图片做质量控制，并生成可视化的 QC 报告。");
  const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await send.waitFor({ state: "visible", timeout: 60_000 });
  await send.click();

  // Turn finished: the send button is usable again and at least one tool card exists.
  await page.locator('[data-testid^="tool-block-"]').first().waitFor({ state: "visible", timeout: 240_000 });
  await page.waitForFunction(() => {
    return !document.querySelector('[data-testid="chat-stop-button"]');
  }, undefined, { timeout: 300_000 }).catch(() => {});
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${SHOTS}/3-chat-collapsed.png`, fullPage: true });

  const cards = page.locator('[data-testid^="tool-block-"]');
  const n = await cards.count();
  console.log(`[tool cards] ${n}`);
  // Collapsed code previews: whole lines only (≤2), remainder counted below.
  const previews = page.getByTestId("tool-code-preview");
  for (let i = 0; i < await previews.count(); i++) {
    const pre = (await previews.nth(i).locator("pre").textContent()) || "";
    expect(pre.split("\n").length, "code preview lines").toBeLessThanOrEqual(2);
    expect(pre.startsWith("\n"), "no leading blank line").toBe(false);
  }
  // Expand every card, then scan the whole chat text.
  for (let i = 0; i < n; i++) {
    const header = cards.nth(i).locator("button[aria-expanded]").first();
    if ((await header.getAttribute("aria-expanded")) === "false") await header.click().catch(() => {});
  }
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${SHOTS}/4-chat-expanded.png`, fullPage: true });
  const chatText = await page.locator("main").innerText().catch(async () => page.locator("body").innerText());
  // The composer/sidebar are not output; restrict to the message list when present.
  const msgs = page.locator('[data-testid="chat-messages"]').first();
  const outText = (await msgs.count()) ? await msgs.innerText() : chatText;
  const leaks = [/galaxy/i, UUID_RE, /s3:\/\//i, /\bS3\b/].filter((re) => re.test(outText)).map(String);
  if (leaks.length) console.log("[leak context]", outText.slice(0, 3000));
  expect(leaks, "backend name / ids / storage in chat output").toEqual([]);

  // The turn ends with an answer: last assistant text is not a dangling announcement.
  const assistant = page.locator('[data-role="assistant"]').last();
  const finalText = ((await assistant.count()) ? await assistant.innerText() : outText).trim();
  console.log("[final answer tail]", finalText.slice(-300));
  expect(/[:：]\s*$/.test(finalText), "answer must not end on an announcement colon").toBe(false);
});
