/**
 * Onboarding Welcome Screen — E2E Tests
 *
 * OB-1  through OB-12 cover the 2-step onboarding flow:
 *   Step 1: domain selection (14 taxonomy domains + "Other" free-text)
 *   Step 2: topic selection (per-domain pills + "Other" per section)
 *
 * No page.route() mocking — all requests hit the live stack.
 */

import { test, expect, Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { setupTestUser, BASE_URL } from "./helpers.js";

// ---------------------------------------------------------------------------
// Screenshot helper
// ---------------------------------------------------------------------------

const SS_DIR = "/tmp/ob-e2e-screenshots";
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

async function ss(page: Page, name: string) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log(`[Screenshot] ${p}`);
}

// ---------------------------------------------------------------------------
// All 14 domain keys from DOMAIN_TAXONOMY (domain-profile-selector.tsx)
// ---------------------------------------------------------------------------

const ALL_DOMAIN_KEYS = [
  "genomics",
  "transcriptomics",
  "single_cell",
  "epigenomics",
  "proteomics",
  "metabolomics",
  "metagenomics",
  "structural_biology",
  "drug_discovery",
  "cryo_em",
  "pharmacology",
  "systems_biology",
  "synthetic_biology",
  "bioimaging",
];

test.setTimeout(120_000);

// ============================================================================
// OB-1: Welcome screen visible for new user with 0 messages
// ============================================================================

test("OB-1: Welcome screen visible for new user with 0 messages", async ({ page }) => {
  await setupTestUser(page, "ob-1");
  await ss(page, "ob-01-before");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });
  console.log("[OB-1] onboarding-welcome visible ✓");
  await ss(page, "ob-01-welcome-visible");
});

// ============================================================================
// OB-2: All 14 domain buttons present
// ============================================================================

test("OB-2: All 14 domain buttons present", async ({ page }) => {
  await setupTestUser(page, "ob-2");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  for (const key of ALL_DOMAIN_KEYS) {
    const btn = page.getByTestId(`onboarding-domain-btn-${key}`);
    await expect(btn).toBeVisible({ timeout: 5_000 });
    console.log(`[OB-2] domain button "${key}" visible ✓`);
  }

  await ss(page, "ob-02-all-domains");
});

// ============================================================================
// OB-3: Multi-select — click 3 domains, all 3 show as selected
// ============================================================================

test("OB-3: Multi-select works — click 3 domains, all 3 show as selected", async ({ page }) => {
  await setupTestUser(page, "ob-3");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  const toSelect = ["genomics", "drug_discovery", "cryo_em"];

  for (const key of toSelect) {
    await page.getByTestId(`onboarding-domain-btn-${key}`).click();
    await page.waitForTimeout(200);
  }

  await ss(page, "ob-03-three-selected");

  // Each selected button should have the "selected" styling — we detect it by
  // checking that the aria or class attributes reflect the active state.
  // The component uses `border-primary bg-primary/10 text-primary` when selected.
  // Verify via DOM: each button's class should contain "border-primary".
  for (const key of toSelect) {
    const btn = page.getByTestId(`onboarding-domain-btn-${key}`);
    const cls = await btn.getAttribute("class");
    expect(cls).toContain("border-primary");
    console.log(`[OB-3] "${key}" shows as selected ✓`);
  }

  // The non-selected domain should NOT have border-primary
  const unselectedBtn = page.getByTestId("onboarding-domain-btn-transcriptomics");
  const unselectedCls = await unselectedBtn.getAttribute("class");
  expect(unselectedCls).not.toContain("bg-primary/10");
  console.log("[OB-3] unselected domain does not have selected style ✓");
});

// ============================================================================
// OB-4: "Continue" button disabled until at least one domain selected
// ============================================================================

test('OB-4: "Continue" button disabled until at least one domain selected', async ({ page }) => {
  await setupTestUser(page, "ob-4");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  // Before any selection, the Continue button should be disabled
  const continueBtn = page.getByRole("button", { name: /continue/i });
  await expect(continueBtn).toBeVisible({ timeout: 5_000 });
  await expect(continueBtn).toBeDisabled();
  console.log("[OB-4] Continue button disabled with 0 selections ✓");

  await ss(page, "ob-04-continue-disabled");

  // After selecting one domain, Continue should be enabled
  await page.getByTestId("onboarding-domain-btn-genomics").click();
  await page.waitForTimeout(200);

  await expect(continueBtn).toBeEnabled();
  console.log("[OB-4] Continue button enabled after 1 selection ✓");
  await ss(page, "ob-04-continue-enabled");
});

