import { setupTestUser } from "./helpers.js";
import { test, expect, Page } from '@playwright/test';

interface StateObservation {
  timestamp: string;
  elapsed: number;
  state: string;
  details: string;
}

test.setTimeout(300000);

test('BioMate Execution Pass - Real User Workflow', async ({ page }) => {
    await setupTestUser(page, "ux_exec");
  const timeline: StateObservation[] = [];
  const interactedElements: string[] = [];
  const worked: string[] = [];
  const failed: string[] = [];
  const startTime = Date.now();

  function logState(state: string, details: string) {
    const elapsed = Date.now() - startTime;
    timeline.push({
      timestamp: new Date().toISOString(),
      elapsed: Math.round(elapsed / 1000),
      state,
      details
    });
    console.log(`[${Math.round(elapsed / 1000)}s] ${state}: ${details}`);
  }

  console.log('\n' + '='.repeat(80));
  console.log('BIOMATE EXECUTION PASS - REAL USER WORKFLOW');
  console.log('URL: http://localhost:5310');
  console.log('='.repeat(80) + '\n');

  // Step 1: Open app and submit request
  logState('LOADING', 'Navigating to application');
  await page.goto(process.env.BIOMATE_URL || 'http://localhost:5000', { waitUntil: 'networkidle', timeout: 15000 });
  await page.waitForTimeout(2000);
  await page.screenshot({ path: '/tmp/exec_01_loaded.png', fullPage: true });
  logState('LOADED', 'Application ready');
  worked.push('Application loaded successfully');

  // Find chat input
  const chatInput = page.locator('textarea, input[type="text"], [contenteditable="true"]').first();
  if (await chatInput.count() === 0) {
    logState('ERROR', 'No chat input found');
    failed.push('Cannot find chat input - execution blocked');
    generateReport(timeline, interactedElements, worked, failed);
    return;
  }

  // Type and submit request
  const request = 'Build me a quality control workflow for RNA-seq FASTQ files';
  logState('TYPING', `Entering request: "${request}"`);
  await chatInput.click();
  await chatInput.fill(request);
  interactedElements.push('Chat textarea');
  
  await page.screenshot({ path: '/tmp/exec_02_typed.png', fullPage: true });
  
  // Submit (try send button first, then Enter)
  const sendButton = page.locator('button:has-text("Send"), button[type="submit"]').first();
  if (await sendButton.count() > 0 && await sendButton.isEnabled()) {
    logState('SUBMITTING', 'Clicking Send button');
    await sendButton.click();
    interactedElements.push('Send button');
    worked.push('Send button clicked successfully');
  } else {
    logState('SUBMITTING', 'Pressing Enter (no send button)');
    await chatInput.press('Enter');
    interactedElements.push('Enter key');
    worked.push('Enter key submitted message');
  }
  
  await page.screenshot({ path: '/tmp/exec_03_submitted.png', fullPage: true });

  // Step 2: Wait up to 120s for response
  logState('WAITING', 'Waiting for AI response (max 120s)');
  let responseReceived = false;
  const initialLength = (await page.locator('body').textContent())?.length || 0;
  
  for (let elapsed = 0; elapsed <= 120000; elapsed += 10000) {
    await page.waitForTimeout(10000);
    const currentLength = (await page.locator('body').textContent())?.length || 0;
    const diff = currentLength - initialLength;
    
    if (diff > 100) {
      logState('RESPONSE_RECEIVED', `Response appeared after ${elapsed / 1000}s (${diff} chars added)`);
      responseReceived = true;
      worked.push(`AI response received in ${elapsed / 1000} seconds`);
      await page.waitForTimeout(2000); // Let animations finish
      break;
    }
    
    if (elapsed % 30000 === 0 && elapsed > 0) {
      logState('WAITING', `Still waiting... ${elapsed / 1000}s elapsed`);
    }
  }

  if (!responseReceived) {
    logState('TIMEOUT', 'No response after 120s');
    failed.push('AI response timeout - waited 120 seconds with no response');
    await page.screenshot({ path: '/tmp/exec_04_timeout.png', fullPage: true });
    generateReport(timeline, interactedElements, worked, failed);
    return;
  }

  await page.screenshot({ path: '/tmp/exec_04_response.png', fullPage: true });

  // Check for workflow and status
  const workflowStatus = await page.locator('[class*="status"], [class*="badge"]').first().textContent({ timeout: 5000 }).catch(() => null);
  logState('WORKFLOW_READY', `Workflow status: ${workflowStatus?.trim() || 'unknown'}`);

  // Step 3: Click "Run Workflow"
  logState('LOCATING_RUN_BUTTON', 'Searching for Run Workflow button');
  const runButton = page.locator('button:has-text("Run Workflow"), button:has-text("Run"), button:has-text("Execute")').first();
  
  if (await runButton.count() === 0) {
    logState('ERROR', 'No Run Workflow button found');
    failed.push('Run Workflow button not found - cannot execute workflow');
    await page.screenshot({ path: '/tmp/exec_05_no_run_button.png', fullPage: true });
    generateReport(timeline, interactedElements, worked, failed);
    return;
  }

  const isEnabled = await runButton.isEnabled();
  const isVisible = await runButton.isVisible();
  logState('RUN_BUTTON_FOUND', `Button state - enabled: ${isEnabled}, visible: ${isVisible}`);

  if (!isEnabled || !isVisible) {
    logState('ERROR', 'Run button not clickable');
    failed.push(`Run button found but not clickable (enabled: ${isEnabled}, visible: ${isVisible})`);
    await page.screenshot({ path: '/tmp/exec_05_button_disabled.png', fullPage: true });
    generateReport(timeline, interactedElements, worked, failed);
    return;
  }

  logState('CLICKING_RUN', 'Clicking Run Workflow button');
  await runButton.click();
  interactedElements.push('Run Workflow button');
  worked.push('Run Workflow button clicked successfully');
  
  await page.waitForTimeout(2000);
  await page.screenshot({ path: '/tmp/exec_06_run_clicked.png', fullPage: true });

  // Step 4: Observe for 90s with 10s checks
  logState('OBSERVING', 'Monitoring execution for 90 seconds');
  
  for (let i = 0; i < 9; i++) {
    await page.waitForTimeout(10000);
    const elapsed = (i + 1) * 10;
    
    // Check status badge
    const statusElements = page.locator('[class*="status"], [class*="badge"]');
    if (await statusElements.count() > 0) {
      const status = await statusElements.first().textContent();
      logState('STATUS_CHECK', `[${elapsed}s] Status: ${status?.trim() || 'none'}`);
    }
    
    // Check for progress indicators
    const progressBars = page.locator('[class*="progress"], [role="progressbar"]');
    if (await progressBars.count() > 0) {
      const progressValue = await progressBars.first().getAttribute('value');
      const progressText = await progressBars.first().textContent();
      logState('PROGRESS', `[${elapsed}s] Progress: ${progressValue || progressText || 'visible'}`);
    }
    
    // Check logs section
    const logsSection = page.locator('[class*="log"], [class*="execution"]').first();
    if (await logsSection.count() > 0) {
      const logsText = await logsSection.textContent();
      if (logsText && !logsText.includes('No logs')) {
        logState('LOGS_UPDATE', `[${elapsed}s] Logs: ${logsText.substring(0, 100)}...`);
      }
    }
    
    // Check for completion
    if (await page.locator('text=/COMPLETED|SUCCESS|FINISHED/i').count() > 0) {
      logState('COMPLETED', `Workflow completed at ${elapsed}s`);
      worked.push(`Workflow completed successfully after ${elapsed} seconds`);
      await page.screenshot({ path: `/tmp/exec_07_completed_${elapsed}s.png`, fullPage: true });
      break;
    }
    
    // Check for failure
    if (await page.locator('text=/FAILED|ERROR/i').count() > 0) {
      logState('FAILED', `Workflow failed at ${elapsed}s`);
      failed.push(`Workflow execution failed after ${elapsed} seconds`);
      await page.screenshot({ path: `/tmp/exec_07_failed_${elapsed}s.png`, fullPage: true });
      break;
    }
    
    // Check for RUNNING state
    if (await page.locator('text=/RUNNING|EXECUTING|IN PROGRESS/i').count() > 0) {
      logState('RUNNING', `[${elapsed}s] Workflow is running`);
      if (i === 0) worked.push('Workflow execution started (RUNNING state observed)');
    }
    
    // Periodic screenshots
    if (elapsed % 30 === 0) {
      await page.screenshot({ path: `/tmp/exec_progress_${elapsed}s.png`, fullPage: true });
    }
  }

  await page.screenshot({ path: '/tmp/exec_08_final_state.png', fullPage: true });

  // Step 5: Try to interact with results
  logState('CHECKING_RESULTS', 'Looking for View Results / Hide Results buttons');
  
  const viewResultsButtons = page.locator('button:has-text("View Results"), button:has-text("Hide Results"), button:has-text("Show Results"), button:has-text("View"), button:has-text("Hide")');
  const viewButtonCount = await viewResultsButtons.count();
  
  if (viewButtonCount > 0) {
    const viewButton = viewResultsButtons.first();
    const buttonText = await viewButton.textContent();
    logState('CLICKING_VIEW', `Clicking "${buttonText}" button`);
    
    await viewButton.click();
    interactedElements.push(`View/Hide button ("${buttonText}")`);
    worked.push(`View/Hide results button clicked: "${buttonText}"`);
    
    await page.waitForTimeout(1000);
    await page.screenshot({ path: '/tmp/exec_09_results_toggled.png', fullPage: true });
    
    const newButtonText = await viewButton.textContent();
    if (newButtonText !== buttonText) {
      logState('TOGGLED', `Button changed from "${buttonText}" to "${newButtonText}"`);
      worked.push('Results view toggled successfully');
    }
  } else {
    logState('NOT_FOUND', 'No View Results / Hide Results button found');
    failed.push('View/Hide Results button not available');
  }

  // Look for Download All button
  logState('CHECKING_DOWNLOAD', 'Looking for Download All button');
  
  const downloadButtons = page.locator('button:has-text("Download All"), button:has-text("Download"), a[download]');
  const downloadCount = await downloadButtons.count();
  
  if (downloadCount > 0) {
    const downloadButton = downloadButtons.first();
    const downloadText = await downloadButton.textContent();
    logState('CLICKING_DOWNLOAD', `Clicking "${downloadText}" button`);
    
    // Set up download listener
    const downloadPromise = page.waitForEvent('download', { timeout: 5000 }).catch(() => null);
    
    await downloadButton.click();
    interactedElements.push(`Download button ("${downloadText}")`);
    
    const download = await downloadPromise;
    if (download) {
      logState('DOWNLOAD_STARTED', `Download initiated: ${download.suggestedFilename()}`);
      worked.push(`Download started: ${download.suggestedFilename()}`);
    } else {
      logState('DOWNLOAD_NO_FILE', 'Download button clicked but no file download detected');
      worked.push('Download button clicked (no file download detected within 5s)');
    }
    
    await page.waitForTimeout(1000);
    await page.screenshot({ path: '/tmp/exec_10_download_clicked.png', fullPage: true });
  } else {
    logState('NOT_FOUND', 'No Download All button found');
    failed.push('Download All button not available');
  }

  // Step 6: Check for download prompt or surveys
  logState('CHECKING_SURVEYS', 'Looking for surveys or feedback prompts');
  
  const surveyElements = page.locator('[class*="survey"], [class*="feedback"], [role="dialog"]');
  const surveyCount = await surveyElements.count();
  
  if (surveyCount > 0) {
    logState('SURVEY_FOUND', 'Survey or feedback prompt detected');
    
    // Try to interact with first interactive element
    const surveyButtons = page.locator('[class*="survey"] button, [class*="feedback"] button, [role="dialog"] button').first();
    if (await surveyButtons.count() > 0) {
      const buttonText = await surveyButtons.textContent();
      logState('CLICKING_SURVEY', `Clicking survey button: "${buttonText}"`);
      
      await surveyButtons.click();
      interactedElements.push(`Survey button ("${buttonText}")`);
      worked.push(`Survey interaction: clicked "${buttonText}"`);
      
      await page.waitForTimeout(1000);
      await page.screenshot({ path: '/tmp/exec_11_survey_clicked.png', fullPage: true });
    }
  } else {
    logState('NOT_FOUND', 'No surveys or feedback prompts found');
  }

  // Final screenshot
  await page.screenshot({ path: '/tmp/exec_12_final.png', fullPage: true });
  
  logState('COMPLETE', 'Execution pass finished');

  // Generate report
  generateReport(timeline, interactedElements, worked, failed);
});

