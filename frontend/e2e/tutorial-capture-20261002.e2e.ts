/**
 * Tutorial screenshot capture — new surfaces (2026-10-02 tutorial set).
 *
 * Captures REAL screenshots of the live dev UI into docs/user-manual/assets/
 * for the CAPTURE markers in the new tutorials (M1/M2, S1, T6–T10, W1/W3).
 * Honesty rule (same as manual-screenshots.e2e.ts): only what actually renders
 * is saved; nothing mocked. Dynamic run states (running / QC-blocked / failed)
 * are NOT forced here and stay as placeholders in the chapters.
 *
 * Run against dev:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/tutorial-capture-20261002.e2e.ts --project=chromium
 */
import { test } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");

async function settle(page: any, ms = 4500) { await page.waitForTimeout(ms); }

// ── 1. Sidebar + Connectors dialog (Instruments / Your connections) ──────────
test("capture sidebar + connectors + instruments (S1/T6/T9)", async ({ page }) => {
  test.setTimeout(180_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  const tryClick = async (tid: string, timeout = 8000) => {
    const el = page.getByTestId(tid);
    if ((await el.count()) > 0) { await el.first().click({ timeout }); return true; }
    return false;
  };
  try {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await settle(page);
    await shot("s1-1-sidebar.png"); // full nav with sidebar on the left

    // Open Connectors dialog
    if (await tryClick("button-connectors-nav")) {
      await settle(page, 3000);
      await shot("t9-1-connectors-dialog.png"); // default tab (Public Databases)
      // Your connections tab
      if (await tryClick("your-connections-tab")) { await settle(page, 2500); await shot("t9-2-your-connections.png"); }
      // Instruments tab — try testid, then role/text fallback
      let onInstruments = await tryClick("tab-instruments");
      if (!onInstruments) {
        const byText = page.getByRole("tab", { name: /instrument/i });
        if ((await byText.count()) > 0) { await byText.first().click({ timeout: 8000 }); onInstruments = true; }
        else { const t = page.getByText(/^Instruments$/).first(); if ((await t.count()) > 0) { await t.click({ timeout: 8000 }); onInstruments = true; } }
      }
      if (onInstruments) {
        await settle(page, 3000);
        await shot("t6-1-instruments-tab.png"); // My instruments + New data events
        // New data events region (empty or populated)
        // Add-instrument form
        if (await tryClick("button-add-instrument")) {
          await settle(page, 2000);
          // pick a type so host/port + residency fields render
          const sel = page.getByTestId("select-instrument-type");
          if ((await sel.count()) > 0) {
            try { await sel.selectOption("opentrons"); } catch { /* may be a custom select */ }
            await settle(page, 1500);
          }
          await shot("t6-2-add-instrument-form.png");
        }
      } else { log.push("SKIP instruments tab (not found)"); }
    } else { log.push("SKIP connectors (nav button not found)"); }
  } catch (e: any) { log.push("FAIL sidebar/connectors — " + (e?.message?.split("\n")[0] ?? e)); }
  console.log("\n[capture sidebar/connectors]\n" + log.join("\n") + "\n");
});

// ── 2. Cold-start modules (M1 Search & evidence, M2 Data analysis) ───────────
test("capture cold-start modules (M1/M2/T0)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  try {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
    await settle(page);
    await shot("m0-1-intent-bar.png"); // intent bar + four module cards (cold start)
    const cards = page.getByTestId("cold-module-card");
    const n = await cards.count();
    for (let i = 0; i < n; i++) {
      const card = cards.nth(i);
      const txt = (await card.innerText().catch(() => "")).toLowerCase();
      let name = "";
      if (/search|evidence/.test(txt)) name = "m1-1-search-module.png";
      else if (/data analysis|analy/.test(txt)) name = "m2-1-data-analysis-module.png";
      if (!name) continue;
      const expand = card.getByTestId("cold-module-expand");
      try { if ((await expand.count()) > 0) await expand.first().click({ timeout: 6000 }); else await card.click({ timeout: 6000 }); } catch { /* best effort */ }
      await settle(page, 2500);
      await shot(name);
    }
  } catch (e: any) { log.push("FAIL cold-start — " + (e?.message?.split("\n")[0] ?? e)); }
  console.log("\n[capture cold-start modules]\n" + log.join("\n") + "\n");
});

