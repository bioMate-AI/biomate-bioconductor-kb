/**
 * Narration-timed real BioMate UI recordings for the tutorial series.
 *
 * Every frame is a device-pixel screencast of the live product (no stills, no
 * mocked routes). Each action logs a close-up region that build-live-episode.py
 * zooms into; zh editions run with BioMate's own Chinese UI setting.
 *
 *   EPISODES=result-downloads,admet-evidence,reproducibility-record LANGS=en,zh TAKE=v3 \
 *   BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/tutorial-live-episodes.e2e.ts --project=chromium --workers=1
 */
import {test,expect,type Page,type Locator} from '@playwright/test';
import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';
import {loginAsFixture,BASE_URL} from './_fixture-login';
import {Screencast,focusOf,type Focus,type TimelineEvent} from './_tutorial-screencast';

const ROOT=path.resolve('..');
const SESSION='chat-1790955154245-s17yy1qla';
const RUN_ID='c40459b2-4dd0-407e-bbbd-e985df4ce0fc';
const VIEWPORT={width:1600,height:900};
const STORYBOARDS:Record<string,string>={
 'result-downloads':'reference/claude_design/tutorials/series/episodes/result-downloads/storyboard.json',
 'reproducibility-record':'reference/claude_design/tutorials/series/episodes/reproducibility-record/storyboard.json',
 'admet-evidence':'reference/claude_design/tutorials/review-pilot/storyboard.json',
};
const EPISODES=(process.env.EPISODES||'result-downloads').split(',');
const LANGS=(process.env.LANGS||'en,zh').split(',');
const TAKE=process.env.TAKE||'v3';
/** File-specific text that proves a preview rendered real content, not a spinner. */
const PREVIEW_KEY:Record<string,string>={
 'predict_admet_properties_results.json':'hERG inhibition',
 'qc_metrics.json':'admet_dili_probability_passes',
 'versions.yml':'biomni_function',
 'toxicity_report.json':'compounds_assessed',
};

/** Recorder-drawn pointer: screencasts omit the OS cursor. Pure overlay; never intercepts input. */
const CURSOR_OVERLAY=`(()=>{const add=()=>{if(document.getElementById('__rec_cursor'))return;const c=document.createElement('div');c.id='__rec_cursor';
c.style.cssText='position:fixed;left:0;top:0;width:22px;height:22px;margin:-11px 0 0 -11px;border-radius:50%;background:rgba(37,99,235,.28);border:2px solid rgba(37,99,235,.9);z-index:2147483647;pointer-events:none;transition:transform .12s;transform:translate(-100px,-100px)';
document.documentElement.appendChild(c);let x=-100,y=-100;
addEventListener('mousemove',e=>{x=e.clientX;y=e.clientY;c.style.transform='translate('+x+'px,'+y+'px)';},true);
addEventListener('mousedown',()=>{c.style.transform='translate('+x+'px,'+y+'px) scale(.7)';c.style.background='rgba(37,99,235,.55)';},true);
addEventListener('mouseup',()=>{c.style.transform='translate('+x+'px,'+y+'px)';c.style.background='rgba(37,99,235,.28)';},true);};
if(document.readyState==='loading')addEventListener('DOMContentLoaded',add);else add();})();`;

type Scene={id:number;seconds:number;narrationSha256:string};
class Director{
 events:TimelineEvent[]=[];scene=0;
 constructor(public page:Page,public cast:Screencast){}
 log(action:string,extra:Record<string,unknown>={}){this.events.push({scene:this.scene,seconds:this.cast.now(),action,...extra});}
 async focus(targets:Locator|Locator[]|null,label:string,pad=28){
  const focus:Focus|null=targets?await focusOf(this.page,Array.isArray(targets)?targets:[targets],pad):null;
  this.log('Focus: '+label,{focus});
 }
 async point(locator:Locator){const b=await locator.boundingBox();expect(b,'pointer target visible').not.toBeNull();await this.page.mouse.move(b!.x+b!.width/2,b!.y+b!.height/2,{steps:28});await this.page.waitForTimeout(300);}
 async click(locator:Locator,label:string){await this.point(locator);await locator.click({timeout:10000});this.log(label);}
 async hold(ms:number){await this.page.waitForTimeout(ms);}
}

