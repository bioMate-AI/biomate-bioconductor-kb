/**
 * E2E (dev, live, no mocks): files run_code generates are KEPT — downloadable, readable in the next
 * turn, and saved into the project automatically in a project chat. No "not produced" footer.
 *
 * Founder 2026-11-11: "where is the QC_report file!!!!" — a QC_Report.txt run_code wrote was deleted
 * with the per-call temp dir; "the picture generated is still not provided for download"; "the
 * generated files should also be saved to project automatically".
 *
 * The report holds a token = sha256(seed)[:16] that the code writes but never prints, so the model
 * can only return it in the next turn by READING the saved file (not recomputing from memory).
 *
 * Flow A (UI, non-project chat): generate report + plot → download chip + figure Download → the
 *   downloaded file holds the token → next turn returns the token → no footer.
 * Flow B (API, one project): chat with context.projectId → file appears in the project as source
 *   'run_code' → its download holds the token. Project deleted in finally.
 *
 * Run: E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/run-code-outputs.e2e.ts --project=chromium
 */
import { test, expect } from "@playwright/test";
import { createHash } from "crypto";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { createProject, deleteProjectLoudly, expandProjectInSidebar, openProjectFiles, revealFile } from "./_project-ui";

const seed = () => `qc${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`;
const tokenOf = (s: string) => createHash("sha256").update(s).digest("hex").slice(0, 16);
const FOOTER = /not produced by any code|并未由本轮执行的代码生成/;
const reportPrompt = (s: string) =>
  `Use run_code (Python) to write a QC report file QC_Report.txt to $OUTPUT_DIR. Its first line must be ` +
  `TOKEN=<t> where t = hashlib.sha256("${s}".encode()).hexdigest()[:16]. Do NOT print t or the file ` +
  `content. Also save a small bar chart qc_plot.png (any 3 bars). Then just say the files are ready.`;

