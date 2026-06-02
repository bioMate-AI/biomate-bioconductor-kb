/**
 * record_slides.js
 * 1. Opens BioMate Intro v3 HTML in headless Chrome
 * 2. Screenshots each slide at 1920x1080
 * 3. Uses ffmpeg to build a timed video clip per slide (matching audio duration)
 * 4. Concatenates all clips + overlays the combined VO audio → final MP4
 */

const puppeteer = require('puppeteer-core');
const { execSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const DIR = __dirname;
const HTML = `file://${path.join(DIR, 'BioMate Intro v3.html')}`;
const SLIDES_AUDIO_DIR = path.join(DIR, 'vo_slides');
const COMBINED_AUDIO = path.join(DIR, 'biomate_intro_v3_vo.mp3');
const SCREENSHOTS_DIR = path.join(DIR, 'slide_screenshots');
const OUTPUT_VIDEO = path.join(DIR, 'biomate_intro_v3.mp4');

const GAP_SEC = 0.8; // must match GAP_MS in generate_vo.py

// Slide label → audio filename mapping (order matches HTML deck)
const SLIDE_AUDIO = [
  '01_title.mp3',
  '02_problem.mp3',
  '03_solution.mp3',
  '04_end_to_end.mp3',
  '05_inside.mp3',
  '06_product.mp3',
  '07_differentiator.mp3',
  'SKIP',             // slide 08 Benchmarks — commented out, skip entirely
  '09_reg_llm.mp3',
  '10_closing.mp3',
];

function audioDurationSec(mp3Path) {
  const result = spawnSync('ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1:nokey=1', mp3Path
  ]);
  return parseFloat(result.stdout.toString().trim());
}

async function main() {
  fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });

  console.log('Launching Chrome...');
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage'],
  });

  const page = await browser.newPage();
  // 2x device scale for crisp rendering; ffmpeg scales down to 1920x1080
  await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 2 });

  console.log('Loading deck...');
  await page.goto(HTML, { waitUntil: 'networkidle0' });

  // Wait for deck-stage to be defined and fonts ready
  await page.waitForFunction(() => customElements.get('deck-stage') !== undefined, { timeout: 10000 });

  // Hide the thumbnail rail so the slide fills the full viewport
  await page.evaluate(() => {
    const stage = document.querySelector('deck-stage');
    if (stage) stage.setAttribute('no-rail', '');
  });

  await new Promise(r => setTimeout(r, 2000)); // let fonts + layout settle

  // Count total slides
  const totalSlides = await page.evaluate(() => {
    const stage = document.querySelector('deck-stage');
    return stage ? stage.length : 0;
  });
  console.log(`Deck has ${totalSlides} slides\n`);

  const clipPaths = [];

  for (let i = 0; i < totalSlides; i++) {
    const audioFile = SLIDE_AUDIO[i];

    // Skip slides marked SKIP (e.g. benchmarks — commented out in deck)
    if (audioFile === 'SKIP') {
      console.log(`  Slide ${i + 1}/${totalSlides}: skipped (benchmarks)`);
      continue;
    }

    // Navigate to slide i
    await page.evaluate((idx) => {
      document.querySelector('deck-stage').goTo(idx);
    }, i);
    await new Promise(r => setTimeout(r, 400)); // wait for transition

    const screenshotPath = path.join(SCREENSHOTS_DIR, `slide_${String(i).padStart(2, '0')}.png`);
    await page.screenshot({ path: screenshotPath, fullPage: false });

    // Determine if there's a next non-skipped slide with audio
    const hasNextAudio = SLIDE_AUDIO.slice(i + 1).some(f => f && f !== 'SKIP');
    let durationSec;

    if (audioFile) {
      const audioPath = path.join(SLIDES_AUDIO_DIR, audioFile);
      const clipDur = audioDurationSec(audioPath);
      durationSec = hasNextAudio ? clipDur + GAP_SEC : clipDur + 0.5;
    }

    console.log(`  Slide ${i + 1}/${totalSlides}: ${screenshotPath.split('/').pop()}  →  ${durationSec.toFixed(1)}s`);

    // Build video clip from screenshot at exact duration
    const clipPath = path.join(SCREENSHOTS_DIR, `clip_${String(i).padStart(2, '0')}.mp4`);
    spawnSync('ffmpeg', [
      '-y', '-loop', '1', '-i', screenshotPath,
      '-t', String(durationSec),
      '-vf', 'format=yuv420p',
      '-c:v', 'h264_videotoolbox',
      '-b:v', '20M',   // high bitrate for crisp 4K
      '-r', '24',
      clipPath,
    ], { stdio: 'inherit' });

    clipPaths.push(clipPath);
  }

  await browser.close();

  // Write concat list
  const concatFile = path.join(SCREENSHOTS_DIR, 'concat.txt');
  fs.writeFileSync(concatFile, clipPaths.map(p => `file '${p}'`).join('\n'));

  // Concatenate video clips (no audio yet)
  console.log('\nConcatenating video clips...');
  const silentVideo = path.join(SCREENSHOTS_DIR, 'silent.mp4');
  spawnSync('ffmpeg', [
    '-y', '-f', 'concat', '-safe', '0', '-i', concatFile,
    '-c', 'copy', silentVideo,
  ], { stdio: 'inherit' });

  // Merge with combined VO audio
  console.log('Merging with VO audio...');
  spawnSync('ffmpeg', [
    '-y',
    '-i', silentVideo,
    '-i', COMBINED_AUDIO,
    '-c:v', 'copy',
    '-c:a', 'aac', '-b:a', '192k',
    OUTPUT_VIDEO,
  ], { stdio: 'inherit' });

  const sizeMB = (fs.statSync(OUTPUT_VIDEO).size / 1024 / 1024).toFixed(1);
  console.log(`\nDone! → ${OUTPUT_VIDEO}  (${sizeMB} MB)`);
}

main().catch(err => { console.error(err); process.exit(1); });
