import { chromium } from '@playwright/test';
const url = process.argv[2], outDir = process.argv[3];
const b = await chromium.launch({ channel:'chrome', args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
const ctx = await b.newContext({ viewport:{width:1920,height:1080}, deviceScaleFactor:1, recordVideo:{ dir:outDir, size:{width:1920,height:1080} } });
const p = await ctx.newPage();
await p.goto(url, { waitUntil:'load', timeout:60000 });
await p.evaluate(()=>document.fonts && document.fonts.ready).catch(()=>{});
const total = await p.evaluate(()=>window.__total||300);
console.log('total secs:', total);
const deadline = Date.now()+(total+25)*1000;
while(Date.now()<deadline){ const d = await p.evaluate(()=>window.__done===true).catch(()=>false); if(d){console.log('done flag at', Math.round((Date.now()-(deadline-(total+25)*1000))/1000),'s'); break;} await p.waitForTimeout(1000); }
await p.waitForTimeout(600);
const v = await p.video().path();
await ctx.close(); await b.close();
console.log('VIDEO_WEBM:'+v);
