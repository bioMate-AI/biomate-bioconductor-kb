(function(){
const NAV=window.MANUAL_NAV,I18N=window.MANUAL_I18N;
const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>Array.from(r.querySelectorAll(s));
let lang=(new URLSearchParams(location.search).get("lang"))||localStorage.getItem("bm-manual-lang")||"en";if(lang!=="zh")lang="en";
const T=k=>I18N[lang][k];
// ---------- routes ----------
const ROUTES=[];const META={};
NAV.forEach(p=>{const push=(it,g)=>{ROUTES.push(it[0]);META[it[0]]={en:it[1],zh:it[2],part:p,group:g};};
 if(p.items)p.items.forEach(it=>push(it));if(p.groups)p.groups.forEach(g=>g.items.forEach(it=>push(it,g)));});
const BYBASE={};ROUTES.forEach(r=>BYBASE[r.split("/").pop()]=r);
const isTut=r=>r.startsWith("tutorials/");
function fileFor(r){if(lang==="zh"){if(isTut(r))return "content/tutorials/zh/"+r.slice(10)+".zh.md";if((window.MANUAL_ZH||[]).includes(r))return "content/zh/"+r+".zh.md";}return "content/"+r+".md";}
function norm(p){const out=[];p.split("/").forEach(s=>{if(s===""||s===".")return;if(s==="..")out.pop();else out.push(s);});return out.join("/");}
function routeFromPath(p){p=p.replace(/^content\//,"").replace(/^zh\//,"");if(p==="README.md")return "";if(/^tutorials\/(zh\/)?README(\.zh)?\.md$/.test(p))return "tutorials";
 let q=p.replace(/^tutorials\/zh\//,"tutorials/").replace(/\.zh\.md$/,"").replace(/\.md$/,"");if(META[q])return q;const b=q.split("/").pop();return BYBASE[b]!==undefined?BYBASE[b]:null;}
const href=(r,a)=>"#/"+r+(a?"~"+encodeURIComponent(a):"");
// ---------- data caches ----------
const cache={};const get=u=>cache[u]||(cache[u]=fetch(u).then(r=>{if(!r.ok)throw new Error(r.status);return r.text();}));
let STATUS={},LEDGER=null;
const ready=Promise.all([get("content/README.md").then(t=>{t.replace(/^- \[(.)\] `([^`]+)`/gm,(_,k,p)=>{STATUS[p.replace(/\.md$/,"")]=k;});}).catch(()=>{}),
 get("content/coverage-ledger.md").then(t=>{LEDGER=parseLedger(t);}).catch(()=>{LEDGER={};})]);
function parseLedger(t){const out={};t.split(/^## /m).slice(1).forEach(sec=>{
  const m=sec.match(/(?:Page|Pages|Chapter):\s*`([^`]+)`/);if(!m||/…|\.\.\./.test(m[1]))return;
  const r=m[1].replace(/^docs\/user-manual\//,"").replace(/\.md$/,"");if(!META[r])return;
  const e=out[r]||(out[r]={ok:0,fix:0,pend:0,road:0,gaps:[]});
  sec.split("\n").filter(l=>/^\|/.test(l)&&!/^\|\s*-/.test(l)).forEach(l=>{const c=l.split("|").slice(1,-1).map(x=>x.trim());
   const st=c.find((x,i)=>i>0&&/✅|🔧|⏳|🗺/.test(x));if(!st)return;
   if(/✅/.test(st))e.ok++;if(/🔧/.test(st))e.fix++;if(/⏳/.test(st))e.pend++;if(/🗺/.test(st)){e.road++;e.gaps.push(c[0].replace(/^(GAP|MISMATCH):\s*/,""));}});});
 return out;}
// ---------- markdown hooks ----------
function mdOpts(file,route){const dir=file.split("/").slice(0,-1).join("/");
 return {zh:lang==="zh",idPrefix:window.shotCode(route)+(file.includes("/zh/")?".zh":""),
  self:id=>href(route,id),
  link:h=>{if(/^(https?:|mailto:)/.test(h))return{href:h,ext:true};if(h[0]==="#")return{href:href(route,h.slice(1))};
   const [p,a]=h.split("#");const r=routeFromPath(norm(dir+"/"+p));if(r===null)return null;return{href:href(r,a)};},
  img:s=>/^https?:/.test(s)?s:norm(dir+"/"+s),
  figure:(src,alt,cap,id,spec)=>'<figure class="shot" data-shot-id="'+id+'"'+(spec?' data-capture="'+spec.replace(/"/g,"&quot;")+'"':'')+'><button class="shotbtn" type="button" data-full="'+src+'" aria-label="Enlarge screenshot"><img src="'+src+'" alt="'+alt.replace(/"/g,"&quot;")+'" loading="lazy"></button><figcaption><span class="shottag" title="'+T("shotNote")+'">'+T("shotTag")+'</span>'+cap+'</figcaption></figure>',
  pending:(txt,id,spec)=>pendingFig(txt,id,spec)};}
function pendingFig(txt,id,spec,add){return '<figure class="shot pending'+(add?" added":"")+'"'+(id?' data-shot-id="'+id+'"':'')+(spec?' data-capture="'+String(spec).replace(/"/g,"&quot;")+'"':'')+'><div class="ph"><span>'+T("shotPending")+'</span>'+(id?'<code class="sid">'+id+'</code>':'')+'</div>'+(txt?'<figcaption>'+txt+'</figcaption>':'')+'</figure>';}
function addShots(body,r){const list=(window.MANUAL_SHOTS||{})[r];if(!list)return;const h2s=$$("h2",body);
 list.forEach(s=>{const h=h2s[s.h2-1];if(!h)return;let at=h;let n=h.nextElementSibling;if(n&&n.classList.contains("rm-lbl")){at=n;n=n.nextElementSibling;}
  if(n&&/^(P|UL|OL|DIV|ASIDE)$/.test(n.tagName)&&!n.classList.contains("shot"))at=n;
  while(at.nextElementSibling&&at.nextElementSibling.classList.contains("added"))at=at.nextElementSibling;
  const t=document.createElement("div");t.innerHTML=pendingFig(s[lang],s.id+(lang==="zh"&&isTut(r)?".zh":""),s.spec,true);at.after(t.firstElementChild);});}
// ---------- nav ----------
function buildNav(cur){const n=$("#nav");let h='<a class="nav-home'+(cur===""?" on":"")+'" href="#/">'+T("home")+'</a>';
 NAV.forEach(p=>{const open=cur&&((p.items&&p.items.some(i=>i[0]===cur))||(p.groups&&(cur==="tutorials"||p.groups.some(g=>g.items.some(i=>i[0]===cur)))));
  h+='<details class="part"'+(open?" open":"")+'><summary><span class="pn">'+p.num+'</span>'+p[lang]+'</summary>';
  if(p.items)h+='<ul>'+p.items.map(i=>'<li><a href="'+href(i[0])+'"'+(i[0]===cur?' class="on" aria-current="page"':'')+'>'+i[lang==="zh"?2:1]+(lang==="zh"&&!(window.MANUAL_ZH||[]).includes(i[0])?'<span class="en-tag">EN</span>':'')+'</a></li>').join("")+'</ul>';
  if(p.groups){h+='<ul><li><a href="#/tutorials"'+(cur==="tutorials"?' class="on"':'')+'>'+(lang==="zh"?"全部教程":"All tutorials")+'</a></li></ul>';p.groups.forEach(g=>{h+='<div class="grp">'+g[lang]+'</div><ul>'+g.items.map(i=>'<li><a href="'+href(i[0])+'"'+(i[0]===cur?' class="on" aria-current="page"':'')+'>'+i[lang==="zh"?2:1]+'</a></li>').join("")+'</ul>';});}
  h+='</details>';});
 n.innerHTML=h;const on=$(".on",n);if(on){const top=on.offsetTop-n.clientHeight/2;if(top>0)n.scrollTop=top;}}
function partLabel(r){const m=META[r];if(!m)return "";const p=m.part;
 if(p.id==="app")return p[lang];if(p.id==="tut")return T("title")==="用户手册"?"教程 · "+m.group.zh:"Tutorials · "+m.group.en;
 return lang==="zh"?"第 "+p.num+" 部分 · "+p.zh:"Part "+p.num+" · "+p.en;}
// ---------- pages ----------
function homePage(){const cards=NAV.map(p=>{const items=p.items||p.groups.flatMap(g=>g.items);
  return '<a class="pcard" href="'+(p.id==="tut"?"#/tutorials":href(items[0][0]))+'"><span class="pn">'+p.num+'</span><span class="pt">'+p[lang]+'</span><span class="pc">'+items.length+" "+(p.id==="tut"?T("tutorials"):T("chapters"))+'</span><span class="pl">'+items.slice(0,4).map(i=>i[lang==="zh"?2:1].replace(/^[A-Z]?[IVX.\d]+ · /,"")).join(" · ")+(items.length>4?" …":"")+'</span></a>';}).join("");
 const start=[["tutorials/T0-getting-started"],["overview/00-what-is-biomate"],["overview/03-first-analysis-5min"]].map(([r])=>'<a class="scard" href="'+href(r)+'"><span class="sk">'+partLabel(r)+'</span><span class="st">'+META[r][lang]+'</span><span class="arr">→</span></a>').join("");
 return '<article class="doc home"><div class="eyebrow">'+T("homeEyebrow")+'</div><h1>'+T("homeTitle")+'</h1><p class="lede">'+T("homeLede")+'</p>'+
  '<h2 id="start">'+T("start")+'</h2><div class="starts">'+start+'</div><h2 id="parts">'+(lang==="zh"?"全部内容":"Contents")+'</h2><div class="pgrid">'+cards+'</div>'+
  '<aside class="callout honesty"><strong>'+T("honestyLbl")+'</strong><p>'+T("honesty")+'</p><p><a href="'+href("appendix/E-coverage-and-roadmap")+'">'+T("openRoadmap")+' →</a></p></aside></article>';}
function tutHub(){const p=NAV.find(x=>x.id==="tut");
 return '<article class="doc"><div class="eyebrow">'+p[lang]+'</div><h1>'+(lang==="zh"?"BioMate 教程":"BioMate tutorials")+'</h1><p class="lede">'+T("tutHub")+'</p>'+
  p.groups.map(g=>'<h2 id="'+mdSlug(g.en)+'">'+g[lang]+'</h2><div class="tlist">'+g.items.map(i=>'<a href="'+href(i[0])+'"><span class="tk">'+(i[1].split(" · ")[1]?i[1].split(" · ")[0]:"")+'</span><span>'+(i[lang==="zh"?2:1].split(" · ")[1]||i[lang==="zh"?2:1])+'</span></a>').join("")+'</div>').join("")+'</article>';}
function coverage(r){const e=LEDGER&&LEDGER[r];if(!e)return "";
 const seg=(n,k,c)=>n?'<span class="cv '+c+'"><b>'+n+'</b> '+T(k)+'</span>':"";
 let h='<div class="coverage"><span class="cvl">'+T("cov")+'</span>'+seg(e.ok,"covV","ok")+seg(e.fix,"covC","fix")+seg(e.pend,"covP","pend")+seg(e.road,"covR","road");
 if(e.gaps.length)h+='<details class="gaps"><summary>'+T("covOpen")+'</summary><ul>'+e.gaps.map(g=>{const c=window.mdClean?window.mdClean(g,"cell"):g;return c?'<li>'+window.mdInline(c)+'</li>':'';}).join("")+'</ul><a href="'+href("appendix/E-coverage-and-roadmap")+'">'+(lang==="zh"?"附录 E · 覆盖范围与路线图 →":"Appendix E · Coverage & roadmap →")+'</a></details>';
 return h+'</div>';}
window.mdInline=s=>s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/`([^`]+)`/g,"<code>$1</code>").replace(/\*\*([^*]+)\*\*/g,"<strong>$1</strong>");
const LIMITS=/not covered|honest limits|what's not|what is not|not yet|known gaps|roadmap|局限|尚未|未覆盖|不涵盖|还不能|暂不/i;
function decorate(art,r){
 // roadmap-style sections
 $$("h2",art).forEach(h2=>{if(!LIMITS.test(h2.textContent))return;const sec=document.createElement("section");sec.className="roadmap-sec";
  const lbl=document.createElement("div");lbl.className="rm-lbl";lbl.textContent=T("roadmapLbl");h2.before(sec);sec.append(h2);
  let n=sec.nextSibling;while(n&&!(n.nodeType===1&&/^H[12]$/.test(n.tagName))&&!(n.nodeType===1&&n.tagName==="HR")){const nx=n.nextSibling;sec.append(n);n=nx;}h2.after(lbl);});
 // trailing colophon (verification notes / companion refs)
 const kids=Array.from(art.children);const last=kids[kids.length-1];
 if(last&&last.tagName==="P"&&last.children.length===1&&last.firstElementChild.tagName==="EM"&&last.textContent.trim()===last.firstElementChild.textContent.trim())last.classList.add("colophon");
 // callout labels
 $$("aside.callout",art).forEach(a=>{const f=a.firstElementChild;if(f&&f.tagName==="P"&&f.firstElementChild&&f.firstElementChild.tagName==="STRONG"&&f.innerHTML.indexOf("<strong>")===0)f.firstElementChild.classList.add("lead");});
 // tables: mark status / narrow first column
 $$(".tbl table",art).forEach(t=>{const cols=t.rows[0]?t.rows[0].cells.length:0;if(cols>=4)t.classList.add("dense");});
 // headings left without content after sanitising
 $$("h2,h3,h4",art).reverse().forEach(h=>{const lv=+h.tagName[1];let n=h.nextElementSibling;if(n&&n.classList.contains("rm-lbl"))n=n.nextElementSibling;
  if(!n||(/^H[1-6]$/.test(n.tagName)&&+n.tagName[1]<=lv)||n.tagName==="HR"){const sec=h.parentElement;h.remove();if(sec&&sec.classList.contains("roadmap-sec")&&!sec.querySelector("h2,h3,p,ul,ol,.tbl"))sec.remove();}});
}
async function chapter(r,anchor){
 let file=fileFor(r);let src,enOnly=lang==="zh"&&!file.includes("/zh/");
 try{src=await get(file);}catch(e){if(lang!=="zh")throw e;file="content/"+r+".md";src=await get(file);enOnly=true;}
 const res=window.renderMarkdown(src,mdOpts(file,r));
 const m=META[r];const title=(res.h1||m[lang]).replace(/\*([^*]+)\*/g,"$1");
 const st=STATUS[r];const flat=ROUTES;const i=flat.indexOf(r);const pv=flat[i-1],nx=flat[i+1];
 const isRoad=r==="appendix/E-coverage-and-roadmap";
 let h='<article class="doc'+(isRoad?" roadmap-page":"")+'"'+(enOnly?' lang="en"':'')+'><div class="eyebrow">'+partLabel(r)+'</div><h1>'+window.mdInline(title)+'</h1>';
 h+='<div class="docmeta">'+(st?'<span class="tok '+(st==="x"?"ok":"pend")+'">'+(st==="x"?T("verified"):T("drafted"))+'</span>':'')+(isRoad?'<span class="tok road">'+T("roadmap")+'</span>':'')+'</div>';
 if(enOnly)h+='<p class="langnote" lang="zh">'+T("enOnly")+'</p>';
 h+=coverage(r);
 h+='<div class="body">'+res.html+'</div>';
 h+='<nav class="pager">'+(pv?'<a class="pv" href="'+href(pv)+'"><span>'+T("prev")+'</span>'+META[pv][lang]+'</a>':'<span></span>')+(nx?'<a class="nx" href="'+href(nx)+'"><span>'+T("next")+'</span>'+META[nx][lang]+'</a>':'')+'</nav></article>';
 return {html:h,heads:res.heads,title};}
// ---------- render ----------
let spy=null,renderSeq=0;
async function render(){const tok=++renderSeq;
 const raw=decodeURIComponent(location.hash.replace(/^#\/?/,""));const [r0,anchor]=raw.split("~");const r=r0||"";
 document.documentElement.lang=lang==="zh"?"zh-CN":"en";
 $$(".lang button").forEach(b=>b.setAttribute("aria-pressed",b.dataset.l===lang));
 $("#q").placeholder=T("search");$(".trial .t").textContent=T("trial");$(".menu-btn span").textContent=T("menu");
 buildNav(r);await ready;if(tok!==renderSeq)return;
 const main=$("#main");let out;
 try{
  if(r==="")out={html:homePage(),title:T("homeTitle")};
  else if(r==="tutorials")out={html:tutHub(),title:lang==="zh"?"教程":"Tutorials"};
  else if(META[r])out=await chapter(r,anchor);
  else out={html:'<article class="doc"><h1>404</h1><p><a href="#/">'+T("home")+'</a></p></article>',title:"404"};
 }catch(e){out={html:'<article class="doc"><h1>—</h1><p>'+e.message+'</p></article>',title:"—"};}
 if(tok!==renderSeq)return;
 main.innerHTML=out.html;const art=$("article",main);if(art&&META[r]){decorate($(".body",art)||art,r);addShots($(".body",art)||art,r);}
 if(r==="tutorials"||r==="")out.heads=$$("h2",art).map(h=>({n:2,id:h.id,t:h.textContent}));
 document.title="BioMate · "+out.title.replace(/<[^>]+>/g,"")+" — "+T("title");
 buildToc((out.heads||[]).filter(h=>document.getElementById(h.id)));document.body.classList.remove("nav-open");
 const tgt=anchor&&document.getElementById(anchor);
 window.scrollTo(0,tgt?tgt.getBoundingClientRect().top+scrollY-84:0);
}
function buildToc(heads){const t=$("#toc");const hs=heads.filter(h=>h.n<=3);
 if(spy)spy.disconnect();if(!hs.length){t.innerHTML="";return;}
 t.innerHTML='<div class="toc-h">'+T("onPage")+'</div><ul>'+hs.map(h=>'<li class="l'+h.n+'"><a href="#" data-id="'+h.id+'">'+h.t+'</a></li>').join("")+'</ul>';
 const links={};$$("a",t).forEach(a=>links[a.dataset.id]=a);
 spy=new IntersectionObserver(es=>{es.forEach(e=>{if(e.isIntersecting){$$("a.on",t).forEach(x=>x.classList.remove("on"));const a=links[e.target.id];if(a)a.classList.add("on");}});},{rootMargin:"-80px 0px -70% 0px"});
 hs.forEach(h=>{const el=document.getElementById(h.id);if(el)spy.observe(el);});}
// ---------- search ----------
let IDX=null,IDXLANG=null;
function plain(s){return s.replace(/<!--[\s\S]*?-->/g,"").replace(/`([^`]*)`/g,"$1").replace(/!\[[^\]]*\]\([^)]*\)/g,"").replace(/\[([^\]]+)\]\([^)]*\)/g,"$1").replace(/[*_>#|]/g," ").replace(/\s+/g," ").trim();}
async function buildIndex(){if(IDX&&IDXLANG===lang)return IDX;IDXLANG=lang;const out=[];
 await Promise.all(ROUTES.map(async r=>{let src;try{src=await get(fileFor(r));}catch(e){try{src=await get("content/"+r+".md");}catch(_){return;}}
  src=src.replace(/<!--[\s\S]*?-->/g,"");const used={};let sec={id:"",t:"",body:[]};const secs=[sec];let inF=false;
  src.split("\n").forEach(l=>{if(/^\s*```/.test(l))inF=!inF;const m=!inF&&l.match(/^(#{2,6})\s+(.*)$/);
   if(m){const t=plain(window.mdClean(m[2],"head"));let s=mdSlug(t.replace(/[<>]/g,""));used[s]=(used[s]||0)+1;if(used[s]>1)s+="-"+used[s];sec={id:s,t,body:[]};secs.push(sec);}else if(!/^# /.test(l))sec.body.push(l);});
  secs.forEach(s=>out.push({r,id:s.id,sec:s.t,text:plain(window.mdClean(s.body.join(" "),"para")),title:META[r][lang]}));}));
 IDX=out;return out;}
function snippet(text,terms){const low=text.toLowerCase();let at=-1;for(const t of terms){at=low.indexOf(t);if(at>=0)break;}
 let s=at<0?text.slice(0,140):text.slice(Math.max(0,at-50),at+110);if(at>50)s="…"+s;
 s=s.replace(/&/g,"&amp;").replace(/</g,"&lt;");terms.forEach(t=>{if(!t)return;s=s.replace(new RegExp("("+t.replace(/[.*+?^${}()|[\]\\]/g,"\\$&")+")","gi"),"<mark>$1</mark>");});return s;}
let sel=-1;
async function doSearch(q){const box=$("#results");q=q.trim().toLowerCase();if(!q){box.hidden=true;return;}
 const idx=await buildIndex();const terms=q.split(/\s+/).filter(Boolean);
 const hits=[];idx.forEach(e=>{const tt=e.title.toLowerCase(),ss=e.sec.toLowerCase(),xx=e.text.toLowerCase();let sc=0;
  for(const t of terms){const a=tt.includes(t),b=ss.includes(t),c=xx.includes(t);if(!a&&!b&&!c)return;sc+=(a?8:0)+(b?5:0)+(c?1+Math.min(4,xx.split(t).length-2):0);}hits.push([sc,e]);});
 hits.sort((a,b)=>b[0]-a[0]);const top=hits.slice(0,24);sel=top.length?0:-1;
 box.innerHTML=top.length?top.map(([_,e],i)=>'<a class="hit'+(i===0?" sel":"")+'" href="'+href(e.r,e.id)+'"><span class="ht">'+e.title+(e.sec?' <i>›</i> '+e.sec.replace(/</g,"&lt;"):'')+'</span><span class="hs">'+snippet(e.text,terms)+'</span></a>').join(""):'<div class="none">'+T("noResults")+'</div>';
 box.hidden=false;}
// ---------- wiring ----------
function setLang(l){if(l===lang)return;lang=l;localStorage.setItem("bm-manual-lang",l);IDX=null;$("#results").hidden=true;render();}
window.addEventListener("hashchange",render);
document.addEventListener("click",e=>{
 const lb=e.target.closest(".lang button");if(lb){setLang(lb.dataset.l);return;}
 const tl=e.target.closest("#toc a[data-id]");if(tl){e.preventDefault();const el=document.getElementById(tl.dataset.id);if(el){history.replaceState(null,"",href(location.hash.replace(/^#\/?/,"").split("~")[0],tl.dataset.id));window.scrollTo({top:el.getBoundingClientRect().top+scrollY-84,behavior:"smooth"});}return;}
 const an=e.target.closest("a.anchor");if(an){e.preventDefault();const u=location.href.split("#")[0]+an.getAttribute("href");history.replaceState(null,"",an.getAttribute("href"));if(navigator.clipboard)navigator.clipboard.writeText(u).catch(()=>{});toast(T("copied"));return;}
 const sb=e.target.closest(".shotbtn");if(sb){openLB(sb.dataset.full,sb.querySelector("img").alt);return;}
 if(e.target.closest("#lb")&&!e.target.closest("#lb img")){closeLB();return;}
 if(e.target.closest(".menu-btn")){document.body.classList.toggle("nav-open");return;}
 if(!e.target.closest(".search")){$("#results").hidden=true;}
 if(e.target.closest("#results a")){$("#results").hidden=true;$("#q").blur();}
});
document.addEventListener("error",e=>{const im=e.target;if(im.tagName!=="IMG")return;const f=im.closest("figure.shot");if(f&&!f.classList.contains("pending")){const cap=f.querySelector("figcaption");const t=document.createElement("div");t.innerHTML=pendingFig(cap?cap.innerHTML.replace(/<span class="shottag"[^>]*>.*?<\/span>/,""):"",f.dataset.shotId,f.dataset.capture);f.replaceWith(t.firstElementChild);}},true);
const q=$("#q");let tmr;
q.addEventListener("input",()=>{clearTimeout(tmr);tmr=setTimeout(()=>doSearch(q.value),120);});
q.addEventListener("focus",()=>{buildIndex();if(q.value.trim())doSearch(q.value);});
q.addEventListener("keydown",e=>{const hs=$$("#results .hit");
 if(e.key==="ArrowDown"||e.key==="ArrowUp"){e.preventDefault();if(!hs.length)return;sel=(sel+(e.key==="ArrowDown"?1:-1)+hs.length)%hs.length;hs.forEach((h,i)=>h.classList.toggle("sel",i===sel));const s=hs[sel];const b=$("#results");if(s.offsetTop<b.scrollTop||s.offsetTop+s.offsetHeight>b.scrollTop+b.clientHeight)b.scrollTop=s.offsetTop-40;}
 else if(e.key==="Enter"&&hs[sel]){location.hash=hs[sel].getAttribute("href");$("#results").hidden=true;q.blur();}
 else if(e.key==="Escape"){$("#results").hidden=true;q.blur();}});
document.addEventListener("keydown",e=>{if(e.key==="Escape")closeLB();
 if((e.key==="/"&&!/INPUT|TEXTAREA/.test(document.activeElement.tagName))||((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==="k")){e.preventDefault();q.focus();q.select();}});
function openLB(src,alt){const lb=$("#lb");$("img",lb).src=src;$("img",lb).alt=alt;$(".lbcap",lb).textContent=T("shotNote");$(".lbclose",lb).textContent=T("close");lb.hidden=false;}
function closeLB(){$("#lb").hidden=true;}
let tt;function toast(m){const t=$("#toast");t.textContent=m;t.hidden=false;clearTimeout(tt);tt=setTimeout(()=>t.hidden=true,1400);}
render();
})();
