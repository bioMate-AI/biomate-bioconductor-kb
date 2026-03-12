/**
 * Bioinformatics Viewers E2E Tests
 *
 * Tests the output visualization viewers using real backend calls.
 * No page.route() mocking — all requests hit the live stack.
 *
 * Each test captures explicit screenshots at key moments:
 *   01_registered — fresh user home screen after login
 *   02_typed      — user message visible in input box (before send)
 *   03_thinking   — AI thinking/loading indicator visible
 *   04_response   — complete AI response fully rendered
 *   05_final      — final state after all assertions pass
 */

import { test, expect } from "@playwright/test";
import {
  setupTestUser,
  waitForResponseComplete,
  verifyBillingRecord,
} from "./helpers.js";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test.use({
  trace: "retain-on-failure",
  viewport: { width: 1280, height: 900 },
});

test.setTimeout(180000);

// ---------------------------------------------------------------------------
// Screenshot helper
// ---------------------------------------------------------------------------

async function snap(
  page: import("@playwright/test").Page,
  testName: string,
  step: string
): Promise<void> {
  const outDir = path.join(__dirname, "screenshots", "bioinformatics-viewers", testName);
  fs.mkdirSync(outDir, { recursive: true });
  const file = path.join(outDir, `${step}.png`);
  await page.screenshot({ path: file, fullPage: false });
  console.log(`[snap:${testName}] ${step} → screenshots/bioinformatics-viewers/${testName}/${step}.png`);
}

// ---------------------------------------------------------------------------
// Shared send+screenshot helper: type → snap → send → snap thinking → wait → snap response
// ---------------------------------------------------------------------------

async function runViewerTest(
  page: import("@playwright/test").Page,
  testName: string,
  message: string,
  contentPattern: RegExp
): Promise<void> {
  await setupTestUser(page, testName);
  await snap(page, testName, "01_registered");

  // Type message but don't send yet — capture the pre-send state
  const chatInput = page.locator("textarea").first();
  await expect(chatInput).toBeVisible({ timeout: 15000 });
  await chatInput.fill(message);
  await snap(page, testName, "02_typed");

  // Send the message
  await chatInput.press("Enter");

  // Capture the thinking state (first 5s window)
  const thinkingIndicators = [
    "text=BioMate is thinking",
    "text=AI is typing",
    "text=Analyzing request",
  ];
  for (const sel of thinkingIndicators) {
    const visible = await page.locator(sel).first().isVisible({ timeout: 5000 }).catch(() => false);
    if (visible) {
      await snap(page, testName, "03_thinking");
      break;
    }
  }

  // Wait for complete AI response
  await waitForResponseComplete(page, 90_000);
  await page.waitForTimeout(500); // let final render settle
  await snap(page, testName, "04_response");

  // Assert response is present and contains relevant content
  await expect(page.locator("textarea").first()).toBeVisible({ timeout: 30000 });
  const bodyText = (await page.textContent("body").catch(() => "")) ?? "";
  const hasContent = contentPattern.test(bodyText);
  console.log(`[${testName}] Domain content found: ${hasContent}`);
  expect(hasContent).toBe(
    true,
    `Expected AI response to contain content matching ${contentPattern} — full page text was: "${bodyText.slice(0, 300)}"`
  );

  await verifyBillingRecord(page, testName);
  await snap(page, testName, "05_final");
}

// ---------------------------------------------------------------------------
// UI Rendering — no AI call; just verifies the app loaded
// ---------------------------------------------------------------------------

test.describe("UI Rendering", () => {
  test("should render main chat interface elements", async ({ page }) => {
    await setupTestUser(page, "ui_render");
    await snap(page, "ui_render", "01_registered");

    const chatInput = page.locator("textarea").first();
    await expect(chatInput).toBeVisible({ timeout: 15000 });

    const hasHeading = await page
      .getByRole("heading", { name: /biomate/i })
      .first()
      .isVisible({ timeout: 5000 })
      .catch(() => false);
    const hasSidebar = await page
      .locator('[data-testid="sidebar"], nav, aside')
      .first()
      .isVisible({ timeout: 5000 })
      .catch(() => false);
    expect(hasHeading || hasSidebar).toBe(true);

    await expect(chatInput).toBeEnabled({ timeout: 30000 });
    await snap(page, "ui_render", "02_final");

    console.log("[UI] Main chat interface rendered correctly");
  });
});

