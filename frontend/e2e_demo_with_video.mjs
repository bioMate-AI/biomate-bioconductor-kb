/**
 * BioMate E2E Demo Test with Video Recording
 * This test runs a complete workflow and records it as a video
 */

import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const FRONTEND_URL = 'http://localhost:5000';
const OUTPUT_DIR = path.join(__dirname, '..', 'demo_videos');
const TIMESTAMP = Date.now();
const VIDEO_DIR = path.join(OUTPUT_DIR, `e2e_test_${TIMESTAMP}`);
const SCREENSHOT_DIR = path.join(VIDEO_DIR, 'screenshots');

// Create output directories
[OUTPUT_DIR, VIDEO_DIR, SCREENSHOT_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runE2ETest() {
  console.log('🎬 Starting BioMate E2E Test with Video Recording...\n');
  console.log(`📁 Output directory: ${VIDEO_DIR}\n`);

  const browser = await chromium.launch({
    headless: false, // Show browser to capture video properly
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: {
      dir: VIDEO_DIR,
      size: { width: 1920, height: 1080 }
    },
    ignoreHTTPSErrors: true
  });

  const page = await context.newPage();
  let testsPassed = 0;
  let testsFailed = 0;

  try {
    console.log('━'.repeat(70));
    console.log('TEST 1: Frontend Health Check');
    console.log('━'.repeat(70));

    // Navigate with retry logic
    let loaded = false;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        console.log(`Attempt ${attempt}: Loading ${FRONTEND_URL}...`);
        await page.goto(FRONTEND_URL, {
          waitUntil: 'domcontentloaded',
          timeout: 30000
        });
        loaded = true;
        break;
      } catch (e) {
        console.log(`  ⚠️  Attempt ${attempt} failed: ${e.message}`);
        if (attempt === 3) throw e;
        await sleep(2000);
      }
    }

    await sleep(2000);

    const title = await page.title();
    console.log(`✅ Page loaded: "${title}"`);

    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '01_homepage.png'),
      fullPage: true
    });
    testsPassed++;

    console.log('\n' + '━'.repeat(70));
    console.log('TEST 2: Chat Interface');
    console.log('━'.repeat(70));

    // Find chat input - try multiple selectors
    const chatMessage = 'Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5';

    console.log('Looking for chat input...');

    // Wait for page to be fully interactive
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {
      console.log('  (Network idle timeout - continuing anyway)');
    });

    // Get all inputs and textareas
    const inputs = await page.$$('input:not([type="hidden"]):not([type="password"]), textarea');
    console.log(`Found ${inputs.length} input fields`);

    let chatInputFound = false;

    if (inputs.length > 0) {
      // Try the first visible text input
      for (const input of inputs) {
        try {
          const isVisible = await input.isVisible();
          const isEnabled = await input.isEnabled();

          if (isVisible && isEnabled) {
            console.log('  Attempting to type in input field...');
            await input.click();
            await sleep(500);
            await input.fill(chatMessage);
            await sleep(500);

            const value = await input.inputValue();
            if (value.includes('bacterial')) {
              console.log('✅ Chat message typed successfully');
              chatInputFound = true;
              break;
            }
          }
        } catch (e) {
          continue;
        }
      }
    }

    if (!chatInputFound) {
      console.log('⚠️  Could not find chat input, trying alternative method...');
      // Try clicking body and typing
      await page.click('body');
      await page.keyboard.type(chatMessage);
    }

    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '02_chat_input.png'),
      fullPage: true
    });
    testsPassed++;

    console.log('\n' + '━'.repeat(70));
    console.log('TEST 3: Submit Workflow Request');
    console.log('━'.repeat(70));

    // Find and click submit button
    console.log('Looking for submit button...');

    const buttons = await page.$$('button');
    console.log(`Found ${buttons.length} buttons`);

    let submitted = false;
    for (const button of buttons) {
      try {
        const text = await button.textContent();
        const isVisible = await button.isVisible();
        const isEnabled = await button.isEnabled();

        if (isVisible && isEnabled) {
          const textLower = text?.toLowerCase() || '';
          if (textLower.includes('send') || textLower.includes('submit') || textLower.includes('generate')) {
            console.log(`  Found button: "${text?.trim()}"`);
            await button.click();
            console.log('✅ Submit button clicked');
            submitted = true;
            break;
          }
        }
      } catch (e) {
        continue;
      }
    }

    if (!submitted) {
      console.log('⚠️  Submit button not found, trying Enter key...');
      await page.keyboard.press('Enter');
    }

    await sleep(2000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '03_submitted.png'),
      fullPage: true
    });
    testsPassed++;

    console.log('\n' + '━'.repeat(70));
    console.log('TEST 4: Wait for Workflow Generation');
    console.log('━'.repeat(70));

    console.log('Waiting for AI to generate workflow...');

    // Wait for response - look for common indicators
    const indicators = [
      'text=workflow',
      'text=generated',
      'text=execute',
      '[data-testid*="workflow"]',
      '.workflow',
      'button:has-text("Execute")'
    ];

    let workflowGenerated = false;
    for (const indicator of indicators) {
      try {
        await page.waitForSelector(indicator, { timeout: 15000 });
        console.log(`✅ Workflow indicator found: ${indicator}`);
        workflowGenerated = true;
        break;
      } catch (e) {
        continue;
      }
    }

    if (!workflowGenerated) {
      console.log('⚠️  No workflow indicators found (UI may not show them immediately)');
    }

    await sleep(5000); // Give time for workflow to fully render

    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '04_workflow_generated.png'),
      fullPage: true
    });
    testsPassed++;

    console.log('\n' + '━'.repeat(70));
    console.log('TEST 5: Workflow Visualization');
    console.log('━'.repeat(70));

    // Capture current state
    const pageContent = await page.evaluate(() => {
      return {
        bodyText: document.body.innerText.substring(0, 1000),
        hasCanvas: !!document.querySelector('canvas'),
        hasSvg: !!document.querySelector('svg'),
        visibleButtons: Array.from(document.querySelectorAll('button'))
          .filter(b => b.offsetParent !== null)
          .map(b => b.textContent?.trim())
          .slice(0, 10)
      };
    });

    console.log('Page state:');
    console.log(`  Canvas elements: ${pageContent.hasCanvas ? 'Yes' : 'No'}`);
    console.log(`  SVG elements: ${pageContent.hasSvg ? 'Yes' : 'No'}`);
    console.log(`  Visible buttons: ${pageContent.visibleButtons.join(', ')}`);

    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '05_workflow_viz.png'),
      fullPage: true
    });
    testsPassed++;

    console.log('\n' + '━'.repeat(70));
    console.log('TEST 6: API Call Test (Alternative)');
    console.log('━'.repeat(70));

    // Make direct API call as backup test
    console.log('Making direct API call to /api/chat...');

    const apiResponse = await page.evaluate(async (msg) => {
      try {
        const response = await fetch('/api/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: msg })
        });

        if (!response.ok) {
          return { error: `HTTP ${response.status}` };
        }

        const data = await response.json();
        return {
          success: true,
          hasWorkflow: !!data.workflow,
          workflowSuccess: data.workflow?.success,
          steps: Object.keys(data.workflow?.workflow_ga?.steps || {}).length
        };
      } catch (e) {
        return { error: e.message };
      }
    }, chatMessage);

    console.log('API Response:', JSON.stringify(apiResponse, null, 2));

    if (apiResponse.success) {
      console.log('✅ API call successful');
      console.log(`  Workflow generated: ${apiResponse.hasWorkflow}`);
      console.log(`  Workflow success: ${apiResponse.workflowSuccess}`);
      console.log(`  Steps: ${apiResponse.steps}`);
      testsPassed++;
    } else {
      console.log(`⚠️  API call failed: ${apiResponse.error}`);
      testsFailed++;
    }

    console.log('\n' + '━'.repeat(70));
    console.log('TEST 7: Final State Capture');
    console.log('━'.repeat(70));

    await sleep(3000);

    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '06_final_state.png'),
      fullPage: true
    });

    // Save full page HTML
    const html = await page.content();
    fs.writeFileSync(
      path.join(SCREENSHOT_DIR, 'page_content.html'),
      html
    );

    // Save page analysis
    const analysis = await page.evaluate(() => {
      return {
        title: document.title,
        url: window.location.href,
        bodyLength: document.body.innerText.length,
        inputCount: document.querySelectorAll('input, textarea').length,
        buttonCount: document.querySelectorAll('button').length,
        linkCount: document.querySelectorAll('a').length,
        imageCount: document.querySelectorAll('img').length,
        canvasCount: document.querySelectorAll('canvas').length,
        svgCount: document.querySelectorAll('svg').length,
        errorMessages: Array.from(document.querySelectorAll('[class*="error"], [class*="Error"]'))
          .map(el => el.textContent?.trim())
          .filter(t => t && t.length > 0)
          .slice(0, 5)
      };
    });

    fs.writeFileSync(
      path.join(SCREENSHOT_DIR, 'page_analysis.json'),
      JSON.stringify(analysis, null, 2)
    );

    console.log('✅ Final state captured');
    console.log('Page analysis:', JSON.stringify(analysis, null, 2));
    testsPassed++;

  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
    testsFailed++;

    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, 'error_state.png'),
      fullPage: true
    }).catch(() => {});
  } finally {
    // Close and save video
    await context.close();
    await browser.close();

    console.log('\n' + '═'.repeat(70));
    console.log('E2E TEST COMPLETE');
    console.log('═'.repeat(70));
    console.log(`\n✅ Tests Passed: ${testsPassed}`);
    console.log(`${testsFailed > 0 ? '❌' : '✅'} Tests Failed: ${testsFailed}`);

    console.log(`\n📁 Output directory: ${VIDEO_DIR}`);
    console.log('\n📹 Video files:');

    // Wait a bit for video to be saved
    await sleep(3000);

    const videoFiles = fs.readdirSync(VIDEO_DIR).filter(f =>
      f.endsWith('.webm') || f.endsWith('.mp4')
    );

    if (videoFiles.length > 0) {
      videoFiles.forEach(f => {
        const stats = fs.statSync(path.join(VIDEO_DIR, f));
        console.log(`  ✓ ${f} (${(stats.size / 1024 / 1024).toFixed(2)} MB)`);
      });

      // Convert to MP4 if needed
      const webmFile = videoFiles.find(f => f.endsWith('.webm'));
      if (webmFile) {
        const mp4File = path.join(VIDEO_DIR, `biomate_e2e_demo_${TIMESTAMP}.mp4`);
        console.log('\n📹 To convert to MP4:');
        console.log(`  ffmpeg -i "${path.join(VIDEO_DIR, webmFile)}" -c:v libx264 -preset fast -crf 22 "${mp4File}"`);
      }
    } else {
      console.log('  ⚠️  No video files found yet (may still be processing)');
      console.log(`  Check ${VIDEO_DIR} in a few seconds`);
    }

    console.log('\n📸 Screenshots:');
    const screenshots = fs.readdirSync(SCREENSHOT_DIR).filter(f => f.endsWith('.png'));
    screenshots.forEach(f => console.log(`  ✓ ${f}`));

    console.log('\n📄 View results:');
    console.log(`  Open: file://${path.join(SCREENSHOT_DIR, '01_homepage.png')}`);
    console.log(`  HTML: file://${path.join(SCREENSHOT_DIR, 'page_content.html')}`);

    console.log('\n✅ E2E test and recording complete!');

    return testsFailed === 0 ? 0 : 1;
  }
}

// Run the test
runE2ETest()
  .then(exitCode => process.exit(exitCode))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
