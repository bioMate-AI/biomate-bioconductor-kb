/** Real, read-only navigation evidence for the tutorial series. No mock results. */
import {test,expect} from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import {loginAsFixture,BASE_URL} from './_fixture-login';

test.use({viewport:{width:1920,height:1080},deviceScaleFactor:2});
test('series: open each real cold-start module',async({page})=>{
 test.setTimeout(120000);
 const dir=path.resolve('../docs/qa/20261003-tutorial-release/navigation');fs.mkdirSync(dir,{recursive:true});
 const evidence:any={checkedAt:new Date().toISOString(),baseUrl:BASE_URL,scope:'Module navigation only; no scientific execution or result validation',checks:[]};
 try {
  await loginAsFixture(page);
  await page.goto(BASE_URL+'/',{waitUntil:'domcontentloaded'});
  // New Chat was removed from the expanded sidebar (founder request); the home
  // route already renders the cold-start dashboard, so click it only if present.
  const _nc = page.getByTestId('button-new-chat').first();
  if (await _nc.isVisible({ timeout: 3000 }).catch(() => false)) await _nc.click();
  await expect(page.getByTestId('cold-start-dashboard')).toBeVisible();
  await expect(page.getByTestId('cold-module-card')).toHaveCount(4);
  await page.getByTestId('button-sidebar-toggle').click();
  await page.screenshot({path:path.join(dir,'overview.png')});
  for(let i=0;i<4;i++){
   const card=page.getByTestId('cold-module-card').nth(i);
   const id=await card.getAttribute('data-module-id');
   expect(id).toMatch(/^[a-z0-9-]+$/);
   await card.getByTestId('cold-module-expand').click();
   await expect(card).toHaveAttribute('data-open','true');
   await expect(card.getByTestId('cold-module-body')).toBeVisible();
   await page.screenshot({path:path.join(dir,`${id}.png`)});
   evidence.checks.push({module:id,passed:true,visibleText:await card.innerText()});
   await card.getByTestId('cold-module-expand').click();
   await expect(card).toHaveAttribute('data-open','false');
  }
  evidence.technicalChecksPassed=true;
 }catch(error){
  evidence.technicalChecksPassed=false;
  evidence.error=String(error).slice(0,1500);
  throw error;
 }finally{
  fs.writeFileSync(path.join(dir,'audit.json'),JSON.stringify(evidence,null,2));
 }
});
