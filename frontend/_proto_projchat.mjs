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
async function shot(name){ await pg.waitForTimeout(1100); await pg.screenshot({path:path.join(outDir,name)}); console.log('shot',name); }

// open a project chat that has a workflow run (status-dot chat under Fibrosis target triage)
for(const t of ['Paired-end RNA-seq','Target evidence review','ADMET screen']){
  const loc = pg.getByText(t,{exact:false});
  if(await loc.count()){ await loc.first().click().catch(()=>{}); console.log('clicked',t); break; }
}
await shot('10_projchat.png');
// try to reveal the workflow panel tabs (Settings/Phases) — click a workflow card / its "Open" / the panel
const texts = await pg.evaluate(()=>Array.from(document.querySelectorAll('*')).filter(e=>e.children.length===0&&e.innerText&&e.innerText.trim().length<22).map(e=>e.innerText.trim()).filter((v,i,a)=>a.indexOf(v)===i).slice(0,80));
console.log('leaf texts:', JSON.stringify(texts));
for(const t of ['Settings','Phases','Open','Review in panel','Workflow']){
  const loc = pg.getByText(t,{exact:false});
  if(await loc.count()){ await loc.first().click().catch(()=>{}); await shot('11_'+t.replace(/\s/g,'')+'.png'); }
}
await b.close();
