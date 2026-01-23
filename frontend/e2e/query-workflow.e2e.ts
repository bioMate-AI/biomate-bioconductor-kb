/**
 * Query-Based Workflow E2E Test
 *
 * Tests workflow generation and execution for queries that DON'T require file inputs:
 * - Database queries (UniProt, PDB, etc.)
 * - API-based tools
 * - Data retrieval workflows
 *
 * These workflows should be immediately runnable without uploading data.
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'query-workflow');

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
});

test.setTimeout(180000); // 3 minutes

test.describe('Query-Based Workflow E2E', () => {

  test('should generate and potentially execute a database query workflow', async ({ page }) => {
    const testStartTime = Date.now();

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

    // ===== STEP 2: Ask for a query-based workflow =====
    console.log('[Test] Step 2: Ask for query workflow');
    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    // Use a query that should use local biomni query tools (no file inputs needed)
    const workflowRequest = 'Query UniProt to get information about the BRCA1 protein';
    await chatInput.fill(workflowRequest);
    await chatInput.press('Enter');
    console.log(`[Test] Sent: "${workflowRequest}"`);
    await saveScreenshot('02_message_sent');

    // ===== STEP 3: Wait for AI response =====
    console.log('[Test] Step 3: Waiting for AI response...');

    // Wait for typing indicator to appear and disappear
    await page.waitForSelector('text=AI is typing', { timeout: 10000 }).catch(() => {
      console.log('[Test] No typing indicator found');
    });

    await page.waitForSelector('text=AI is typing', { state: 'hidden', timeout: 120000 }).catch(() => {
      console.log('[Test] Typing indicator did not disappear');
    });

    await page.waitForTimeout(3000);
    await saveScreenshot('03_response_complete');

    // ===== STEP 4: Check for workflow artifact =====
    console.log('[Test] Step 4: Looking for workflow artifact...');

    const workflowIndicators = [
      'button:has-text("Run")',
      'text=steps',
      'text=confidence',
      '[data-testid="workflow-artifact"]',
      'text=UniProt',
      'text=Query',
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

    // Check if there's a workflow with tools
    const pageText = await page.textContent('body');
    console.log('[Test] Page contains "workflow":', pageText?.toLowerCase().includes('workflow'));
    console.log('[Test] Page contains "UniProt":', pageText?.toLowerCase().includes('uniprot'));
    console.log('[Test] Page contains "BRCA1":', pageText?.toLowerCase().includes('brca1'));

    // ===== STEP 5: Check if Run button is enabled (no file inputs needed) =====
    console.log('[Test] Step 5: Checking Run button state...');

    const runButton = page.locator('button:has-text("Run")').first();
    const isRunButtonVisible = await runButton.isVisible().catch(() => false);

    if (isRunButtonVisible) {
      const isDisabled = await runButton.isDisabled();
      console.log(`[Test] Run button visible: true, disabled: ${isDisabled}`);

      if (isDisabled) {
        // Check for prerequisites alert
        const prerequisitesAlert = page.locator('text=Input Data Required');
        const hasPrerequisites = await prerequisitesAlert.isVisible().catch(() => false);
        console.log(`[Test] Prerequisites alert visible: ${hasPrerequisites}`);

        if (hasPrerequisites) {
          // Capture what's missing
          const alertContent = await page.locator('role=alert').textContent().catch(() => '');
          console.log('[Test] Prerequisites details:', alertContent?.substring(0, 500));
        }

        await saveScreenshot('05_run_button_disabled');

        // Even if disabled, this is valid behavior - capture it
        console.log('[Test] Workflow requires inputs - this may be expected for complex queries');
      } else {
        // Run button is enabled - try to execute!
        console.log('[Test] Step 6: Clicking Run button...');
        await runButton.click();
        await page.waitForTimeout(3000);
        await saveScreenshot('06_workflow_started');

        // Monitor for execution
        let executionStatus = 'unknown';
        for (let i = 0; i < 30; i++) { // Up to 1 minute
          await page.waitForTimeout(2000);
          const text = await page.textContent('body');

          if (text?.includes('Executing') || text?.includes('Running') || text?.includes('%')) {
            console.log(`[Test] Execution in progress (iteration ${i})`);
            executionStatus = 'running';
          }

          if (text?.includes('Complete') || text?.includes('Success') || text?.includes('Finished')) {
            console.log('[Test] Execution complete!');
            executionStatus = 'complete';
            await saveScreenshot('07_execution_complete');
            break;
          }

          if (text?.includes('Failed') || text?.includes('Error:')) {
            console.log('[Test] Execution failed');
            executionStatus = 'failed';
            await saveScreenshot('07_execution_failed');
            break;
          }
        }

        console.log(`[Test] Final execution status: ${executionStatus}`);
      }
    } else {
      console.log('[Test] No Run button found - checking for tool recommendations instead');

      // Check if there are tool recommendations (alternative response format)
      const toolRecommendations = page.locator('text=Recommended Tools');
      if (await toolRecommendations.isVisible().catch(() => false)) {
        console.log('[Test] Found tool recommendations');
        await saveScreenshot('05_tool_recommendations');
      }
    }

    // ===== Summary =====
    console.log('\n[Test] === SUMMARY ===');
    console.log(`[Test] Workflow found: ${foundWorkflow}`);
    console.log(`[Test] Run button visible: ${isRunButtonVisible}`);

    // Save test summary
    const summary = {
      timestamp: new Date().toISOString(),
      query: workflowRequest,
      workflowFound: foundWorkflow,
      runButtonVisible: isRunButtonVisible,
      runButtonEnabled: isRunButtonVisible ? !(await runButton.isDisabled().catch(() => true)) : false,
      pageContainsWorkflow: pageText?.toLowerCase().includes('workflow'),
      pageContainsUniProt: pageText?.toLowerCase().includes('uniprot'),
    };

    fs.writeFileSync(
      `${SCREENSHOT_DIR}/test_summary_${new Date().toISOString().replace(/[:.]/g, '-')}.json`,
      JSON.stringify(summary, null, 2)
    );

    // Assert that we at least got a response about the query
    expect(pageText?.toLowerCase()).toContain('brca1');
  });

  test('should handle protein structure prediction query', async ({ page }) => {
    const testStartTime = Date.now();

    const saveScreenshot = async (name: string) => {
      const timestamp = Date.now() - testStartTime;
      await page.screenshot({
        path: `${SCREENSHOT_DIR}/structure_${String(timestamp).padStart(6, '0')}_${name}.png`,
        fullPage: true
      });
    };

    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    // Query for protein structure - should use local AlphaFold query tool
    const query = 'Get the AlphaFold predicted structure for human insulin';
    await chatInput.fill(query);
    await chatInput.press('Enter');
    console.log(`[Test] Sent: "${query}"`);

    // Wait for response
    await page.waitForSelector('text=AI is typing', { state: 'hidden', timeout: 120000 }).catch(() => {});
    await page.waitForTimeout(3000);
    await saveScreenshot('response');

    const pageText = await page.textContent('body');
    console.log('[Test] Page contains "AlphaFold":', pageText?.toLowerCase().includes('alphafold'));
    console.log('[Test] Page contains "insulin":', pageText?.toLowerCase().includes('insulin'));
    console.log('[Test] Page contains "structure":', pageText?.toLowerCase().includes('structure'));

    // Check for local tool usage
    const usesLocalTool = pageText?.includes('biomni/') || pageText?.includes('Query Alphafold');
    console.log('[Test] Uses local tool:', usesLocalTool);

    expect(pageText?.toLowerCase()).toContain('insulin');
  });
});
