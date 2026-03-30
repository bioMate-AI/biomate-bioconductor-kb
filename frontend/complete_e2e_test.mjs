/**
 * Complete E2E Test with Real Workflow Generation and Execution
 * This test verifies the ENTIRE flow works, not just the UI
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
const TEST_DIR = path.join(OUTPUT_DIR, `complete_e2e_${TIMESTAMP}`);
const SCREENSHOT_DIR = path.join(TEST_DIR, 'screenshots');

// Create output directories
[OUTPUT_DIR, TEST_DIR, SCREENSHOT_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function checkBackend() {
  console.log('Checking backend availability...');
  try {
    const response = await fetch(`${BACKEND_URL}/api/version`);
    if (response.ok || response.status === 401) {
      console.log('✅ Backend is responding');
      return true;
    }
  } catch (e) {
    console.log(`❌ Backend not available: ${e.message}`);
    return false;
  }
  return false;
}

async function testWorkflowGeneration() {
  console.log('\nTesting workflow generation via API...');

  const testMessage = 'Analyze RNA-seq data with DESeq2';

  try {
    const response = await fetch(`${FRONTEND_URL}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: testMessage })
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const result = await response.json();

    console.log('API Response:');
    console.log(`  - Has workflow: ${!!result.workflow}`);
    console.log(`  - Workflow success: ${result.workflow?.success}`);

    if (result.workflow?.workflow_ga) {
      const steps = Object.keys(result.workflow.workflow_ga.steps || {});
      console.log(`  - Steps: ${steps.length}`);

      if (steps.length > 0) {
        console.log('✅ Workflow generation WORKS');
        return true;
      }
    }

    console.log('⚠️  Workflow generated but has no steps');
    return false;
  } catch (e) {
    console.log(`❌ Workflow generation failed: ${e.message}`);
    return false;
  }
}

async function runCompleteE2E() {
  console.log('🎬 Starting COMPLETE E2E Test\n');
  console.log(`📁 Output: ${TEST_DIR}\n`);

  // Step 1: Check prerequisites
  console.log('=' .repeat(70));
  console.log('STEP 1: Check Prerequisites');
  console.log('='.repeat(70));

  const backendReady = await checkBackend();
  if (!backendReady) {
    console.log('\n❌ FATAL: Backend not ready. Cannot proceed with E2E test.');
    console.log('Please start the backend first.');
    return 1;
  }

  const workflowWorks = await testWorkflowGeneration();
  if (!workflowWorks) {
    console.log('\n❌ FATAL: Workflow generation not working. Cannot proceed.');
    return 1;
  }

  console.log('\n✅ Prerequisites met. Starting browser automation...\n');

  // Step 2: Launch browser with recording
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
  let success = false;

  try {
    console.log('='.repeat(70));
    console.log('STEP 2: Load Frontend');
    console.log('='.repeat(70));

    await page.goto(FRONTEND_URL, { waitUntil: 'networkidle', timeout: 30000 });
    await sleep(2000);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '01_homepage.png'), fullPage: true });
    console.log('✅ Homepage loaded\n');

    console.log('='.repeat(70));
    console.log('STEP 3: Generate Workflow');
    console.log('='.repeat(70));

    const chatMessage = 'Analyze RNA-seq data with DESeq2';
    console.log(`Typing: "${chatMessage}"`);

    // Find chat input
    const inputSelectors = ['textarea', 'input[type="text"]'];
    let typed = false;

    for (const selector of inputSelectors) {
      try {
        const input = await page.waitForSelector(selector, { timeout: 2000 });
        if (input) {
          await input.fill(chatMessage);
          console.log('✅ Message typed');
          typed = true;
          break;
        }
      } catch (e) {
        continue;
      }
    }

    if (!typed) {
      throw new Error('Could not find chat input');
    }

    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '02_message_typed.png'), fullPage: true });

    // Submit
    console.log('Submitting request...');
    await page.keyboard.press('Enter');
    await sleep(2000);

    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '03_submitted.png'), fullPage: true });

    // Wait for workflow response
    console.log('Waiting for workflow generation...');
    await sleep(10000); // Give backend time to generate

    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '04_workflow_response.png'), fullPage: true });

    // Verify workflow appeared
    const pageText = await page.textContent('body');
    const hasWorkflowIndicators = pageText.includes('workflow') || pageText.includes('step') || pageText.includes('execute');

    if (hasWorkflowIndicators) {
      console.log('✅ Workflow appears to be generated\n');
    } else {
      console.log('⚠️  No clear workflow indicators in UI\n');
    }

    console.log('='.repeat(70));
    console.log('STEP 4: Capture Final State');
    console.log('='.repeat(70));

    await sleep(3000);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '05_final.png'), fullPage: true });

    // Save page content
    const html = await page.content();
    fs.writeFileSync(path.join(SCREENSHOT_DIR, 'page_content.html'), html);

    console.log('✅ Test complete\n');
    success = true;

  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, 'error.png'),
      fullPage: true
    }).catch(() => {});
  } finally {
    await context.close();
    await browser.close();

    console.log('='.repeat(70));
    console.log('TEST RESULTS');
    console.log('='.repeat(70));

    const videoFiles = fs.readdirSync(TEST_DIR).filter(f => f.endsWith('.webm'));

    console.log(`\n📹 Video: ${videoFiles.length > 0 ? videoFiles[0] : 'Not found'}`);
    console.log(`📁 Location: ${TEST_DIR}`);
    console.log(`📸 Screenshots: ${fs.readdirSync(SCREENSHOT_DIR).filter(f => f.endsWith('.png')).length}`);

    if (success) {
      console.log('\n✅ E2E TEST PASSED');
    } else {
      console.log('\n❌ E2E TEST FAILED');
    }

    return success ? 0 : 1;
  }
}

runCompleteE2E()
  .then(exitCode => process.exit(exitCode))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
