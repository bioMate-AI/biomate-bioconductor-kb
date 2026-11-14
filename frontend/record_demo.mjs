import { chromium } from "playwright";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const FRONTEND_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const DEMO_PROMPT =
  process.env.DEMO_PROMPT ||
  "Build a cryo-EM single-particle analysis workflow from movies through refinement and resolution/QC checks.";
const RECOVERY_PROMPT =
  "My current workflow run is blocked by missing prerequisites. Please generate a runnable demo path with sample/test inputs and a workflow variant that can produce one visualizable report and downloadable outputs.";
const OUTPUT_DIR = path.join(__dirname, "..", "demo_videos");
const TIMESTAMP = Date.now();
const SCREENSHOT_DIR = path.join(OUTPUT_DIR, `screenshots_${TIMESTAMP}`);

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });
if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitAssistantDone(page) {
  await page.waitForSelector("text=AI is typing", { timeout: 10000 }).catch(() => {});
  await page.waitForSelector("text=AI is typing", { state: "hidden", timeout: 180000 }).catch(() => {});
  await page.waitForTimeout(1500);
}

async function resolveRunButton(page) {
  const candidates = [
    page.getByTestId("button-run-workflow-panel").last(),
    page.getByRole("button", { name: /run workflow/i }).last(),
    page.getByRole("button", { name: /^run$/i }).last(),
    page.getByRole("button", { name: /execute/i }).last(),
  ];
  for (const candidate of candidates) {
    if (await candidate.isVisible().catch(() => false)) return candidate;
  }
  return null;
}

async function waitForTerminalRunStatus(frontendUrl, runId, timeoutMs = 360000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const resp = await fetch(`${frontendUrl}/api/workflows/runs/${runId}/status?includeSteps=true`);
      if (resp.ok) {
        const payload = await resp.json();
        const status = String(payload?.status || "").toLowerCase();
        if (["completed", "failed", "cancelled"].includes(status)) {
          return payload;
        }
      }
    } catch {
      // retry
    }
    await sleep(3000);
  }
  return null;
}

async function recordDemo() {
  console.log("🎬 Starting strict BioMate proof recording...");
  const browser = await chromium.launch({ headless: true, ignoreHTTPSErrors: true });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    ignoreHTTPSErrors: true,
    recordVideo: { dir: OUTPUT_DIR, size: { width: 1920, height: 1080 } },
  });

  const page = await context.newPage();
  const pageVideo = page.video();
  const runCapture = { runId: null, invocationId: null, executeResponse: null };

  page.on("response", async (response) => {
    if (!response.url().includes("/api/workflows/execute")) return;
    try {
      const payload = await response.json();
      runCapture.runId = payload?.runId ?? null;
      runCapture.invocationId = payload?.invocationId ?? null;
      runCapture.executeResponse = payload;
      console.log("✅ Captured execute response:", {
        runId: runCapture.runId,
        invocationId: runCapture.invocationId,
      });
    } catch {
      // ignore parse failures
    }
  });

  try {
    console.log("Step 1: Open UI and ensure chat input is ready");
    await page.goto(FRONTEND_URL, { waitUntil: "networkidle", timeout: 60000 });
    const chatInput = page.getByTestId("chat-input");
    await chatInput.waitFor({ state: "visible", timeout: 30000 });
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, "01_homepage_ready.png"), fullPage: true });

    console.log("Step 2: Send Cryo-EM prompt via strict selectors");
    await chatInput.fill(DEMO_PROMPT);
    await page.getByTestId("chat-send-button").click();
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, "02_prompt_sent.png"), fullPage: true });

    console.log("Step 3: Wait for assistant response and workflow panel");
    await waitAssistantDone(page);
    await page.waitForFunction(() => {
      const runButton = document.querySelector('[data-testid="button-run-workflow-panel"]');
      const bodyText = document.body?.innerText || "";
      return !!runButton || /Nextflow Workflow|Workflow/i.test(bodyText);
    }, { timeout: 180000 });
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, "03_workflow_presented.png"), fullPage: true });

    console.log("Step 4: Resolve and trigger Run");
    let runButton = await resolveRunButton(page);
    if (!runButton) throw new Error("Run button not found");

    let usedRecoveryPrompt = false;
    let runEnabled = await runButton.isEnabled().catch(() => false);
    if (!runEnabled) {
      console.log("Run disabled; sending recovery prompt...");
      usedRecoveryPrompt = true;
      await chatInput.fill(RECOVERY_PROMPT);
      await page.getByTestId("chat-send-button").click();
      await waitAssistantDone(page);
      runButton = await resolveRunButton(page);
      if (!runButton) throw new Error("Run button missing after recovery");
      runEnabled = await runButton.isEnabled().catch(() => false);
    }

    if (!runEnabled) throw new Error("Run button remained disabled after recovery");
    await runButton.click();
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, "04_run_clicked.png"), fullPage: true });

    console.log("Step 5: Wait for terminal run status");
    const runCaptureStartedAt = Date.now();
    while (!runCapture.runId && Date.now() - runCaptureStartedAt < 30000) {
      await sleep(500);
    }

    let terminalStatusPayload = null;
    if (runCapture.runId) {
      terminalStatusPayload = await waitForTerminalRunStatus(FRONTEND_URL, runCapture.runId, 360000);
    } else {
      const terminalCue = page
        .locator("text=COMPLETED")
        .last()
        .or(page.locator("text=FAILED").last())
        .or(page.locator("text=CANCELLED").last());
      await terminalCue.waitFor({ state: "visible", timeout: 360000 });
    }
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, "05_terminal_state.png"), fullPage: true });

    console.log("Step 6: Capture post-run state");
    await sleep(1500);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, "06_final_state.png"), fullPage: true });

    const html = await page.content();
    fs.writeFileSync(path.join(SCREENSHOT_DIR, "page_content.html"), html);

    let runStatus = null;
    if (runCapture.runId) {
      try {
        const resp = await fetch(`${FRONTEND_URL}/api/workflows/runs/${runCapture.runId}/status?includeSteps=true`);
        if (resp.ok) runStatus = await resp.json();
      } catch {
        // non-fatal
      }
    }

    const proof = {
      timestamp: new Date().toISOString(),
      frontendUrl: FRONTEND_URL,
      demoPrompt: DEMO_PROMPT,
      recoveryPromptUsed: usedRecoveryPrompt,
      runCapture,
      runStatus: terminalStatusPayload || runStatus,
    };
    fs.writeFileSync(path.join(SCREENSHOT_DIR, "proof_summary.json"), JSON.stringify(proof, null, 2));
    console.log("✅ Saved proof_summary.json");
  } catch (error) {
    console.error("\n❌ Strict recorder failed:", error.message);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, "error_state.png"), fullPage: true });
    throw error;
  } finally {
    await context.close();
    let savedVideoPath = null;
    if (pageVideo) {
      savedVideoPath = path.join(OUTPUT_DIR, `biomate_demo_${TIMESTAMP}.webm`);
      try {
        await pageVideo.saveAs(savedVideoPath);
      } catch (error) {
        console.warn("⚠️ Failed to save Playwright video explicitly:", error.message);
      }
    }
    await browser.close();

    console.log("\n" + "=".repeat(70));
    console.log("✅ STRICT RECORDING COMPLETE");
    console.log("=".repeat(70));
    console.log(`📁 Screenshots: ${SCREENSHOT_DIR}`);
    if (savedVideoPath) console.log(`📹 Video: ${savedVideoPath}`);
  }
}

recordDemo().catch((error) => {
  console.error(error);
  process.exit(1);
});