async function openPreview(d:Director,name:string){
 const row=d.page.getByRole('row').filter({hasText:name});
 await d.click(row.getByText(/^(view|查看)$/).first(),'Preview '+name);
 const close=d.page.getByRole('button',{name:/^(Close preview|关闭预览)$/}).first();
 await expect(close).toBeVisible();
 const body=d.page.locator('pre').filter({hasText:PREVIEW_KEY[name]}).first();
 await expect(body,`preview of ${name} shows its real content`).toBeVisible({timeout:15000});
 await expect(d.page.getByText(/Loading preview|正在加载预览/)).toHaveCount(0);
 await expect(d.page.getByText(/Failed to load file|文件加载失败/)).toHaveCount(0);
 d.log('Preview content verified: '+name);
 return {body,close};
}
async function closePreview(d:Director,close:Locator){await d.click(close,'Close preview');}
/** Focus on the lines of a <pre> that contain `needle`, so the close-up shows the actual values. */
async function focusLines(d:Director,pre:Locator,needles:string[],label:string){
 const rect=await pre.evaluate((el,needles)=>{
  const text=el.textContent||'';const r=document.createRange();const boxes:DOMRect[]=[];
  const walker=document.createTreeWalker(el,NodeFilter.SHOW_TEXT);let node:Node|null;let offset=0;const nodes:{n:Node;start:number}[]=[];
  while((node=walker.nextNode())){nodes.push({n:node,start:offset});offset+=(node.textContent||'').length;}
  for(const needle of needles){let i=text.indexOf(needle);while(i>=0){const end=i+needle.length;const a=nodes.findLast(x=>x.start<=i)!;const b=nodes.findLast(x=>x.start<end)!;
   r.setStart(a.n,i-a.start);r.setEnd(b.n,end-b.start);r.getClientRects().length&&boxes.push(r.getBoundingClientRect());i=text.indexOf(needle,end);}}
  if(!boxes.length)return null;const host=el.getBoundingClientRect();
  const y0=Math.min(...boxes.map(b=>b.top)),y1=Math.max(...boxes.map(b=>b.bottom));
  return {x:host.left,y:y0,w:host.width,h:y1-y0};
 },needles);
 expect(rect,`values ${needles.join(', ')} visible in preview`).not.toBeNull();
 const vp=d.page.viewportSize()!;const pad=24;
 const f={x:Math.max(0,Math.round(rect!.x-pad)),y:Math.max(0,Math.round(rect!.y-pad)),w:Math.round(Math.min(vp.width,rect!.w+2*pad)),h:Math.round(Math.min(vp.height,rect!.h+2*pad))};
 d.log('Focus: '+label,{focus:f});
}
async function scrollIntoPanel(d:Director,locator:Locator){await locator.evaluate(el=>el.scrollIntoView({block:'center',behavior:'smooth'}));await d.hold(900);}

const tabs=(p:Page)=>({summary:p.getByTestId('after-tab-summary'),outputs:p.getByTestId('after-tab-outputs'),record:p.getByTestId('after-tab-record')});
const fileRow=(p:Page,name:string)=>p.getByRole('row').filter({hasText:name});
const header=(p:Page)=>p.getByText('Predict ADMET Properties (AI)',{exact:true}).last();

