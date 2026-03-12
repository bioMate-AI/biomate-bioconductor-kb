import { setupTestUser } from "./helpers.js";
import { test, expect } from "@playwright/test";
import { writeFile } from "fs/promises";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const PROMPT =
  process.env.MEANINGFUL_PROMPT ||
  "Build a cryo-EM single-particle workflow from movies to final map with QC checkpoints and actionable interpretation guidance.";

test.setTimeout(480000);

interface RunStatusPayload {
  status?: string;
  nextflowStatus?: {
    status?: string;
    invocation_id?: string;
    error?: string;
  };
  artifactReadiness?: {
    hasOutputs?: boolean;
    visualizableCount?: number;
    downloadableCount?: number;
    totalOutputs?: number;
    meetsContract?: boolean;
  };
  errorMessage?: string;
}

const DOMAIN_KEYWORDS = [
  "cryo",
  "micrograph",
  "ctf",
  "particle",
  "refinement",
  "fsc",
  "resolution",
  "motion correction",
  "2d classification",
  "3d reconstruction",
];

const NON_MEANINGFUL_HINTS = [
  "demo workflow",
  "placeholder",
  "mock workflow",
  "example workflow",
  "for demonstration only",
  "synthetic output",
];

async function waitAssistantDone(page: any): Promise<void> {
  await page.waitForSelector("text=AI is typing", { timeout: 12000 }).catch(() => {});
  await page.waitForSelector("text=AI is typing", { state: "hidden", timeout: 180000 }).catch(() => {});
  await page.waitForTimeout(1500);
}

async function resolveRunButton(page: any) {
  const candidates = [
    page.getByTestId("button-run-workflow-panel").last(),
    page.getByRole("button", { name: /run workflow/i }).last(),
    page.getByRole("button", { name: /^run$/i }).last(),
    page.getByRole("button", { name: /execute/i }).last(),
  ];
  for (const candidate of candidates) {
    if (await candidate.isVisible().catch(() => false)) {
      return candidate;
    }
  }
  return null;
}

