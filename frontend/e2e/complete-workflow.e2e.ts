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

interface RunStatusResponse {
  runId: string;
  status: string;
  progress?: {
    completedSteps?: number;
    totalSteps?: number;
  };
  errorMessage?: string;
  nextflowStatus?: {
    status?: string;
    completed?: boolean;
    error?: string;
  };
  usefulness?: {
    hasOutputs?: boolean;
    visualizableCount?: number;
    downloadableCount?: number;
    totalOutputs?: number;
    meetsContract?: boolean;
  };
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
    // Use a request that consistently returns a real executable workflow card.
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

    // ===== STEP 5: Click execution button if available =====
    // Some workflow cards use "Execute"/"Start"/"Run Workflow" instead of literal "Run".
    const runButtonCandidates = [
      page.getByRole('button', { name: /run workflow/i }).last(),
      page.getByRole('button', { name: /^run$/i }).last(),
      page.getByRole('button', { name: /execute/i }).last(),
      page.getByRole('button', { name: /start/i }).last(),
      page.locator('button:has-text("▶ Run")').last(),
      page.locator('button:has-text("Run")').last(),
    ];
    let runButton = runButtonCandidates[runButtonCandidates.length - 1];
    for (const candidate of runButtonCandidates) {
      if (await candidate.isVisible().catch(() => false)) {
        runButton = candidate;
        break;
      }
    }
    let executionRunId: string | null = null;
    let executeApiRunId: string | null = null;
    let backendTerminalStatus: string | null = null;
    let executionComplete = false;
    let outputFound = false;
    let outputVisualizable = false;
    let outputDownloadable = false;

    page.on('response', async (resp) => {
      if (!resp.url().includes('/api/workflows/execute')) {
        return;
      }
      try {
        const payload = await resp.json();
        executeApiRunId =
          payload?.execution?.run?.id ||
          payload?.execution?.runId ||
          payload?.runId ||
          executeApiRunId;
      } catch {
        // ignore parse failures for non-json responses
      }
    });

