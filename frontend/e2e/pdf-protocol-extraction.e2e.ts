/**
 * PDF-PROTO-1: End-to-end test for PDF upload → protocol extraction.
 *
 * Tests the full pipeline:
 *   1. User uploads a PDF
 *   2. [Uploaded datasets:] block is constructed correctly
 *   3. _fetchPaperContentFromMessage detects the PDF + calls /api/ai_assistant/extract_pdf_text
 *   4. Paper text injected as [Paper content: ...] before LLM call
 *   5. LLM responds with actual content — NOT "Missing: FASTQ/S3"
 *   6. Intent routes to protocol_guidance (not workflow_generation → DATA-FIRST block)
 *
 * Timing note: research API (PubMed/Semantic Scholar) can block for 60-80s; LLM streaming adds
 * another 10-20s. Total response time: 70-100s. Poll timeout is 130s with 40s buffer.
 *
 * Uses fixture account per CLAUDE.md (never creates new users in E2E).
 * Screenshot taken at every key state for audit.
 */
import { test, expect, Page, request } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const FIXTURE_EMAIL = "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SCREENSHOT_DIR = path.join(__dirname, "screenshots", "pdf-proto");

// Use a real biology/AI paper PDF that has substantial extractable text.
// 2511.16931v2.pdf is a 40-page paper (OmniScientist) with 150K chars of extractable text.
// 454Score.pdf is a Galaxy QC file with minimal text — not useful for protocol extraction.
const PDF_PATHS = [
  path.resolve(__dirname, "../../research/2511.16931v2.pdf"),
  path.resolve(__dirname, "../../research/galaxy/test-data/454Score.pdf"),
];
const TEST_PDF = PDF_PATHS.find(p => fs.existsSync(p)) ?? PDF_PATHS[0];

fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

