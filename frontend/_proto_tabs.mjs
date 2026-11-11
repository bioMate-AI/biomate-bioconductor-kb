import { chromium } from 'playwright';
const url='http://localhost:7788/BioMate%20Data-Centric%20Prototype.html';
const b=await chromium.launch({channel:'chrome',args:['--hide-scrollbars']});
const pg=await b.newPage({viewport:{width:1512,height:945}});
await pg.goto(url,{waitUntil:'load'});
await pg.waitForFunction(()=>typeof window.App==='function'&&document.getElementById('root')?.innerText.trim().length>60,{timeout:60000}).catch(()=>{});
await pg.waitForTimeout(1800);
await pg.getByText('Paired-end RNA-seq',{exact:false}).first().click().catch(()=>{});
await pg.waitForTimeout(1500);
async function clickExact(t){const l=pg.getByText(t,{exact:true});if(await l.count()){await l.first().click({timeout:4000}).catch(()=>{});return true}return false}
await clickExact('Workflow settings'); await pg.waitForTimeout(1200); await pg.screenshot({path:'/tmp/proto_shots/12_wfsettings.png'}); console.log('12 settings');
await clickExact('Phases'); await pg.waitForTimeout(1200); await pg.screenshot({path:'/tmp/proto_shots/13_phases.png'}); console.log('13 phases');
await b.close();
