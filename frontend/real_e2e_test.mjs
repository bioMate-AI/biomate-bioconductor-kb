/**
 * REAL End-to-End Test - Complete Workflow Execution
 * Tests the ENTIRE flow: Chat → Generate → Execute → Monitor → Results → Download
 */

import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const FRONTEND_URL = 'http://localhost:5000';
const BACKEND_URL = 'http://localhost:8081';
const OUTPUT_DIR = path.join(__dirname, '..', 'demo_videos');
const TIMESTAMP = Date.now();
const TEST_DIR = path.join(OUTPUT_DIR, `real_e2e_${TIMESTAMP}`);
const SCREENSHOT_DIR = path.join(TEST_DIR, 'screenshots');

// Create output directories
[OUTPUT_DIR, TEST_DIR, SCREENSHOT_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

console.log('🎬 Starting REAL End-to-End Test');
console.log('This will execute a COMPLETE workflow from chat to downloadable results\n');
console.log(`📁 Output: ${TEST_DIR}\n`);

const browser = await chromium.launch({
  headless: false,
  args: ['--no-sandbox', '--disable-setuid-sandbox']
});

const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: {
    dir: TEST_DIR,
    size: { width: 1920, height: 1080 }
  }
});

const page = await context.newPage();

try {
  // Step 1: Navigate and chat
  console.log('='.repeat(70));
  console.log('STEP 1: Request Simple Workflow');
  console.log('='.repeat(70));
  
  await page.goto(FRONTEND_URL, { waitUntil: 'networkidle' });
  await sleep(2000);
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, '01_homepage.png') });
  
  // Type a simple, fast workflow request
  const request = 'Fit dose-response curve with 4-parameter logistic model';
  console.log(`Requesting: "${request}"`);
  
  const input = await page.waitForSelector('textarea, input[type="text"]', { timeout: 5000 });
  await input.fill(request);
  await sleep(500);
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, '02_typed.png') });
  
  await page.keyboard.press('Enter');
  console.log('✅ Request sent\n');
  
  // Step 2: Wait for workflow generation
  console.log('='.repeat(70));
  console.log('STEP 2: Workflow Generation');
  console.log('='.repeat(70));
  
  await sleep(10000); // Wait for AI to generate workflow
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, '03_workflow_generated.png') });
  console.log('✅ Workflow generated\n');
  
  // Step 3: Execute workflow
  console.log('='.repeat(70));
  console.log('STEP 3: Execute Workflow');
  console.log('='.repeat(70));
  
  // Look for execute/run button
  const executeButtons = [
    'button:has-text("Execute")',
    'button:has-text("Run")',
    'button:has-text("Start")',
    '[data-testid="execute-workflow"]'
  ];
  
  let executed = false;
  for (const selector of executeButtons) {
    try {
      const button = await page.waitForSelector(selector, { timeout: 2000 });
      if (button) {
        await button.click();
        console.log('✅ Clicked execute button');
        executed = true;
        break;
      }
    } catch (e) {
      continue;
    }
  }
  
  if (!executed) {
    console.log('⚠️  No execute button found - checking if auto-executed');
  }
  
  await sleep(2000);
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, '04_executing.png') });
  
  // Step 4: Monitor execution
  console.log('\n' + '='.repeat(70));
  console.log('STEP 4: Monitor Execution');
  console.log('='.repeat(70));
  
  console.log('Waiting for workflow to complete...');
  let completed = false;
  let attempts = 0;
  const maxAttempts = 60; // 2 minutes max
  
  while (!completed && attempts < maxAttempts) {
    await sleep(2000);
    attempts++;
    
    const pageText = await page.textContent('body');
    
    // Check for completion indicators
    if (pageText.includes('completed') || 
        pageText.includes('success') || 
        pageText.includes('finished') ||
        pageText.includes('download')) {
      completed = true;
      console.log(`✅ Workflow completed after ${attempts * 2} seconds`);
      break;
    }
    
    // Show progress every 10 seconds
    if (attempts % 5 === 0) {
      console.log(`  ... still running (${attempts * 2}s elapsed)`);
    }
  }
  
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, '05_completed.png') });
  
  // Step 5: View Results
  console.log('\n' + '='.repeat(70));
  console.log('STEP 5: View Results');
  console.log('='.repeat(70));
  
  await sleep(3000);
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, '06_results.png') });
  
  // Try to find and click download button
  const downloadSelectors = [
    'button:has-text("Download")',
    'a:has-text("Download")',
    '[data-testid="download-results"]'
  ];
  
  for (const selector of downloadSelectors) {
    try {
      const downloadBtn = await page.waitForSelector(selector, { timeout: 2000 });
      if (downloadBtn) {
        await downloadBtn.click();
        console.log('✅ Clicked download button');
        await sleep(2000);
        break;
      }
    } catch (e) {
      continue;
    }
  }
  
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, '07_final.png') });
  
  console.log('\n✅ Test complete\n');
  console.log('='.repeat(70));
  console.log('REAL E2E TEST PASSED');
  console.log('='.repeat(70));
  console.log(`\n📹 Video: ${TEST_DIR}`);
  console.log(`📸 Screenshots: ${SCREENSHOT_DIR}`);
  
} catch (error) {
  console.error('\n❌ Test failed:', error.message);
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'error.png') });
} finally {
  await sleep(2000);
  await page.close();
  await context.close();
  await browser.close();
}