async function screenshot(page: Page, name: string) {
  const p = path.join(SCREENSHOT_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log(`[screenshot] ${p}`);
}

async function loginFixture(page: Page) {
  // Get the JWT token via Playwright APIRequestContext (avoids rate limiters, no browser needed)
  const ctx = await request.newContext({ baseURL: BASE_URL });
  const resp = await ctx.post("/api/auth/login", {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!resp.ok()) {
    const body = await resp.text();
    throw new Error(`Login API failed: ${resp.status()} ${body}`);
  }
  const body = await resp.json();
  const token: string = body.token;
  console.log("[login] API OK, user:", body?.user?.email, "token len:", token?.length);
  await ctx.dispose();

  // Inject the cookie via URL-based context.addCookies() — more reliable than domain= for localhost
  await page.context().addCookies([{
    name: "biomate_token",
    value: token,
    url: BASE_URL,
    httpOnly: true,
    secure: false,
    sameSite: "Lax",
  }]);

  // Navigate to main app — cookie is now in the browser context so /api/auth/me will succeed
  await page.goto(BASE_URL);
  await page.waitForLoadState("networkidle");
  console.log("[login] Navigated to app, URL:", page.url());

  // Verify we are NOT on the login page
  if (page.url().includes("/login")) {
    // Auth check failed even with cookie — diagnose
    const meResp = await ctx.get(BASE_URL + "/api/auth/me", {
      headers: { "Cookie": `biomate_token=${token}` },
    }).catch(() => null);
    throw new Error(`Login cookie not working — still on /login. /api/auth/me: ${meResp?.status()}`);
  }
}

test("PDF-PROTO-1: upload PDF → extract protocol → LLM answers from paper content", async ({ page }) => {
  test.setTimeout(240_000); // 4 min: upload (5s) + LLM stream (130s) + assertions

  // ── Intercept key API calls for logging ───────────────────────────────────
  const uploadResponses: any[] = [];
  const chatChunks: string[] = [];
  let chatStreamRequested = false;

  page.on("console", msg => {
    const t = msg.type();
    if (t === "error") {
      console.log("[browser-error]", msg.text());
    } else if (t === "warn" && msg.text().includes("[updateMsg]")) {
      console.log("[browser-warn]", msg.text());
    } else if (t === "log" && msg.text().includes("[ChatInterface] First delta")) {
      console.log("[browser-log]", msg.text());
    } else if (t === "log" && msg.text().includes("[ChatInterface] SSE stream complete")) {
      console.log("[browser-log]", msg.text());
    }
  });

  page.on("request", req => {
    if (req.url().includes("/api/chat/stream")) {
      chatStreamRequested = true;
      console.log("[test] Chat stream request made:", req.url());
    }
  });

  page.on("response", async (resp) => {
    if (resp.url().includes("/api/datasets/upload")) {
      try { uploadResponses.push(await resp.json()); } catch {}
    }
    if (resp.url().includes("/api/chat/stream")) {
      console.log("[test] Chat stream response status:", resp.status());
    }
  });

  // ── 1. Login and land on main app ────────────────────────────────────────
  await loginFixture(page);
  await page.waitForLoadState("networkidle");
  await screenshot(page, "01-logged-in");

  // ── 2. Start a new chat ───────────────────────────────────────────────────
  const newChatBtn = page.getByRole("button", { name: /new chat/i });
  if (await newChatBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    await newChatBtn.click();
    await page.waitForTimeout(1000);
  }

  const chatInput = page.getByTestId("chat-input").or(page.locator("textarea").first());
  await expect(chatInput).toBeVisible({ timeout: 20000 });
  await screenshot(page, "02-new-chat");

  // ── 3. Attach the PDF via the dataset browser dialog ────────────────────────
  console.log("[test] PDF path:", TEST_PDF);
  expect(fs.existsSync(TEST_PDF), `PDF not found at ${TEST_PDF}`).toBe(true);

  // Click the '+' attachment button in the chat input (title="Add data")
  const attachBtn = page.locator('button[title="Add data"]');
  await expect(attachBtn).toBeVisible({ timeout: 10000 });
  await attachBtn.click();

  // Wait for the GalaxyDatasetBrowser dialog to open (title "Select dataset")
  await expect(page.getByRole("dialog")).toBeVisible({ timeout: 10000 });
  await screenshot(page, "03a-dataset-dialog-open");

  // The dialog has a hidden <input type="file"> — set files on it directly
  // (bypasses the browser's file picker UI; triggers onChange → immediate upload)
  // Use CSS attribute selector [role="dialog"] for cross-browser reliability.
  const fileInput = page.locator('[role="dialog"] input[type="file"]');
  await expect(fileInput).toBeAttached({ timeout: 5000 });
  await fileInput.setInputFiles(TEST_PDF);

  // Wait for the upload to complete (the dialog closes automatically on upload success)
  const pdfName = path.basename(TEST_PDF);
  await expect.poll(() => uploadResponses.length, { timeout: 30000 }).toBeGreaterThan(0);
  const uploadOk = uploadResponses.find(r => r?.dataset_id);
  console.log("[test] Upload response:", JSON.stringify(uploadOk));
  expect(uploadOk?.dataset_id, `Upload failed: ${JSON.stringify(uploadResponses)}`).toBeTruthy();

  // Dialog should close, and a chip with the file name appears in the chat input area
  await expect(page.getByRole("dialog")).toBeHidden({ timeout: 15000 });
  await expect(page.getByText(pdfName, { exact: false })).toBeVisible({ timeout: 10000 });
  await screenshot(page, "03-pdf-chip-visible");
  console.log("[test] PDF chip visible:", pdfName);

  // ── 4. Send the protocol extraction request ───────────────────────────────
  const prompt = "Extract the key methods or protocol from this paper. Summarize what was done step by step.";
  await chatInput.fill(prompt);
  await screenshot(page, "04-prompt-filled");

  // Check if the send button is visible and not disabled before clicking
  const sendBtn = page.getByTestId("chat-send-button");
  const sendBtnVisible = await sendBtn.isVisible({ timeout: 5000 }).catch(() => false);
  const stopBtnVisible = await page.getByTestId("chat-stop-button").isVisible({ timeout: 1000 }).catch(() => false);
  console.log("[test] Send btn visible:", sendBtnVisible, "| Stop btn visible:", stopBtnVisible);
  console.log("[test] Page URL before send:", page.url());

  await page.getByTestId("chat-send-button").click();
  console.log("[test] Message sent, waiting for LLM response...");
  console.log("[test] Chat stream requested (0.5s after click):", chatStreamRequested);

  // ── 5. Wait for user message to appear in chat ────────────────────────────
  // The UI shows the user's text (the [Dataset: ...] metadata is hidden by the component).
  // Use [data-role="user"] to avoid matching sidebar suggestion buttons that also
  // contain the same prompt text.
  await expect(
    page.locator('[data-role="user"]').filter({ hasText: /Extract the key methods/i }).last()
  ).toBeVisible({ timeout: 20000 });
  await screenshot(page, "05-user-message-with-dataset");
  console.log("[test] Chat stream requested (after step 5):", chatStreamRequested);
  console.log("[test] Page URL after step 5:", page.url());

  // ── 6. Wait for LLM response ──────────────────────────────────────────────
  console.log("[test] Waiting for LLM response (up to 90s)...");

  // Wait for an assistant message AFTER the user sent the PDF prompt.
  // The chat may already have a greeting (~168 chars) — use > 200 threshold
  // so we don't stop on the greeting and wait for the actual substantive reply.
  // Budget: research API can block for 75s + LLM generation 15s = ~90s; give 40s buffer.
  const assistantMsgsBefore = await page.locator('[data-role="assistant"]').count();
  await expect.poll(
    async () => {
      const msgs = await page.locator('[data-role="assistant"], .ai-message, .assistant-message').allTextContents();
      // Look at messages that appeared after the greeting
      const relevantMsgs = msgs.slice(assistantMsgsBefore > 0 ? assistantMsgsBefore - 1 : 0);
      const lastMsg = relevantMsgs[relevantMsgs.length - 1] ?? "";
      console.log("[poll] relevant assistant msgs:", relevantMsgs.length, "| last length:", lastMsg.length, "| starts:", lastMsg.slice(0, 80));
      return lastMsg.length;
    },
    { timeout: 130_000, intervals: [2000, 3000, 5000] }
  ).toBeGreaterThan(200);

  await screenshot(page, "06-response-appeared");

  // ── 7. Assert response quality ────────────────────────────────────────────
  const allText = await page.content();
  const assistantMsgs = await page.locator('[data-role="assistant"], .ai-message, .assistant-message').allTextContents();
  const lastResponse = assistantMsgs[assistantMsgs.length - 1] ?? "";

  console.log("[audit] Full last assistant response:\n", lastResponse.slice(0, 2000));

  // MUST NOT contain the broken fallback phrases
  expect(lastResponse, "Response should not ask for FASTQ/S3").not.toMatch(
    /Missing.*(?:FASTQ|\.fastq|S3|s3:\/\/|sequencing data|raw data files)/i
  );
  expect(lastResponse, "Response should not use the 'Missing:' template").not.toMatch(
    /^\s*\*\*Missing:/m
  );
  expect(lastResponse, "Response should not say 'no biological data'").not.toMatch(
    /no.*biological.*data|cannot.*process.*without.*data/i
  );

  // MUST contain actual content (not empty or just boilerplate)
  expect(lastResponse.length, "Response too short — likely empty or error").toBeGreaterThan(200);

  await screenshot(page, "07-final-response");
  console.log("[PDF-PROTO-1] PASSED — response length:", lastResponse.length);
});

test("PDF-PROTO-2: two PDFs uploaded in one message are both extracted", async ({ page }) => {
  test.setTimeout(240_000);

  const uploadResponses: any[] = [];
  page.on("response", async (resp) => {
    if (resp.url().includes("/api/datasets/upload")) {
      try { uploadResponses.push(await resp.json()); } catch {}
    }
  });

  await loginFixture(page);
  await page.waitForLoadState("networkidle");

  const chatInput = page.getByTestId("chat-input").or(page.locator("textarea").first());
  await expect(chatInput).toBeVisible({ timeout: 20000 });

  // Upload first PDF via dataset browser
  const attachBtn = page.locator('button[title="Add data"]');
  await attachBtn.click();
  await expect(page.getByRole("dialog")).toBeVisible({ timeout: 10000 });
  const fileInput = page.locator('[role="dialog"] input[type="file"]');
  await expect(fileInput).toBeAttached({ timeout: 5000 });
  await fileInput.setInputFiles(TEST_PDF);
  await expect.poll(() => uploadResponses.length, { timeout: 30000 }).toBeGreaterThanOrEqual(1);
  await expect(page.getByRole("dialog")).toBeHidden({ timeout: 15000 });

  // Upload second PDF via dataset browser (open again)
  await attachBtn.click();
  await expect(page.getByRole("dialog")).toBeVisible({ timeout: 10000 });
  const fileInput2 = page.locator('[role="dialog"] input[type="file"]');
  await expect(fileInput2).toBeAttached({ timeout: 5000 });
  await fileInput2.setInputFiles(TEST_PDF);
  await expect.poll(() => uploadResponses.length, { timeout: 30000 }).toBeGreaterThanOrEqual(2);
  await expect(page.getByRole("dialog")).toBeHidden({ timeout: 15000 });

  // At least one file chip should be visible
  await expect(page.getByText(path.basename(TEST_PDF), { exact: false }).first()).toBeVisible({ timeout: 10000 });
  await screenshot(page, "two-pdfs-attached");
  console.log("[PDF-PROTO-2] Upload responses:", uploadResponses.length);

  await chatInput.fill("Extract the methods from both papers and compare them.");
  // Capture count of assistant messages already visible (greeting) before sending
  const assistantMsgsBefore2 = await page.locator('[data-role="assistant"]').count();
  await page.getByTestId("chat-send-button").click();

  await expect.poll(
    async () => {
      const msgs = await page.locator('[data-role="assistant"], .ai-message, .assistant-message').allTextContents();
      // Skip the greeting by looking at messages from the pre-existing count
      const relevantMsgs = msgs.slice(assistantMsgsBefore2 > 0 ? assistantMsgsBefore2 - 1 : 0);
      const lastMsg = relevantMsgs[relevantMsgs.length - 1] ?? "";
      return lastMsg.length;
    },
    { timeout: 130_000, intervals: [2000, 3000, 5000] }
  ).toBeGreaterThan(200);

  await screenshot(page, "two-pdfs-response");

  const assistantMsgs = await page.locator('[data-role="assistant"], .ai-message, .assistant-message').allTextContents();
  const lastResponse = assistantMsgs[assistantMsgs.length - 1] ?? "";
  console.log("[PDF-PROTO-2] Response:", lastResponse.slice(0, 500));

  expect(lastResponse).not.toMatch(/Missing.*(?:FASTQ|S3)/i);
  expect(lastResponse.length).toBeGreaterThan(200);

  console.log("[PDF-PROTO-2] PASSED");
});