// ============================================================================
// OB-5: "Other domain" text input present and accepts text
// ============================================================================

test('"OB-5: Other domain" text input present and accepts text', async ({ page }) => {
  await setupTestUser(page, "ob-5");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  // The Other domain input has a distinctive placeholder
  const otherInput = page.locator(
    'input[placeholder*="Other domain"]'
  );
  await expect(otherInput).toBeVisible({ timeout: 5_000 });
  console.log("[OB-5] Other domain input visible ✓");

  await otherInput.fill("spatial genomics, immunology");
  await page.waitForTimeout(200);

  const value = await otherInput.inputValue();
  expect(value).toBe("spatial genomics, immunology");
  console.log("[OB-5] Other domain input accepts text ✓");

  await ss(page, "ob-05-other-domain-input");
});

// ============================================================================
// OB-6: After clicking Continue, topics step shows domain labels as headings
// ============================================================================

test("OB-6: After clicking Continue, topics step shows domain labels as section headings", async ({ page }) => {
  await setupTestUser(page, "ob-6");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  // Select two domains
  const selectedDomains = ["genomics", "proteomics"];
  for (const key of selectedDomains) {
    await page.getByTestId(`onboarding-domain-btn-${key}`).click();
    await page.waitForTimeout(150);
  }

  // Advance to Step 2
  const continueBtn = page.getByRole("button", { name: /continue/i });
  await expect(continueBtn).toBeEnabled();
  await continueBtn.click();
  await page.waitForTimeout(500);

  await ss(page, "ob-06-topics-step");

  // Step 2 heading
  const heading = page.getByText("Which topics interest you?");
  await expect(heading).toBeVisible({ timeout: 5_000 });
  console.log("[OB-6] Topics step heading visible ✓");

  // Domain labels appear as section headings (uppercase text)
  // DOMAIN_LABELS: genomics → "Genomics", proteomics → "Proteomics"
  for (const label of ["Genomics", "Proteomics"]) {
    const sectionHeading = page.locator("h4").filter({ hasText: new RegExp(label, "i") });
    await expect(sectionHeading.first()).toBeVisible({ timeout: 5_000 });
    console.log(`[OB-6] Section heading "${label}" visible ✓`);
  }
});

// ============================================================================
// OB-7: Topics are clickable pills — click one, it shows as selected
// ============================================================================

test("OB-7: Topics are clickable pills — click one, it shows as selected", async ({ page }) => {
  await setupTestUser(page, "ob-7");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  // Select genomics (has topics: "variant calling", "WGS", etc.)
  await page.getByTestId("onboarding-domain-btn-genomics").click();
  await page.waitForTimeout(150);

  const continueBtn = page.getByRole("button", { name: /continue/i });
  await expect(continueBtn).toBeEnabled();
  await continueBtn.click();
  await page.waitForTimeout(500);

  await ss(page, "ob-07-topics-before-click");

  // Click the "variant calling" topic pill — scope to onboarding overlay to
  // avoid matching chat-history buttons with the same label
  const welcome2 = page.getByTestId("onboarding-welcome");
  const pill = welcome2.getByRole("button", { name: /^variant calling$/i });
  await expect(pill).toBeVisible({ timeout: 5_000 });
  await pill.click();
  await page.waitForTimeout(200);

  // After click the pill should have the selected class (border-primary)
  const cls = await pill.getAttribute("class");
  expect(cls).toContain("border-primary");
  console.log("[OB-7] Topic pill shows as selected after click ✓");

  await ss(page, "ob-07-topic-selected");
});

// ============================================================================
// OB-8: "Other topics" text input present per domain section
// ============================================================================

test('"OB-8: Other topics" text input present per domain section', async ({ page }) => {
  await setupTestUser(page, "ob-8");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  await page.getByTestId("onboarding-domain-btn-genomics").click();
  await page.waitForTimeout(150);

  const continueBtn = page.getByRole("button", { name: /continue/i });
  await continueBtn.click();
  await page.waitForTimeout(500);

  // The per-domain Other input placeholder includes "Other Genomics topics"
  const otherTopicsInput = page.locator('input[placeholder*="Other Genomics topics"]');
  await expect(otherTopicsInput).toBeVisible({ timeout: 5_000 });
  console.log("[OB-8] Per-domain Other topics input visible ✓");

  await otherTopicsInput.fill("long-read sequencing, pangenomics");
  const value = await otherTopicsInput.inputValue();
  expect(value).toBe("long-read sequencing, pangenomics");
  console.log("[OB-8] Per-domain Other topics input accepts text ✓");

  await ss(page, "ob-08-other-topics");
});

