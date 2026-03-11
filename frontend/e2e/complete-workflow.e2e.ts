/**
 * Complete Workflow E2E Test
 *
 * Tests the ENTIRE flow from asking for a workflow to downloading output:
 * 1. User registers and logs in
 * 2. AI generates workflow with steps (WorkflowArtifact renders)
 * 3. User clicks "Run Workflow"
 * 4. Progress is tracked against real backend
 * 5. Output is available for download
 *
 * NO page.route() mocks — all calls hit the live BioMate backend.
 */

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
  clickRunAndWaitForTerminal,
} from './helpers.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'complete-workflow');

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
  storageState: { cookies: [], origins: [] },
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
  artifactReadiness?: {
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
        fullPage: true,
      });
      console.log(`[Screenshot] ${name} at ${timestamp}ms`);
    };

    // ===== STEP 1: Register and navigate to app =====
    console.log('[Test] Step 1: Register test user and navigate to app');
    await setupTestUser(page, 'cwf');
    await page.waitForTimeout(2000);
    await saveScreenshot('01_initial');

    // ===== STEP 2: Ask for a workflow =====
    console.log('[Test] Step 2: Ask for workflow');
    const workflowRequest = 'Build me a quality control workflow for RNA-seq FASTQ files';
    const foundWorkflow = await sendMessageAndWaitForResponse(page, workflowRequest);
    console.log(`[Test] Sent: "${workflowRequest}"`);

    // Additional wait for rendering
    await page.waitForTimeout(3000);
    await saveScreenshot('02_response_complete');

    // ===== STEP 3: Check for WorkflowArtifact =====
    console.log('[Test] Step 3: Looking for WorkflowArtifact...');

    // Look for workflow artifact indicators
    const workflowIndicators = [
      'button:has-text("Run")',
      'text=steps',
      'text=confidence',
      '[data-testid="workflow-artifact"]',
      'text=RNA STARSolo',
      'text=MultiQC',
      'text=FastQC',
    ];

    let detectedWorkflow = foundWorkflow;
    if (!detectedWorkflow) {
      for (const indicator of workflowIndicators) {
        const element = page.locator(indicator).first();
        if (await element.isVisible().catch(() => false)) {
          console.log(`[Test] Found workflow indicator: ${indicator}`);
          detectedWorkflow = true;
          break;
        }
      }
    }

    await saveScreenshot('03_workflow_check');

    if (!detectedWorkflow) {
      console.log('[Test] WorkflowArtifact NOT found! Checking page content...');
      const pageContent = await page.textContent('body');
      console.log('[Test] Page contains "workflow":', pageContent?.toLowerCase().includes('workflow'));
      console.log('[Test] Page contains "step":', pageContent?.toLowerCase().includes('step'));

      const hasError = pageContent?.toLowerCase().includes('error') ||
                       pageContent?.toLowerCase().includes('failed');
      console.log('[Test] Page contains error:', hasError);

      const html = await page.content();
      fs.writeFileSync(`${SCREENSHOT_DIR}/debug_page.html`, html);
      console.log('[Test] Saved page HTML to debug_page.html');
    }

    // ===== STEP 4: Handle disabled Run button with prerequisite recovery =====
    const chatInput = page.locator('textarea').first();
    const runButtonCandidates = [
      page.getByTestId('button-run-workflow-panel').first(),
      page.getByRole('button', { name: /run workflow/i }).first(),
      page.getByRole('button', { name: /^run$/i }).first(),
      page.getByRole('button', { name: /execute/i }).first(),
    ];

    let runButton = runButtonCandidates[0];
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
      if (!resp.url().includes('/api/workflows/execute')) return;
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
        await saveScreenshot('03b_prereq_recovery_response');

        // Re-resolve run button after recovery turn
        for (const candidate of runButtonCandidates) {
          if (await candidate.isVisible().catch(() => false)) {
            runButton = candidate;
            break;
          }
        }
        runEnabled = await runButton.isEnabled().catch(() => false);
      }

      expect(runEnabled, 'Run button remains disabled after prerequisite recovery').toBe(true);
      console.log('[Test] Step 4: Clicking Run button...');
      await runButton.click();
      await page.waitForTimeout(2000);
      await saveScreenshot('04_workflow_running');

      // Capture the run id emitted by frontend log
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

      // ===== STEP 5: Monitor execution progress =====
      console.log('[Test] Step 5: Monitoring execution progress...');

      for (let i = 0; i < 60; i++) { // Up to 2 minutes
        await page.waitForTimeout(2000);

        const pageText = await page.textContent('body');

        if (pageText?.includes('Executing') || pageText?.includes('Running') || pageText?.includes('%')) {
          console.log(`[Test] Execution in progress (iteration ${i})`);
          if (i % 10 === 0) {
            await saveScreenshot(`05_progress_${i}`);
          }
        }

        if (
          pageText?.includes('Complete') ||
          pageText?.includes('COMPLETED') ||
          pageText?.includes('Success') ||
          pageText?.includes('Finished')
        ) {
          console.log(`[Test] Execution complete at iteration ${i}`);
          executionComplete = true;
          await saveScreenshot('06_execution_complete');
          break;
        }

        if (pageText?.includes('Failed') || pageText?.includes('Error:')) {
          console.log(`[Test] Execution error at iteration ${i}`);
          await saveScreenshot('06_execution_error');
          break;
        }
      }

      // ===== STEP 5b: Backend-truth check for terminal state =====
      console.log('[Test] Step 5b: Poll backend run status for terminal state...');
      const terminalStatuses = new Set(['completed', 'failed', 'error', 'cancelled']);
      let statusPayload: RunStatusResponse | null = null;

      if (executionRunId) {
        for (let i = 0; i < 45; i++) { // Up to ~90s for status/artifact-readiness convergence
          await page.waitForTimeout(2000);
          const result = await page.evaluate(async (url: string) => {
            try {
              const r = await fetch(url);
              if (!r.ok) return { ok: false, status: r.status, body: null };
              return { ok: true, status: r.status, body: await r.json() };
            } catch {
              return { ok: false, status: 0, body: null };
            }
          }, `/api/workflows/runs/${executionRunId}/status?includeSteps=true`);

          if (!result.ok) {
            console.log(`[Test] Backend poll ${i}: HTTP ${result.status}`);
            continue;
          }

          statusPayload = result.body as RunStatusResponse;
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
            if (status !== 'completed' || statusPayload?.artifactReadiness?.meetsContract) {
              break;
            }
          }

          if (nfCompleted && (status === 'running' || status === 'pending')) {
            backendTerminalStatus = 'completed';
            if (statusPayload?.artifactReadiness?.meetsContract) {
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
          statusPayload?.artifactReadiness?.meetsContract,
          `Run completed before artifact readiness. artifactReadiness=${JSON.stringify(statusPayload?.artifactReadiness || {})}`
        ).toBe(true);

        executionComplete = true;
      }
      await saveScreenshot('06b_backend_terminal_complete');

      // ===== STEP 6: Check for output/download =====
      if (executionComplete) {
        console.log('[Test] Step 6: Checking for output...');
        await page.waitForTimeout(3000);
        await saveScreenshot('07_before_output_check');

        // Dismiss the post-run survey if present
        const surveyDialog = page.getByTestId('post-run-survey-dialog');
        if (await surveyDialog.isVisible().catch(() => false)) {
          await page.keyboard.press('Escape');
          await page.waitForTimeout(300);
        }

        // Dismiss post-run feedback modal before validating output affordances
        const feedbackSkip = page.getByRole('button', { name: /^skip$/i }).first();
        if (await feedbackSkip.isVisible().catch(() => false)) {
          await feedbackSkip.click().catch(() => {});
          await page.waitForTimeout(300);
        }

        // Scroll to output section if View Results button is visible
        const viewResultsBtnVisible = await page.getByRole('button', { name: /hide results/i }).first().isVisible().catch(() => false);
        if (!viewResultsBtnVisible) {
          const viewBtn = page.getByRole('button', { name: /view results/i }).first();
          if (await viewBtn.isVisible().catch(() => false) && await viewBtn.isEnabled().catch(() => false)) {
            await viewBtn.click();
            await page.waitForTimeout(1000);
          }
        }

        const outputStateBadge = page.getByTestId('output-result-state-badge').first();
        const runtimeArtifactsCard = page.getByTestId('nextflow-runtime-artifacts').first();
        const noOutputsMessage = page.getByText('No outputs generated yet').first();
        const hasOutputCards = await outputStateBadge.isVisible().catch(() => false);
        const hasRuntimeArtifacts = await runtimeArtifactsCard.isVisible().catch(() => false);
        const hasEmptyOutputsMessage = await noOutputsMessage.isVisible().catch(() => false);

        outputFound = hasOutputCards || hasRuntimeArtifacts;
        if (outputFound) {
          console.log(
            `[Test] Output evidence found: outputCards=${hasOutputCards}, runtimeArtifacts=${hasRuntimeArtifacts}, emptyMessage=${hasEmptyOutputsMessage}`
          );
          await saveScreenshot('07_output_available');
        }

        // Check visualizability
        const reportButton = page.getByRole('button', { name: /^report$/i }).first();
        if (hasOutputCards && !hasEmptyOutputsMessage && await reportButton.isVisible().catch(() => false)) {
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
          if (hasEmptyOutputsMessage) {
            outputVisualizable = false;
          }
          console.log(
            `[Test] Visualization indicator visible=${outputVisualizable} (hasOutputCards=${hasOutputCards}, emptyMessage=${hasEmptyOutputsMessage})`
          );
        }

        // Check downloadability
        if (hasOutputCards && !hasEmptyOutputsMessage) {
          for (let attempt = 0; attempt < 20 && !outputDownloadable; attempt++) {
            const outputDownloadCandidates = page.getByRole('button', { name: /download/i });
            const candidateCount = await outputDownloadCandidates.count();
            for (let idx = 0; idx < candidateCount; idx++) {
              const candidate = outputDownloadCandidates.nth(idx);
              const visible = await candidate.isVisible().catch(() => false);
              if (!visible) continue;
              const enabled = await candidate.isEnabled().catch(() => false);
              if (enabled) {
                outputDownloadable = true;
                break;
              }
            }
            if (!outputDownloadable) {
              await page.waitForTimeout(1000);
            }
          }

          const downloadButton = page.getByRole('button', { name: /^download$/i }).first();
          if (!outputDownloadable && await downloadButton.isVisible().catch(() => false)) {
            outputDownloadable = await downloadButton.isEnabled().catch(() => false);
          }
          if (!outputDownloadable) {
            const downloadAllButton = page.getByRole('button', { name: /download all/i }).first();
            if (await downloadAllButton.isVisible().catch(() => false)) {
              outputDownloadable = await downloadAllButton.isEnabled().catch(() => false);
            }
          }
          if (!outputDownloadable && executionRunId) {
            try {
              const statusResp = await page.request.get(`/api/workflows/runs/${executionRunId}/status`);
              if (statusResp.ok()) {
                const statusJson: any = await statusResp.json();
                const invocationIdFromStatus = statusJson?.nextflowStatus?.invocation_id;
                if (invocationIdFromStatus) {
                  const outputsResp = await page.request.get(`/api/invocations/${invocationIdFromStatus}/outputs`);
                  if (outputsResp.ok()) {
                    const outputsJson: any[] = await outputsResp.json();
                    if (Array.isArray(outputsJson) && outputsJson.length > 0 && outputsJson[0]?.id) {
                      const downloadProbe = await page.request.get(`/api/outputs/${outputsJson[0].id}/download`);
                      outputDownloadable = downloadProbe.ok();
                    }
                  }
                }
              }
            } catch {
              // Keep UI-based result if API probe fails
            }
          }
          console.log(`[Test] Output download control enabled=${outputDownloadable}`);
        } else {
          outputDownloadable = false;
          console.log(
            `[Test] Dataset download controls not found (hasOutputCards=${hasOutputCards}, emptyMessage=${hasEmptyOutputsMessage})`
          );
        }

        if (outputVisualizable && outputDownloadable) {
          await saveScreenshot('08_output_visualizable_and_downloadable');
        }
      }
    } else {
      console.log('[Test] No Run button found in WorkflowArtifact');
    }

    // Hard requirements for real E2E success
    expect(detectedWorkflow, 'Workflow artifact was not rendered').toBe(true);
    expect(executionComplete, 'Execution did not complete successfully').toBe(true);
    expect(outputFound, 'No output indicators were found after completion').toBe(true);
    expect(outputVisualizable, 'Output is not visualizable from frontend').toBe(true);
    expect(outputDownloadable, 'Output is not downloadable from frontend').toBe(true);

    // ===== STEP 7: Check Workflow History =====
    console.log('[Test] Step 7: Checking Workflow History...');
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

    const logsPath = `${SCREENSHOT_DIR}/console_logs_${Date.now()}.json`;
    fs.writeFileSync(logsPath, JSON.stringify(consoleLogs, null, 2));
    console.log(`[Test] Console logs saved to: ${logsPath}`);

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

    console.log('\n[Test] === Test Summary ===');
    console.log(`  Workflow artifact found: ${detectedWorkflow}`);
    console.log(`  Total duration: ${Date.now() - testStartTime}ms`);
  });
});
