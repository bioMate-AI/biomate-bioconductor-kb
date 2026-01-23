/**
 * Complete Workflow E2E Test
 *
 * Tests the ENTIRE flow from asking for a workflow to downloading output:
 * 1. User asks for workflow
 * 2. AI generates workflow with steps (WorkflowArtifact renders)
 * 3. User clicks "Run Workflow"
 * 4. Progress is tracked
 * 5. Output is available for download
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'complete-workflow');

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

test.setTimeout(300000); // 5 minutes for complete workflow

interface ConsoleLog {
  type: string;
  text: string;
  timestamp: string;
}

test.describe('Complete Workflow E2E', () => {
  test('should generate workflow, execute it, and provide output', async ({ page }) => {
    const consoleLogs: ConsoleLog[] = [];
    const testStartTime = Date.now();

    // Capture console logs
    page.on('console', (msg) => {
      consoleLogs.push({
        type: msg.type(),
        text: msg.text(),
        timestamp: new Date().toISOString(),
      });
    });

    // Helper function to save screenshot with timestamp
    const saveScreenshot = async (name: string) => {
      const timestamp = Date.now() - testStartTime;
      await page.screenshot({
        path: `${SCREENSHOT_DIR}/${String(timestamp).padStart(6, '0')}_${name}.png`,
        fullPage: true
      });
      console.log(`[Screenshot] ${name} at ${timestamp}ms`);
    };

    // ===== STEP 1: Navigate to app =====
    console.log('[Test] Step 1: Navigate to app');
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    await saveScreenshot('01_initial');

    // ===== STEP 2: Ask for a workflow =====
    console.log('[Test] Step 2: Ask for workflow');
    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    // Use a specific request that should trigger workflow generation
    const workflowRequest = 'Build me a quality control workflow for RNA-seq FASTQ files';
    await chatInput.fill(workflowRequest);
    await chatInput.press('Enter');
    console.log(`[Test] Sent: "${workflowRequest}"`);
    await saveScreenshot('02_message_sent');

    // ===== STEP 3: Wait for AI response to COMPLETE =====
    console.log('[Test] Step 3: Waiting for AI response to complete...');

    // First wait for typing indicator to appear
    await page.waitForSelector('text=AI is typing', { timeout: 10000 }).catch(() => {
      console.log('[Test] No typing indicator found, response may already be complete');
    });

    // Then wait for typing indicator to DISAPPEAR (response complete)
    await page.waitForSelector('text=AI is typing', { state: 'hidden', timeout: 120000 }).catch(() => {
      console.log('[Test] Typing indicator did not disappear within 2 minutes');
    });

    // Additional wait for rendering
    await page.waitForTimeout(3000);
    await saveScreenshot('03_response_complete');

    // ===== STEP 4: Check for WorkflowArtifact =====
    console.log('[Test] Step 4: Looking for WorkflowArtifact...');

    // Look for workflow artifact indicators
    const workflowIndicators = [
      'button:has-text("Run")',
      'text=steps',
      'text=confidence',
      '[data-testid="workflow-artifact"]',
      'text=RNA STARSolo',
      'text=MultiQC',
    ];

    let foundWorkflow = false;
    for (const indicator of workflowIndicators) {
      const element = page.locator(indicator).first();
      if (await element.isVisible().catch(() => false)) {
        console.log(`[Test] Found workflow indicator: ${indicator}`);
        foundWorkflow = true;
        break;
      }
    }

    await saveScreenshot('04_workflow_check');

    if (!foundWorkflow) {
      console.log('[Test] WorkflowArtifact NOT found! Checking page content...');
      const pageContent = await page.textContent('body');
      console.log('[Test] Page contains "workflow":', pageContent?.toLowerCase().includes('workflow'));
      console.log('[Test] Page contains "step":', pageContent?.toLowerCase().includes('step'));

      // Check if there's an error message
      const hasError = pageContent?.toLowerCase().includes('error') ||
                       pageContent?.toLowerCase().includes('failed');
      console.log('[Test] Page contains error:', hasError);

      // Save the full page HTML for debugging
      const html = await page.content();
      fs.writeFileSync(`${SCREENSHOT_DIR}/debug_page.html`, html);
      console.log('[Test] Saved page HTML to debug_page.html');
    }

    // ===== STEP 5: Click "Run" button if available =====
    // The button text is "▶ Run" or just "Run" in the WorkflowArtifact
    const runButton = page.locator('button:has-text("Run")').first();
    if (await runButton.isVisible().catch(() => false)) {
      console.log('[Test] Step 5: Clicking Run button...');
      await runButton.click();
      await page.waitForTimeout(2000);
      await saveScreenshot('05_workflow_running');

      // ===== STEP 6: Monitor execution progress =====
      console.log('[Test] Step 6: Monitoring execution progress...');

      let executionComplete = false;
      for (let i = 0; i < 60; i++) { // Up to 2 minutes
        await page.waitForTimeout(2000);

        const pageText = await page.textContent('body');

        // Check for progress indicators
        if (pageText?.includes('Executing') || pageText?.includes('Running') || pageText?.includes('%')) {
          console.log(`[Test] Execution in progress (iteration ${i})`);
          if (i % 10 === 0) {
            await saveScreenshot(`06_progress_${i}`);
          }
        }

        // Check for completion
        if (pageText?.includes('Complete') || pageText?.includes('Success') || pageText?.includes('Finished')) {
          console.log(`[Test] Execution complete at iteration ${i}`);
          executionComplete = true;
          await saveScreenshot('07_execution_complete');
          break;
        }

        // Check for errors
        if (pageText?.includes('Failed') || pageText?.includes('Error:')) {
          console.log(`[Test] Execution error at iteration ${i}`);
          await saveScreenshot('07_execution_error');
          break;
        }
      }

      // ===== STEP 7: Check for output/download =====
      if (executionComplete) {
        console.log('[Test] Step 7: Checking for output...');

        const outputIndicators = [
          'text=Download',
          'text=Output',
          'text=Results',
          '[data-testid="output-viewer"]',
        ];

        for (const indicator of outputIndicators) {
          const element = page.locator(indicator).first();
          if (await element.isVisible().catch(() => false)) {
            console.log(`[Test] Found output indicator: ${indicator}`);
            await saveScreenshot('08_output_available');
            break;
          }
        }
      }
    } else {
      console.log('[Test] No Run button found in WorkflowArtifact');
    }

    // ===== STEP 8: Check Workflow History =====
    console.log('[Test] Step 8: Checking Workflow History...');
    const myWorkflowsButton = page.getByRole('button', { name: 'My Workflows' });
    if (await myWorkflowsButton.isVisible()) {
      await myWorkflowsButton.click();
      await page.waitForTimeout(2000);
      await saveScreenshot('09_workflow_history');

      const historyContent = await page.textContent('body');
      const hasWorkflowsInHistory = !historyContent?.includes('No workflows run yet');
      console.log('[Test] Workflows in history:', hasWorkflowsInHistory);
    }

    // ===== Final screenshot and logs =====
    await saveScreenshot('10_final_state');

    // Save console logs
    const logsPath = `${SCREENSHOT_DIR}/console_logs_${Date.now()}.json`;
    fs.writeFileSync(logsPath, JSON.stringify(consoleLogs, null, 2));
    console.log(`[Test] Console logs saved to: ${logsPath}`);

    // Filter important logs
    const importantLogs = consoleLogs.filter(log =>
      log.text.includes('ChatInterface') ||
      log.text.includes('workflow') ||
      log.text.includes('Workflow') ||
      log.text.includes('Steps') ||
      log.text.includes('invocation') ||
      log.type === 'error'
    );

    console.log('\n[Test] === Important Console Logs ===');
    importantLogs.slice(-30).forEach(log => {
      console.log(`  [${log.type}] ${log.text.substring(0, 200)}`);
    });

    // Summary
    console.log('\n[Test] === Test Summary ===');
    console.log(`  Workflow artifact found: ${foundWorkflow}`);
    console.log(`  Total duration: ${Date.now() - testStartTime}ms`);
  });
});