    if (await runButton.isVisible().catch(() => false)) {
      let runEnabled = await runButton.isEnabled().catch(() => false);
      if (!runEnabled) {
        console.log('[Test] Run button is disabled. Attempting prerequisite recovery prompt...');
        const recoveryButton = page.getByTestId('button-prereq-recovery').last();
        if (await recoveryButton.isVisible().catch(() => false)) {
          await recoveryButton.click();
        } else {
          const recoveryPrompt =
            'I do not have input files yet. Please generate a minimal runnable test dataset path and rerunnable workflow that can produce one visualizable report and downloadable output.';
          await chatInput.fill(recoveryPrompt);
          await chatInput.press('Enter');
        }
        await page.waitForSelector('text=AI is typing', { state: 'hidden', timeout: 120000 }).catch(() => {});
        await page.waitForTimeout(3000);
        await saveScreenshot('04b_prereq_recovery_response');

        // Re-resolve run button after recovery turn.
        for (const candidate of runButtonCandidates) {
          if (await candidate.isVisible().catch(() => false)) {
            runButton = candidate;
            break;
          }
        }
        runEnabled = await runButton.isEnabled().catch(() => false);
      }

      expect(runEnabled, 'Run button remains disabled after prerequisite recovery').toBe(true);
      console.log('[Test] Step 5: Clicking Run button...');
      await runButton.click();
      await page.waitForTimeout(2000);
      await saveScreenshot('05_workflow_running');

      // Capture the run id emitted by frontend log.
      for (let i = 0; i < 15; i++) {
        const runLog = [...consoleLogs].reverse().find((log) =>
          log.text.includes('Workflow execution started:')
        );
        if (runLog) {
          const match = runLog.text.match(/Workflow execution started:\s*([a-f0-9-]+)/i);
          if (match?.[1]) {
            executionRunId = match[1];
            console.log(`[Test] Captured execution run ID: ${executionRunId}`);
            break;
          }
        }
        await page.waitForTimeout(1000);
      }
      if (!executionRunId && executeApiRunId) {
        executionRunId = executeApiRunId;
      }
      if (!executionRunId) {
        console.log('[Test] Could not capture execution run ID from logs/API; continuing with UI checks.');
      }

      // ===== STEP 6: Monitor execution progress =====
      console.log('[Test] Step 6: Monitoring execution progress...');

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

      // ===== STEP 6b: Backend-truth check for terminal state =====
      console.log('[Test] Step 6b: Poll backend run status for terminal state...');
      const terminalStatuses = new Set(['completed', 'failed', 'error', 'cancelled']);
      let statusPayload: RunStatusResponse | null = null;

      if (executionRunId) {
        for (let i = 0; i < 45; i++) { // Up to ~90s for status/usefulness convergence
          await page.waitForTimeout(2000);
          const response = await page.request.get(`${BASE_URL}/api/workflows/runs/${executionRunId}/status`);
          if (!response.ok()) {
            console.log(`[Test] Backend poll ${i}: HTTP ${response.status()}`);
            continue;
          }

          statusPayload = (await response.json()) as RunStatusResponse;
          const status = (statusPayload.status || '').toLowerCase();
          const nfStatus = (statusPayload.nextflowStatus?.status || '').toLowerCase();
          const nfCompleted = !!statusPayload.nextflowStatus?.completed;

          if (i % 5 === 0) {
            console.log(
              `[Test] Backend poll ${i}: status=${status}, nfStatus=${nfStatus}, nfCompleted=${nfCompleted}, ` +
              `progress=${statusPayload.progress?.completedSteps ?? 0}/${statusPayload.progress?.totalSteps ?? 0}`
            );
          }

          if (terminalStatuses.has(status)) {
          backendTerminalStatus = status;
          // For successful completion, keep polling briefly until usefulness
          // contract is satisfied to avoid failing on persistence lag.
          if (status !== 'completed' || statusPayload?.usefulness?.meetsContract) {
            break;
          }
          }

          if (nfCompleted && (status === 'running' || status === 'pending')) {
          backendTerminalStatus = 'completed';
          if (statusPayload?.usefulness?.meetsContract) {
            break;
          }
          }
        }

        expect(backendTerminalStatus, 'Run did not reach terminal backend state in time').toBeTruthy();
        expect(
          backendTerminalStatus,
          `Run reached non-success terminal state. Backend error: ${statusPayload?.errorMessage || statusPayload?.nextflowStatus?.error || 'n/a'}`
        ).toBe('completed');
        expect(
          statusPayload?.usefulness?.meetsContract,
          `Run completed without useful outputs. usefulness=${JSON.stringify(statusPayload?.usefulness || {})}`
        ).toBe(true);

        executionComplete = true;
      }
      await saveScreenshot('07_backend_terminal_complete');

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
            outputFound = true;
            break;
          }
        }

        // Enforce frontend completion standard:
        // 1) output should be visualizable
        // 2) output should be downloadable
        const reportButton = page.getByRole('button', { name: /^report$/i }).first();
        const downloadButton = page.getByRole('button', { name: /^download$/i }).first();

        if (await reportButton.isVisible().catch(() => false)) {
          outputVisualizable = await reportButton.isEnabled().catch(() => false);
          console.log(`[Test] Report button visible, enabled=${outputVisualizable}`);
        } else {
          const visualizationCandidates = [
            page.locator('[data-testid="output-viewer"]').first(),
            page.getByRole('button', { name: /view results/i }).first(),
            page.getByRole('button', { name: /hide results/i }).first(),
            page.locator('text=Output Results').first(),
            page.locator('text=Visualization').first(),
          ];
          for (const candidate of visualizationCandidates) {
            if (await candidate.isVisible().catch(() => false)) {
              outputVisualizable = true;
              break;
            }
          }
          console.log(`[Test] Visualization indicator visible=${outputVisualizable}`);
        }

        if (await downloadButton.isVisible().catch(() => false)) {
          outputDownloadable = await downloadButton.isEnabled().catch(() => false);
          console.log(`[Test] Download button visible, enabled=${outputDownloadable}`);
        } else {
          const downloadIndicator = page.locator('a:has-text("Download"), button:has-text("Download All")').first();
          outputDownloadable = await downloadIndicator.isVisible().catch(() => false);
          console.log(`[Test] Download indicator visible=${outputDownloadable}`);
        }

        if (outputVisualizable && outputDownloadable) {
          await saveScreenshot('09_output_visualizable_and_downloadable');
        }
      }
    } else {
      console.log('[Test] No Run button found in WorkflowArtifact');
    }

    // Hard requirements for real E2E success.
    expect(foundWorkflow, 'Workflow artifact was not rendered').toBe(true);
    expect(executionComplete, 'Execution did not complete successfully').toBe(true);
    expect(outputFound, 'No output indicators were found after completion').toBe(true);
    expect(outputVisualizable, 'Output is not visualizable from frontend').toBe(true);
    expect(outputDownloadable, 'Output is not downloadable from frontend').toBe(true);

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
