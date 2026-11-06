/** Actual result navigation, preview and download; no simulated UI. */
import {test,expect} from '@playwright/test';
import fs from 'node:fs';import path from 'node:path';
import {loginAsFixture,BASE_URL} from './_fixture-login';
test.use({viewport:{width:1920,height:1080},deviceScaleFactor:1,video:{mode:'on',size:{width:1920,height:1080}}});
test('record real output actions',async({page})=>{
 test.setTimeout(180000);
 const out=path.resolve('../recording/video/series-actions');fs.mkdirSync(out,{recursive:true});
 await loginAsFixture(page);
 await page.goto(BASE_URL+'/?session=chat-1790955154245-s17yy1qla',{waitUntil:'domcontentloaded'});
 await expect(page.getByTestId('after-tab-outputs')).toBeVisible({timeout:30000});
 const sidebar=page.getByTestId('button-sidebar-toggle');if(await sidebar.isVisible())await sidebar.click();
 await page.getByTestId('after-tab-outputs').click();
 const notNow=page.getByRole('button',{name:'Not now',exact:true});
 try {await notNow.waitFor({state:'visible',timeout:10000});await notNow.click();}catch{if(await notNow.isVisible())throw new Error('Feedback dismissal failed');}
 await page.getByTestId('after-tab-summary').click();await page.waitForTimeout(1000);
 const started=Date.now();const events:any[]=[];
 async function click(locator:any,label:string){const box=await locator.boundingBox();expect(box).not.toBeNull();await page.mouse.move(box.x+box.width/2,box.y+box.height/2,{steps:24});await page.waitForTimeout(500);events.push({seconds:(Date.now()-started)/1000,action:label});await locator.click();}
 await page.waitForTimeout(1500);await click(page.getByTestId('after-tab-outputs'),'Open Outputs');
 const row=page.getByRole('row').filter({hasText:'toxicity_report.json'});await expect(row).toBeVisible();await page.waitForTimeout(1800);
 await click(row.getByText('view',{exact:true}),'Preview toxicity_report.json');
 await expect(page.getByText('compounds_assessed',{exact:false}).first()).toBeVisible({timeout:15000});await page.waitForTimeout(4000);
 await page.screenshot({path:path.join(out,'preview-evidence.png')});
 await click(page.getByRole('button',{name:'Close preview',exact:true}),'Close preview');await page.waitForTimeout(1200);
 const downloaded=page.waitForEvent('download');await click(row.getByRole('link',{name:'dl',exact:true}),'Download toxicity_report.json');
 const download=await downloaded;await download.saveAs(path.join(out,'downloaded-toxicity_report.json'));
 const data=JSON.parse(fs.readFileSync(path.join(out,'downloaded-toxicity_report.json'),'utf8'));expect(data.compounds_assessed).toBe(3);
 events.push({seconds:(Date.now()-started)/1000,action:'Downloaded content verified',compounds:data.compounds_assessed});
 await page.waitForTimeout(1800);await click(page.getByTestId('after-tab-record'),'Open Reproducibility record');
 await expect(page.getByTestId('repro-tab')).toBeVisible();await page.waitForTimeout(3500);
 const duration=(Date.now()-started)/1000;const video=page.video();await page.close();await video!.saveAs(path.join(out,'outputs-actions-raw.webm'));
 fs.writeFileSync(path.join(out,'actions.json'),JSON.stringify({status:'REAL_UI_ACTIONS_RECORDED',duration,events,source:'BioMate development; existing completed ADMET run'},null,2));
});
