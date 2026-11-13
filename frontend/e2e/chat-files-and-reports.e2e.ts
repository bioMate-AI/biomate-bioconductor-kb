/**
 * E2E (dev, live, no mocks, zh UI) — founder screenshots 2026-11-12:
 *   noImageHandle · chineseCharacter_multiFiguresInOne · noTimeStamp_moreGeneratedFiles… ·
 *   "no direct download link… link to the folder" · "biomate has no ability to generate doc files" ·
 *   htmlNotVisulized · "show the linked view in the right artifact view".
 *
 * Flow A (one login, one project chat):
 *   1. Image question ("这张图在说什么" + PNG): the reply describes the picture — never "无法查看".
 *   2. CSV QC request asking for Chinese-titled figures (one per file), a Markdown report with the
 *      figures, and a Word document: the reply ends with a Generated files list containing .png,
 *      .md and .docx; clicking a file opens it beside the chat (right panel); the .md shows its
 *      figures; the folder link reveals the chat's folder on the Data page.
 *
 * Run: E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/chat-files-and-reports.e2e.ts --project=chromium
 */
import { test, expect, type Page } from "@playwright/test";
import fs from "fs";
import path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ locale: "zh-CN" });
const SHOTS = "e2e/screenshots/chat-files-and-reports";

async function settle(page: Page, maxMs = 8 * 60_000): Promise<void> {
  // A turn is done when the composer is idle (no Stop) and the chat text is unchanged for 15 s.
  const msgs = page.getByTestId("chat-messages").first();
  let last = "", since = Date.now();
  const deadline = Date.now() + maxMs;
  for (;;) {
    const text = await msgs.innerText().catch(() => "");
    const busy = await page.getByTestId("chat-stop-button").count();
    if (text !== last || busy > 0) { last = text; since = Date.now(); }
    if (Date.now() - since >= 15_000) return;
    if (Date.now() > deadline) throw new Error("turn did not settle");
    await page.waitForTimeout(2500);
  }
}

async function send(page: Page, text: string, file?: { name: string; mimeType: string; buffer: Buffer }) {
  if (file) {
    await page.locator('[data-testid="chat-attach-file-input"]').setInputFiles([file]);
    await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 30_000 }).catch(() => {});
  }
  const input = page.getByTestId("chat-input");
  await input.click();
  await input.fill(text);
  await page.locator('[data-testid="chat-send-button"]:not([disabled])').click({ timeout: 60_000 });
  await page.getByTestId("chat-stop-button").waitFor({ state: "visible", timeout: 20_000 }).catch(() => {});
}

test("zh: image question, documents with figures, generated files beside the chat", async ({ page }) => {
  test.setTimeout(20 * 60 * 1000);
  fs.mkdirSync(SHOTS, { recursive: true });
  await page.addInitScript(() => { try { localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "zh" })); } catch {} });
  await loginAsFixture(page);
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
  // Generated files are saved only in PROJECT chats (by design) — start the chat inside a project,
  // through the sidebar like a user: open the project, then its "+ 新建对话".
  const projects = (await (await page.request.get(BASE_URL + "/api/projects")).json())?.projects ?? [];
  const project = projects.find((p: any) => p.name === "test" && p.status !== "archived") ?? projects.find((p: any) => p.status !== "archived");
  expect(project, "the fixture account needs one project").toBeTruthy();
  await page.getByTestId(`button-project-${project.id}`).click({ timeout: 30_000 });
  await page.getByTestId(`project-new-chat-${project.id}`).click({ timeout: 30_000 });
  await page.waitForTimeout(1500);

  // ── 1. Image question ──────────────────────────────────────────────────────
  const png = fs.readFileSync(path.resolve("client/public/biomate-logo.png"));
  await send(page, "这张图在说什么", { name: "logo.png", mimeType: "image/png", buffer: png });
  await settle(page);
  const firstReply = (await page.locator('[data-role="assistant"]').last().innerText()).trim();
  console.log("[image reply]", firstReply.slice(0, 300));
  expect(firstReply, "the model must see the image").not.toMatch(/无法(直接)?(查看|显示|看到)|cannot (see|view)/);
  await page.screenshot({ path: `${SHOTS}/1-image-reply.png`, fullPage: true });

  // ── 2. CSV QC with figures, Markdown + Word ────────────────────────────────
  const csv = ["compound,mw,logp,herg_ic50_um,dili", "A,320.4,2.1,35,low", "B,451.2,4.8,0.8,high",
    "C,287.3,1.2,120,low", "D,512.6,5.4,2.5,medium", "E,198.2,0.4,200,low", "F,388.9,3.3,9.6,medium"].join("\n");
  await send(page,
    "对这个文件做质量控制：画 2 张图（中文标题，每张图单独保存），再生成一份包含这些图的 Markdown 报告和一份 Word（.docx）报告。",
    { name: "admet_qc.csv", mimeType: "text/csv", buffer: Buffer.from(csv) });
  await settle(page, 12 * 60_000);
  await page.screenshot({ path: `${SHOTS}/2-qc-reply.png`, fullPage: true });

  const card = page.getByTestId("generated-files").last();
  await expect(card, "the reply lists the files it saved").toBeVisible({ timeout: 60_000 });
  const names = await card.getByTestId("generated-file-open").allInnerTexts();
  console.log("[generated files]", names);
  expect(names.some((n) => /\.png$/i.test(n)), "a figure was saved").toBe(true);
  expect(names.some((n) => /\.md$/i.test(n)), "a Markdown report was saved").toBe(true);
  expect(names.some((n) => /\.docx$/i.test(n)), "a Word document was saved").toBe(true);

  // Open the Markdown report beside the chat: its figures render.
  await card.getByTestId("generated-file-open").filter({ hasText: /\.md$/i }).first().click();
  const panel = page.getByTestId("chat-file-panel");
  await expect(panel).toBeVisible({ timeout: 20_000 });
  await expect(page.getByTestId("chat-input")).toBeVisible(); // the chat is still there
  await expect(panel.getByTestId("markdown-figure").first()).toBeVisible({ timeout: 30_000 });
  await page.screenshot({ path: `${SHOTS}/3-md-beside-chat.png` });
  await panel.getByTestId("chat-file-panel-close").click();

  // A figure beside the chat — check the Chinese title rendered (screenshot is audited by eye).
  await card.getByTestId("generated-file-open").filter({ hasText: /\.png$/i }).first().click();
  await expect(page.getByTestId("chat-file-panel")).toBeVisible({ timeout: 20_000 });
  await page.waitForTimeout(3000);
  await page.screenshot({ path: `${SHOTS}/4-figure-beside-chat.png` });
  await page.getByTestId("chat-file-panel-close").click();

  // Folder link → Data page reveals the chat's folder (named "<title> · <time>").
  await card.getByTestId("generated-files-folder").click();
  await page.waitForURL(/\/files\?/, { timeout: 30_000 });
  const folderParam = new URL(page.url()).searchParams.get("folder") || "";
  expect(folderParam).toMatch(/^outputs\/analysis\/.+ · \d{4}-\d{2}-\d{2} \d{2}\.\d{2}$/);
  await expect(page.locator(`[data-testid="folder-${folderParam}"]`)).toBeVisible({ timeout: 30_000 });
  await page.screenshot({ path: `${SHOTS}/5-data-folder.png` });
});
