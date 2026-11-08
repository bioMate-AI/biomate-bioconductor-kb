// Generalized: capture REAL BioMate product UI for ANY workflow from a NL goal.
// Env: CAPTURE_GOAL (required), CAPTURE_OUT (dir), CAPTURE_MODE=prerun|full, BIOMATE_URL
const { chromium } = require('/Users/kky/biomate-review/frontend/node_modules/playwright');
const fs=require('fs'), path=require('path');
const BASE=process.env.BIOMATE_URL||"https://dev-public.biomate.ai";
const GOAL=process.env.CAPTURE_GOAL; const OUT=process.env.CAPTURE_OUT;
const MODE=process.env.CAPTURE_MODE||"prerun";
const LANG=process.env.CAPTURE_LANG||"en"; // en|zh — zh switches the BioMate UI to Chinese
if(!GOAL||!OUT){console.error("need CAPTURE_GOAL + CAPTURE_OUT");process.exit(2);}
fs.mkdirSync(OUT,{recursive:true});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function login(){
  const https=require('https');
  return new Promise((res,rej)=>{
    const d=JSON.stringify({email:"lifeifei163361@163.com",password:"WpmFixture!2026"});
    const u=new URL(BASE+"/api/auth/login");
    const rq=https.request({hostname:u.hostname,path:u.pathname,method:"POST",headers:{"Content-Type":"application/json","Content-Length":Buffer.byteLength(d)}},r=>{let b="";r.on("data",c=>b+=c);r.on("end",()=>{try{res(JSON.parse(b).token)}catch(e){rej(b)}})});
    rq.on("error",rej);rq.write(d);rq.end();
  });
}
(async()=>{
  const token=await login();
  const b=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
  const ctx=await b.newContext({viewport:{width:1600,height:1000},deviceScaleFactor:2});
  const host=new URL(BASE).hostname;
  await ctx.addCookies([{name:"biomate_token",value:token,domain:host,path:"/",secure:true,sameSite:"Lax"}]);
  if(LANG==="zh"){
    // i18n.ts reads localStorage['biomate-user-settings'].language once at load (no live re-render),
    // so seed it BEFORE any app script runs; "chinese" → zh locale bundle.
    await ctx.addInitScript(()=>{try{const k='biomate-user-settings';let s={};try{s=JSON.parse(localStorage.getItem(k)||'{}')}catch(e){}s.language='chinese';localStorage.setItem(k,JSON.stringify(s));}catch(e){}});
    console.log("locale: zh (chinese UI)");
  }
  const pg=await ctx.newPage();
  const shot=async(n,sel)=>{try{const l=pg.locator(sel).first();await l.waitFor({state:"visible",timeout:8000});await l.screenshot({path:path.join(OUT,n)});console.log("shot",n);return true}catch(e){return false}};
  try{
    await pg.goto(BASE+"/",{waitUntil:"commit",timeout:60000});
    const input=pg.getByTestId("chat-input"); await input.waitFor({state:"visible",timeout:90000}); await sleep(4000);
    await input.click(); await input.fill(GOAL);
    const send=pg.locator('[data-testid="chat-send-button"]:not([disabled])'); await send.waitFor({state:"visible",timeout:30000}); await send.click();
    console.log("submitted:",GOAL.slice(0,60));
    // wait for the workflow panel / confirm button
    const confirm=pg.getByRole("button",{name:/confirm.*run|确认并运行|确认运行|确认运行工作流/i});
    await confirm.first().waitFor({timeout:180000}); await sleep(3500);
    // full-page chat+panel composite + the panel + the chat card
    await pg.screenshot({path:path.join(OUT,"full.png")});
    await shot("panel-prerun.png",'[data-testid="workflow-artifact-panel"]');
    await shot("chat-card.png",'[data-testid^="wf-chip"], .wf-card, [data-testid="workflow-card"]');
    await shot("param-strip.png",'[data-testid="workflow-overall-status-badge"]');
    if(MODE==="full"){
      await confirm.first().click({timeout:15000}); console.log("confirmed run");
      await sleep(8000); await shot("running.png",'[data-testid="workflow-artifact-panel"]');
      // best-effort completed states (may timeout for long/non-running)
      try{ await pg.getByTestId("after-summary-tab").first().waitFor({timeout:600000}); await sleep(2000);
           await shot("completed-findings.png",'[data-testid="after-summary-tab"]');
           await shot("outputs-table.png",'[data-testid="output-files-table"]');
           await shot("completed-panel.png",'[data-testid="workflow-artifact-panel"]'); }catch(e){console.log("completed states not reached:",e.message);}
    }
  }catch(e){console.log("CAPTURE ERROR",e.message); try{await pg.screenshot({path:path.join(OUT,"_fail.png")})}catch{}}
  await b.close();
})();
