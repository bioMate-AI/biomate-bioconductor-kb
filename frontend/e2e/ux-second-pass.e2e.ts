import { setupTestUser } from "./helpers.js";
import { test, expect, Page } from '@playwright/test';

interface ObservedElement {
  element: string;
  status: 'present' | 'not observed';
  details?: string;
}

interface InteractionOutcome {
  action: string;
  result: string;
  timestamp: string;
}

test.setTimeout(300000);

test('BioMate Second-Pass UX Review - Extended Wait Strategy', async ({ page }) => {
    await setupTestUser(page, "ux_2nd");
  const observedElements: ObservedElement[] = [];
  const interactions: InteractionOutcome[] = [];
  const screenshots: string[] = [];
  
  console.log('\n' + '='.repeat(80));
  console.log('BIOMATE SECOND-PASS UX REVIEW - EXTENDED WAIT STRATEGY');
  console.log('URL: http://localhost:5310');
  console.log('Wait Strategy: 10s increments up to 120s total');
  console.log('='.repeat(80));

  // Navigate to application
  console.log('\n[STEP 1] Loading application...');
  await page.goto(process.env.BIOMATE_URL || 'http://localhost:5000', { waitUntil: 'networkidle', timeout: 15000 });
  await page.waitForTimeout(2000);
  await page.screenshot({ path: '/tmp/ux2_01_landing.png', fullPage: true });
  screenshots.push('01_landing.png');
  console.log('✓ Application loaded');

  // Find and fill chat input
  console.log('\n[STEP 2] Locating chat input...');
  const chatInput = page.locator('textarea, input[type="text"], [contenteditable="true"]').first();
  
  if (await chatInput.count() === 0) {
    console.log('✗ CRITICAL: No chat input found');
    observedElements.push({ element: 'Chat input field', status: 'not observed' });
    generateReport(observedElements, interactions, screenshots, 'high', 'Cannot proceed without chat input');
    return;
  }
  
  console.log('✓ Chat input located');
  observedElements.push({ element: 'Chat input field', status: 'present', details: 'Textarea with placeholder' });

  // Type the workflow request
  const workflowRequest = 'Build me a quality control workflow for RNA-seq FASTQ files';
  console.log(`\n[STEP 3] Typing request: "${workflowRequest}"`);
  
  await chatInput.click();
  await page.waitForTimeout(500);
  await chatInput.fill(workflowRequest);
  console.log('✓ Request typed');
  
  await page.screenshot({ path: '/tmp/ux2_02_typed.png', fullPage: true });
  screenshots.push('02_typed.png');

  // Find send button or use Enter
  console.log('\n[STEP 4] Submitting request...');
  const sendButton = page.locator('button:has-text("Send"), button[type="submit"]').first();
  
  if (await sendButton.count() > 0) {
    console.log('✓ Send button found');
    observedElements.push({ element: 'Send button', status: 'present' });
    await sendButton.click();
    interactions.push({
      action: 'Clicked Send button',
      result: 'Message submitted',
      timestamp: new Date().toISOString()
    });
  } else {
    console.log('⚠ No Send button - using Enter key');
    observedElements.push({ element: 'Send button', status: 'not observed' });
    await chatInput.press('Enter');
    interactions.push({
      action: 'Pressed Enter key',
      result: 'Message submitted (no send button available)',
      timestamp: new Date().toISOString()
    });
  }
  
  await page.screenshot({ path: '/tmp/ux2_03_submitted.png', fullPage: true });
  screenshots.push('03_submitted.png');

  // Check for immediate loading indicator
  console.log('\n[STEP 5] Checking for loading indicator...');
  await page.waitForTimeout(500);
  
  const loadingIndicators = page.locator('[class*="loading"], [class*="spinner"], [class*="typing"], [data-testid*="loading"]');
  const loadingCount = await loadingIndicators.count();
  
  if (loadingCount > 0) {
    console.log(`✓ Loading indicator found (${loadingCount} elements)`);
    observedElements.push({ element: 'Loading/typing indicator', status: 'present', details: `${loadingCount} loading elements visible` });
  } else {
    console.log('✗ No loading indicator visible');
    observedElements.push({ element: 'Loading/typing indicator', status: 'not observed' });
  }

  // Extended wait strategy: 10s increments up to 120s
  console.log('\n[STEP 6] Waiting for AI response (10s increments, max 120s)...');
  
  let responseReceived = false;
  let totalWaitTime = 0;
  const maxWaitTime = 120000; // 120 seconds
  const checkInterval = 10000; // 10 seconds
  
  const initialBodyLength = (await page.locator('body').textContent())?.length || 0;
  console.log(`Initial body text length: ${initialBodyLength} characters`);
  
  for (let elapsed = 0; elapsed <= maxWaitTime; elapsed += checkInterval) {
    await page.waitForTimeout(checkInterval);
    totalWaitTime += checkInterval;
    
    const currentBodyLength = (await page.locator('body').textContent())?.length || 0;
    const lengthDiff = currentBodyLength - initialBodyLength;
    
    console.log(`[${totalWaitTime / 1000}s] Body length: ${currentBodyLength} (diff: ${lengthDiff})`);
    
    // Check if significant new content appeared
    if (lengthDiff > 100) {
      console.log(`✓ Response detected after ${totalWaitTime / 1000}s`);
      responseReceived = true;
      await page.waitForTimeout(2000); // Let animations finish
      break;
    }
    
    // Take periodic screenshots
    if (elapsed % 30000 === 0 && elapsed > 0) {
      await page.screenshot({ path: `/tmp/ux2_wait_${elapsed / 1000}s.png`, fullPage: true });
      screenshots.push(`wait_${elapsed / 1000}s.png`);
    }
  }
  
  if (!responseReceived) {
    console.log(`✗ No response after ${totalWaitTime / 1000}s`);
    interactions.push({
      action: 'Waited for AI response',
      result: `Timeout - no response after ${totalWaitTime / 1000}s`,
      timestamp: new Date().toISOString()
    });
    await page.screenshot({ path: '/tmp/ux2_04_timeout.png', fullPage: true });
    screenshots.push('04_timeout.png');
  } else {
    interactions.push({
      action: 'Waited for AI response',
      result: `Response received after ${totalWaitTime / 1000}s`,
      timestamp: new Date().toISOString()
    });
    await page.screenshot({ path: '/tmp/ux2_04_response.png', fullPage: true });
    screenshots.push('04_response.png');
  }

  // Check for workflow card and related elements
  console.log('\n[STEP 7] Inspecting workflow elements...');
  
  // Workflow card title
  const workflowTitles = page.locator('[class*="workflow"] h1, [class*="workflow"] h2, [class*="workflow"] h3, [data-testid*="workflow-title"]');
  const titleCount = await workflowTitles.count();
  if (titleCount > 0) {
    const titleText = await workflowTitles.first().textContent();
    console.log(`✓ Workflow card title found: "${titleText}"`);
    observedElements.push({ element: 'Workflow card title', status: 'present', details: titleText || 'Title visible' });
  } else {
    console.log('✗ Workflow card title not observed');
    observedElements.push({ element: 'Workflow card title', status: 'not observed' });
  }
  
  // Status badge (RUNNING/COMPLETED/FAILED)
  const statusBadges = page.locator('[class*="status"], [class*="badge"]');
  const statusCount = await statusBadges.count();
  if (statusCount > 0) {
    const statusTexts = [];
    for (let i = 0; i < Math.min(statusCount, 3); i++) {
      const text = await statusBadges.nth(i).textContent();
      if (text) statusTexts.push(text.trim());
    }
    console.log(`✓ Status badge(s) found: ${statusTexts.join(', ')}`);
    observedElements.push({ element: 'Status badge (RUNNING/COMPLETED/FAILED)', status: 'present', details: statusTexts.join(', ') });
  } else {
    console.log('✗ Status badge not observed');
    observedElements.push({ element: 'Status badge (RUNNING/COMPLETED/FAILED)', status: 'not observed' });
  }
  
  // Run button
  const runButtons = page.locator('button:has-text("Run"), button:has-text("Execute"), button:has-text("Start")');
  const runButtonCount = await runButtons.count();
  if (runButtonCount > 0) {
    const runButton = runButtons.first();
    const isEnabled = await runButton.isEnabled();
    const isVisible = await runButton.isVisible();
    const buttonText = await runButton.textContent();
    console.log(`✓ Run button found: "${buttonText}" (enabled: ${isEnabled}, visible: ${isVisible})`);
    observedElements.push({ 
      element: 'Run button', 
      status: 'present', 
      details: `"${buttonText}" - enabled: ${isEnabled}, visible: ${isVisible}` 
    });
  } else {
    console.log('✗ Run button not observed');
    observedElements.push({ element: 'Run button', status: 'not observed' });
  }
  
  // View/Hide results button
  const viewHideButtons = page.locator('button:has-text("View"), button:has-text("Hide"), button:has-text("Show Results"), button:has-text("Collapse")');
  const viewHideCount = await viewHideButtons.count();
  if (viewHideCount > 0) {
    const buttonTexts = [];
    for (let i = 0; i < Math.min(viewHideCount, 3); i++) {
      const text = await viewHideButtons.nth(i).textContent();
      if (text) buttonTexts.push(text.trim());
    }
    console.log(`✓ View/Hide results button(s) found: ${buttonTexts.join(', ')}`);
    observedElements.push({ element: 'View/Hide results button', status: 'present', details: buttonTexts.join(', ') });
  } else {
    console.log('✗ View/Hide results button not observed');
    observedElements.push({ element: 'View/Hide results button', status: 'not observed' });
  }
  
  // Download All button
  const downloadAllButtons = page.locator('button:has-text("Download All"), button:has-text("Download"), a[download]');
  const downloadAllCount = await downloadAllButtons.count();
  if (downloadAllCount > 0) {
    const downloadTexts = [];
    for (let i = 0; i < Math.min(downloadAllCount, 3); i++) {
      const text = await downloadAllButtons.nth(i).textContent();
      if (text) downloadTexts.push(text.trim());
    }
    console.log(`✓ Download button(s) found: ${downloadTexts.join(', ')}`);
    observedElements.push({ element: 'Download All button', status: 'present', details: downloadTexts.join(', ') });
  } else {
    console.log('✗ Download All button not observed');
    observedElements.push({ element: 'Download All button', status: 'not observed' });
  }
  
  // Report Confusion button
  const confusionButtons = page.locator('button:has-text("Report"), button:has-text("Confusion"), button:has-text("Feedback"), button:has-text("Issue")');
  const confusionCount = await confusionButtons.count();
  if (confusionCount > 0) {
    const confusionTexts = [];
    for (let i = 0; i < Math.min(confusionCount, 3); i++) {
      const text = await confusionButtons.nth(i).textContent();
      if (text) confusionTexts.push(text.trim());
    }
    console.log(`✓ Report/Feedback button(s) found: ${confusionTexts.join(', ')}`);
    observedElements.push({ element: 'Report Confusion button', status: 'present', details: confusionTexts.join(', ') });
  } else {
    console.log('✗ Report Confusion button not observed');
    observedElements.push({ element: 'Report Confusion button', status: 'not observed' });
  }
  
  // Inline helpful/not helpful buttons
  const helpfulButtons = page.locator('button:has-text("Helpful"), button:has-text("Not Helpful"), button[aria-label*="thumbs"], button:has-text("👍"), button:has-text("👎")');
  const helpfulCount = await helpfulButtons.count();
  if (helpfulCount > 0) {
    console.log(`✓ Helpful/Not Helpful button(s) found (${helpfulCount} buttons)`);
    observedElements.push({ element: 'Inline helpful/not helpful buttons', status: 'present', details: `${helpfulCount} feedback buttons` });
  } else {
    console.log('✗ Inline helpful/not helpful buttons not observed');
    observedElements.push({ element: 'Inline helpful/not helpful buttons', status: 'not observed' });
  }
  
  // Post-run survey/session pulse
  const surveyElements = page.locator('[class*="survey"], [class*="pulse"], [class*="feedback-form"]');
  const surveyCount = await surveyElements.count();
  if (surveyCount > 0) {
    console.log(`✓ Post-run survey/session pulse found`);
    observedElements.push({ element: 'Post-run survey/session pulse', status: 'present' });
  } else {
    console.log('✗ Post-run survey/session pulse not observed');
    observedElements.push({ element: 'Post-run survey/session pulse', status: 'not observed' });
  }

  // Attempt to run workflow if button is available
  console.log('\n[STEP 8] Attempting workflow execution...');
  
  if (runButtonCount > 0) {
    const runButton = runButtons.first();
    const isEnabled = await runButton.isEnabled();
    const isVisible = await runButton.isVisible();
    
    if (isEnabled && isVisible) {
      console.log('✓ Clicking Run button...');
      await runButton.click();
      interactions.push({
        action: 'Clicked Run button',
        result: 'Workflow execution initiated',
        timestamp: new Date().toISOString()
      });
      
      await page.waitForTimeout(2000);
      await page.screenshot({ path: '/tmp/ux2_05_run_clicked.png', fullPage: true });
      screenshots.push('05_run_clicked.png');
      
      // Observe state changes for 60 seconds
      console.log('Observing state changes for 60 seconds...');
      
      for (let i = 0; i < 6; i++) {
        await page.waitForTimeout(10000);
        const elapsed = (i + 1) * 10;
        
        // Check for status changes
        const currentStatus = await page.locator('[class*="status"], [class*="badge"]').first().textContent();
        console.log(`[${elapsed}s] Current status: ${currentStatus?.trim() || 'none'}`);
        
        // Check for progress indicators
        const progressBars = await page.locator('[class*="progress"], [role="progressbar"]').count();
        if (progressBars > 0) {
          const progressValue = await page.locator('[class*="progress"], [role="progressbar"]').first().getAttribute('value');
          console.log(`[${elapsed}s] Progress: ${progressValue || 'unknown'}`);
        }
        
        // Take screenshots at 20s, 40s, 60s
        if (elapsed % 20 === 0) {
          await page.screenshot({ path: `/tmp/ux2_exec_${elapsed}s.png`, fullPage: true });
          screenshots.push(`exec_${elapsed}s.png`);
        }
        
        // Check for completion
        const completionIndicators = await page.locator('text=/COMPLETED|SUCCESS|FINISHED/i').count();
        if (completionIndicators > 0) {
          console.log(`✓ Workflow completed at ${elapsed}s`);
          interactions.push({
            action: 'Workflow execution',
            result: `Completed after ${elapsed}s`,
            timestamp: new Date().toISOString()
          });
          break;
        }
        
        // Check for failure
        const failureIndicators = await page.locator('text=/FAILED|ERROR/i').count();
        if (failureIndicators > 0) {
          console.log(`✗ Workflow failed at ${elapsed}s`);
          interactions.push({
            action: 'Workflow execution',
            result: `Failed after ${elapsed}s`,
            timestamp: new Date().toISOString()
          });
          break;
        }
      }
      
      await page.screenshot({ path: '/tmp/ux2_06_final_state.png', fullPage: true });
      screenshots.push('06_final_state.png');
      
    } else {
      console.log(`✗ Run button not clickable (enabled: ${isEnabled}, visible: ${isVisible})`);
      interactions.push({
        action: 'Attempted to click Run button',
        result: `Button not clickable - enabled: ${isEnabled}, visible: ${isVisible}`,
        timestamp: new Date().toISOString()
      });
    }
  } else {
    console.log('✗ Cannot execute - no Run button available');
    interactions.push({
      action: 'Attempted workflow execution',
      result: 'No Run button available',
      timestamp: new Date().toISOString()
    });
  }

  // Test View/Hide functionality if available
  console.log('\n[STEP 9] Testing View/Hide functionality...');
  
  if (viewHideCount > 0) {
    const viewHideButton = viewHideButtons.first();
    const initialText = await viewHideButton.textContent();
    console.log(`✓ Clicking View/Hide button: "${initialText}"`);
    
    await viewHideButton.click();
    await page.waitForTimeout(1000);
    
    const newText = await viewHideButton.textContent();
    const textChanged = initialText !== newText;
    
    console.log(`Button text after click: "${newText}" (changed: ${textChanged})`);
    interactions.push({
      action: `Clicked View/Hide button ("${initialText}")`,
      result: `Button text: "${newText}", state toggled: ${textChanged}`,
      timestamp: new Date().toISOString()
    });
    
    await page.screenshot({ path: '/tmp/ux2_07_view_toggled.png', fullPage: true });
    screenshots.push('07_view_toggled.png');
  }

  // Final screenshot
  await page.screenshot({ path: '/tmp/ux2_08_final.png', fullPage: true });
  screenshots.push('08_final.png');

  // Determine confidence level
  const presentCount = observedElements.filter(e => e.status === 'present').length;
  const totalElements = observedElements.length;
  const interactionCount = interactions.length;
  
  let confidenceLevel: 'high' | 'medium' | 'low';
  let confidenceReason: string;
  
  if (responseReceived && runButtonCount > 0 && presentCount > totalElements * 0.6) {
    confidenceLevel = 'high';
    confidenceReason = `Response received, ${presentCount}/${totalElements} elements observed, ${interactionCount} interactions completed`;
  } else if (responseReceived || presentCount > totalElements * 0.4) {
    confidenceLevel = 'medium';
    confidenceReason = `Partial observation: ${presentCount}/${totalElements} elements found, ${interactionCount} interactions attempted`;
  } else {
    confidenceLevel = 'low';
    confidenceReason = `Limited observation: only ${presentCount}/${totalElements} elements found, response timeout`;
  }

  // Generate final report
  generateReport(observedElements, interactions, screenshots, confidenceLevel, confidenceReason);
});

