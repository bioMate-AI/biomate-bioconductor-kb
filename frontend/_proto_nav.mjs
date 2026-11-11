import { chromium } from 'playwright';
import path from 'path';
const url = 'http://localhost:7788/BioMate%20Data-Centric%20Prototype.html';
const outDir = '/tmp/proto_shots';
const b = await chromium.launch({ channel:'chrome', args:['--hide-scrollbars'] });
const pg = await b.newPage({ viewport:{width:1512,height:945}, deviceScaleFactor:1 });
pg.on('pageerror', e => console.log('  [pageerror]', String(e).slice(0,120)));
await pg.goto(url, { waitUntil:'load' });
await pg.waitForFunction(() => typeof window.App==='function' && document.getElementById('root')?.innerText.trim().length>60, {timeout:60000}).catch(()=>{});
await pg.waitForTimeout(2000);

async function shot(name){ await pg.waitForTimeout(1200); await pg.screenshot({path:path.join(outDir,name)}); const t=await pg.evaluate(()=>(document.getElementById('root')?.innerText||'').replace(/\n+/g,' | ').slice(0,260)); console.log(name,'→',t); }
async function clickText(t, which=0){
  const loc = pg.getByText(t, {exact:false});
  const n = await loc.count();
  if(n===0){ console.log('  NOTFOUND:',t); return false; }
  try{ await loc.nth(Math.min(which,n-1)).click({timeout:4000}); return true; }catch(e){ console.log('  CLICKERR',t,e.message.slice(0,60)); return false; }
}

// 1) Instructions page
await clickText('Instructions');
await shot('01_instructions.png');

// 2) back to cold start, open a worked example via a module card
await clickText('New chat', 0);
await shot('02_newchat.png');
await clickText('Data analysis');
await shot('03_dataanalysis.png');

await b.close();