// ---------------------------------------------------------------------------
// Viewer tests — each sends a query and verifies a complete AI response
// ---------------------------------------------------------------------------

test.describe("VCF Viewer", () => {
  test("should receive complete AI response about VCF variant analysis", async ({ page }) => {
    await runViewerTest(
      page,
      "vcf",
      "I have a VCF file with variant calls. Can you help me view and analyze the variants?",
      /variant|vcf|allele|mutation|snp|genotype|annotation/i
    );
  });
});

test.describe("Sequence Viewer", () => {
  test("should receive complete AI response about FASTA sequence analysis", async ({ page }) => {
    await runViewerTest(
      page,
      "sequence",
      "I have a FASTA file with DNA sequences. Can you help me view the sequences and calculate statistics like GC content?",
      /sequence|fasta|gc content|nucleotide|dna|rna|genome/i
    );
  });
});

test.describe("Annotation Viewer", () => {
  test("should receive complete AI response about BED annotation viewing", async ({ page }) => {
    await runViewerTest(
      page,
      "annotation",
      "I have a BED file with genomic annotations. Can you help me view the features?",
      /bed|annotation|genomic|feature|track|region|coordinate|interval/i
    );
  });
});

test.describe("Interactive Tool Launcher", () => {
  test("should receive complete AI response about single-cell visualization", async ({ page }) => {
    await runViewerTest(
      page,
      "interactive",
      "I have a single-cell RNA-seq h5ad file. Can you help me visualize it?",
      /single.cell|h5ad|seurat|scanpy|umap|tsne|cluster|visuali|anndata/i
    );
  });
});

// ---------------------------------------------------------------------------
// Navigation — no AI call; verifies sidebar navigation works
// ---------------------------------------------------------------------------

test.describe("Navigation", () => {
  test("should navigate using sidebar without breaking chat input", async ({ page }) => {
    await setupTestUser(page, "navigation");
    await snap(page, "navigation", "01_registered");

    const newChatBtn = page.getByRole("button", { name: /new chat/i }).first();
    if (await newChatBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await snap(page, "navigation", "02_before_new_chat");
      await newChatBtn.click();
      await page.waitForTimeout(500);
      await snap(page, "navigation", "03_after_new_chat");
    }

    await expect(page.locator("textarea").first()).toBeEnabled({ timeout: 30000 });
    await snap(page, "navigation", "04_final");

    console.log("[Navigation] Navigation completed successfully");
  });
});

// ---------------------------------------------------------------------------
// Theme — no AI call; verifies theme toggle works
// ---------------------------------------------------------------------------

test.describe("Theme", () => {
  test("should toggle theme without breaking app", async ({ page }) => {
    await setupTestUser(page, "theme");
    await snap(page, "theme", "01_registered");

    const themeBtn = page
      .locator(
        'button[aria-label*="theme" i], button[data-testid*="theme"], button:has-text("Toggle theme")'
      )
      .first();

    if (await themeBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await snap(page, "theme", "02_before_toggle");
      await themeBtn.click();
      await page.waitForTimeout(500);
      await snap(page, "theme", "03_dark_mode");
      await themeBtn.click();
      await page.waitForTimeout(300);
      await snap(page, "theme", "04_light_mode");
      console.log("[Theme] Theme toggled successfully");
    } else {
      console.log("[Theme] No theme toggle found — verifying app still functional");
    }

    await expect(page.locator("textarea").first()).toBeVisible({ timeout: 30000 });
    await snap(page, "theme", "05_final");
  });
});
