// Probe the live Models panel on dev: screenshots + every API call status + console errors.
//   node scripts/models_probe.mjs <outDir>
import { chromium } from "@playwright/test";
import { readFileSync, mkdirSync, writeFileSync } from "fs";
import { homedir } from "os";

const BASE = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const out = process.argv[2]; mkdirSync(out, { recursive: true });
const PW = readFileSync(`${homedir()}/.config/biomate/e2e_fixture_password`, "utf8").trim();
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1600, height: 1000 }, locale: "zh-CN" });
const r = await ctx.request.post(`${BASE}/api/auth/login`, { data: { email: "lifeifei163361@163.com", password: PW }, headers: { "x-e2e-test-token": "biomate-e2e-bypass-token-dev-only" } });
const j = await r.json();
await ctx.addCookies([{ name: "biomate_token", value: j.token || j.accessToken, domain: new URL(BASE).hostname, path: "/", secure: true }]);
const p = await ctx.newPage();
const log = [];
p.on("response", (res) => { const u = res.url(); if (u.includes("/api/")) log.push(`${res.status()} ${res.request().method()} ${u.replace(BASE, "")}`); });
p.on("console", (m) => { if (m.type() === "error") log.push(`CONSOLE ${m.text().slice(0, 300)}`); });
p.on("pageerror", (e) => log.push(`PAGEERROR ${String(e).slice(0, 300)}`));
let i = 0;
const shot = async (name) => { await p.waitForTimeout(2500); await p.screenshot({ path: `${out}/${String(++i).padStart(2, "0")}_${name}.png`, fullPage: false }); log.push(`--- shot ${name}`); };

await p.goto(`${BASE}/models`, { waitUntil: "networkidle", timeout: 60000 }).catch(() => {});
await shot("models_landing");
const texts = await p.locator("button, a, [role=tab]").allInnerTexts();
log.push("CLICKABLES: " + JSON.stringify(texts.map(t => t.trim()).filter(Boolean).slice(0, 80)));
writeFileSync(`${out}/page_text_landing.txt`, await p.locator("main, body").first().innerText());
for (const label of (process.env.CLICK || "").split("|").filter(Boolean)) {
  const el = p.getByText(label, { exact: false }).first();
  if (await el.count()) { await el.click().catch(e => log.push(`CLICKFAIL ${label} ${e.message.split("\n")[0]}`)); await shot(label.replace(/\W+/g, "_").slice(0, 30) || "click"); writeFileSync(`${out}/page_text_${i}.txt`, await p.locator("body").innerText()); }
  else log.push(`NOTFOUND ${label}`);
}
writeFileSync(`${out}/log.txt`, log.join("\n"));
await b.close();
