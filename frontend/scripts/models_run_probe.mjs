// Functional probe of Models → "Run a model" (inference) and Train → "在聊天中检查" on dev.
//   node scripts/models_run_probe.mjs <outDir>
import { chromium } from "@playwright/test";
import { readFileSync, mkdirSync, writeFileSync } from "fs";
import { homedir } from "os";

// Precedence must match e2e/_e2e-base-url.ts: BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL > fallback
const BASE = (process.env.BASE_URL || process.env.PLAYWRIGHT_BASE_URL || process.env.BIOMATE_URL || "https://dev-public.biomate.ai").replace(/\/+$/, "");
const out = process.argv[2]; mkdirSync(out, { recursive: true });
const PW = readFileSync(`${homedir()}/.config/biomate/e2e_fixture_password`, "utf8").trim();
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1600, height: 1000 }, locale: "zh-CN" });
const r = await ctx.request.post(`${BASE}/api/auth/login`, { data: { email: "lifeifei163361@163.com", password: PW }, headers: { "x-e2e-test-token": "biomate-e2e-bypass-token-dev-only" } });
const j = await r.json();
await ctx.addCookies([{ name: "biomate_token", value: j.token || j.accessToken, domain: new URL(BASE).hostname, path: "/", secure: true }]);
const p = await ctx.newPage();
const log = [];
p.on("response", async (res) => {
  const u = res.url(); if (!u.includes("/api/") || u.includes("telemetry")) return;
  let body = ""; if (res.request().method() !== "GET" || res.status() >= 400) { try { body = (await res.text()).slice(0, 400); } catch {} }
  log.push(`${res.status()} ${res.request().method()} ${u.replace(BASE, "")} ${body}`);
});
p.on("pageerror", (e) => log.push(`PAGEERROR ${String(e).slice(0, 300)}`));
let i = 0;
const shot = async (n, wait = 2000) => { await p.waitForTimeout(wait); await p.screenshot({ path: `${out}/${String(++i).padStart(2, "0")}_${n}.png` }); log.push(`--- shot ${n}`); };

// A) Run a model → Structure → Run inference
await p.goto(`${BASE}/models`, { waitUntil: "networkidle", timeout: 60000 }).catch(() => {});
await p.getByText("Run a model").first().click();
await p.waitForTimeout(1500);
const ta = p.locator("textarea, input[type=text]").first();
await ta.fill("MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEKAVQVKVKALPDAQFEVVHSLAKWKRQTLGQHDFSAGEGLYTHMKALRPDEDRLSPLHSVYVDQWDWERVMGDGERQFSTLKSTVEAIWAGIKATEAAVSEEFGLAPFLPDQIHFVHSQELLSRYPDLDAKGRERAIAKDLGAVFLVGIGGKLSDGHRHDVRAPDYDDWUAQGNLRRYLA".replace("U", ""));
await shot("run_a_model_filled", 500);
await p.getByText("Run inference").first().click().catch(e => log.push("CLICKFAIL run inference " + e.message.split("\n")[0]));
await shot("run_inference_10s", 10000);
await shot("run_inference_60s", 50000);
writeFileSync(`${out}/text_run_inference.txt`, await p.locator("body").innerText());

// B) Train tab → pick first project + first dataset → 在聊天中检查
await p.goto(`${BASE}/models`, { waitUntil: "networkidle", timeout: 60000 }).catch(() => {});
const selects = p.locator("select");
const opts = await selects.nth(0).locator("option").allInnerTexts();
log.push("PROJECT OPTIONS " + JSON.stringify(opts));
const proj = process.env.PROJECT || opts.find(o => /Hospital|MG PBMC/.test(o)) || opts[1];
await selects.nth(0).selectOption({ label: proj });
await p.waitForTimeout(2500);
const dsOpts = await selects.nth(1).locator("option").allInnerTexts();
log.push(`DATASET OPTIONS for ${proj}: ` + JSON.stringify(dsOpts));
if (dsOpts.length > 1) await selects.nth(1).selectOption({ index: 1 });
await p.waitForTimeout(1500);
const target = p.locator("input").filter({ hasNot: p.locator("[type=number]") }).first();
await p.locator('input').nth(0).fill(process.env.TARGET || "label").catch(() => {});
await shot("train_filled", 800);
await p.getByText("在聊天中检查").first().click().catch(e => log.push("CLICKFAIL check-in-chat " + e.message.split("\n")[0]));
await shot("train_after_click_5s", 5000);
await shot("train_after_click_90s", 85000);
writeFileSync(`${out}/text_train.txt`, await p.locator("body").innerText());
writeFileSync(`${out}/log.txt`, log.join("\n"));
await b.close();