function generateReport(
  observedElements: ObservedElement[],
  interactions: InteractionOutcome[],
  screenshots: string[],
  confidenceLevel: 'high' | 'medium' | 'low',
  confidenceReason: string
) {
  console.log('\n' + '='.repeat(80));
  console.log('BIOMATE SECOND-PASS UX REVIEW - FINAL REPORT');
  console.log('='.repeat(80));
  
  // Section 1: Observed UI Elements
  console.log('\n## 1) OBSERVED UI ELEMENTS');
  console.log('-'.repeat(80));
  
  const presentElements = observedElements.filter(e => e.status === 'present');
  const notObservedElements = observedElements.filter(e => e.status === 'not observed');
  
  console.log('\n### PRESENT:');
  if (presentElements.length > 0) {
    presentElements.forEach(e => {
      console.log(`✓ ${e.element}`);
      if (e.details) console.log(`  Details: ${e.details}`);
    });
  } else {
    console.log('(None)');
  }
  
  console.log('\n### NOT OBSERVED:');
  if (notObservedElements.length > 0) {
    notObservedElements.forEach(e => {
      console.log(`✗ ${e.element}`);
    });
  } else {
    console.log('(None - all elements present)');
  }
  
  // Section 2: Interaction Outcomes
  console.log('\n## 2) INTERACTION OUTCOMES');
  console.log('-'.repeat(80));
  
  if (interactions.length > 0) {
    interactions.forEach((interaction, idx) => {
      console.log(`\n${idx + 1}. ${interaction.action}`);
      console.log(`   Result: ${interaction.result}`);
      console.log(`   Time: ${interaction.timestamp}`);
    });
  } else {
    console.log('(No interactions completed)');
  }
  
  // Section 3: UX Findings
  console.log('\n## 3) UX FINDINGS');
  console.log('-'.repeat(80));
  
  console.log('\n### CLEAR:');
  const clearFindings: string[] = [];
  
  if (presentElements.some(e => e.element === 'Chat input field')) {
    clearFindings.push('Chat input is immediately visible and accessible');
  }
  if (presentElements.some(e => e.element === 'Workflow card title')) {
    clearFindings.push('Workflow is presented as a distinct visual element with title');
  }
  if (presentElements.some(e => e.element === 'Status badge (RUNNING/COMPLETED/FAILED)')) {
    clearFindings.push('Workflow status is clearly indicated with badge');
  }
  if (presentElements.some(e => e.element === 'Run button')) {
    clearFindings.push('Run button is available for workflow execution');
  }
  
  if (clearFindings.length > 0) {
    clearFindings.forEach(f => console.log(`✓ ${f}`));
  } else {
    console.log('(Limited clear elements observed)');
  }
  
  console.log('\n### CONFUSING:');
  const confusingFindings: string[] = [];
  
  if (notObservedElements.some(e => e.element === 'Send button')) {
    confusingFindings.push('No visible Send button - users must discover Enter key');
  }
  if (notObservedElements.some(e => e.element === 'Loading/typing indicator')) {
    confusingFindings.push('No loading indicator after submission - unclear if request was received');
  }
  if (notObservedElements.some(e => e.element === 'Inline helpful/not helpful buttons')) {
    confusingFindings.push('No feedback mechanism for users to rate AI responses');
  }
  if (notObservedElements.some(e => e.element === 'Report Confusion button')) {
    confusingFindings.push('No way to report issues or confusion during workflow');
  }
  
  if (confusingFindings.length > 0) {
    confusingFindings.forEach(f => console.log(`⚠ ${f}`));
  } else {
    console.log('(No confusing elements identified)');
  }
  
  console.log('\n### BROKEN/RISKY:');
  const brokenFindings: string[] = [];
  
  const timeoutInteraction = interactions.find(i => i.result.includes('Timeout'));
  if (timeoutInteraction) {
    brokenFindings.push('AI response timeout - users wait indefinitely without response');
  }
  
  const disabledRunButton = interactions.find(i => i.result.includes('not clickable'));
  if (disabledRunButton) {
    brokenFindings.push('Run button disabled without explanation of prerequisites');
  }
  
  const failedExecution = interactions.find(i => i.result.includes('Failed'));
  if (failedExecution) {
    brokenFindings.push('Workflow execution failed - error state observed');
  }
  
  if (brokenFindings.length > 0) {
    brokenFindings.forEach(f => console.log(`✗ ${f}`));
  } else {
    console.log('(No broken or risky issues observed)');
  }
  
  // Section 4: Confidence Level
  console.log('\n## 4) CONFIDENCE LEVEL');
  console.log('-'.repeat(80));
  console.log(`\nLevel: ${confidenceLevel.toUpperCase()}`);
  console.log(`\nReason: ${confidenceReason}`);
  
  console.log('\n' + '='.repeat(80));
  console.log(`Screenshots captured: ${screenshots.length} files in /tmp/ux2_*.png`);
  console.log(`Elements observed: ${presentElements.length}/${observedElements.length}`);
  console.log(`Interactions completed: ${interactions.length}`);
  console.log('='.repeat(80) + '\n');
}