// ── 3. Dataset object tabs (T10: lineage / versions / preview / origin) ──────
test("capture dataset object tabs (T10)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  const tab = async (tid: string, name: string) => {
    const t = page.getByTestId(tid);
    if ((await t.count()) > 0) { await t.first().click({ timeout: 8000 }); await settle(page, 3000); await shot(name); return true; }
    log.push("SKIP " + tid); return false;
  };
  try {
    // Find a real dataset id via the API, then use the /files?file=<id> deep-link
    // (data-hub.tsx opens it directly as a DatasetObject — robust vs. tree clicks).
    const projResp = await page.request.get(BASE_URL + "/api/projects");
    const projJson = await projResp.json().catch(() => []);
    const projects = Array.isArray(projJson) ? projJson : (projJson.projects || []);
    let fileId: string | null = null, projId: string | null = null, fileName = "";
    for (const p of projects) {
      const fr = await page.request.get(`${BASE_URL}/api/projects/${p.id}/files`);
      if (!fr.ok()) continue;
      const fj = await fr.json().catch(() => []);
      const arr = Array.isArray(fj) ? fj : (fj.files || []);
      if (arr.length > 0) { fileId = arr[0].id || arr[0].datasetId || arr[0].hid; projId = p.id; fileName = arr[0].name || arr[0].fileName || ""; break; }
    }
    if (!fileId) { log.push("SKIP dataset tabs (no project with files via API)"); }
    else {
      // useActiveProject() reads localStorage['biomate-active-project-id']; set it so
      // the data hub opens that project (deep-link ?file= alone shows the picker).
      await page.addInitScript((pid) => { try { localStorage.setItem("biomate-active-project-id", pid as string); } catch { /* ignore */ } }, projId);
      await page.goto(BASE_URL + `/files?file=${encodeURIComponent(fileId)}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
      await settle(page, 5000);
      let obj = page.getByTestId("dataset-object");
      if ((await obj.count()) === 0 && fileName) {
        // Fallback: click the file row by name in the tree.
        const row = page.getByText(fileName, { exact: false }).first();
        if ((await row.count()) > 0) { await row.click({ timeout: 8000 }); await settle(page, 3500); obj = page.getByTestId("dataset-object"); }
      }
      if ((await obj.count()) === 0) { log.push("SKIP dataset-object did not mount for " + fileId); }
      else {
        await shot("t10-0-dataset-object.png");
        await tab("dataset-tab-preview", "t10-1-dataset-preview.png");
        await tab("dataset-tab-lineage", "t10-2-dataset-lineage.png");
        await tab("dataset-tab-consumers", "t10-3-dataset-consumers.png");
        await tab("dataset-tab-versions", "t10-4-dataset-versions.png");
        await tab("dataset-tab-origin", "t10-5-dataset-origin.png");
      }
    }
  } catch (e: any) { log.push("FAIL dataset tabs — " + (e?.message?.split("\n")[0] ?? e)); }
  console.log("\n[capture dataset tabs]\n" + log.join("\n") + "\n");
});

// ── 4. Workflow viewer deep: phases, settings, full step view (W1/W3) ────────
const RUN_ID = process.env.MANUAL_RUN_ID || "15736778-6689-44d9-bca1-563987669457";
test("capture workflow viewer deep (W1/W3)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  try {
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto(BASE_URL + `/debug/viewer/${RUN_ID}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
    await settle(page, 6000);
    await shot("w1-0-panel-overview.png"); // whole panel w/ tabs
    const clickText = async (label: RegExp, timeout = 8000) => {
      const el = page.getByText(label, { exact: false }).first();
      if ((await el.count()) > 0) { await el.click({ timeout }); return true; }
      return false;
    };
    // Workflow settings tab
    if (await clickText(/^Workflow settings$/)) { await settle(page, 2500); await shot("w1-2-workflow-settings.png"); }
    else { log.push("SKIP workflow-settings tab"); }
    // Phases tab
    if (await clickText(/^Phases$/)) {
      await settle(page, 3000);
      await shot("w1-1-phases.png");
      // Full step view: open a step's Details → full-step-view-dialog (needs real steps)
      const details = page.getByRole("button", { name: /details|full step/i });
      if ((await details.count()) > 0) {
        await details.first().click({ timeout: 8000 });
        await settle(page, 3000);
        await shot("w3-1-full-step-view.png");
      } else { log.push("SKIP full step view (debug run has no step rows — needs a real run)"); }
    } else { log.push("SKIP phases tab"); }
  } catch (e: any) { log.push("FAIL viewer deep — " + (e?.message?.split("\n")[0] ?? e)); }
  console.log("\n[capture viewer deep]\n" + log.join("\n") + "\n");
});

// ── 5. Project page: standing instructions + members/roles (T7) ──────────────
test("capture project page (T7)", async ({ page }) => {
  test.setTimeout(150_000);
  await loginAsFixture(page);
  const log: string[] = [];
  const shot = async (name: string) => { await page.screenshot({ path: path.join(ASSETS, name) }); log.push("OK   " + name); };
  try {
    // Project detail renders at /projects?project=<id> (App.tsx reads ?project).
    const projResp = await page.request.get(BASE_URL + "/api/projects");
    const projJson = await projResp.json().catch(() => []);
    const projects = Array.isArray(projJson) ? projJson : (projJson.projects || []);
    if (projects.length === 0) { log.push("SKIP project page (no projects via API)"); }
    else {
      await page.goto(BASE_URL + `/projects?project=${projects[0].id}`, { waitUntil: "domcontentloaded", timeout: 45_000 });
      await settle(page, 5000);
      await shot("t7-0-project-overview.png"); // whole project-detail page
      let found = false;
      const si = page.getByTestId("standing-instructions-card");
      if ((await si.count()) > 0) { await si.first().scrollIntoViewIfNeeded(); await settle(page, 1500); await shot("t7-1-standing-instructions.png"); found = true; }
      const members = page.getByTestId("members-panel");
      if ((await members.count()) > 0) { await members.first().scrollIntoViewIfNeeded(); await settle(page, 1500); await shot("t7-2-members-roles.png"); found = true; }
      if (!found) log.push("SKIP standing-instructions/members cards (not found on detail page)");
    }
  } catch (e: any) { log.push("FAIL project page — " + (e?.message?.split("\n")[0] ?? e)); }
  console.log("\n[capture project page]\n" + log.join("\n") + "\n");
});