test.describe("run_code generated files are kept", () => {
  test.setTimeout(10 * 60 * 1000);

  // Flow A (normal, non-project chat) — commented out per founder 2026-11-11: "normal chat comment
  // out, only project". Kept as test.skip so it can be re-enabled.
  test.skip("Flow A — UI: download chip, figure download, next-turn read, no footer", async ({ page }) => {
    const s = seed(); const token = tokenOf(s);
    await loginAsFixture(page);
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
    const nc = page.getByTestId("button-new-chat");
    if ((await nc.count()) > 0) { await nc.first().click({ timeout: 8000 }); await expect(page.getByTestId("chat-input")).toBeEditable(); }

    const send = async (text: string) => {
      const input = page.getByTestId("chat-input");
      await input.click(); await input.fill(text);
      const btn = page.locator('[data-testid="chat-send-button"]:not([disabled])');
      await btn.waitFor({ state: "visible", timeout: 60_000 });
      await btn.click({ timeout: 15_000 }).catch(async () => { await btn.click({ force: true }); });
    };

    await send(reportPrompt(s));
    const chip = page.locator('[data-testid="run-code-file-download"]', { hasText: "QC_Report.txt" }).first();
    await chip.waitFor({ state: "visible", timeout: 240_000 });
    await page.screenshot({ path: "e2e/screenshots/run-code-outputs-1-generated.png", fullPage: true });

    // The report downloads and holds the token the model never saw.
    const [dl] = await Promise.all([page.waitForEvent("download", { timeout: 60_000 }), chip.click()]);
    const body = fs.readFileSync((await dl.path())!, "utf8");
    expect(body, "downloaded QC_Report.txt must hold the token").toContain(`TOKEN=${token}`);

    // The figure has its own Download.
    const figDl = page.locator("figure").filter({ has: page.getByTestId("run-code-figure") })
      .locator('[data-testid="run-code-file-download"]').first();
    await expect(figDl, "figure must offer a download").toBeVisible();
    const href = (await figDl.getAttribute("href")) || "";
    expect(/^\/api\/datasets\/[^/]+\/download$|^data:image\//.test(href), `figure href: ${href.slice(0, 60)}`).toBe(true);

    // Next turn: the saved file is still there for the model to read.
    const before = (await page.locator("body").innerText()).length;
    await send("Give me the exact TOKEN line from QC_Report.txt — read the file you saved, do not recompute it.");
    // Condition: the token appears in the new turn (once in the downloaded-file assertion above is not in the DOM).
    await page.waitForFunction((t) => (document.body.innerText || "").includes(t), `TOKEN=${token}`, { timeout: 240_000 });
    const after = await page.locator("body").innerText();
    await page.screenshot({ path: "e2e/screenshots/run-code-outputs-2-next-turn.png", fullPage: true });
    expect(after.slice(before).includes(token), "next turn must return the token from the saved file").toBe(true);
    expect(FOOTER.test(after), "no 'not produced by any code' footer").toBe(false);
  });

  test("Flow B — project chat (UI): file saved into the project, downloadable, under Analysis outputs", async ({ page }) => {
    const s = seed(); const token = tokenOf(s);
    await loginAsFixture(page);              // ONE login: cookie session for the browser and page.request
    const api = page.request;
    const projectName = `e2e run_code outputs ${new Date().toISOString().slice(0, 16)}`;
    const projectId = await createProject(api, projectName);
    try {
      await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
      await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
      // New chats start inside a project (sidebar: project → New Chat).
      await expandProjectInSidebar(page, projectId);
      await page.getByTestId(`project-new-chat-${projectId}`).click({ timeout: 15_000 });
      const input = page.getByTestId("chat-input");
      await expect(input).toBeEditable({ timeout: 15_000 });
      await input.click(); await input.fill(reportPrompt(s));
      const btn = page.locator('[data-testid="chat-send-button"]:not([disabled])');
      await btn.waitFor({ state: "visible", timeout: 60_000 });
      // The button disables itself while the reply streams: click once, then confirm the message was
      // sent (no retry against a now-disabled button).
      await btn.click({ timeout: 15_000, noWaitAfter: true });
      await expect(page.getByText(s, { exact: false }).first(), "prompt must be sent").toBeVisible({ timeout: 30_000 });

      const chip = page.locator('[data-testid="run-code-file-download"]', { hasText: "QC_Report.txt" }).first();
      await chip.waitFor({ state: "visible", timeout: 240_000 });
      // The figure offers a download too (also the condition that the reply finished rendering).
      const figDl = page.locator("figure").filter({ has: page.getByTestId("run-code-figure") })
        .locator('[data-testid="run-code-file-download"]').first();
      await expect(figDl, "figure must offer a download").toBeVisible({ timeout: 60_000 });
      await page.screenshot({ path: "e2e/screenshots/run-code-outputs-project-1-chat.png", fullPage: true });
      const [dl] = await Promise.all([page.waitForEvent("download", { timeout: 60_000 }), chip.click()]);
      const body = fs.readFileSync((await dl.path())!, "utf8");
      expect(body, "downloaded QC_Report.txt must hold the token").toContain(`TOKEN=${token}`);
      const chatText = await page.locator("body").innerText();
      expect(FOOTER.test(chatText), "no 'not produced by any code' footer").toBe(false);

      // Saved into the project: source run_code, under "Analysis outputs" (folder-outputs/analysis),
      // in this chat's own folder ("<chat title> · <date time>/QC_Report.txt", ab11d0adca).
      const files = await (await api.get(`${BASE_URL}/api/projects/${projectId}/files`)).json();
      const f = (files.files || []).find((x: any) => String(x.name).split("/").pop() === "QC_Report.txt");
      expect(f, `QC_Report.txt must be in the project; got ${(files.files || []).map((x: any) => `${x.name}:${x.source}`).join(", ")}`).toBeTruthy();
      expect(f.source).toBe("run_code");
      const chatFolder = String(f.name).includes("/") ? String(f.name).slice(0, String(f.name).lastIndexOf("/")) : "";
      expect(chatFolder, "the output is filed in this chat's own folder").toMatch(/ · \d{4}-\d{2}-\d{2} \d{2}\.\d{2}$/);
      await openProjectFiles(page, projectId, projectName);
      await revealFile(page, f.id, chatFolder, "outputs/analysis");   // folders start collapsed; expand only if so
      await page.screenshot({ path: "e2e/screenshots/run-code-outputs-project-2-files.png", fullPage: true });
      await expect(page.getByTestId(`file-open-${f.id}`), "file listed in the project files view").toBeVisible();
    } finally {
      await deleteProjectLoudly(api, projectId);
    }
  });
});
