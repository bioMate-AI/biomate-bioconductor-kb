/* BMLens — shows a real kit screen (BMUI.screen) through a camera window.
   <div class="lens" data-run="d1" data-screen="summary"
        data-focus="0:s-answer|8:tbl-shortlist@1.4"   camera moves (t:region[@maxScale]); 'all' = whole screen
        data-rings="12-20:row-A-07"                  highlight ring on a region between a–b seconds
        data-anim="10:fig-cv"                        region starts hidden-in, animates at t
        data-progress="0:1|3:2"                      running screens: step k is running at t
        data-cursor="35:confirm"></div>             cursor travels to a region and clicks */
window.BMLens=(function(){
const parse=s=>(s||'').split('|').filter(Boolean).map(x=>{const i=x.indexOf(':');return[x.slice(0,i),x.slice(i+1)];});
function build(l){if(l.querySelector('.lv')){l._b={layer:l.querySelector('.ll'),scr:l.querySelector('.bmx')};return;}if(!window.BMUI||!BMUI.runs[l.dataset.run])return;
 const vp=document.createElement('div');vp.className='lv';const layer=document.createElement('div');layer.className='ll';
 const pr=parse(l.dataset.progress);const so={w:+l.dataset.w||1000,cw:+l.dataset.cw||330};if(pr.length)so.progress=+pr[0][1];layer.innerHTML=BMUI.screen(l.dataset.run,l.dataset.screen,so);if(BMUI.mount3d)BMUI.mount3d(layer);
 vp.appendChild(layer);l.appendChild(vp);l._b={layer,scr:layer.firstElementChild};}
function rect(l,name){const{layer,scr}=l._b;if(name==='all')return{x:0,y:0,w:scr.offsetWidth,h:scr.offsetHeight};
 const el=scr.querySelector(`[data-region="${name}"]`);if(!el)return null;const t=layer.style.transform;layer.style.transform='none';
 const R=scr.getBoundingClientRect(),E=el.getBoundingClientRect(),K=R.width/scr.offsetWidth||1;layer.style.transform=t;
 return{x:(E.left-R.left)/K,y:(E.top-R.top)/K,w:E.width/K,h:E.height/K,el};}
function focus(l,spec,instant){let[name,mx='']=spec.split('@');const left=/[<L]$/.test(mx);mx=parseFloat(mx);const r=rect(l,name);if(!r)return;const{layer,scr}=l._b,W=l.offsetWidth,H=l._H||l.offsetHeight,P=name==='all'?0:22;
 const s=Math.min(left?Infinity:W/(r.w+2*P),H/(r.h+2*P),+mx||+l.dataset.max||1.7),SW=scr.offsetWidth*s,SH=scr.offsetHeight*s;
 const cl=(c,sz,L)=>sz<=L?(L-sz)/2:Math.min(0,Math.max(L-sz,c));
 const tx=cl(left?P-r.x*s:W/2-(r.x+r.w/2)*s,SW,W),ty=cl(name==='all'?0:H/2-(r.y+r.h/2)*s,SH,H);
 layer.style.transition=instant?'none':'transform 1.15s cubic-bezier(.6,0,.2,1)';layer.style.transform=`translate(${tx}px,${ty}px) scale(${s})`;l._s=s;}
function ring(l,name,on){let g=l._b.layer.querySelector(`.lring[data-for="${name}"]`);
 if(!g){const r=rect(l,name);if(!r)return;g=document.createElement('div');g.className='lring';g.dataset.for=name;Object.assign(g.style,{left:r.x-5+'px',top:r.y-5+'px',width:r.w+10+'px',height:r.h+10+'px'});l._b.layer.appendChild(g);}
 const s=l._s||1;g.style.borderWidth=(3/s)+'px';g.style.boxShadow=`0 0 0 ${6/s}px var(--hot-soft)`;g.style.borderRadius=(9/s)+'px';g.offsetWidth;g.classList.toggle('on',on);}
function progress(l,k){const scr=l._b.scr,steps=[...scr.querySelectorAll('[data-region^="step-"]')],n=steps.length;
 steps.forEach((s,j)=>{const i=j+1,c=k>i?'x_st-d':k===i?'x_st-r':'';s.classList.remove('x_st-d','x_st-r');if(c)s.classList.add(c);const ch=s.querySelector('.x-chip');if(ch)ch.textContent=BMUI.t(c==='x_st-d'?'Done':c==='x_st-r'?'Running':'Queued');});
 const bar=scr.querySelector('[data-region="p-runbar"] .x_bar i'),meta=scr.querySelector('[data-region="p-runbar"] .x_meta');if(bar)bar.style.width=Math.round(100*Math.min(n,k-1)/n)+'%';if(meta)meta.textContent=BMUI.t(`${Math.min(n,k-1)}/${n} steps`);
 let o=0;scr.querySelectorAll('.x-phase').forEach(p=>{const c=p.querySelectorAll('.x-step').length,a=o+1,b=o+c;p.classList.toggle('x_done',k>b);p.classList.toggle('x_running',k>=a&&k<=b);const pc=p.querySelector('.x_pc');if(pc)pc.textContent=`${Math.max(0,Math.min(c,k-a))}/${c}`;o=b;});}
function cursor(l,name,at){const r=rect(l,name);if(!r)return;let c=l._b.layer.querySelector('.lcur');if(!c){c=document.createElement('div');c.className='lcur';c.innerHTML='<svg viewBox="0 0 34 40"><path d="M3 2 L3 32 L11 25 L16 37 L22 34 L17 23 L28 23 Z" fill="#111" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/></svg>';l._b.layer.appendChild(c);}
 const s=l._s||1,x=r.x+r.w*.55,y=r.y+r.h*.55;Object.assign(c.style,{width:34/s+'px',height:40/s+'px',transition:'none',left:x+160/s+'px',top:y+120/s+'px',opacity:0});c.offsetWidth;
 c.style.transition='left 1.1s cubic-bezier(.55,0,.2,1),top 1.1s cubic-bezier(.55,0,.2,1),opacity .3s';Object.assign(c.style,{left:x+'px',top:y+'px',opacity:1});
 at(1.2,()=>{c.classList.remove('click');c.offsetWidth;c.classList.add('click');const t=r.el;t.classList.add('lpress');setTimeout(()=>t.classList.remove('lpress'),400);});at(4,()=>c.style.opacity=0);}
function reset(l){l._b.layer.querySelectorAll('.lring,.lcur').forEach(e=>e.remove());l._b.scr.querySelectorAll('.lpending,.lon').forEach(e=>e.classList.remove('lpending','lon'));}
function play(scene,at){scene.querySelectorAll('.lens').forEach(l=>{build(l);reset(l);
 if(l._h0==null)l._h0=l.style.height;l._H=0;l.style.transition='none';l.style.height=l._h0;l.offsetWidth;l.style.transition='';const F=parse(l.dataset.focus);let cur=F.length?F[0][1]:null;if(cur){focus(l,cur,true);F.slice(1).forEach(([t,s])=>at(+t,()=>{cur=s;focus(l,s);}));}
 parse(l.dataset.size).forEach(([t,hh])=>at(+t,()=>{l._H=+hh;l.style.height=hh+'px';if(cur)focus(l,cur);}));
 parse(l.dataset.anim).forEach(([t,n])=>{const r=rect(l,n);if(!r)return;r.el.classList.add('lpending');at(+t,()=>{r.el.classList.remove('lpending');r.el.classList.add('lon');});});
 const tags=[...scene.querySelectorAll('.tags .tag')];tags.forEach(t=>t.classList.remove('mo-on','mo-past'));
 parse(l.dataset.rings).forEach(([ab,n0])=>{const[a,b]=ab.split('-').map(Number),[n,tg]=n0.split('#'),tag=tg&&tags[+tg-1];at(a,()=>{ring(l,n,true);if(tag){tag.classList.remove('mo-past');tag.classList.add('mo-on');}});if(b)at(b,()=>{ring(l,n,false);if(tag){tag.classList.remove('mo-on');tag.classList.add('mo-past');}});});
 const P=parse(l.dataset.progress);if(P.length){progress(l,+P[0][1]);P.slice(1).forEach(([t,k])=>at(+t,()=>progress(l,+k)));}
 parse(l.dataset.cursor).forEach(([t,n])=>at(+t,()=>cursor(l,n,(d,f)=>at(+t+d,f))));});}
function final(root){root.querySelectorAll('.lens').forEach(l=>{build(l);reset(l);const Z=parse(l.dataset.size);if(Z.length){l._H=+Z[Z.length-1][1];l.style.height=l._H+'px';}const F=parse(l.dataset.focus);if(F.length)focus(l,F[F.length-1][1],true);const P=parse(l.dataset.progress);if(P.length)progress(l,+P[P.length-1][1]);});}
if(/[?&]review\b/.test(location.search))document.body.classList.add('review');
addEventListener('keydown',function(e){if(e.key==='r'||e.key==='R')document.body.classList.toggle('review');});
return{build,play,final};
})();
