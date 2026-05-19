// Diagnostic: open dev-public with a known completed runId in URL state,
// wait for chat-output-attachments to render, dump what it contains.
// No pipeline run cost — just exercises the React render path against the
// canonical endpoint with real data.
//
// Usage: node frontend/e2e/output-render-probe.mjs <runId>

import { chromium } from "playwright";

const RID = process.argv[2] || "3f5678de-cefa-4f24-a4e7-c3c3a7d24df0"; // v17
const BASE = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

const browser = await chromium.launch();
const ctx = await browser.newContext({
  extraHTTPHeaders: { "x-e2e-test-token": TOKEN },
});
const page = await ctx.newPage();
page.on("console", (m) => console.log(`[console:${m.type()}]`, m.text().slice(0, 300)));
page.on("pageerror", (e) => console.log("[pageerror]", e.message));
page.on("requestfailed", (r) =>
  console.log("[reqfail]", r.url(), r.failure()?.errorText)
);

// 1. Fetch outputs directly to confirm endpoint state at probe time
const resp = await page.request.get(`${BASE}/api/runs/${RID}/outputs`);
const body = await resp.json().catch(() => ({}));
const items = body.outputs || [];
const mrcs = items.filter((o) => o.fileType === "density_map");
console.log(`[api] /api/runs/${RID}/outputs → ${items.length} items, ${mrcs.length} density_map`);
if (mrcs[0]) {
  console.log("[api] mrc[0]:", {
    name: mrcs[0].name,
    fileType: mrcs[0].fileType,
    hasDownloadUrl: !!mrcs[0].downloadUrl,
    hasMetadataS3Uri: !!mrcs[0].metadata?.s3Uri,
  });
}

// 2. Load the app at a runs URL (most direct way to surface ChatOutputAttachments)
await page.goto(`${BASE}/runs/${RID}`, { waitUntil: "domcontentloaded" });
await page.waitForTimeout(5000);

// 3. Look for the testid markers
const tags = {
  chatOutputAttachments: await page.locator('[data-testid="chat-output-attachments"]').count(),
  densityMapViewer: await page.locator('[data-testid="density-map-viewer"]').count(),
  outputResultStateBadge: await page.locator('[data-testid="output-result-state-badge"]').count(),
};
console.log("[dom counts]", tags);

// 4. Inner text of chat-output-attachments if present
if (tags.chatOutputAttachments > 0) {
  const text = await page
    .locator('[data-testid="chat-output-attachments"]')
    .first()
    .textContent()
    .catch(() => "");
  console.log("[chat-output-attachments text]", (text || "").slice(0, 800));
}

// 5. Try a session+message URL too, in case ChatOutputAttachments only renders inside a chat session
const sessionsResp = await page.request.get(`${BASE}/api/sessions?limit=5`);
const sessions = await sessionsResp.json().catch(() => []);
console.log("[sessions] count:", Array.isArray(sessions) ? sessions.length : "non-list");

await browser.close();
