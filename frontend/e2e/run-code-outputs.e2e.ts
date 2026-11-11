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
import { loginAsFixture, BASE_URL, E2E_TOKEN } from "./_fixture-login";

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
    if ((await nc.count().catch(() => 0)) > 0) { await nc.first().click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1500); }

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
    await page.waitForFunction((t) => (document.body.innerText || "").split(t).length > 2, `TOKEN=${token}`, { timeout: 240_000 })
      .catch(() => {});
    await page.waitForTimeout(3000);
    const after = await page.locator("body").innerText();
    await page.screenshot({ path: "e2e/screenshots/run-code-outputs-2-next-turn.png", fullPage: true });
    expect(after.slice(before).includes(token), "next turn must return the token from the saved file").toBe(true);
    expect(FOOTER.test(after), "no 'not produced by any code' footer").toBe(false);
  });

  test("Flow B — project chat saves the file into the project", async ({ request }) => {
    const s = seed(); const token = tokenOf(s);
    const pw = process.env.E2E_FIXTURE_PASSWORD;
    test.skip(!pw, "E2E_FIXTURE_PASSWORD not set");
    const H = { "x-e2e-test-token": E2E_TOKEN };
    const login = await request.post(`${BASE_URL}/api/auth/login`, { headers: H, data: { email: "lifeifei163361@163.com", password: pw } });
    expect(login.ok(), `login ${login.status()}`).toBeTruthy();
    const auth = { ...H, Authorization: `Bearer ${(await login.json()).token}` };
    const pr = await request.post(`${BASE_URL}/api/projects`, { headers: auth, data: { name: `e2e run_code outputs ${new Date().toISOString().slice(0, 16)}` } });
    expect(pr.ok(), `create project ${pr.status()}`).toBeTruthy();
    const pj = await pr.json(); const projectId = pj.id || pj.project?.id;
    expect(projectId, "project id").toBeTruthy();
    try {
      const chat = await request.post(`${BASE_URL}/api/chat/stream`, {
        headers: { ...auth, Accept: "text/event-stream" },
        data: { message: reportPrompt(s), sessionId: `e2e-ro-${Date.now()}`, context: { projectId } },
        timeout: 300_000,
      });
      expect(chat.ok(), `chat ${chat.status()}`).toBeTruthy();
      const sse = await chat.text();
      expect(FOOTER.test(sse), "no footer in the project-chat reply").toBe(false);

      const files = await (await request.get(`${BASE_URL}/api/projects/${projectId}/files`, { headers: auth })).json();
      const f = (files.files || []).find((x: any) => x.name === "QC_Report.txt");
      expect(f, `QC_Report.txt must be in the project; got ${(files.files || []).map((x: any) => `${x.name}:${x.source}`).join(", ")}`).toBeTruthy();
      expect(f.source).toBe("run_code");
      const u = await (await request.get(`${BASE_URL}/api/projects/${projectId}/files/${f.id}/url`, { headers: auth })).json();
      const content = await (await request.get(u.url.startsWith("http") ? u.url : `${BASE_URL}${u.url}`, { headers: u.url.startsWith("http") ? {} : auth })).text();
      expect(content, "project copy must hold the token").toContain(`TOKEN=${token}`);
    } finally {
      await request.delete(`${BASE_URL}/api/projects/${projectId}`, { headers: auth }).catch(() => {});
    }
  });
});
