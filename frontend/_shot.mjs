import { chromium } from 'playwright';
const [url, out, at] = process.argv.slice(2);
const b = await chromium.launch({ channel:'chrome', args:['--use-gl=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
const p = await b.newPage({ viewport:{width:1920,height:1080} });
await p.goto(url, { waitUntil:'load' });
await p.waitForTimeout(Number(at)*1000);
await p.screenshot({ path: out });
await b.close();
