import { setupTestUser } from "./helpers.js";
import { test, expect, Page } from '@playwright/test';

interface VerificationResult {
  improvement: string;
  status: 'present' | 'not observed';
  details?: string;
}

test('BioMate UX Improvements Verification', async ({ page }) => {
    await setupTestUser(page, "ux_impr");
  const confirmed: VerificationResult[] = [];
  const missing: VerificationResult[] = [];

  console.log('\n' + '='.repeat(80));
  console.log('BIOMATE UX IMPROVEMENTS VERIFICATION');
  console.log('URL: http://localhost:5310');
  console.log('='.repeat(80) + '\n');

  // Step 1: Open app
  console.log('[STEP 1] Opening application...');
  await page.goto(process.env.BIOMATE_URL || 'http://localhost:5000', { waitUntil: 'networkidle', timeout: 15000 });
  await page.waitForTimeout(2000);
  await page.screenshot({ path: '/tmp/verify_01_loaded.png', fullPage: true });
  console.log('✓ Application loaded\n');

  // Step 2: Confirm send affordance
  console.log('[STEP 2] Checking send affordance...');
  
  // Check for visible send button
  const sendButton = page.locator('button:has-text("Send"), button[type="submit"], button[aria-label*="send" i]').first();
  const sendButtonCount = await sendButton.count();
  
  if (sendButtonCount > 0) {
    const isVisible = await sendButton.isVisible();
    const buttonText = await sendButton.textContent();
    const ariaLabel = await sendButton.getAttribute('aria-label');
    
    if (isVisible) {
      console.log(`✓ Send button found: "${buttonText || ariaLabel}"`);
      confirmed.push({
        improvement: 'Visible Send button',
        status: 'present',
        details: `Button text: "${buttonText?.trim() || ariaLabel || 'icon only'}"`
      });
    } else {
      console.log('✗ Send button exists but not visible');
      missing.push({
        improvement: 'Visible Send button',
        status: 'not observed',
        details: 'Button in DOM but not visible'
      });
    }
  } else {
    console.log('✗ No Send button found');
    missing.push({
      improvement: 'Visible Send button',
      status: 'not observed',
      details: 'No send button in DOM'
    });
  }
  
  // Check for Enter/Shift+Enter helper hint
  const enterHints = page.locator('text=/Enter to send|Press Enter|Shift.*Enter|⏎/i');
  const hintCount = await enterHints.count();
  
  if (hintCount > 0) {
    const hintText = await enterHints.first().textContent();
    console.log(`✓ Keyboard hint found: "${hintText}"`);
    confirmed.push({
      improvement: 'Enter/Shift+Enter helper hint',
      status: 'present',
      details: hintText || 'Hint visible'
    });
  } else {
    console.log('✗ No Enter/Shift+Enter helper hint found');
    missing.push({
      improvement: 'Enter/Shift+Enter helper hint',
      status: 'not observed',
      details: 'No keyboard shortcut hint visible'
    });
  }
  
  await page.screenshot({ path: '/tmp/verify_02_send_affordance.png', fullPage: true });
  console.log('');

  // Step 3: Submit prompt
  console.log('[STEP 3] Submitting workflow request...');
  const chatInput = page.locator('textarea, input[type="text"], [contenteditable="true"]').first();
  
  if (await chatInput.count() === 0) {
    console.log('✗ CRITICAL: No chat input found');
    generateReport(confirmed, missing);
    return;
  }
  
  const prompt = 'Build me a quality control workflow for RNA-seq FASTQ files';
  await chatInput.click();
  await chatInput.fill(prompt);
  console.log(`✓ Typed: "${prompt}"`);
  
  await page.screenshot({ path: '/tmp/verify_03_typed.png', fullPage: true });
  
  // Submit via button if available, otherwise Enter
  if (sendButtonCount > 0 && await sendButton.isVisible()) {
    await sendButton.click();
    console.log('✓ Clicked Send button');
  } else {
    await chatInput.press('Enter');
    console.log('✓ Pressed Enter');
  }
  
  await page.screenshot({ path: '/tmp/verify_04_submitted.png', fullPage: true });
  console.log('');

  // Step 4: Check for pending-response UI immediately
  console.log('[STEP 4] Checking for pending-response UI...');
  await page.waitForTimeout(500); // Give UI time to update
  
  // Check for spinner/loading indicator
  const spinners = page.locator('[class*="spinner"], [class*="loading"], [role="status"], [aria-busy="true"]');
  const spinnerCount = await spinners.count();
  
  if (spinnerCount > 0) {
    console.log(`✓ Loading spinner found (${spinnerCount} elements)`);
    confirmed.push({
      improvement: 'Loading spinner during AI response',
      status: 'present',
      details: `${spinnerCount} loading indicators visible`
    });
  } else {
    console.log('✗ No loading spinner found');
    missing.push({
      improvement: 'Loading spinner during AI response',
      status: 'not observed',
      details: 'No spinner or loading indicator visible'
    });
  }
  
  // Check for "generating response" text
  const generatingText = page.locator('text=/generating|thinking|processing|working/i');
  const generatingCount = await generatingText.count();
  
  if (generatingCount > 0) {
    const statusText = await generatingText.first().textContent();
    console.log(`✓ Status text found: "${statusText}"`);
    confirmed.push({
      improvement: 'Status text about generating response',
      status: 'present',
      details: statusText || 'Status message visible'
    });
  } else {
    console.log('✗ No "generating response" text found');
    missing.push({
      improvement: 'Status text about generating response',
      status: 'not observed',
      details: 'No status message visible'
    });
  }
  
  await page.screenshot({ path: '/tmp/verify_05_pending.png', fullPage: true });
  console.log('');

  // Wait for response
  console.log('[STEP 5] Waiting for AI response (max 60s)...');
  const initialLength = (await page.locator('body').textContent())?.length || 0;
  let responseReceived = false;
  
  for (let i = 0; i < 12; i++) {
    await page.waitForTimeout(5000);
    const currentLength = (await page.locator('body').textContent())?.length || 0;
    
    if (currentLength > initialLength + 100) {
      console.log(`✓ Response received after ${(i + 1) * 5}s`);
      responseReceived = true;
      await page.waitForTimeout(2000);
      break;
    }
  }
  
  if (!responseReceived) {
    console.log('✗ No response after 60s');
    generateReport(confirmed, missing);
    return;
  }
  
  await page.screenshot({ path: '/tmp/verify_06_response.png', fullPage: true });
  console.log('');

  // Step 5: Click Run Workflow
  console.log('[STEP 6] Clicking Run Workflow...');
  const runButton = page.locator('button:has-text("Run Workflow"), button:has-text("Run")').first();
  
  if (await runButton.count() === 0) {
    console.log('✗ No Run Workflow button found');
    generateReport(confirmed, missing);
    return;
  }
  
  if (!await runButton.isEnabled()) {
    console.log('✗ Run button is disabled');
    generateReport(confirmed, missing);
    return;
  }
  
  await runButton.click();
  console.log('✓ Clicked Run Workflow');
  await page.waitForTimeout(2000);
  await page.screenshot({ path: '/tmp/verify_07_running.png', fullPage: true });
  console.log('');

  // Step 6: Check for execution progress cues
  console.log('[STEP 7] Checking execution progress cues...');
  
  // Check for "Last update" timestamp
  const lastUpdateText = page.locator('text=/last update|updated|ago/i');
  const lastUpdateCount = await lastUpdateText.count();
  
  if (lastUpdateCount > 0) {
    const updateText = await lastUpdateText.first().textContent();
    console.log(`✓ "Last update" found: "${updateText}"`);
    confirmed.push({
      improvement: '"Last update" timestamp',
      status: 'present',
      details: updateText || 'Timestamp visible'
    });
  } else {
    console.log('✗ No "Last update" timestamp found');
    missing.push({
      improvement: '"Last update" timestamp',
      status: 'not observed',
      details: 'No timestamp visible'
    });
  }
  
  // Check for running hint message
  const runningHints = page.locator('text=/running|executing|in progress|processing/i');
  const runningHintCount = await runningHints.count();
  
  if (runningHintCount > 0) {
    const hintText = await runningHints.first().textContent();
    console.log(`✓ Running hint found: "${hintText}"`);
    confirmed.push({
      improvement: 'Running hint message',
      status: 'present',
      details: hintText || 'Hint visible'
    });
  } else {
    console.log('✗ No running hint message found');
    missing.push({
      improvement: 'Running hint message',
      status: 'not observed',
      details: 'No execution hint visible'
    });
  }
  
  // Check for progress indicator
  const progressBars = page.locator('[class*="progress"], [role="progressbar"]');
  const progressCount = await progressBars.count();
  
  if (progressCount > 0) {
    console.log(`✓ Progress indicator found (${progressCount} elements)`);
    confirmed.push({
      improvement: 'Progress indicator during execution',
      status: 'present',
      details: `${progressCount} progress elements visible`
    });
  } else {
    console.log('✗ No progress indicator found');
    missing.push({
      improvement: 'Progress indicator during execution',
      status: 'not observed',
      details: 'No progress bar or percentage visible'
    });
  }
  
  // Check for status badge
  const statusBadges = page.locator('[class*="status"], [class*="badge"]');
  const badgeCount = await statusBadges.count();
  
  if (badgeCount > 0) {
    const badgeText = await statusBadges.first().textContent();
    console.log(`✓ Status badge found: "${badgeText}"`);
    confirmed.push({
      improvement: 'Status badge (RUNNING/COMPLETED)',
      status: 'present',
      details: badgeText || 'Badge visible'
    });
  }
  
  await page.screenshot({ path: '/tmp/verify_08_progress.png', fullPage: true });
  
  // Wait a bit to see if status changes
  await page.waitForTimeout(10000);
  await page.screenshot({ path: '/tmp/verify_09_final.png', fullPage: true });
  
  console.log('');
  generateReport(confirmed, missing);
});

