// Diagnostic: drive the dev-public chat-session flow to inspect what
// ChatOutputAttachments actually renders for a completed run. No GPU
// pipeline run required.
//
// Reads CS-14 case: viewer doesn't mount despite canonical endpoint
// returning 258 outputs with 3 density_map. This probe answers:
// - Does ChatOutputAttachments mount in the chat-session render?
// - If yes, what testids and DOM tree exist inside it?
// - Are the .mrc items reaching the density_map case?
//
// Usage: node frontend/e2e/output-render-probe.mjs <runId>
// Falls back to v17's runId when omitted.

import { chromium } from "playwright";
import { randomBytes } from "crypto";

const RID = process.argv[2] || "3f5678de-cefa-4f24-a4e7-c3c3a7d24df0";
const BASE = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

const log = (label, value) => console.log(`[${label}]`, typeof value === "string" ? value : JSON.stringify(value).slice(0, 800));

// 1. Verify the canonical endpoint state right now
async function checkApi() {
  const r = await fetch(`${BASE}/api/runs/${RID}/outputs`);
  if (!r.ok) { log("api", `HTTP ${r.status}`); return null; }
  const body = await r.json();
  const items = body.outputs || [];
  const mrcs = items.filter((o) => o.fileType === "density_map");
  log("api", { runId: RID, count: items.length, mrcs: mrcs.length, mrcSample: mrcs[0]?.name });
  return body;
}

// 2. Open a real browser session against dev
async function runBrowserProbe() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({
    extraHTTPHeaders: { "x-e2e-test-token": TOKEN },
  });
  const page = await ctx.newPage();
  page.on("console", (m) => {
    const t = m.text();
    if (t.length < 500 && !t.includes("fonts.gstatic")) console.log(`  [browser:${m.type()}]`, t.slice(0, 300));
  });
  page.on("pageerror", (e) => console.log("  [browser:pageerror]", e.message));

  // 2a. Register a throwaway user via the e2e bypass (mirror super-test payload)
  const email = `probe-${randomBytes(4).toString("hex")}@test.local`;
  const regResp = await page.request.post(`${BASE}/api/auth/register`, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": TOKEN },
    data: {
      fullName: "Probe User",
      email,
      password: "TestPass123!",
      termsAccepted: true,
    },
  });
  if (!regResp.ok()) {
    log("register", `HTTP ${regResp.status()} — ${await regResp.text().catch(() => "")}`);
  } else {
    log("register", `OK (${email})`);
  }

  // App route is `/` (no /chat path). Navigate there.
  await page.goto(`${BASE}/`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(3000);

  log("nav", page.url());

  // 2c. Find or create a chat session that contains a workflow message
  //     referencing our runId. Simplest: directly inject the message via
  //     localStorage / app state so we render the workflow viewer.
  //
  //     If that fails, fall through to inspecting whatever IS on the page.

  const initial = await page.evaluate(() => ({
    title: document.title,
    hasChatOutput: !!document.querySelector('[data-testid="chat-output-attachments"]'),
    hasViewer: !!document.querySelector('[data-testid="density-map-viewer"]'),
    hasNFViewer: !!document.querySelector('[data-testid*="nextflow"]'),
    bodyTextHead: (document.body.innerText || "").slice(0, 300),
  }));
  log("initial-page", initial);

  // 2d. Drive the UI: find the chat input, type a prompt, click send.
  //     Wait for the workflow viewer to mount, then capture DOM.
  const composerSelectors = [
    'textarea[placeholder*="workflow" i]',
    'textarea[placeholder*="ask" i]',
    'input[placeholder*="workflow" i]',
    '[data-testid*="chat-input"]',
    '[data-testid*="composer"]',
    'textarea',
  ];
  let composer = null;
  for (const sel of composerSelectors) {
    const loc = page.locator(sel).first();
    if (await loc.isVisible({ timeout: 1000 }).catch(() => false)) { composer = loc; log("composer", sel); break; }
  }
  if (composer) {
    await composer.fill("Run CryoSPARC SPA on s3://biomate-cryo-data/empiar/EMPIAR-10025");
    // Find send button
    const send = page.locator('button[type="submit"], [data-testid*="send"], button:has-text("Send")').first();
    await send.click({ timeout: 5000 }).catch(() => {});
    // Wait for workflow card to appear, then check viewer panel
    await page.waitForTimeout(20_000);
  } else {
    log("composer", "NOT FOUND — page may require login first");
  }

  const after = await page.evaluate(() => ({
    hasChatOutput: !!document.querySelector('[data-testid="chat-output-attachments"]'),
    hasViewer: !!document.querySelector('[data-testid="density-map-viewer"]'),
    visibleTestIds: Array.from(document.querySelectorAll("[data-testid]"))
      .map((el) => el.dataset.testid)
      .slice(0, 30),
  }));
  log("after-message", after);

  // 2f. If we have chat-output-attachments, dump it
  if (after.hasChatOutput) {
    const dump = await page.evaluate(() => {
      const root = document.querySelector('[data-testid="chat-output-attachments"]');
      if (!root) return null;
      return {
        innerTextHead: root.innerText.slice(0, 1500),
        childCount: root.children.length,
        testidsInside: Array.from(root.querySelectorAll("[data-testid]")).map((el) => el.dataset.testid).slice(0, 40),
        // Pull a few items if any
        cards: Array.from(root.querySelectorAll('[class*="card"], [class*="Card"]'))
          .slice(0, 5)
          .map((el) => (el.textContent || "").slice(0, 100)),
      };
    });
    log("chat-output-attachments-dump", dump);
  }

  await browser.close();
}

console.log("=== Output render probe ===");
console.log(`runId: ${RID}`);
console.log(`base:  ${BASE}`);
console.log("");

await checkApi();
console.log("");
await runBrowserProbe().catch((e) => console.log("probe failed:", e.message));
