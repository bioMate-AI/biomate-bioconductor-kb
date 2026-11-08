// Screenshot specific scenes of a v4 deck in fully-revealed state (direct DOM, no engine nav).
import { chromium } from 'playwright';
import path from 'path';
const deck = process.argv[2];
const outDir = process.argv[3];
const idxs = (process.argv[4]||'0,2,3,4,5').split(',').map(Number);
const url = 'file://' + encodeURI(deck) + '?rec=1';
const b = await chromium.launch({ channel:'chrome', args:['--use-gl=swiftshader','--enable-unsafe-swiftshader','--hide-scrollbars'] });
const pg = await b.newPage({ viewport:{width:1920,height:1080}, deviceScaleFactor:1 });
await pg.goto(url, { waitUntil:'load' });
await pg.waitForTimeout(1500);
for (const k of idxs){
  await pg.evaluate((kk)=>{
    const S=[...document.querySelectorAll('.scene')];
    S.forEach((s,ix)=>s.classList.toggle('active', ix===kk));
    const s=S[kk]; if(!s) return;
    s.querySelectorAll('[data-at]').forEach(e=>e.classList.add('on'));
    s.querySelectorAll('.in').forEach(e=>e.classList.add('on'));
    s.querySelectorAll('.beats li').forEach(e=>e.classList.add('on'));
    // update counter for context
    const n=document.querySelector('.ctl .n'); if(n) n.textContent=`${kk+1} / ${S.length}`;
  }, k);
  await pg.waitForTimeout(800);
  const f = path.join(outDir, `scene_${k}.png`);
  await pg.screenshot({ path:f });
  console.log('shot', k, '->', f);
}
await b.close();