function generateReport(confirmed: VerificationResult[], missing: VerificationResult[]) {
  console.log('\n' + '='.repeat(80));
  console.log('UX IMPROVEMENTS VERIFICATION REPORT');
  console.log('='.repeat(80));
  
  console.log('\n## CONFIRMED IMPROVEMENTS (Present)');
  console.log('-'.repeat(80));
  if (confirmed.length > 0) {
    confirmed.forEach((item, idx) => {
      console.log(`${idx + 1}. ✓ ${item.improvement}`);
      if (item.details) {
        console.log(`   Details: ${item.details}`);
      }
    });
  } else {
    console.log('(No improvements confirmed)');
  }
  
  console.log('\n## STILL-MISSING CUES (Not Observed)');
  console.log('-'.repeat(80));
  if (missing.length > 0) {
    missing.forEach((item, idx) => {
      console.log(`${idx + 1}. ✗ ${item.improvement}`);
      if (item.details) {
        console.log(`   Details: ${item.details}`);
      }
    });
  } else {
    console.log('(All expected improvements are present)');
  }
  
  console.log('\n## REAL-USER VERDICT');
  console.log('-'.repeat(80));
  
  const totalExpected = confirmed.length + missing.length;
  const percentPresent = totalExpected > 0 ? Math.round((confirmed.length / totalExpected) * 100) : 0;
  
  let verdict = '';
  
  if (percentPresent >= 80) {
    verdict = `The BioMate application shows significant UX improvements with ${confirmed.length} out of ${totalExpected} expected enhancements present (${percentPresent}%). Users now have clear visual feedback during AI response generation and workflow execution, making the application feel responsive and trustworthy. The addition of send button affordances, loading indicators, and progress cues addresses the primary pain points from previous testing. The experience is now production-ready for real users, though ${missing.length} minor improvements could still enhance the experience further.`;
  } else if (percentPresent >= 50) {
    verdict = `The application shows moderate improvement with ${confirmed.length} out of ${totalExpected} expected enhancements present (${percentPresent}%). While some critical feedback mechanisms are now in place, ${missing.length} important cues are still missing. Users will have a better experience than before, but the application would benefit from implementing the remaining improvements before broader deployment. The current state is acceptable for beta testing but needs refinement for production use.`;
  } else {
    verdict = `The application shows limited improvement with only ${confirmed.length} out of ${totalExpected} expected enhancements present (${percentPresent}%). Critical feedback mechanisms are still missing, which means users will continue to experience confusion during AI response waits and workflow execution. The ${missing.length} missing improvements are essential for a good user experience. Additional development work is needed before the application is ready for real user testing.`;
  }
  
  console.log(verdict);
  
  console.log('\n' + '='.repeat(80));
  console.log(`Improvements confirmed: ${confirmed.length}`);
  console.log(`Still missing: ${missing.length}`);
  console.log(`Success rate: ${percentPresent}%`);
  console.log('Screenshots saved to /tmp/verify_*.png');
  console.log('='.repeat(80) + '\n');
}
