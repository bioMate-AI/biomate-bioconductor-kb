/**
 * Capture the COMPLETED workflow panel from the real ADMET run's LIVE chat
 * session (correct workflow title + real outputs, no /debug/viewer banner).
 * Findings are empty for this run (inline_findings=[]), so the Summary shows the
 * honest "analysis unavailable/in-progress" state — captured as-is, not faked.
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const SESSION = process.env.SESSION_ID || "chat-1790955154245-s17yy1qla";

test("capture completed run from live session", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  try {
    await page.goto(BASE_URL + `/?session=${encodeURIComponent(SESSION)}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await page.waitForTimeout(7000);
    await shot("r8-completed-chat-and-panel.png"); // full: chat + right panel

    // Ensure the workflow panel is open — click the workflow card / chip if needed.
    const viewerTitle = page.getByText(/Predict ADMET Properties/i).first();
    if ((await page.getByText(/After run/i).count()) === 0) {
      const card = page.getByText(/Predict ADMET Properties/i).first();
      if ((await card.count()) > 0) { await card.click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(3000); }
    }
    await shot("r3-completed.png"); // completed panel (correct title)

    // Outputs tab (correct title this time).
    const outTab = page.getByText(/^Outputs$/).first();
    if ((await outTab.count()) > 0) { await outTab.click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(2500); await shot("r5-outputs-named.png"); }
    else log.push("SKIP outputs (tab not found in session view)");

    // Summary / findings — capture whatever the real (empty-findings) state is.
    const sumTab = page.getByText(/^Summary$/).first();
    if ((await sumTab.count()) > 0) { await sumTab.click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(2000); await shot("r4-findings-state.png"); }
  } catch (e: any) { log.push("FAIL session-capture — " + (e?.message?.split("\n")[0] ?? e)); }
  // eslint-disable-next-line no-console
  console.log("\n[session-capture]\n" + log.join("\n") + "\n");
});
