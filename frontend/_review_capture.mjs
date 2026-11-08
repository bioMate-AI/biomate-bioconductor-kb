// Capture every scene of a v4/edu deck as a PNG, driven by the engine's Next button (reliable).
import { chromium } from 'playwright';
import path from 'path';
const deck = process.argv[2], outDir = process.argv[3];
const url = 'file://' + encodeURI(deck) + '?rec=1';
const b = await chromium.launch({ channel:'chrome', args:['--use-gl=swiftshader','--enable-unsafe-swiftshader','--hide-scrollbars'] });
const pg = await b.newPage({ viewport:{width:1920,height:1080}, deviceScaleFactor:1 });
await pg.goto(url, { waitUntil:'load' });
await pg.waitForTimeout(1200);
const n = await pg.evaluate(()=>document.querySelectorAll('.scene').length);
for (let i=0;i<n;i++){
  if (i>0){
    // advance exactly one scene via the engine's Next button (clears auto-advance timers, plays scene → lens renders)
    await pg.evaluate(()=>document.querySelector('.ctl .nx').click());
  }
  await pg.waitForTimeout(4200);                     // let lens render + early reveals fire
  await pg.evaluate(()=>{                            // force-reveal any remaining staged text
    const s=document.querySelector('.scene.active'); if(!s) return;
    s.querySelectorAll('[data-at]').forEach(e=>e.classList.add('on'));
    s.querySelectorAll('.in').forEach(e=>e.classList.add('on'));
    s.querySelectorAll('.beats li').forEach(e=>e.classList.add('on'));
  });
  await pg.waitForTimeout(500);
  const idx = await pg.evaluate(()=>[...document.querySelectorAll('.scene')].findIndex(s=>s.classList.contains('active')));
  await pg.screenshot({ path: path.join(outDir, `s${String(i).padStart(2,'0')}.png`) });
  process.stdout.write(`${i}(active:${idx}) `);
}
console.log('\ndone', n, 'scenes');
await b.close();
