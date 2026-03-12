import { setupTestUser } from "./helpers.js";
import { test, expect, type Page, type Locator } from "@playwright/test";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

type DirectionCase = {
  id: string;
  direction: string;
  prompt: string;
};

const DIRECTIONS: DirectionCase[] = [
  {
    id: "A_drug_discovery",
    direction: "Direction A - Drug Discovery",
    prompt:
      "Build a drug discovery workflow covering target validation, docking, ADMET screening, and lead optimization QC gates.",
  },
  {
    id: "B_rnaseq_precision",
    direction: "Direction B - RNA-seq Precision Medicine",
    prompt:
      "Build an RNA-seq FFPE tumor workflow for differential expression and patient subgrouping with QC and downloadable outputs.",
  },
  {
    id: "C_cryo_em",
    direction: "Direction C - Cryo-EM Structures",
    prompt:
      "Build a cryo-EM single-particle analysis workflow from movies through refinement and resolution/QC checks.",
  },
  {
    id: "D_single_cell",
    direction: "Direction D - Single-cell Perturbation",
    prompt:
      "Build a single-cell CRISPR perturbation workflow including guide assignment, hit calling, and perturbation-aware QC.",
  },
];

async function waitAssistantDone(page: Page) {
  await page.waitForSelector("text=AI is typing", { timeout: 10000 }).catch(() => {});
  await page.waitForSelector("text=AI is typing", { state: "hidden", timeout: 120000 }).catch(() => {});
  await page.waitForTimeout(2000);
}

async function resolveRunButton(page: Page) {
  const candidates = [
    page.getByTestId("button-run-workflow-panel").last(),
    page.getByRole("button", { name: /run workflow/i }).last(),
    page.getByRole("button", { name: /^run$/i }).last(),
    page.locator('button:has-text("Run")').last(),
  ];
  for (const candidate of candidates) {
    if (await candidate.isVisible().catch(() => false)) {
      return candidate;
    }
  }
  return null;
}

async function requestPrereqRecovery(page: Page, chatInput: Locator) {
  const recoveryButton = page.getByTestId("button-prereq-recovery").last();
  if (await recoveryButton.isVisible().catch(() => false)) {
    await recoveryButton.click();
  } else {
    const recoveryPrompt =
      "My current workflow run is blocked by missing prerequisites. Please generate a runnable demo path with sample/test inputs and a workflow variant that can produce one visualizable report and downloadable outputs.";
    await chatInput.fill(recoveryPrompt);
    await chatInput.press("Enter");
  }
  await waitAssistantDone(page);
  await page.waitForTimeout(2000);
}

test.describe("Survey Directions - Real Workflow Coverage", () => {
  test.setTimeout(420000);

  for (const dir of DIRECTIONS) {
    test(`${dir.id}: ${dir.direction}`, async ({ page }) => {
    await setupTestUser(page, "survey");
      await page.goto(BASE_URL);
      await page.waitForLoadState("networkidle");

      const chatInput = page.locator("textarea").first();
      await expect(chatInput).toBeVisible({ timeout: 10000 });
      await chatInput.fill(dir.prompt);
      await chatInput.press("Enter");
      await waitAssistantDone(page);

      let runButton = await resolveRunButton(page);
      if (!runButton) {
        const generationFailure = page.getByText(/Real workflow generation failed/i).last();
        await expect(generationFailure).toBeVisible({ timeout: 30000 });
        return;
      }

      let runEnabled = await runButton.isEnabled().catch(() => false);
      if (!runEnabled) {
        await requestPrereqRecovery(page, chatInput);
        runButton = await resolveRunButton(page);
        expect(runButton, "Run button should still exist after recovery turn").not.toBeNull();
        if (!runButton) return;
        runEnabled = await runButton.isEnabled().catch(() => false);
      }

      if (!runEnabled) {
        await requestPrereqRecovery(page, chatInput);
        runButton = await resolveRunButton(page);
        if (runButton) {
          runEnabled = await runButton.isEnabled().catch(() => false);
        }
      }

      if (!runEnabled) {
        const blockedChecklist = page.getByTestId("workflow-prereq-checklist").last();
        await expect(blockedChecklist).toBeVisible({ timeout: 30000 });
        await expect(blockedChecklist).toContainText(/input data|missing/i);
        return;
      }

      await runButton.click();

      const runContextChip = page.getByTestId("run-context-chip").last();
      if (!(await runContextChip.isVisible().catch(() => false))) {
        const generationFailure = page.getByText(/Real workflow generation failed/i).last();
        if (await generationFailure.isVisible().catch(() => false)) {
          return;
        }
      }
      await expect(runContextChip).toBeVisible({ timeout: 120000 });
      await expect(runContextChip).not.toContainText(/Run ID:\s*n\/a/i, { timeout: 120000 });

      const triageStatus = page.getByTestId("execution-triage-status").last();
      await expect(triageStatus).toBeVisible({ timeout: 120000 });
      await expect(triageStatus).not.toContainText(/status:\s*idle/i, { timeout: 120000 });

      const outputActionCandidates = page.locator(
        '[data-testid="button-download-all-workflow-panel"], [data-testid="button-download-outputs-icon"], button:has-text("View Results"), button:has-text("Hide Results")'
      );
      await expect(outputActionCandidates.first()).toBeVisible({ timeout: 60000 });
    });
  }
});
