/**
 * AfterRunReport comprehensive audit
 * ===================================
 * Navigates to the most recent completed run session, screenshots every tab
 * in AfterRunReport, downloads the markdown report, and downloads all outputs.
 * Everything is saved to /tmp/afterrun-audit-<timestamp>/.
 */

import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.setTimeout(5 * 60_000);

const TS = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
const AUDIT_DIR = path.join("/tmp", `afterrun-audit-${TS}`);
fs.mkdirSync(AUDIT_DIR, { recursive: true });
console.log("[audit] output dir:", AUDIT_DIR);

let sharedPage: Page;

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);
});

test.afterAll(async () => {
  await sharedPage?.close();
});

async function ss(page: Page, name: string) {
  const p = path.join(AUDIT_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log("[audit] screenshot:", name + ".png");
}

test("AfterRunReport full audit — all tabs, download report, download all", async () => {
  const page = sharedPage;

  // ── 1. Find most recent completed run with chatSessionId ──────────────────
  const runsResp = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=20`);
  expect(runsResp.ok(), `GET /api/workflows/runs failed: ${runsResp.status()}`).toBeTruthy();
  const runs = await runsResp.json() as any[];

  const completed = runs.find(r =>
    ["completed", "ok", "succeeded"].includes(r.execution?.status ?? r.status ?? "") &&
    r.chatSessionId
  );
  expect(completed, "No completed run with chatSessionId found").toBeTruthy();
  console.log("[audit] using run:", completed.id, "session:", completed.chatSessionId);

  // ── 2. Navigate to session ────────────────────────────────────────────────
  await page.goto(`${BASE_URL}/?session=${encodeURIComponent(completed.chatSessionId)}`, {
    waitUntil: "domcontentloaded",
  });
  // Wait for panel tabs to appear (workflow panel opened from session restore)
  await page.waitForSelector('[data-testid^="panel-tab-"]', { timeout: 20000 });
  await ss(page, "00_session_loaded");

  // ── 3. Click "After run" panel tab ───────────────────────────────────────
  const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
  await expect(afterRunTab).toBeVisible({ timeout: 5000 });
  await afterRunTab.click();
  await page.waitForTimeout(1500);
  await ss(page, "01_after_run_tab");

  // ── 4. Screenshot every AfterRunReport inner tab ─────────────────────────
  const innerTabs = [
    { id: "findings",   label: "Findings"   },
    { id: "outputs",    label: "Outputs"    },
    { id: "methods",    label: "Methods"    },
    { id: "params",     label: "Parameters" },
    { id: "software",   label: "Software"   },
    { id: "citations",  label: "Citations"  },
    { id: "qc",         label: "QC report"  },
  ];

  const visibleTabs: string[] = [];
  for (const { id, label } of innerTabs) {
    const tab = page.locator(`[data-testid="after-tab-${id}"]`);
    if (await tab.count() === 0) {
      console.log(`[audit] tab ${id} not present — skipping`);
      continue;
    }
    visibleTabs.push(id);
    await tab.click();
    await page.waitForTimeout(800);
    await ss(page, `02_tab_${id}`);
    console.log(`[audit] tab "${label}" screenshotted`);

    // For outputs tab: capture text content of every file preview
    if (id === "outputs") {
      const previews = page.locator("[data-testid^='step-output-preview-'], .output-file-row, .step-output-file");
      const count = await previews.count();
      console.log(`[audit] outputs tab has ${count} file preview elements`);
      // Capture inner text of the whole outputs section
      const outputsSection = page.locator(".after-run-outputs, [data-testid='after-tab-outputs-content'], .outputs-tab");
      const text = await outputsSection.count() > 0
        ? await outputsSection.first().innerText().catch(() => "(could not read text)")
        : await page.locator(".after-run-report").innerText().catch(() => "(could not read text)");
      fs.writeFileSync(path.join(AUDIT_DIR, "outputs_tab_content.txt"), text);
      console.log("[audit] saved outputs_tab_content.txt");
    }

    // For findings tab: capture markdown content
    if (id === "findings") {
      const text = await page.locator(".after-run-report").innerText().catch(() => "");
      fs.writeFileSync(path.join(AUDIT_DIR, "findings_tab_content.txt"), text);
      console.log("[audit] saved findings_tab_content.txt");
    }

    // For methods tab: capture text
    if (id === "methods") {
      const text = await page.locator(".after-run-report").innerText().catch(() => "");
      fs.writeFileSync(path.join(AUDIT_DIR, "methods_tab_content.txt"), text);
      console.log("[audit] saved methods_tab_content.txt");
    }
  }
  console.log("[audit] visible tabs:", visibleTabs.join(", "));
  fs.writeFileSync(path.join(AUDIT_DIR, "visible_tabs.txt"), visibleTabs.join("\n"));

  // ── 5. Click "Download Report" button and save the .md file ──────────────
  // Go back to outputs tab first (where the download button is visible at top)
  const outputsTabBtn = page.locator('[data-testid="after-tab-outputs"]');
  if (await outputsTabBtn.count() > 0) await outputsTabBtn.click();
  await page.waitForTimeout(500);

  const downloadReportBtn = page.locator('[data-testid="afterrun-download-report"]');
  if (await downloadReportBtn.count() > 0) {
    const [reportDownload] = await Promise.all([
      page.waitForEvent("download", { timeout: 15000 }),
      downloadReportBtn.click(),
    ]);
    const reportPath = await reportDownload.path();
    const reportName = reportDownload.suggestedFilename();
    if (reportPath) {
      const dest = path.join(AUDIT_DIR, reportName || "biomate-run-report.md");
      fs.copyFileSync(reportPath, dest);
      const size = fs.statSync(dest).size;
      console.log(`[audit] report downloaded: ${reportName} (${size} bytes)`);
      fs.writeFileSync(path.join(AUDIT_DIR, "report_content.md"),
        fs.readFileSync(dest, "utf8"));
    }
    await ss(page, "05_after_download_report");
  } else {
    console.log("[audit] Download Report button not found");
    fs.writeFileSync(path.join(AUDIT_DIR, "report_content.md"), "(Download Report button not present)");
  }

  // ── 6. Click "Download All" button and save the zip ──────────────────────
  // JobButton polls an async API to build the zip — may time out if the run
  // has no S3 output files (e.g. in-memory ADMET runs). Screenshot the button
  // state and capture what we can; do not fail the audit on timeout.
  const downloadAllBtn = page.locator(".afterrun-download-all-btn").first();
  if (await downloadAllBtn.count() > 0) {
    await ss(page, "06a_download_all_button");
    console.log("[audit] Download All button text:", await downloadAllBtn.innerText().catch(() => "?"));
    console.log("[audit] clicking Download All (60s timeout, non-fatal)...");
    try {
      const [zipDownload] = await Promise.all([
        page.waitForEvent("download", { timeout: 60000 }),
        downloadAllBtn.click(),
      ]);
      const zipPath = await zipDownload.path();
      const zipName = zipDownload.suggestedFilename();
      if (zipPath) {
        const dest = path.join(AUDIT_DIR, zipName || "biomate-outputs.zip");
        fs.copyFileSync(zipPath, dest);
        const size = fs.statSync(dest).size;
        console.log(`[audit] zip downloaded: ${zipName} (${size} bytes)`);

        // List zip contents
        const { execSync } = require("child_process");
        try {
          const contents = execSync(`unzip -l "${dest}" 2>&1`).toString();
          fs.writeFileSync(path.join(AUDIT_DIR, "zip_contents.txt"), contents);
          console.log("[audit] zip contents:\n" + contents);
        } catch (e: any) {
          fs.writeFileSync(path.join(AUDIT_DIR, "zip_contents.txt"), e.message || String(e));
        }
      }
      await ss(page, "06b_after_download_all");
    } catch (e: any) {
      // Download All may time out for runs without S3 output files
      const note = `Download All timed out or failed: ${e?.message?.slice(0, 200) ?? e}`;
      console.log("[audit]", note);
      fs.writeFileSync(path.join(AUDIT_DIR, "zip_contents.txt"), note);
      await ss(page, "06b_download_all_timeout");
    }
  } else {
    console.log("[audit] Download All button not found");
    fs.writeFileSync(path.join(AUDIT_DIR, "zip_contents.txt"), "(Download All button not present)");
  }

  // ── 7. Interactive tools row audit ───────────────────────────────────────
  // Return to outputs tab and screenshot the tools row in detail
  if (await outputsTabBtn.count() > 0) await outputsTabBtn.click();
  await page.waitForTimeout(500);
  const toolsRow = page.locator('[data-testid="afterrun-interactive-tools-row"]');
  if (await toolsRow.count() > 0) {
    await ss(page, "07_interactive_tools_row");
    const rowText = await toolsRow.innerText().catch(() => "");
    fs.writeFileSync(path.join(AUDIT_DIR, "interactive_tools_row.txt"), rowText);
    console.log("[audit] interactive tools row:", rowText.replace(/\n/g, " | "));
  } else {
    console.log("[audit] no interactive tools row (no outputs yet)");
    fs.writeFileSync(path.join(AUDIT_DIR, "interactive_tools_row.txt"), "(not present — run has no outputs)");
  }

  // ── 8. Full-panel final screenshot ───────────────────────────────────────
  await ss(page, "08_final");

  // ── 9. Write audit manifest ───────────────────────────────────────────────
  const manifest = {
    run_id: completed.id,
    run_status: completed.execution?.status,
    chat_session_id: completed.chatSessionId,
    workflow_name: completed.workflowName,
    audit_dir: AUDIT_DIR,
    visible_tabs: visibleTabs,
    files: fs.readdirSync(AUDIT_DIR),
  };
  fs.writeFileSync(path.join(AUDIT_DIR, "manifest.json"), JSON.stringify(manifest, null, 2));
  console.log("[audit] manifest:", JSON.stringify(manifest, null, 2));
});
