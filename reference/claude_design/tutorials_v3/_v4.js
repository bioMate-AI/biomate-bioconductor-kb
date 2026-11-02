/* BioMate walkthrough v4 engine — scenes, beat timeline, charts, overview. */
(function(){
const S=[...document.querySelectorAll('.scene')],KEY='bm-v4-'+(document.body.dataset.deck||'deck');
const REC=/[?&]rec=1/.test(location.search);if(REC)document.documentElement.classList.add('rec');
let i=REC?0:Math.min(S.length-1,+(localStorage.getItem(KEY)||0)),playing=true,T=[];
window.__sceneDurations=S.map(s=>+s.dataset.seconds||30);window.__timeline=(()=>{let t=0;return S.map((s,k)=>{const d=window.__sceneDurations[k],r={scene:k+1,label:s.dataset.label||'',start:t,seconds:d};t+=d;return r;});})();window.__total=window.__sceneDurations.reduce((a,b)=>a+b,0);window.__done=false;
function fit(){if(!innerWidth||!innerHeight)return;const k=Math.min(innerWidth/1920,innerHeight/1080);document.body.style.transform=`translate(${(innerWidth-1920*k)/2}px,${(innerHeight-1080*k)/2}px) scale(${k})`;}
addEventListener('resize',fit);addEventListener('load',fit);fit();requestAnimationFrame(fit);if(window.ResizeObserver)new ResizeObserver(fit).observe(document.documentElement);
/* seeded rng */
function rng(a){return()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;}}
function gauss(r){let u=0,v=0;while(!u)u=r();while(!v)v=r();return Math.sqrt(-2*Math.log(u))*Math.cos(2*Math.PI*v);}
const D=window.__deckData=window.__deckData||{};
const ns='http://www.w3.org/2000/svg';
const svg=(w,h,inner)=>`<svg xmlns="${ns}" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${inner}</svg>`;
const C={
 hist(el){const m=D.measured,w=+el.dataset.w||560,h=+el.dataset.h||170,b=[];for(let x=4;x<10;x+=.5)b.push(m.filter(v=>v>=x&&v<x+.5).length);
  const mx=Math.max(...b),bw=(w-40)/b.length;let s='';b.forEach((c,j)=>{const bh=(h-36)*c/mx;s+=`<rect class="bar" style="--i:${j}" x="${20+j*bw+3}" y="${h-24-bh}" width="${bw-6}" height="${bh}" rx="4"></rect>`;});
  s+=`<line class="ax" x1="14" x2="${w-14}" y1="${h-24}" y2="${h-24}"></line>`;[4,5,6,7,8,9,10].forEach(t=>{s+=`<text class="lb" x="${20+(t-4)*2*bw}" y="${h-4}" text-anchor="middle">${t}</text>`});
  el.innerHTML=svg(w,h,s);},
 scatter(el){const m=D.measured,p=D.pred,w=+el.dataset.w||470,h=+el.dataset.h||420,P=48,lo=4,hi=10,X=v=>P+(v-lo)/(hi-lo)*(w-P-12),Y=v=>h-P-(v-lo)/(hi-lo)*(h-P-12);let s='';
  [5,6,7,8,9].forEach(t=>{s+=`<line class="gl" x1="${X(t)}" x2="${X(t)}" y1="${Y(hi)}" y2="${Y(lo)}"></line><line class="gl" x1="${X(lo)}" x2="${X(hi)}" y1="${Y(t)}" y2="${Y(t)}"></line><text class="lb" x="${X(t)}" y="${h-P+24}" text-anchor="middle">${t}</text><text class="lb" x="${P-12}" y="${Y(t)+5}" text-anchor="end">${t}</text>`});
  s+=`<line class="ax" x1="${X(lo)}" x2="${X(hi)}" y1="${Y(lo)}" y2="${Y(lo)}"></line><line class="ax" x1="${X(lo)}" x2="${X(lo)}" y1="${Y(lo)}" y2="${Y(hi)}"></line><line class="ln" x1="${X(lo)}" y1="${Y(lo)}" x2="${X(hi)}" y2="${Y(hi)}"></line>`;
  m.forEach((v,j)=>{s+=`<circle class="pt" style="--i:${j}" cx="${X(v)}" cy="${Y(p[j])}" r="${w<300?4:7}"></circle>`});
  if(w>=300)s+=`<text class="lb2" x="${(X(lo)+X(hi))/2}" y="${h-2}" text-anchor="middle">measured pIC50</text><text class="lb2" transform="translate(12 ${(Y(lo)+Y(hi))/2}) rotate(-90)" text-anchor="middle">predicted (held-out)</text>`;
  el.innerHTML=svg(w,h,s);},
 bits(el){const r=rng(11),cols=64,rows=16,c=9,g=2;let s='',k=0;for(let y=0;y<rows;y++)for(let x=0;x<cols;x++){const lit=r()<.036;s+=`<rect class="bit${lit?' lit':''}" style="--i:${lit?k++:0}" x="${x*(c+g)}" y="${y*(c+g)}" width="${c}" height="${c}" rx="2"></rect>`;}
  el.innerHTML=svg(cols*(c+g),rows*(c+g),s);},
 trees(el){const r=rng(5),w=+el.dataset.w||520,h=110,lo=5.5,hi=9,X=v=>16+(v-lo)/(hi-lo)*(w-32);let s=`<line class="ax" x1="16" x2="${w-16}" y1="70" y2="70"></line>`,sum=0;const v=[];for(let j=0;j<26;j++){const t=7.4+gauss(r)*.45;v.push(t);sum+=t;}
  v.forEach((t,j)=>{s+=`<circle class="pt" style="--i:${j};fill:var(--acc)" cx="${X(t)}" cy="${48-(j%3)*12}" r="6"></circle>`});
  const mu=sum/v.length;s+=`<line class="ln" style="stroke:var(--hot);stroke-dasharray:none;stroke-width:3" x1="${X(mu)}" x2="${X(mu)}" y1="14" y2="80"></line><text class="lb" x="${X(mu)}" y="102" text-anchor="middle" style="fill:var(--hot);font-weight:600">${document.documentElement.lang.startsWith('zh')?'平均 ':'average '}${mu.toFixed(1)}</text>`;
  [6,7,8,9].forEach(t=>{s+=`<text class="lb" x="${X(t)}" y="90" text-anchor="middle" style="font-size:12px">${t}</text>`});
  el.innerHTML=svg(w,h,s);},
 domain(el){const r=rng(21),w=+el.dataset.w||600,h=+el.dataset.h||430,cx=w*.42,cy=h*.55;let s='';
  s+=`<ellipse class="hull" cx="${cx}" cy="${cy}" rx="${w*.27}" ry="${h*.3}" transform="rotate(-14 ${cx} ${cy})"></ellipse>`;
  for(let j=0;j<42;j++){const a=gauss(r)*w*.11,b=gauss(r)*h*.12;s+=`<circle class="pt" style="--i:${j};fill:var(--acc);fill-opacity:.55" cx="${cx+a}" cy="${cy+b*.9-a*.2}" r="7"></circle>`;}
  s+=`<text class="lb" x="${cx-w*.2}" y="${cy-h*.33}" style="fill:var(--acc);font-weight:600">training chemistry · 42</text>`;
  el.innerHTML=svg(w,h,s);}
};
/* data for this deck (illustrative where tagged) */
if(!D.measured){const r=rng(7),n=42;let m=[...Array(n)].map(()=>gauss(r));const mu=m.reduce((a,b)=>a+b)/n,sd=Math.sqrt(m.reduce((a,b)=>a+(b-mu)**2,0)/n);m=m.map(v=>6.8+(v-mu)/sd*1.153);
 let e=m.map(v=>-.25*(v-6.8)+.4*gauss(r));const em=e.reduce((a,b)=>a+b)/n;e=e.map(v=>v-em);const rms=Math.sqrt(e.reduce((a,b)=>a+b*b,0)/n);e=e.map(v=>v*.61/rms);
 D.measured=m;D.pred=m.map((v,j)=>v+e[j]);}
document.querySelectorAll('[data-chart]').forEach(el=>C[el.dataset.chart]&&C[el.dataset.chart](el));
document.querySelectorAll('[data-m]').forEach(el=>{el.textContent=D.measured[+el.dataset.m].toFixed(2)});
/* timeline */
function count(el){const to=+el.dataset.to,dec=+(el.dataset.dec||0),t0=performance.now(),d=1100;(function f(t){const k=Math.min(1,(t-t0)/d),e=1-Math.pow(1-k,3);el.textContent=(to*e).toLocaleString('en-US',{minimumFractionDigits:dec,maximumFractionDigits:dec});if(k<1)requestAnimationFrame(f);})(t0);}
function type(el){const s=el.dataset.text,d=(+el.dataset.dur||1.6)*1000,t0=performance.now();(function f(t){const k=Math.min(1,(t-t0)/d);el.textContent=s.slice(0,Math.round(s.length*k));if(k<1)requestAnimationFrame(f);})(t0);}
function reset(s){s.querySelectorAll('.on,.off,.hlon').forEach(e=>e.classList.remove('on','off','hlon'));s.querySelectorAll('[data-to]').forEach(e=>e.textContent=(0).toFixed(+(e.dataset.dec||0)));s.querySelectorAll('[data-text]').forEach(e=>e.textContent='');s.querySelectorAll('[data-w]').forEach(e=>{if(e.tagName==='I')e.style.width='0'});}
function at(sec,fn){T.push(setTimeout(fn,sec*1000));}
function journey(s){const j=+s.dataset.journey||0;document.querySelectorAll('.journey span[data-j]').forEach(x=>{const k=+x.dataset.j;x.classList.toggle('jcur',k===j);x.classList.toggle('past',j>0&&k<j||j===9);});}
function go(n){T.forEach(clearTimeout);T=[];S.forEach(s=>{s.classList.remove('active');s.querySelectorAll('.lens .lv').forEach(e=>e.remove());});i=Math.max(0,Math.min(S.length-1,n));localStorage.setItem(KEY,i);
 const s=S[i];reset(s);s.classList.add('active');journey(s);document.querySelector('.ctl .n').textContent=`${i+1} / ${S.length}`;
 s.querySelectorAll('[data-at]').forEach(e=>at(+e.dataset.at,()=>{e.classList.add('on');if(e.dataset.to)count(e);if(e.dataset.text)type(e);if(e.dataset.w&&e.tagName==='I')e.style.width=e.dataset.w;}));
 s.querySelectorAll('[data-off]').forEach(e=>at(+e.dataset.off,()=>e.classList.add('off')));
 s.querySelectorAll('[data-hl]').forEach(e=>{const[a,b]=e.dataset.hl.split('-').map(Number);at(a,()=>e.classList.add('hlon'));if(b)at(b,()=>e.classList.remove('hlon'));});
 s.querySelectorAll('[data-jat]').forEach(e=>at(+e.dataset.jat,()=>{document.querySelectorAll('.journey span[data-j]').forEach(x=>x.classList.toggle('jcur',x.dataset.j===e.dataset.j))}));
 if(window.BMLens)BMLens.play(s,at);
 const d=+s.dataset.seconds||30,p=document.querySelector('.prog');p.style.transition='none';p.style.width='0';p.offsetWidth;p.style.transition=`width ${d}s linear`;p.style.width='100%';
 if(playing)at(d,()=>{if(i<S.length-1)go(i+1);else window.__done=true;});}
function toggle(){playing=!playing;document.querySelector('.ctl .pp').textContent=playing?'❚❚':'▶';if(playing)go(i);else{T.forEach(clearTimeout);T=[];const p=document.querySelector('.prog');p.style.width=getComputedStyle(p).width;p.style.transition='none';}}
/* overview: end-state clones */
const ov=document.querySelector('.ovw');
function buildOv(){ov.innerHTML='';S.forEach((s,k)=>{const c=document.createElement('div');c.className='ovc';c.innerHTML=`<div class="th"></div><div class="lab">${s.dataset.label||k+1}</div><div class="nt">${s.dataset.note||''}</div>`;
 const cl=s.cloneNode(true);cl.classList.add('active');cl.style.top='0';cl.querySelectorAll('[data-at],.chart').forEach(e=>{e.classList.add('on');if(e.dataset.to)e.textContent=(+e.dataset.to).toLocaleString('en-US',{minimumFractionDigits:+(e.dataset.dec||0),maximumFractionDigits:+(e.dataset.dec||0)});if(e.dataset.text)e.textContent=e.dataset.text;if(e.dataset.w&&e.tagName==='I')e.style.width=e.dataset.w;});cl.querySelectorAll('[data-off]').forEach(e=>e.classList.add('off'));cl.querySelectorAll('.cur').forEach(e=>e.remove());cl.querySelectorAll('.beats li').forEach(e=>e.classList.add('off'));
 c.querySelector('.th').appendChild(cl);if(window.BMUI&&BMUI.mount3d)BMUI.mount3d(cl);c.onclick=()=>{document.body.classList.remove('ov');ov.innerHTML='';go(k)};ov.appendChild(c);});}
function ovfit(){ov.querySelectorAll('.th').forEach(t=>{t.firstChild.style.transform=`scale(${t.clientWidth/1920})`});if(window.BMLens&&document.body.classList.contains('ov'))BMLens.final(ov);}
function tog(){const on=document.body.classList.toggle('ov');if(on){buildOv();ovfit();}else ov.innerHTML='';}
document.querySelector('.ctl .ovb').onclick=tog;
document.querySelector('.ctl .pv').onclick=()=>go(i-1);document.querySelector('.ctl .nx').onclick=()=>go(i+1);document.querySelector('.ctl .pp').onclick=toggle;
addEventListener('keydown',e=>{if(e.key==='ArrowRight')go(i+1);else if(e.key==='ArrowLeft')go(i-1);else if(e.key===' '){e.preventDefault();toggle();}else if(e.key==='o')tog();});
go(i);
})();
