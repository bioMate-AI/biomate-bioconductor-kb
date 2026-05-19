// Audit harness — opens each of the 4 scenarios in live-mock mode,
// captures 4 screenshots (early / mid / late / final), records a video,
// and writes a JSON summary of assertions per scenario.
//
//   node audit.js
//
// Output: docs/20260519_research_agent_v2_audit/{screenshots,videos,audit.json}

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const OUT  = '/home/yzhang/biomate/docs/20260519_research_agent_v2_audit';
const SHOT = path.join(OUT, 'screenshots');
const VID  = path.join(OUT, 'videos');

const SCENARIOS = [
  { id: 'drugscreen', label: 'Drug screen (ADMET + autoloop + comparison)',
    expectCompare: true,  expectFindings: /BBB-penetrant|47 BBB/i },
  { id: 'cryosparc',  label: 'Cryo-EM SPA (5 phases + CTF gate)',
    expectCompare: false, expectFindings: /reconstruction|3\.1 Å/i },
  { id: 'rnaseq',     label: 'Bulk RNA-seq (nf-core/rnaseq)',
    expectCompare: false, expectFindings: /DEGs|1,847/i },
  { id: 'variant',    label: 'Variant calling (nf-core/sarek)',
    expectCompare: false, expectFindings: /PASS variants|ts\/tv/i },
];

(async () => {
  const browser = await chromium.launch();
  const summary = [];

  for (const sc of SCENARIOS) {
    const ctx = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      recordVideo: { dir: VID, size: { width: 1440, height: 900 } },
    });
    const page = await ctx.newPage();
    const errs = []; page.on('pageerror', e => errs.push(String(e)));

    const url = `http://127.0.0.1:8765/index.html?live=mock&scenario=${sc.id}&speed=2`;
    await page.goto(url, { waitUntil: 'networkidle' });

    // Early — plan should be on screen, run starting
    await page.waitForTimeout(2000);
    await page.screenshot({ path: path.join(SHOT, `${sc.id}_1_early.png`), fullPage: false });

    // Mid — phases in progress
    await page.waitForTimeout(4000);
    await page.screenshot({ path: path.join(SHOT, `${sc.id}_2_mid.png`),   fullPage: false });

    // Late — most phases done, comparison card if any
    await page.waitForTimeout(6000);
    await page.screenshot({ path: path.join(SHOT, `${sc.id}_3_late.png`),  fullPage: false });

    // Final — completed + findings
    await page.waitForTimeout(6000);
    await page.screenshot({ path: path.join(SHOT, `${sc.id}_4_final.png`), fullPage: true });

    const obs = await page.evaluate(() => {
      const t = document.body.innerText;
      return {
        planItems:  document.querySelectorAll('[class*=plan-item]').length,
        promo:      document.querySelectorAll('[class*=promotion]').length,
        hasCompare: /Run A.*Run B|Compare runs/i.test(t),
        bodyText:   t.slice(0, 5000),
      };
    });

    const passFindings = sc.expectFindings.test(obs.bodyText);
    const result = {
      scenario:    sc.id,
      label:       sc.label,
      jsErrors:    errs.length,
      planItems:   obs.planItems,
      hasCompare:  obs.hasCompare,
      expectedCompare: sc.expectCompare,
      compareOk:   obs.hasCompare === sc.expectCompare,
      findingsOk:  passFindings,
      pass:        errs.length === 0 && obs.planItems === 5
                   && (obs.hasCompare === sc.expectCompare) && passFindings,
      jsErrorList: errs.slice(0, 3),
    };
    summary.push(result);
    console.log(JSON.stringify(result, null, 2));

    await page.close();
    const videoPath = await page.video().path();
    await ctx.close();
    // Rename video to scenario id
    const dst = path.join(VID, `${sc.id}.webm`);
    if (fs.existsSync(videoPath)) fs.renameSync(videoPath, dst);
  }

  fs.writeFileSync(path.join(OUT, 'audit.json'), JSON.stringify(summary, null, 2));
  const allPass = summary.every(s => s.pass);
  console.log('\n=== ALL PASS: ' + allPass + ' ===');
  await browser.close();
  process.exit(allPass ? 0 : 1);
})();
