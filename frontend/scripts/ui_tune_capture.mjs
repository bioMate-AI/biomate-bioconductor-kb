// Capture real dev-UI screenshots, optionally with a candidate CSS override
// injected, for the Gemini appearance-tuning loop.
//   node scripts/ui_tune_capture.mjs <outDir> [overrideCss]
import { chromium } from "@playwright/test";
import { readFileSync, mkdirSync, existsSync } from "fs";
import { homedir } from "os";

const BASE = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const EMAIL = "lifeifei163361@163.com";
const PW = process.env.E2E_FIXTURE_PASSWORD ||
  readFileSync(`${homedir()}/.config/biomate/e2e_fixture_password`, "utf8").trim();
const [outDir, cssPath] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });
const css = cssPath && existsSync(cssPath) ? readFileSync(cssPath, "utf8") : "";

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1, locale: "en-US" });
const login = await ctx.request.post(`${BASE}/api/auth/login`, {
  data: { email: EMAIL, password: PW },
  headers: { "x-e2e-test-token": "biomate-e2e-bypass-token-dev-only" },
});
const body = await login.json().catch(() => ({}));
const token = body.token || body.accessToken;
if (!token) { console.error("login failed", login.status(), JSON.stringify(body).slice(0, 300)); process.exit(1); }
const host = new URL(BASE).hostname;
await ctx.addCookies([{ name: "biomate_token", value: token, domain: host, path: "/", secure: true, httpOnly: false }]);
await ctx.addInitScript(() => { try { localStorage.setItem("i18nextLng", "en"); } catch {} });

const page = await ctx.newPage();
async function inject() { if (css) await page.addStyleTag({ content: css }); }
async function shot(name) { await inject(); await page.waitForTimeout(800); await page.screenshot({ path: `${outDir}/${name}.png` }); console.log("saved", name); }

await page.goto(BASE + "/", { waitUntil: "networkidle", timeout: 60000 }).catch(() => {});
await page.waitForTimeout(2500);
await shot("01_landing");

// Run Manager overlay, then open a completed run into the workspace view.
await page.getByText("Run Manager", { exact: false }).first().click().catch(() => {});
await page.waitForTimeout(2500);
await shot("02_run_manager");
const col = page.locator(':text-is("COMPLETED"), :text-is("Completed")').first();
const card = col.locator('xpath=ancestor::*[4]').getByText(/admet|probe|ADMET/).first();
await card.click({ timeout: 8000 }).catch((e) => console.log("no completed run clickable:", e.message.split("\n")[0]));
await page.waitForTimeout(6000);
await shot("03_workspace_run");
await browser.close();
