import pw from '/Users/kky/biomate-review/frontend/node_modules/playwright/index.js';
const { chromium }=pw;
const br=await chromium.launch({headless:true});
const pg=await br.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:2});
await pg.goto('file:///Users/kky/biomate-review/reference/claude_design/biomate_market_v1/index.html',{waitUntil:'networkidle'});
await pg.waitForTimeout(800);
for(let i=1;i<=10;i++){
  const el=await pg.$('#slide-'+i);
  await el.screenshot({path:`render/slide-${i}.png`});
  console.log('rendered slide',i);
}
await br.close();
