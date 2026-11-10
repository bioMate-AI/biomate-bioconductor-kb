import { chromium } from '@playwright/test';
const url = process.argv[2], outDir = process.argv[3];
const b = await chromium.launch({ channel:'chrome', args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
const ctx = await b.newContext({ viewport:{width:1920,height:1080}, deviceScaleFactor:1, recordVideo:{ dir:outDir, size:{width:1920,height:1080} } });
const p = await ctx.newPage();
const tCtx = Date.now();
await p.goto(url, { waitUntil:'load', timeout:60000 });
await p.evaluate(()=>document.fonts && document.fonts.ready).catch(()=>{});
// wait until the engine is actually playing scene 1 (active class on first scene + timeline set)
await p.waitForFunction(()=>window.__timeline && document.querySelector('.scene.active'), null, {timeout:15000}).catch(()=>{});
const tAnim = Date.now();
const leadin = (tAnim - tCtx)/1000;
const timeline = await p.evaluate(()=>window.__timeline);
const total = await p.evaluate(()=>window.__total||300);
const deadline = Date.now()+(total+25)*1000;
while(Date.now()<deadline){ const d = await p.evaluate(()=>window.__done===true).catch(()=>false); if(d) break; await p.waitForTimeout(1000); }
await p.waitForTimeout(700);
const v = await p.video().path();
await ctx.close(); await b.close();
console.log(JSON.stringify({webm:v, leadin, total, timeline}));