test.describe("Meaningful User Value Gate", () => {
  test("fails unless workflow run yields meaningful and usable outputs", async ({ page }, testInfo) => {
    await setupTestUser(page, "mvg");
    const reasons: string[] = [];
    let runId: string | null = null;
    let invocationId: string | null = null;
    let latestAssistantText = "";
    let statusPayload: RunStatusPayload | null = null;
    let outputsPayload: any[] = [];

    const screenshot = async (name: string) => {
      await page.screenshot({ path: testInfo.outputPath(`${name}.png`), fullPage: true });
    };

    page.on("response", async (response) => {
      if (!response.url().includes("/api/workflows/execute")) {
        return;
      }
      try {
        const payload = await response.json();
        runId =
          payload?.execution?.run?.id ||
          payload?.execution?.runId ||
          payload?.runId ||
          runId;
        invocationId =
          payload?.execution?.run?.invocationId ||
          payload?.execution?.invocationId ||
          payload?.invocationId ||
          invocationId;
      } catch {
        // ignore response parse errors
      }
    });

    await page.goto(BASE_URL);
    await page.waitForLoadState("networkidle");
    await screenshot("01-landing");

    const chatInput = page.locator("textarea").first();
    await expect(chatInput).toBeVisible({ timeout: 20000 });

    await chatInput.fill(PROMPT);
    await chatInput.press("Enter");
    await waitAssistantDone(page);
    await screenshot("02-after-assistant");

    const assistantMessages = page.locator('[data-role="assistant"]');
    const assistantCount = await assistantMessages.count();
    if (assistantCount > 0) {
      latestAssistantText = (await assistantMessages.nth(assistantCount - 1).innerText().catch(() => "")) || "";
    }

    const lowerAssistant = latestAssistantText.toLowerCase();
    const domainHits = DOMAIN_KEYWORDS.filter((kw) => lowerAssistant.includes(kw));
    const fakeSignals = NON_MEANINGFUL_HINTS.filter((kw) => lowerAssistant.includes(kw));
    if (domainHits.length < 2) {
      reasons.push(`assistant response too generic (domain_hits=${domainHits.length})`);
    }
    if (fakeSignals.length > 0) {
      reasons.push(`assistant contains non-meaningful hints: ${fakeSignals.join(", ")}`);
    }

    let workflowArtifactVisible = await page
      .locator('[data-testid="workflow-artifact"]')
      .first()
      .isVisible()
      .catch(() => false);
    if (!workflowArtifactVisible) {
      // Some UX paths require explicit conversion from assistant response to workflow artifact.
      const createWorkflowBtn = page.getByRole("button", { name: /create workflow/i }).last();
      if (await createWorkflowBtn.isVisible().catch(() => false)) {
        await createWorkflowBtn.click();
        await page.waitForTimeout(1500);
        workflowArtifactVisible = await page
          .locator('[data-testid="workflow-artifact"]')
          .first()
          .isVisible()
          .catch(() => false);
        await screenshot("03b-after-create-workflow");
      }
    }
    if (!workflowArtifactVisible) {
      reasons.push("workflow artifact not rendered");
    }

    let runButton = await resolveRunButton(page);
    if (!runButton) {
      reasons.push("run button not found");
    } else {
      let runEnabled = await runButton.isEnabled().catch(() => false);
      if (!runEnabled) {
        await chatInput.fill(
          "I do not have inputs yet. Provide a runnable option with sample data that yields at least one visualizable report and one downloadable output."
        );
        await chatInput.press("Enter");
        await waitAssistantDone(page);
        await screenshot("03-after-recovery");
        runButton = await resolveRunButton(page);
        runEnabled = !!runButton && (await runButton.isEnabled().catch(() => false));
      }
      if (!runEnabled || !runButton) {
        reasons.push("run button remained disabled");
      } else {
        await runButton.click();
      }
    }

    await screenshot("04-after-run-click");

    if (!runId) {
      for (let i = 0; i < 25 && !runId; i++) {
        await page.waitForTimeout(500);
      }
    }
    if (!runId) {
      reasons.push("runId not captured from execute response");
    }

    if (runId) {
      for (let i = 0; i < 120; i++) {
        await page.waitForTimeout(2000);
        const statusResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
        if (!statusResp.ok()) continue;
        statusPayload = (await statusResp.json()) as RunStatusPayload;
        const state = String(statusPayload?.status || "").toLowerCase();
        if (["completed", "failed", "cancelled", "error"].includes(state)) {
          break;
        }
      }
    }

    await screenshot("05-terminal-state");

    const finalStatus = String(statusPayload?.status || "").toLowerCase();
    if (finalStatus !== "completed") {
      reasons.push(`workflow did not complete successfully (status=${finalStatus || "unknown"})`);
    }
    if (!statusPayload?.artifactReadiness?.meetsContract) {
      reasons.push("artifact readiness contract not met");
    }
    if ((statusPayload?.artifactReadiness?.visualizableCount || 0) < 1) {
      reasons.push("no visualizable outputs reported");
    }
    if ((statusPayload?.artifactReadiness?.downloadableCount || 0) < 1) {
      reasons.push("no downloadable outputs reported");
    }

    if (!invocationId) {
      invocationId = statusPayload?.nextflowStatus?.invocation_id || null;
    }

    if (invocationId) {
      const outputsResp = await page.request.get(`${BASE_URL}/api/invocations/${invocationId}/outputs`);
      if (outputsResp.ok()) {
        outputsPayload = (await outputsResp.json()) as any[];
      }
    }

    const realUsableOutputs = Array.isArray(outputsPayload)
      ? outputsPayload.filter((o) => {
          const size = Number(o?.size || 0);
          const ext = String(o?.extension || "").toLowerCase();
          const fileType = String(o?.fileType || "").toLowerCase();
          return size > 0 || !!ext || (fileType !== "" && fileType !== "other");
        })
      : [];
    if (realUsableOutputs.length < 1) {
      reasons.push("outputs endpoint has no usable output entries");
    }

    const outputSectionVisible = await page.locator("text=Output Results").first().isVisible().catch(() => false);
    const reportVisible = await page.getByRole("button", { name: /^report$/i }).first().isVisible().catch(() => false);
    const downloadButtons = page.getByRole("button", { name: /download/i });
    let hasEnabledDownload = false;
    const downloadCount = await downloadButtons.count();
    for (let i = 0; i < downloadCount; i++) {
      const btn = downloadButtons.nth(i);
      const visible = await btn.isVisible().catch(() => false);
      if (!visible) continue;
      const enabled = await btn.isEnabled().catch(() => false);
      if (enabled) {
        hasEnabledDownload = true;
        break;
      }
    }
    if (!outputSectionVisible) {
      reasons.push("output section not visible in UI");
    }
    if (!reportVisible) {
      reasons.push("report visualization action not visible");
    }
    if (!hasEnabledDownload) {
      reasons.push("no enabled download action visible");
    }

    await screenshot("06-final-ui");

    const verdict = reasons.length === 0 ? "PASS" : "FAIL";
    const report = {
      suite: "meaningful-value-gate",
      timestamp: new Date().toISOString(),
      baseUrl: BASE_URL,
      prompt: PROMPT,
      verdict,
      reasons,
      evidence: {
        runId,
        invocationId,
        assistantDomainHits: domainHits,
        assistantFakeSignals: fakeSignals,
        assistantExcerpt: latestAssistantText.slice(0, 500),
        statusPayload,
        outputsCount: Array.isArray(outputsPayload) ? outputsPayload.length : 0,
        usableOutputsCount: realUsableOutputs.length,
        ui: {
          outputSectionVisible,
          reportVisible,
          hasEnabledDownload,
        },
      },
    };

    const reportPath = testInfo.outputPath("meaningful-value-gate-report.json");
    await writeFile(reportPath, JSON.stringify(report, null, 2), "utf-8");
    await testInfo.attach("meaningful-value-gate-report", {
      path: reportPath,
      contentType: "application/json",
    });

    expect(report.verdict, `Meaningful value gate failed: ${reasons.join(" | ")}`).toBe("PASS");
  });
});
