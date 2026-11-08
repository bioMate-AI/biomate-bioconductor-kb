/** Read-only probe: render the tutorial run in BioMate's Chinese UI and list visible English labels. */
import {test,expect} from '@playwright/test';
import fs from 'node:fs';import path from 'node:path';
import {loginAsFixture,BASE_URL} from './_fixture-login';
test.use({viewport:{width:1600,height:900},deviceScaleFactor:2});
test('probe Chinese UI on tutorial run',async({page})=>{
 test.setTimeout(120000);
 const out=path.resolve('../docs/qa/20261003-tutorial-release/zh-ui-probe');fs.mkdirSync(out,{recursive:true});
 await page.addInitScript(()=>{const k='biomate-user-settings';const s=JSON.parse(localStorage.getItem(k)||'{}');s.language='chinese';localStorage.setItem(k,JSON.stringify(s));});
 await loginAsFixture(page);
 await page.goto(BASE_URL+'/?session=chat-1790955154245-s17yy1qla',{waitUntil:'domcontentloaded'});
 await expect(page.getByTestId('after-tab-outputs')).toBeVisible({timeout:45000});
 const shots:Record<string,string>={summary:'after-tab-summary',outputs:'after-tab-outputs',record:'after-tab-record'};
 const english:Record<string,string[]>={};
 for(const [name,id] of Object.entries(shots)){
  await page.getByTestId(id).click();await page.waitForTimeout(2500);
  await page.screenshot({path:path.join(out,`${name}.png`)});
  english[name]=await page.evaluate(()=>{const seen=new Set<string>();const w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);let n;while((n=w.nextNode())){const t=(n.textContent||'').trim();const el=n.parentElement;if(!t||!el||el.closest('pre,code,textarea,[data-testid*="chat-message"]'))continue;const r=el.getBoundingClientRect();if(r.width===0||r.height===0)continue;if(/[A-Za-z]{3,}/.test(t)&&!/[\u4e00-\u9fff]/.test(t))seen.add(t.slice(0,80));}return [...seen];});
 }
 fs.writeFileSync(path.join(out,'english-labels.json'),JSON.stringify({url:BASE_URL,english},null,2));
});
