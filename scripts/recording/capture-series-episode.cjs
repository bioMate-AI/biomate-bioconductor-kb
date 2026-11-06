const { chromium } = require('../../frontend/node_modules/playwright');
const fs = require('fs');
const path = require('path');
(async()=>{
 const root=path.resolve(__dirname,'../..');
 const episode=process.argv[2];
 if(!episode || !/^[a-z0-9-]+$/.test(episode))throw new Error('Provide an episode ID');
 const storyboard=JSON.parse(fs.readFileSync(path.join(root,'reference/claude_design/tutorials/series/episodes',episode,'storyboard.json'),'utf8'));
 const out=path.join(root,'docs/qa/20261003-tutorial-release/series-frames',episode);fs.mkdirSync(out,{recursive:true});
 const browser=await chromium.launch({channel:'chrome',headless:true});
 const page=await browser.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1});
 const issues=[];
 try {
  for(const lang of ['en','zh']){
   await page.goto(`http://127.0.0.1:7788/reference/claude_design/tutorials/series/index.html?episode=${episode}&lang=${lang}`,{waitUntil:'networkidle'});
   await page.waitForFunction(()=>window.__ready===true);
   await page.evaluate(()=>document.fonts.ready);
   for(let i=0;i<storyboard.scenes.length;i++){
    await page.evaluate(n=>window.renderScene(n),i);await page.waitForTimeout(900);
    const bad=await page.evaluate(()=>[...document.querySelectorAll('h1,.subtitle,.card,.card .label,.card .value,.screen,.footer')].flatMap(el=>{
     const b=el.getBoundingClientRect();const footer=document.querySelector('.footer').getBoundingClientRect();
     return b.left<0||b.right>1921||b.bottom>1080||(!el.classList.contains('card')&&(el.scrollWidth>el.clientWidth+2||el.scrollHeight>el.clientHeight+2))||(!el.classList.contains('footer')&&b.bottom>footer.top-8)?[{text:el.textContent.slice(0,100),bounds:{x:b.x,y:b.y,width:b.width,height:b.height},scroll:[el.scrollWidth,el.scrollHeight]}]:[];
    }));
    issues.push(...bad.map(x=>({language:lang,scene:i+1,...x})));
    await page.screenshot({path:path.join(out,`${lang}-${String(i+1).padStart(2,'0')}.png`)});
   }
  }
  fs.writeFileSync(path.join(out,'layout-audit.json'),JSON.stringify({frames:storyboard.scenes.length*2,issues},null,2));
  console.log(JSON.stringify({frames:storyboard.scenes.length*2,issues:issues.length}));if(issues.length)process.exitCode=1;
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