type Plan=Record<number,(d:Director)=>Promise<void>>;
const PLANS:Record<string,Plan>={
 'result-downloads':{
  1:async d=>{await d.focus(null,'Whole workspace');await d.hold(2500);await d.point(header(d.page));await d.focus([header(d.page),tabs(d.page).summary],'Workflow name and completed run');await d.hold(2500);},
  2:async d=>{const t=tabs(d.page);await d.focus([header(d.page),t.outputs],'Run identity and After-run tabs');await d.hold(2200);await d.click(t.outputs,'Open Outputs');await d.hold(900);
   await d.focus(d.page.getByRole('table').first(),'Output file table');for(const n of ['predict_admet_properties_results.json','qc_metrics.json','versions.yml']){await d.point(fileRow(d.page,n));await d.hold(1500);}},
  3:async d=>{for(const [n,needles] of [['predict_admet_properties_results.json',['hERG inhibition','DILI probability']],['qc_metrics.json',['dili_probability','admet_dili_probability_passes']],['versions.yml',['python','biomni_function']]] as const){
   await d.focus(null,'Wide before preview');const {body,close}=await openPreview(d,n);await focusLines(d,body,[...needles],'Values in '+n);await d.hold(2600);await d.focus(null,'Wide');await closePreview(d,close);await d.hold(400);}},
  4:async d=>{const row=fileRow(d.page,'toxicity_report.json');await d.focus(row,'toxicity_report.json row');await d.hold(900);
   const pending=d.page.waitForEvent('download');await d.click(row.getByRole('link',{name:/^(dl|下载)$/}).first(),'Download toxicity report');
   const dl=await pending;const out=path.join(ROOT,'recording/video/series-actions',`result-downloads-${TAKE}`,(d as any).lang);fs.mkdirSync(out,{recursive:true});
   const file=path.join(out,'downloaded-toxicity_report.json');await dl.saveAs(file);const data=JSON.parse(fs.readFileSync(file,'utf8'));expect(data.compounds_assessed).toBe(3);
   d.log('Downloaded content verified',{compounds:data.compounds_assessed,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')});await d.hold(800);
   await d.focus(null,'Wide');const {body,close}=await openPreview(d,'toxicity_report.json');await focusLines(d,body,['compounds_assessed','"smiles"'],'Compounds in the downloaded report');await d.hold(3200);await d.focus(null,'Wide');await closePreview(d,close);},
  5:async d=>{const t=tabs(d.page);await d.hold(800);await d.click(t.record,'Open Reproducibility record');await expect(d.page.getByTestId('repro-tab')).toBeVisible();
   await d.focus(d.page.getByTestId('repro-tab'),'Record identity and outputs',16);await d.hold(2500);await d.point(d.page.getByTestId('repro-tab'));await d.page.mouse.wheel(0,220);await d.hold(1800);},
 },
 'reproducibility-record':{
  1:async d=>{await d.focus(null,'Whole workspace');await d.hold(2000);await d.click(tabs(d.page).record,'Open Reproducibility record');await expect(d.page.getByTestId('repro-tab')).toBeVisible();await d.hold(800);await d.focus(d.page.getByTestId('after-record-tab'),'Record tab',12);await d.hold(2000);},
  2:async d=>{const repro=d.page.getByTestId('repro-tab');await d.focus(repro,'Workflow identity and run id',12);await d.hold(3500);await d.point(repro);await d.page.mouse.wheel(0,260);await d.hold(1500);await d.focus(repro,'Outputs listed in the record',12);await d.hold(2500);},
  3:async d=>{const inputs=d.page.getByText(/No bound inputs recorded|未记录绑定输入/).first();await scrollIntoPanel(d,inputs);await d.focus(inputs,'Empty input bindings',40);await d.hold(3200);
   const sha=d.page.getByRole('columnheader',{name:'SHA-256'}).first();await scrollIntoPanel(d,sha);await d.focus(d.page.getByRole('table').filter({has:sha}).first(),'Empty SHA-256 column',16);await d.hold(3000);},
  4:async d=>{const btn=d.page.getByRole('button',{name:/Compute checksums|计算校验和/}).first();await d.focus(btn,'Opt-in checksum control',60);await d.point(btn);await d.hold(4000);},
  5:async d=>{const s=d.page.getByTestId('record-section-params');await scrollIntoPanel(d,s);await d.click(s.locator('summary'),'Expand Resolved parameters');await d.hold(800);await d.focus(s,'Submitted parameters',12);await d.hold(3500);
   const dlRec=d.page.getByRole('button',{name:/Download record|下载记录/}).first();await scrollIntoPanel(d,dlRec);await d.focus(dlRec,'Download record (JSON)',60);await d.point(dlRec);await d.hold(2500);},
 },
 'admet-evidence':{
  1:async d=>{await d.focus(null,'Whole workspace');await d.hold(3000);await d.focus([header(d.page),tabs(d.page).summary],'Completed ADMET run');await d.hold(3000);},
  2:async d=>{const s=d.page.getByTestId('panel-tab-settings');await d.click(s,'Open Workflow settings');await d.hold(900);const smiles=d.page.getByText('smiles_list',{exact:false}).first();await expect(smiles).toBeVisible();
   await d.focus(smiles.locator('xpath=ancestor::*[self::div or self::tr][1]/..'),'Submitted SMILES in order',24);await d.hold(5000);await d.click(d.page.getByTestId('panel-tab-after-run'),'Back to After run');await d.hold(600);},
  3:async d=>{await d.click(tabs(d.page).summary,'Open Summary');await d.hold(600);const card=d.page.getByTestId('findings-card');await d.focus(card,'Findings across endpoints',12);await d.hold(6000);},
  4:async d=>{const t=tabs(d.page);await d.focus([header(d.page),t.summary],'Completed badge and Summary');await d.hold(2600);const note=d.page.getByTestId('findings-manifest-note');await scrollIntoPanel(d,note);
   const caveat=d.page.getByText(/confirm with wet-lab assays|湿实验/).first();await d.focus(caveat,'Experimental confirmation caveat',40);await d.hold(3500);},
  5:async d=>{await d.click(tabs(d.page).outputs,'Open Outputs');await d.hold(800);await d.focus(d.page.getByRole('table').first(),'Six output files');await d.hold(2500);
   await d.focus(null,'Wide');const {body,close}=await openPreview(d,'toxicity_report.json');await focusLines(d,body,['compounds_assessed'],'Report covers three compounds');await d.hold(2500);await d.focus(null,'Wide');await closePreview(d,close);},
  6:async d=>{await d.focus(null,'Wide');const {body,close}=await openPreview(d,'predict_admet_properties_results.json');await focusLines(d,body,['Compound:','hERG inhibition'],'hERG scores per compound');await d.hold(7000);(d as any).openClose=close;},
  7:async d=>{await closePreview(d,(d as any).openClose);await d.hold(400);const {body,close}=await openPreview(d,'toxicity_report.json');await focusLines(d,body,['herg_ic50_uM','hERG_probability'],'Classification score vs IC50 estimates');await d.hold(6500);await d.focus(null,'Wide');await closePreview(d,close);},
  8:async d=>{const {body,close}=await openPreview(d,'qc_metrics.json');await focusLines(d,body,['dili_probability','dili_probability_threshold','admet_dili_probability_passes'],'DILI 0.875 vs 0.5 threshold: check not passed');await d.hold(9000);await d.focus(null,'Wide');await closePreview(d,close);},
  9:async d=>{await d.click(tabs(d.page).record,'Open Reproducibility record');await expect(d.page.getByTestId('repro-tab')).toBeVisible();await d.hold(700);
   const inputs=d.page.getByText(/No bound inputs recorded|未记录绑定输入/).first();await scrollIntoPanel(d,inputs);await d.focus(inputs,'Empty input bindings',60);await d.hold(4000);
   const sha=d.page.getByRole('columnheader',{name:'SHA-256'}).first();await d.focus(d.page.getByRole('table').filter({has:sha}).first(),'Checksums not included by default',16);await d.hold(3500);},
  10:async d=>{await d.click(tabs(d.page).summary,'Back to Summary');await d.hold(600);await d.focus(d.page.getByTestId('findings-card'),'Findings with limits stated',12);await d.hold(5000);},
 },
};

function loadScenes(episode:string,lang:string):Scene[]{
 const sb=JSON.parse(fs.readFileSync(path.join(ROOT,STORYBOARDS[episode]),'utf8'));
 return sb.scenes.map((s:any)=>{const r=JSON.parse(fs.readFileSync(path.join(ROOT,`recording/audio/series/${episode}/${lang}/step-${String(s.id).padStart(3,'0')}.json`),'utf8'));
  const h=crypto.createHash('sha256').update(s[lang].narration).digest('hex');expect(r.narrationSha256,`narration audio for ${episode}/${lang}/${s.id} matches storyboard text`).toBe(h);
  return {id:s.id,seconds:r.seconds+.8,narrationSha256:h};});
}

/** Visible English-only labels inside the filmed panel (zh editions must not show untranslated UI). */
async function untranslatedLabels(page:Page){
 return page.evaluate(()=>{const root=document.querySelector('.after-run-report')?.closest('[data-testid]')?.parentElement||document.body;const seen=new Set<string>();
  const w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);let n;while((n=w.nextNode())){const t=(n.textContent||'').trim();const el=n.parentElement;if(!t||!el||el.closest('pre,code,table td,[data-no-i18n]'))continue;
   const r=el.getBoundingClientRect();if(!r.width||!r.height||r.bottom<0||r.top>innerHeight)continue;if(/[A-Za-z]{3,}/.test(t)&&!/[\u4e00-\u9fff]/.test(t))seen.add(t.slice(0,80));}
  return [...seen];});
}

test.use({viewport:VIEWPORT,deviceScaleFactor:2});
for(const episode of EPISODES)for(const lang of LANGS)test(`record ${episode} ${lang}`,async({page})=>{
 test.setTimeout(420000);
 const scenes=loadScenes(episode,lang);
 const out=path.join(ROOT,'recording/video/series-actions',`${episode}-${TAKE}`,lang);fs.mkdirSync(out,{recursive:true});
 await page.addInitScript(({lang})=>{const k='biomate-user-settings';let s:any={};try{s=JSON.parse(localStorage.getItem(k)||'{}');}catch{}s.language=lang==='zh'?'chinese':'english';localStorage.setItem(k,JSON.stringify(s));},{lang});
 await page.addInitScript(CURSOR_OVERLAY);
 await loginAsFixture(page);
 await page.goto(`${BASE_URL}/?session=${SESSION}`,{waitUntil:'domcontentloaded'});
 const t=tabs(page);await expect(t.outputs).toBeVisible({timeout:45000});
 const toggle=page.getByTestId('button-sidebar-toggle');if(await toggle.isVisible())await toggle.click();
 await t.outputs.click();
 const notNow=page.getByRole('button',{name:/^(Not now|暂不)$/});
 try{await notNow.waitFor({state:'visible',timeout:10000});await notNow.click();}catch{if(await notNow.isVisible())throw new Error('Feedback dismissal failed');}
 await expect(notNow).toHaveCount(0);
 await t.summary.click();await page.mouse.move(VIEWPORT.width*0.62,VIEWPORT.height*0.55);await page.waitForTimeout(800);
 const labels:Record<string,string[]>={};
 const cast=new Screencast(page,path.join(out,'frames'));await cast.begin();
 const d=new Director(page,cast);(d as any).lang=lang;
 let target=0;
 for(const scene of scenes){d.scene=scene.id;d.log('Scene start');
  await PLANS[episode][scene.id](d);
  labels[`scene-${scene.id}`]=await untranslatedLabels(page);
  target+=scene.seconds;const remaining=target-cast.now();
  expect(remaining,`scene ${scene.id} actions must fit the narration (${scene.seconds.toFixed(1)} s)`).toBeGreaterThan(0);
  await page.waitForTimeout(remaining*1000);
 }
 const duration=cast.now();const frames=await cast.end();
 expect(frames.length,'screencast captured frames').toBeGreaterThan(50);
 fs.writeFileSync(path.join(out,'timeline.json'),JSON.stringify({episode,language:lang,take:TAKE,runId:RUN_ID,session:SESSION,baseUrl:BASE_URL,
  format:'REAL_UI_SCREENCAST',viewport:VIEWPORT,deviceScaleFactor:2,cursor:'recorder-drawn overlay (screencasts omit the OS pointer)',
  uiLanguageSetting:lang==='zh'?'chinese':'english',duration,scenes,events:d.events,untranslatedLabels:labels},null,2));
});
