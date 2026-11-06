/** Narration-timed real UI footage. No screenshots are used as video frames. */
import {test,expect} from '@playwright/test';
import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';
import {loginAsFixture,BASE_URL} from './_fixture-login';
test.use({viewport:{width:1600,height:900},deviceScaleFactor:1,video:{mode:'on',size:{width:1600,height:900}}});
for(const lang of ['en','zh'])test(`record output-download lesson ${lang}`,async({page})=>{
 test.setTimeout(240000);
 const root=path.resolve('..');const out=path.join(root,'recording/video/series-actions/result-downloads-v3',lang);fs.mkdirSync(out,{recursive:true});
 const script=JSON.parse(fs.readFileSync(path.join(root,'reference/claude_design/tutorials/series/episodes/result-downloads/storyboard.json'),'utf8'));
 const scenes=script.scenes.map((s:any)=>{const r=JSON.parse(fs.readFileSync(path.join(root,`recording/audio/series/result-downloads/${lang}/step-${String(s.id).padStart(3,'0')}.json`),'utf8'));expect(r.narrationSha256).toBe(crypto.createHash('sha256').update(s[lang].narration).digest('hex'));return {id:s.id,seconds:r.seconds+.8,narrationSha256:r.narrationSha256};});
 await loginAsFixture(page);await page.goto(BASE_URL+'/?session=chat-1790955154245-s17yy1qla',{waitUntil:'domcontentloaded'});
 await expect(page.getByTestId('after-tab-outputs')).toBeVisible({timeout:30000});
 await page.getByTestId('button-sidebar-toggle').click();await page.getByTestId('after-tab-outputs').click();
 const notNow=page.getByRole('button',{name:'Not now',exact:true});
 try{await notNow.waitFor({state:'visible',timeout:10000});await notNow.click();}catch{if(await notNow.isVisible())throw new Error('Feedback dismissal failed');}
 await page.getByTestId('after-tab-summary').click();await page.waitForTimeout(500);
 const start=Date.now();const events:any[]=[];let current=0;
 async function click(locator:any,label:string){const box=await locator.boundingBox();expect(box).not.toBeNull();await page.mouse.move(box.x+box.width/2,box.y+box.height/2,{steps:20});await page.waitForTimeout(250);await locator.click({timeout:10000});events.push({scene:current,seconds:(Date.now()-start)/1000,action:label});}
 async function preview(name:string){const row=page.getByRole('row').filter({hasText:name});await click(row.getByText('view',{exact:true}),'Preview '+name);await expect(page.getByRole('button',{name:'Close preview',exact:true})).toBeVisible();const contentKey:Record<string,string>={'predict_admet_properties_results.json':'predict_admet_properties','qc_metrics.json':'metrics','versions.yml':'biomni_function','toxicity_report.json':'compounds_assessed'};await expect(page.locator('pre').filter({hasText:contentKey[name]}).first()).toBeVisible({timeout:15000});await expect(page.getByText(/Loading preview/)).not.toBeVisible({timeout:15000});await expect(page.getByText(/Failed to load file:/)).toHaveCount(0);await page.waitForTimeout(1600);}
 async function close(){await click(page.getByRole('button',{name:'Close preview',exact:true}),'Close preview');}
 let target=0;
 for(const scene of scenes){current=scene.id;events.push({scene:current,seconds:(Date.now()-start)/1000,action:'Scene start'});
  if(current===1){await page.waitForTimeout(2500);await page.getByText('Predict ADMET Properties (AI)',{exact:true}).first().hover();await page.waitForTimeout(1000);}
  if(current===2){await page.waitForTimeout(1000);await click(page.getByTestId('after-tab-outputs'),'Open Outputs');for(const name of ['predict_admet_properties_results.json','qc_metrics.json','versions.yml']){await page.getByRole('row').filter({hasText:name}).hover();await page.waitForTimeout(1800);}}
  if(current===3){for(const name of ['predict_admet_properties_results.json','qc_metrics.json','versions.yml']){await preview(name);await close();}}
  if(current===4){const row=page.getByRole('row').filter({hasText:'toxicity_report.json'});const pending=page.waitForEvent('download');await click(row.getByRole('link',{name:'dl',exact:true}),'Download toxicity report');const download=await pending;await download.saveAs(path.join(out,'downloaded-toxicity_report.json'));const data=JSON.parse(fs.readFileSync(path.join(out,'downloaded-toxicity_report.json'),'utf8'));expect(data.compounds_assessed).toBe(3);events.push({scene:current,seconds:(Date.now()-start)/1000,action:'Downloaded content verified',compounds:3});await page.waitForTimeout(1200);await preview('toxicity_report.json');await expect(page.getByText('compounds_assessed',{exact:false}).first()).toBeVisible();await page.mouse.wheel(0,180);await page.waitForTimeout(1500);await close();}
  if(current===5){await page.waitForTimeout(900);await click(page.getByTestId('after-tab-record'),'Open Reproducibility record');await expect(page.getByTestId('repro-tab')).toBeVisible();await page.waitForTimeout(2500);await page.getByTestId('repro-tab').hover();await page.mouse.wheel(0,210);await page.waitForTimeout(2000);}
  target+=scene.seconds;const remaining=target*1000-(Date.now()-start);expect(remaining,'Actions must fit the narration timeline').toBeGreaterThan(0);await page.waitForTimeout(remaining);
 }
 const duration=(Date.now()-start)/1000;const video=page.video();await page.close();await video!.saveAs(path.join(out,'raw.webm'));
 fs.writeFileSync(path.join(out,'timeline.json'),JSON.stringify({language:lang,format:'REAL_UI_SCREEN_RECORDING',duration,scenes,events},null,2));
});
