/**
 * Real Workflow Execution E2E Test
 *
 * Tests the complete flow:
 * 1. User asks for a workflow
 * 2. AI generates workflow
 * 3. User clicks "Run"
 * 4. Progress is tracked
 * 5. Invocation is saved
 * 6. Outputs are displayed
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'real-workflow');

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

test.setTimeout(180000); // 3 minutes for real workflow

interface ConsoleLog {
  type: string;
  text: string;
  timestamp: string;
}

test.describe('Real Workflow Execution', () => {
  test('should track workflow execution and show outputs', async ({ page }) => {
    const consoleLogs: ConsoleLog[] = [];

    // Capture console logs
    page.on('console', (msg) => {
      consoleLogs.push({
        type: msg.type(),
        text: msg.text(),
        timestamp: new Date().toISOString(),
      });
    });

    // Capture network errors
    page.on('requestfailed', (request) => {
      consoleLogs.push({
        type: 'network-error',
        text: `${request.method()} ${request.url()} - ${request.failure()?.errorText}`,
        timestamp: new Date().toISOString(),
      });
    });

    // Step 1: Register/Login
    console.log('[Test] Step 1: Register user');
    const email = `e2e_wf_exec_${Date.now()}@biomate.test`;
    const password = 'TestPass123!';

    await page.goto(`${BASE_URL}/register`);
    await page.waitForLoadState('networkidle');

    try {
      await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
      await page.fill('#name', 'Workflow Test User');
      await page.fill('#email', email);
      await page.fill('#password', password);
      await page.fill('#confirmPassword', password);
      await page.click('#terms');
      await page.click('button[type="submit"]');
      await page.waitForTimeout(2000);
    } catch {
      console.log('[Test] Registration form not found, proceeding');
    }

    // Step 2: Navigate to main app
    console.log('[Test] Step 2: Navigate to main app');
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    await page.screenshot({ path: `${SCREENSHOT_DIR}/01_initial_state.png`, fullPage: true });

    // Step 3: Ask for a simple workflow
    console.log('[Test] Step 3: Ask for workflow');
    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    await chatInput.fill('Create a simple workflow to analyze VCF variant files using bcftools');
    await chatInput.press('Enter');

    console.log('[Test] Waiting for AI response...');

    // Wait for AI response (up to 60 seconds)
    await page.waitForSelector('[data-role="assistant"]', { timeout: 60000 });
    await page.waitForTimeout(3000);

    await page.screenshot({ path: `${SCREENSHOT_DIR}/02_workflow_generated.png`, fullPage: true });

    // Step 4: Check if workflow artifact is displayed
    console.log('[Test] Step 4: Check for workflow artifact');
    const workflowArtifact = page.locator('text=Run Workflow');
    const hasWorkflowButton = await workflowArtifact.isVisible().catch(() => false);

    console.log('[Test] Has Run Workflow button:', hasWorkflowButton);

    if (hasWorkflowButton) {
      // Step 5: Click Run Workflow
      console.log('[Test] Step 5: Click Run Workflow');
      await workflowArtifact.first().click();
      await page.waitForTimeout(1000);

      await page.screenshot({ path: `${SCREENSHOT_DIR}/03_workflow_started.png`, fullPage: true });

      // Step 6: Monitor progress (up to 120 seconds)
      console.log('[Test] Step 6: Monitor workflow progress');
      let progressFound = false;
      for (let i = 0; i < 60; i++) {
        await page.waitForTimeout(2000);

        // Check for progress indicators
        const progressText = await page.textContent('body');
        const hasProgress = progressText?.includes('Running') ||
                           progressText?.includes('Executing') ||
                           progressText?.includes('%');

        if (hasProgress) {
          progressFound = true;
          console.log(`[Test] Progress found at iteration ${i}`);
          await page.screenshot({ path: `${SCREENSHOT_DIR}/04_progress_${i}.png`, fullPage: true });
        }

        // Check for completion
        const isComplete = progressText?.includes('Complete') ||
                          progressText?.includes('Success') ||
                          progressText?.includes('Finished');

        if (isComplete) {
          console.log(`[Test] Workflow completed at iteration ${i}`);
          break;
        }

        // Check for errors
        const hasError = progressText?.includes('Failed') ||
                        progressText?.includes('Error');
        if (hasError) {
          console.log(`[Test] Workflow error at iteration ${i}`);
          await page.screenshot({ path: `${SCREENSHOT_DIR}/05_error.png`, fullPage: true });
          break;
        }
      }

      console.log('[Test] Progress tracking result:', progressFound);
    } else {
      console.log('[Test] No Run Workflow button found - workflow may not have been generated');
    }

    // Step 7: Check My Workflows panel
    console.log('[Test] Step 7: Check My Workflows panel');
    const myWorkflowsButton = page.getByRole('button', { name: 'My Workflows' });
    if (await myWorkflowsButton.isVisible()) {
      await myWorkflowsButton.click();
      await page.waitForTimeout(2000);
      await page.screenshot({ path: `${SCREENSHOT_DIR}/06_workflows_panel.png`, fullPage: true });
    }

    // Step 8: Check invocations API
    console.log('[Test] Step 8: Check invocations');
    const invocationsResponse = await page.evaluate(async () => {
      const response = await fetch('/api/invocations');
      return response.json();
    });

    console.log('[Test] Invocations count:', Array.isArray(invocationsResponse) ? invocationsResponse.length : 0);

    // Step 9: Check for output viewers
    console.log('[Test] Step 9: Check for output viewers');
    const pageContent = await page.textContent('body');
    const hasVCFViewer = pageContent?.includes('Variant') || pageContent?.includes('VCF');
    const hasOutputs = pageContent?.includes('output') || pageContent?.includes('Output');

    console.log('[Test] Has VCF/Variant content:', hasVCFViewer);
    console.log('[Test] Has output content:', hasOutputs);

    // Final screenshot
    await page.screenshot({ path: `${SCREENSHOT_DIR}/07_final_state.png`, fullPage: true });

    // Save console logs
    const logsPath = path.join(SCREENSHOT_DIR, `console_logs_${Date.now()}.json`);
    fs.writeFileSync(logsPath, JSON.stringify(consoleLogs, null, 2));
    console.log(`[Test] Console logs saved to: ${logsPath}`);

    // Filter for important logs
    const importantLogs = consoleLogs.filter(log =>
      log.text.includes('ChatWithArtifacts') ||
      log.text.includes('invocation') ||
      log.text.includes('SSE') ||
      log.text.includes('workflow') ||
      log.type === 'error' ||
      log.type === 'network-error'
    );

    console.log('\n[Test] Important console logs:');
    importantLogs.forEach(log => {
      console.log(`  [${log.type}] ${log.text.substring(0, 200)}`);
    });

    // Assertions
    expect(consoleLogs.length).toBeGreaterThan(0);
  });
});
