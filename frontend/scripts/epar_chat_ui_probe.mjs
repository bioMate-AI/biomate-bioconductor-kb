// Live UI check on dev: attach the EPAR dataset, ask "不用工作流" — expect no workflow
// card/panel, the answer below the progress box, and refresh keeping the chat.
//   node scripts/epar_chat_ui_probe.mjs <outDir> <projectId> <fileId>
import { chromium } from "@playwright/test";
import { readFileSync, mkdirSync, writeFileSync } from "fs";
import { homedir } from "os";

// Precedence must match e2e/_e2e-base-url.ts: BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL > fallback
const BASE = (process.env.BASE_URL || process.env.PLAYWRIGHT_BASE_URL || process.env.BIOMATE_URL || "https://dev-public.biomate.ai").replace(/\/+$/, "");
const [out, projectId, fileId] = process.argv.slice(2); mkdirSync(out, { recursive: true });
const PW = readFileSync(`${homedir()}/.config/biomate/e2e_fixture_password`, "utf8").trim();
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1600, height: 1000 }, locale: "zh-CN" });
const r = await ctx.request.post(`${BASE}/api/auth/login`, { data: { email: "lifeifei163361@163.com", password: PW }, headers: { "x-e2e-test-token": "biomate-e2e-bypass-token-dev-only" } });
const j = await r.json();
await ctx.addCookies([{ name: "biomate_token", value: j.token || j.accessToken, domain: new URL(BASE).hostname, path: "/", secure: true }]);
await ctx.addInitScript(() => { try { localStorage.setItem("i18nextLng", "zh"); } catch {} });
const p = await ctx.newPage();
const log = [];
const q = new URLSearchParams({ project: projectId, attachFile: fileId, draft: "你可以直接编程统计吗 不用工作流" });
await p.goto(`${BASE}/?${q}`, { waitUntil: "networkidle", timeout: 60000 }).catch(() => {});
await p.waitForTimeout(3000);
await p.screenshot({ path: `${out}/01_draft.png` });
await p.keyboard.press("Enter").catch(() => {});
const send = p.locator('button[type=submit], [data-testid="button-send"]').last();
if (await send.isEnabled().catch(() => false)) await send.click().catch(() => {});
// wait until streaming finishes (send button re-enabled / no typing indicator) — max 240s
for (let s = 0; s < 240; s += 5) {
  await p.waitForTimeout(5000);
  const busy = await p.locator('[data-testid="typing-indicator"], .animate-spin').count();
  if (s > 20 && busy === 0) break;
}
await p.waitForTimeout(3000);
await p.screenshot({ path: `${out}/02_answer.png`, fullPage: false });
const panelOpen = await p.locator('.wf-panel, [data-testid="workflow-panel"]').count();
const cards = await p.locator('[data-testid="chat-message-workflow"], [data-testid^="wf-chip"]').count();
const url1 = p.url();
log.push(`url after answer: ${url1}`, `workflow panel elements: ${panelOpen}`, `workflow cards: ${cards}`);
writeFileSync(`${out}/answer_text.txt`, await p.locator("main, body").first().innerText());
await p.reload({ waitUntil: "networkidle" }).catch(() => {});
await p.waitForTimeout(5000);
await p.screenshot({ path: `${out}/03_after_refresh.png` });
const bodyText = await p.locator("body").innerText();
log.push(`url after refresh: ${p.url()}`, `question still visible after refresh: ${bodyText.includes("不用工作流")}`);
writeFileSync(`${out}/log.txt`, log.join("\n"));
await b.close();
