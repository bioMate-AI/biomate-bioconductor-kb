/**
 * BioMate UI Demo Video Recorder
 * Uses Puppeteer to automate browser and record the UI
 */

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const FRONTEND_URL = 'https://localhost:5000';
const OUTPUT_DIR = path.join(__dirname, 'demo_videos');
const SCREENSHOT_DIR = path.join(OUTPUT_DIR, `screenshots_${Date.now()}`);

// Create output directories
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}
if (!fs.existsSync(SCREENSHOT_DIR)) {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function recordDemo() {
  console.log('🎬 Starting BioMate UI Demo Recording...\n');

  const browser = await puppeteer.launch({
    headless: true, // Set to false to see the browser
    ignoreHTTPSErrors: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu'
    ],
    defaultViewport: {
      width: 1920,
      height: 1080
    }
  });

  const page = await browser.newPage();

  try {
    // Step 1: Load homepage
    console.log('Step 1: Loading BioMate homepage...');
    await page.goto(FRONTEND_URL, { waitUntil: 'networkidle2', timeout: 30000 });
    await sleep(2000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '01_homepage.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 01_homepage.png');

    // Step 2: Find chat input and type message
    console.log('\nStep 2: Typing workflow request...');
    const chatMessage = 'Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5';

    // Try different selectors for chat input
    const inputSelectors = [
      'input[type="text"]',
      'textarea',
      'input[placeholder*="message"]',
      'input[placeholder*="chat"]',
      '[data-testid="chat-input"]',
      '.chat-input',
      '#chat-input'
    ];

    let inputFound = false;
    for (const selector of inputSelectors) {
      try {
        const input = await page.$(selector);
        if (input) {
          await input.type(chatMessage, { delay: 50 });
          inputFound = true;
          console.log(`✅ Chat input found (${selector})`);
          break;
        }
      } catch (e) {
        continue;
      }
    }

    if (!inputFound) {
      console.log('⚠️  Chat input not found, capturing current state...');
    }

    await sleep(1000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '02_chat_input.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 02_chat_input.png');

    // Step 3: Submit chat (find and click submit button)
    console.log('\nStep 3: Submitting workflow request...');
    const submitSelectors = [
      'button[type="submit"]',
      'button:contains("Send")',
      'button:contains("Submit")',
      '[data-testid="send-button"]',
      '.send-button'
    ];

    for (const selector of submitSelectors) {
      try {
        const button = await page.$(selector);
        if (button) {
          await button.click();
          console.log(`✅ Submit button clicked (${selector})`);
          break;
        }
      } catch (e) {
        continue;
      }
    }

    // Wait for response
    await sleep(5000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '03_workflow_generation.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 03_workflow_generation.png');

    // Step 4: Wait for workflow to appear
    console.log('\nStep 4: Waiting for generated workflow...');
    await sleep(3000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '04_generated_workflow.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 04_generated_workflow.png');

    // Step 5: Look for execute button
    console.log('\nStep 5: Looking for execute button...');
    await sleep(2000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '05_ready_to_execute.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 05_ready_to_execute.png');

    // Step 6: Capture full page state
    console.log('\nStep 6: Capturing full interface...');
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '06_full_interface.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 06_full_interface.png');

    // Get page HTML for debugging
    const html = await page.content();
    fs.writeFileSync(
      path.join(SCREENSHOT_DIR, 'page_content.html'),
      html
    );
    console.log('✅ Page HTML saved: page_content.html');

    console.log('\n' + '='.repeat(60));
    console.log('✅ DEMO RECORDING COMPLETE!');
    console.log('='.repeat(60));
    console.log(`\n📁 Screenshots saved to: ${SCREENSHOT_DIR}`);
    console.log('\nTo create a video from screenshots:');
    console.log(`  cd ${SCREENSHOT_DIR}`);
    console.log('  ffmpeg -framerate 1 -pattern_type glob -i "*.png" \\');
    console.log('    -c:v libx264 -pix_fmt yuv420p \\');
    console.log('    -vf "scale=1920:1080" \\');
    console.log('    ../biomate_demo.mp4');

  } catch (error) {
    console.error('\n❌ Error during recording:', error.message);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, 'error_state.png'),
      fullPage: true
    });
    console.log('Error screenshot saved: error_state.png');
  } finally {
    await browser.close();
  }
}

// Run the demo
recordDemo().catch(console.error);
