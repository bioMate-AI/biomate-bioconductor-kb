import { chromium } from 'playwright';
import path from 'path';
const url = 'http://localhost:7788/BioMate%20Data-Centric%20Prototype.html';
const outDir = '/tmp/proto_shots';
const b = await chromium.launch({ channel:'chrome', args:['--hide-scrollbars'] });
const pg = await b.newPage({ viewport:{width:1512,height:945}, deviceScaleFactor:1 });
pg.on('pageerror', e => console.log('  [pageerror]', String(e).slice(0,120)));
await pg.goto(url, { waitUntil:'load' });
await pg.waitForFunction(() => typeof window.App==='function' && document.getElementById('root')?.innerText.trim().length>60, {timeout:60000}).catch(()=>{});
await pg.waitForTimeout(1800);
async function shot(name){ await pg.waitForTimeout(1000); await pg.screenshot({path:path.join(outDir,name)}); console.log('shot',name); }
async function click(sel, which=0, label=''){ const l=pg.locator(sel); const n=await l.count(); if(!n){console.log('  NF',label||sel);return false;} try{await l.nth(Math.min(which,n-1)).click({timeout:5000});return true;}catch(e){console.log('  ERR',label||sel,e.message.slice(0,50));return false;} }

// open Data analysis → qPCR example
await pg.getByText('Data analysis',{exact:false}).first().click().catch(()=>{});
await pg.waitForTimeout(900);
// the qPCR row's "open"
await pg.getByText('open',{exact:true}).first().click().catch(()=>{});
await shot('04_run_settings.png');

// list panel tab buttons / headings to orient
const tabs = await pg.evaluate(()=>Array.from(document.querySelectorAll('button')).map(b=>b.innerText.trim()).filter(t=>t&&t.length<24).slice(0,60));
console.log('buttons:', JSON.stringify(tabs));

// Phases tab
for(const t of ['Phases','Steps','阶段']){ if(await click(`button:has-text("${t}")`,0,t)){ await shot('05_phases.png'); break; } }
// Confirm & run
for(const t of ['Confirm','Run workflow','确认']){ if(await click(`button:has-text("${t}")`,0,t)){ await shot('06_running.png'); break; } }
await pg.waitForTimeout(2500); await shot('07_afterrun.png');
// after-run sub-tabs
for(const t of ['Summary','Outputs','Report']){ if(await click(`button:has-text("${t}")`,0,t)){ await shot('08_'+t+'.png'); } }
// a step → step deep view
await click('button:has-text("step"),[class*=step]',0,'step');
await shot('09_stepdeep.png');
await b.close();