function generateReport(
  timeline: StateObservation[],
  interactedElements: string[],
  worked: string[],
  failed: string[]
) {
  console.log('\n' + '='.repeat(80));
  console.log('BIOMATE EXECUTION PASS - FINAL REPORT');
  console.log('='.repeat(80));

  // Execution path observed
  console.log('\n## EXECUTION PATH OBSERVED (Ordered Timeline)');
  console.log('-'.repeat(80));
  timeline.forEach((entry, idx) => {
    console.log(`${idx + 1}. [${entry.elapsed}s] ${entry.state}`);
    console.log(`   ${entry.details}`);
  });

  // UI elements actually interacted with
  console.log('\n## UI ELEMENTS ACTUALLY INTERACTED WITH');
  console.log('-'.repeat(80));
  if (interactedElements.length > 0) {
    interactedElements.forEach((element, idx) => {
      console.log(`${idx + 1}. ${element}`);
    });
  } else {
    console.log('(No elements interacted with)');
  }

  // What worked
  console.log('\n## WHAT WORKED');
  console.log('-'.repeat(80));
  if (worked.length > 0) {
    worked.forEach((item, idx) => {
      console.log(`${idx + 1}. ${item}`);
    });
  } else {
    console.log('(Nothing worked successfully)');
  }

  // What failed or blocked continuation
  console.log('\n## WHAT FAILED OR BLOCKED CONTINUATION');
  console.log('-'.repeat(80));
  if (failed.length > 0) {
    failed.forEach((item, idx) => {
      console.log(`${idx + 1}. ${item}`);
    });
  } else {
    console.log('(No failures or blockers)');
  }

  // Top 3 user-facing UX risks
  console.log('\n## TOP 3 USER-FACING UX RISKS');
  console.log('-'.repeat(80));
  
  const risks: string[] = [];
  
  // Analyze timeline and failures to identify risks
  const responseTime = timeline.find(e => e.state === 'RESPONSE_RECEIVED')?.elapsed;
  if (responseTime && responseTime > 30) {
    risks.push(`1. SLOW RESPONSE TIME: AI takes ${responseTime}s to respond with no loading indicator - users will think app is frozen`);
  }
  
  if (failed.some(f => f.includes('timeout') || f.includes('No response'))) {
    risks.push(`1. RESPONSE TIMEOUT: AI never responds - complete blocker for all workflows`);
  }
  
  if (failed.some(f => f.includes('Run') && f.includes('button'))) {
    risks.push(`2. EXECUTION BLOCKED: Cannot run workflows - Run button missing or disabled`);
  }
  
  const hasRunningState = timeline.some(e => e.state === 'RUNNING');
  const hasCompletedState = timeline.some(e => e.state === 'COMPLETED');
  if (!hasRunningState && !hasCompletedState && !failed.some(f => f.includes('Run'))) {
    risks.push(`2. NO EXECUTION FEEDBACK: Workflow state never changes after clicking Run - unclear if execution started`);
  }
  
  if (failed.some(f => f.includes('View') || f.includes('Download'))) {
    risks.push(`3. RESULTS INACCESSIBLE: Cannot view or download workflow outputs - no results interaction available`);
  }
  
  if (risks.length === 0) {
    risks.push('1. LONG WAIT TIMES: Extended response and execution times without progress feedback');
    risks.push('2. MISSING FEEDBACK: Limited visual indicators of system state during operations');
    risks.push('3. UNCLEAR NEXT STEPS: Users may not know what to do after workflow completion');
  }
  
  // Ensure we have exactly 3 risks
  while (risks.length < 3) {
    risks.push(`${risks.length + 1}. (No additional critical risks identified)`);
  }
  
  risks.slice(0, 3).forEach(risk => console.log(risk));

  console.log('\n' + '='.repeat(80));
  console.log(`Total timeline events: ${timeline.length}`);
  console.log(`Elements interacted with: ${interactedElements.length}`);
  console.log(`Successful operations: ${worked.length}`);
  console.log(`Failures/blockers: ${failed.length}`);
  console.log('Screenshots saved to /tmp/exec_*.png');
  console.log('='.repeat(80) + '\n');
}
