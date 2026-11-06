const {chromium}=require('../../frontend/node_modules/playwright');
const fs=require('fs');const path=require('path');
(async()=>{
 const root=path.resolve(__dirname,'../..');
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}});
  await page.goto('http://127.0.0.1:7788/reference/claude_design/tutorials/series/review.html');
  const rows=[];
  for(const card of await page.locator('article').all()){
   for(const lang of ['en','zh']){
    await card.locator(`button[data-lang=${lang}]`).click();
    await card.locator('video').evaluate(v=>v.readyState>=1?null:new Promise((resolve,reject)=>{v.onloadedmetadata=resolve;v.onerror=()=>reject(new Error('Video failed to load'));}));
    const duration=await card.locator('video').evaluate(v=>v.duration);
    const captions=new URL(await card.locator('.captions').getAttribute('href'),page.url()).href;
    const response=await page.request.get(captions);
    if(!response.ok()||!(await response.text()).startsWith('WEBVTT'))throw new Error('Caption load failed');
    rows.push({title:await card.locator('h2').innerText(),language:lang,seconds:duration,captionsLoaded:true});
   }
  }
  fs.writeFileSync(path.join(root,'docs/qa/20261003-tutorial-release/review-player-audit.json'),JSON.stringify(rows,null,2));
  await page.screenshot({path:path.join(root,'docs/qa/20261003-tutorial-release/review-player.png'),fullPage:true});
  console.log(JSON.stringify({editions:rows.length,loaded:true}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