// ============================================================================
// OB-9: "Next — Enter BioMate" button present on topics step
// ============================================================================

test('"OB-9: Next — Enter BioMate" button present on topics step', async ({ page }) => {
  await setupTestUser(page, "ob-9");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  await page.getByTestId("onboarding-domain-btn-drug_discovery").click();
  await page.waitForTimeout(150);

  const continueBtn = page.getByRole("button", { name: /continue/i });
  await continueBtn.click();
  await page.waitForTimeout(500);

  const nextBtn = page.getByRole("button", { name: /next.*enter biomate/i });
  await expect(nextBtn).toBeVisible({ timeout: 5_000 });
  console.log('[OB-9] "Next — Enter BioMate" button visible ✓');

  await ss(page, "ob-09-next-button");
});

// ============================================================================
// OB-10: Clicking "Next" closes the welcome screen
// ============================================================================

test('OB-10: Clicking "Next" closes welcome screen', async ({ page }) => {
  await setupTestUser(page, "ob-10");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  // Step 1: select a domain and advance
  await page.getByTestId("onboarding-domain-btn-single_cell").click();
  await page.waitForTimeout(150);

  const continueBtn = page.getByRole("button", { name: /continue/i });
  await continueBtn.click();
  await page.waitForTimeout(500);

  await ss(page, "ob-10-topics-step");

  // Step 2: click Next
  const nextBtn = page.getByRole("button", { name: /next.*enter biomate/i });
  await expect(nextBtn).toBeVisible({ timeout: 5_000 });
  await nextBtn.click();

  // Welcome screen should disappear
  await expect(welcome).not.toBeVisible({ timeout: 15_000 });
  console.log("[OB-10] Welcome screen hidden after clicking Next ✓");

  await ss(page, "ob-10-welcome-hidden");
});

// ============================================================================
// OB-11: After completing onboarding, welcome does not reappear on reload
// ============================================================================

test("OB-11: After completing onboarding, welcome screen does not re-appear on reload", async ({ page }) => {
  await setupTestUser(page, "ob-11");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  // Complete the onboarding flow
  await page.getByTestId("onboarding-domain-btn-epigenomics").click();
  await page.waitForTimeout(150);

  const continueBtn = page.getByRole("button", { name: /continue/i });
  await continueBtn.click();
  await page.waitForTimeout(500);

  const nextBtn = page.getByRole("button", { name: /next.*enter biomate/i });
  await expect(nextBtn).toBeVisible({ timeout: 5_000 });
  await nextBtn.click();

  await expect(welcome).not.toBeVisible({ timeout: 15_000 });
  console.log("[OB-11] Welcome hidden after Next ✓");

  // Verify localStorage key is set
  const flagValue = await page.evaluate(() => localStorage.getItem("biomate_onboarding_done"));
  expect(flagValue).toBe("1");
  console.log("[OB-11] biomate_onboarding_done=1 in localStorage ✓");

  // Reload and confirm welcome does NOT reappear
  await page.reload();
  await page.waitForLoadState("load");
  await page.waitForTimeout(2_000);

  await ss(page, "ob-11-after-reload");

  const welcomeAfterReload = page.getByTestId("onboarding-welcome");
  await expect(welcomeAfterReload).not.toBeVisible({ timeout: 10_000 });
  console.log("[OB-11] Welcome screen does not reappear after reload ✓");
});

// ============================================================================
// OB-12: "Skip" on domains step immediately closes welcome screen
// ============================================================================

test('OB-12: "Skip" on domains step immediately closes welcome screen', async ({ page }) => {
  await setupTestUser(page, "ob-12");

  const welcome = page.getByTestId("onboarding-welcome");
  await expect(welcome).toBeVisible({ timeout: 15_000 });

  await ss(page, "ob-12-before-skip");

  // Click Skip (on Step 1 — no domain selected)
  const skipBtn = page.getByRole("button", { name: /^skip$/i });
  await expect(skipBtn).toBeVisible({ timeout: 5_000 });
  await skipBtn.click();

  // Welcome screen should disappear immediately
  await expect(welcome).not.toBeVisible({ timeout: 10_000 });
  console.log("[OB-12] Welcome screen hidden immediately after Skip ✓");

  // localStorage key should be set
  const flagValue = await page.evaluate(() => localStorage.getItem("biomate_onboarding_done"));
  expect(flagValue).toBe("1");
  console.log("[OB-12] biomate_onboarding_done=1 after Skip ✓");

  await ss(page, "ob-12-after-skip");
});
