/**
 * BioMate UI Demo Video Recorder using Playwright
 */

const { chromium } = require('playwright');
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
  console.log('🎬 Starting BioMate UI Demo Recording with Playwright...\n');

  const browser = await chromium.launch({
    headless: true,
    ignoreHTTPSErrors: true
  });

  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    ignoreHTTPSErrors: true,
    recordVideo: {
      dir: OUTPUT_DIR,
      size: { width: 1920, height: 1080 }
    }
  });

  const page = await context.newPage();

  try {
    // Step 1: Load homepage
    console.log('Step 1: Loading BioMate homepage...');
    await page.goto(FRONTEND_URL, { waitUntil: 'networkidle', timeout: 30000 });
    await sleep(2000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '01_homepage.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 01_homepage.png');

    // Get page title
    const title = await page.title();
    console.log(`Page title: ${title}`);

    // Step 2: Find and interact with chat
    console.log('\nStep 2: Looking for chat interface...');

    // Try to find any input fields
    const inputs = await page.$$('input, textarea');
    console.log(`Found ${inputs.length} input/textarea elements`);

    const chatMessage = 'Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5';

    // Try to type in the first text input/textarea found
    if (inputs.length > 0) {
      for (let i = 0; i < inputs.length; i++) {
        try {
          const inputType = await inputs[i].getAttribute('type');
          const placeholder = await inputs[i].getAttribute('placeholder');
          console.log(`Input ${i}: type=${inputType}, placeholder=${placeholder}`);

          // Skip hidden or password inputs
          if (inputType === 'hidden' || inputType === 'password') {
            continue;
          }

          // Try to type in this input
          await inputs[i].fill(chatMessage);
          console.log(`✅ Typed message into input ${i}`);
          await sleep(1000);
          break;
        } catch (e) {
          console.log(`  Could not type in input ${i}: ${e.message}`);
          continue;
        }
      }
    }

    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '02_chat_input.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 02_chat_input.png');

    // Step 3: Look for submit button
    console.log('\nStep 3: Looking for submit button...');
    const buttons = await page.$$('button');
    console.log(`Found ${buttons.length} button elements`);

    for (let i = 0; i < buttons.length; i++) {
      const text = await buttons[i].textContent();
      const type = await buttons[i].getAttribute('type');
      console.log(`Button ${i}: text="${text?.trim()}", type=${type}`);

      if (type === 'submit' || text?.toLowerCase().includes('send') || text?.toLowerCase().includes('submit')) {
        try {
          await buttons[i].click();
          console.log(`✅ Clicked button: "${text?.trim()}"`);
          break;
        } catch (e) {
          console.log(`  Could not click button: ${e.message}`);
        }
      }
    }

    await sleep(5000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '03_after_submit.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 03_after_submit.png');

    // Step 4: Wait and capture response
    console.log('\nStep 4: Waiting for response...');
    await sleep(5000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '04_response.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 04_response.png');

    // Step 5: Capture final state
    console.log('\nStep 5: Capturing final state...');
    await sleep(3000);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, '05_final.png'),
      fullPage: true
    });
    console.log('✅ Screenshot saved: 05_final.png');

    // Save page HTML
    const html = await page.content();
    fs.writeFileSync(
      path.join(SCREENSHOT_DIR, 'page_content.html'),
      html
    );
    console.log('✅ Page HTML saved');

    // Save page structure analysis
    const structure = await page.evaluate(() => {
      return {
        title: document.title,
        inputCount: document.querySelectorAll('input, textarea').length,
        buttonCount: document.querySelectorAll('button').length,
        mainElementClasses: Array.from(document.querySelectorAll('[class]')).slice(0, 10).map(el => el.className)
      };
    });

    fs.writeFileSync(
      path.join(SCREENSHOT_DIR, 'page_structure.json'),
      JSON.stringify(structure, null, 2)
    );
    console.log('✅ Page structure saved');

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
    await page.screenshot({
      path: path.join(SCREENSHOT_DIR, 'error_state.png'),
      fullPage: true
    });
  } finally {
    await context.close();
    await browser.close();

    console.log('\n' + '='.repeat(70));
    console.log('✅ DEMO RECORDING COMPLETE!');
    console.log('='.repeat(70));
    console.log(`\n📁 Output directory: ${SCREENSHOT_DIR}`);
    console.log(`📹 Video will be saved to: ${OUTPUT_DIR}`);
    console.log('\nFiles created:');
    const files = fs.readdirSync(SCREENSHOT_DIR);
    files.forEach(f => console.log(`  - ${f}`));

    console.log('\n📝 To create a slideshow video from screenshots:');
    console.log(`  ffmpeg -framerate 1/3 -pattern_type glob -i '${SCREENSHOT_DIR}/*.png' \\`);
    console.log(`    -c:v libx264 -pix_fmt yuv420p \\`);
    console.log(`    -vf "scale=1920:1080,setsar=1" \\`);
    console.log(`    ${OUTPUT_DIR}/biomate_demo_slideshow.mp4`);

    console.log('\n📝 To create a faster slideshow (1 second per frame):');
    console.log(`  ffmpeg -framerate 1 -pattern_type glob -i '${SCREENSHOT_DIR}/*.png' \\`);
    console.log(`    -c:v libx264 -pix_fmt yuv420p \\`);
    console.log(`    ${OUTPUT_DIR}/biomate_demo_fast.mp4`);
  }
}

recordDemo().catch(console.error);
