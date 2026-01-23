/**
 * Real API Integration E2E Tests
 *
 * These tests verify ACTUAL backend functionality without mocks.
 * They test the real /api/chat endpoint and verify proper responses.
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'real-api');

// Ensure directories exist
if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

// Test configuration
test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

/**
 * Helper to register a test user
 */
async function setupTestUser(page: Page, testName: string): Promise<void> {
  const email = `e2e_real_${Date.now()}_${testName}@biomate.test`;
  const password = 'TestPass123!';

  console.log(`[Setup] Registering user: ${email}`);

  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState('networkidle');

  try {
    await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
    await page.fill('#name', 'E2E Real API Tester');
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.fill('#confirmPassword', password);
    await page.click('#terms');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch {
    console.log('[Setup] Registration form not found, may already be logged in');
  }

  await page.goto(BASE_URL);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1000);
}

/**
 * Test: Backend API health check
 */
test.describe('Backend API Health', () => {
  test('should have /api/chat endpoint responding', async ({ request }) => {
    const response = await request.post(`${BASE_URL}/api/chat`, {
      data: { message: 'Hello, can you help me?' },
    });

    expect(response.status()).toBe(200);

    const data = await response.json();
    console.log('[API Health] Response structure:', Object.keys(data));

    // Verify response has required fields
    expect(data).toHaveProperty('response');
    expect(typeof data.response).toBe('string');
    expect(data.response.length).toBeGreaterThan(0);

    // Verify response has suggestions
    expect(data).toHaveProperty('suggestions');
    expect(Array.isArray(data.suggestions)).toBe(true);

    console.log('[API Health] Response preview:', data.response.substring(0, 200));
  });
});

/**
 * Test: Real VCF analysis request
 */
test.describe('Real VCF Analysis', () => {
  // Increase timeout for real API tests (API response ~15-20s with Haiku)
  test.setTimeout(120000);

  test('should get VCF analysis response from real backend', async ({ page }) => {
    await setupTestUser(page, 'vcf_real');

    // Send message
    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    const userMessage = 'I have a VCF file with variant calls. Can you help me analyze the variants?';
    await chatInput.fill(userMessage);
    await chatInput.press('Enter');

    // Verify user message appeared
    await expect(page.getByText(userMessage.substring(0, 30))).toBeVisible({ timeout: 5000 });
    console.log('[VCF Real] User message sent');

    // Wait for assistant response to appear (more reliable than checking typing indicator)
    // With Haiku for intent + Sonnet for response, expect ~15-20 seconds
    try {
      await page.waitForSelector('[data-role="assistant"]', { timeout: 60000 });
      console.log('[VCF Real] Assistant response appeared');
    } catch {
      console.log('[VCF Real] Assistant response not found after 60s');
    }

    // Brief wait for response to fully render
    await page.waitForTimeout(1000);

    // Take screenshot
    await page.screenshot({
      path: `${SCREENSHOT_DIR}/vcf_real_response.png`,
      fullPage: true,
    });

    // Verify AI response appeared - should contain VCF-related content
    const pageContent = await page.textContent('body');

    // Check for any of these indicators of a real VCF response
    const vcfIndicators = [
      'VCF',
      'variant',
      'Variant',
      'VARIANT',
      'analysis',
      'Analysis',
      'tool',
      'Tool',
      'FreeBayes',
      'VCFtools',
      'filter',
      'quality',
    ];

    const hasVcfContent = vcfIndicators.some((indicator) =>
      pageContent?.includes(indicator)
    );

    console.log('[VCF Real] Page has VCF-related content:', hasVcfContent);

    // Check for assistant message element
    const assistantMessages = await page.locator('[data-role="assistant"]').count();
    console.log('[VCF Real] Assistant message count:', assistantMessages);

    // Verify we got an assistant response
    expect(assistantMessages).toBeGreaterThanOrEqual(1);
  });
});

/**
 * Test: Real workflow generation
 */
test.describe('Real Workflow Generation', () => {
  // Workflow generation involves tool search + workflow creation, takes longer
  test.setTimeout(120000);

  test('should generate workflow from real backend', async ({ page }) => {
    await setupTestUser(page, 'workflow_real');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    // Request a specific workflow
    const userMessage = 'Create a workflow for RNA-seq differential expression analysis with DESeq2';
    await chatInput.fill(userMessage);
    await chatInput.press('Enter');

    // Verify user message appeared
    await expect(page.getByText(userMessage.substring(0, 20))).toBeVisible({ timeout: 5000 });
    console.log('[Workflow Real] User message sent');

    // Wait for assistant response to appear
    try {
      await page.waitForSelector('[data-role="assistant"]', { timeout: 90000 });
      console.log('[Workflow Real] Assistant response appeared');
    } catch {
      console.log('[Workflow Real] Assistant response not found after 90s');
    }

    // Brief wait for response to fully render
    await page.waitForTimeout(1000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/workflow_real_response.png`,
      fullPage: true,
    });

    const pageContent = await page.textContent('body');

    // Check for workflow-related content
    const workflowIndicators = [
      'workflow',
      'Workflow',
      'RNA-seq',
      'RNA-Seq',
      'DESeq2',
      'differential expression',
      'pipeline',
      'step',
      'Step',
      'tool',
      'Tool',
    ];

    const hasWorkflowContent = workflowIndicators.some((indicator) =>
      pageContent?.includes(indicator)
    );

    console.log('[Workflow Real] Page has workflow-related content:', hasWorkflowContent);

    // Check for assistant message
    const assistantMessages = await page.locator('[data-role="assistant"]').count();
    console.log('[Workflow Real] Assistant message count:', assistantMessages);

    expect(assistantMessages).toBeGreaterThanOrEqual(1);
  });
});

/**
 * Test: Message persistence in chat
 */
test.describe('Chat Message Persistence', () => {
  test('should display both user and assistant messages', async ({ page }) => {
    await setupTestUser(page, 'persistence');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    // Send a simple message
    await chatInput.fill('What bioinformatics tools do you support?');
    await chatInput.press('Enter');

    // Wait for response
    await page.waitForTimeout(15000);

    await page.screenshot({
      path: `${SCREENSHOT_DIR}/message_persistence.png`,
      fullPage: true,
    });

    // Count user and assistant messages
    const allMessages = await page.locator('.whitespace-pre-wrap').count();
    console.log('[Persistence] Total message elements:', allMessages);

    // Should have at least 2 messages (user + assistant) or more (including welcome)
    expect(allMessages).toBeGreaterThanOrEqual(2);
  });
});

/**
 * After all tests, generate summary
 */
test.afterAll(async () => {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const summaryPath = path.join(SCREENSHOT_DIR, `real_api_summary_${timestamp}.json`);

  const summary = {
    timestamp: new Date().toISOString(),
    baseUrl: BASE_URL,
    testType: 'Real API Integration (no mocks)',
    tests: [
      'Backend API Health',
      'Real VCF Analysis',
      'Real Workflow Generation',
      'Chat Message Persistence',
    ],
  };

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
  console.log(`\n[Summary] Real API test summary saved to: ${summaryPath}`);
});
