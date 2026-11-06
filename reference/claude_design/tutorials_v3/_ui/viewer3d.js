/* BioMate 3D structure viewer (Structure evidence class). Builds a conformer from a SMILES string in the browser — heavy atoms, sticks —
   and renders it on a canvas with slow auto-rotation and drag-to-rotate. The geometry is computed here by distance geometry (bond lengths,
   bond angles, planar rings, steric repulsion); it is not a docked pose and not a force-field-minimised structure.
   Use:  BMUI.block({k:'viewer', smiles:'…', title:'…', score:'−6.4 kcal/mol'});  then BMUI.mount3d(rootElement). */
(function(){
const U=window.BMUI;if(!U)return;
const COL={C:'#6b7480',O:'#d1503f',N:'#3f6fd1',F:'#4aa86b',S:'#d1a63f',Cl:'#4aa86b',Br:'#a0532f'},RAD={C:1,O:.95,N:.95,F:.85,S:1.15,Cl:1.1,Br:1.2};
function parse(smi){const at=[],bd=[],st=[],ring={};let prev=-1,ord=1,i=0;
 const add=(el,ar)=>{at.push({el,ar});const k=at.length-1;if(prev>=0)bd.push([prev,k,ord===1&&ar&&at[prev].ar?1.5:ord]);prev=k;ord=1;};
 while(i<smi.length){const c=smi[i];
  if(c==='('){st.push(prev);i++;continue}if(c===')'){prev=st.pop();i++;continue}
  if(c==='='){ord=2;i++;continue}if(c==='#'){ord=3;i++;continue}if(c==='-'||c==='/'||c==='\\'||c==='@'){i++;continue}
  if(/\d/.test(c)){const n=+c;if(ring[n]!==undefined){const a=ring[n];bd.push([a,prev,ord===1&&at[a].ar&&at[prev].ar?1.5:ord]);delete ring[n];ord=1}else ring[n]=prev;i++;continue}
  if(c==='['){const j=smi.indexOf(']',i);const m=smi.slice(i+1,j).match(/[A-Z][a-z]?|[cnos]/);const t=m?m[0]:'C';add(t[0].toUpperCase()+t.slice(1),t.length===1&&/[cnos]/.test(t));i=j+1;continue}
  if(smi.substr(i,2)==='Cl'||smi.substr(i,2)==='Br'){add(smi.substr(i,2),false);i+=2;continue}
  if(/[CNOSFPI]/.test(c)){add(c,false);i++;continue}
  if(/[cnos]/.test(c)){add(c.toUpperCase(),true);i++;continue}
  i++;}
 return{at,bd};}
function rings6(n,adj,ar){const out=[],seen=new Set();
 const dfs=(s,u,path)=>{if(path.length===6){if(adj[u].includes(s)){const key=[...path].sort((a,b)=>a-b).join();if(!seen.has(key)){seen.add(key);out.push([...path]);}}return}
  for(const v of adj[u])if(v>s&&ar[v]&&!path.includes(v)){path.push(v);dfs(s,v,path);path.pop();}};
 for(let s=0;s<n;s++)if(ar[s])dfs(s,s,[s]);return out;}
function embed(smi,seed){const{at,bd}=parse(smi),n=at.length,adj=at.map(()=>[]),ord={};
 bd.forEach(([a,b,o])=>{adj[a].push(b);adj[b].push(a);ord[a+'_'+b]=ord[b+'_'+a]=o;});
 const ar=at.map(a=>a.ar),bl=(a,b)=>{const o=ord[a+'_'+b],p=[at[a].el,at[b].el].sort().join('');if(o===1.5)return 1.40;if(p==='CO')return o===2?1.22:1.36;if(p==='CN')return o===2?1.28:1.47;return o===2?1.34:1.52;};
 const D=Array.from({length:n},()=>Array(n).fill(0)),W=Array.from({length:n},()=>Array(n).fill(0));
 const set=(a,b,d,w)=>{D[a][b]=D[b][a]=d;W[a][b]=W[b][a]=w;};
 for(let a=0;a<n;a++)for(let b=a+1;b<n;b++)set(a,b,3.4,.04);
 bd.forEach(([a,b])=>set(a,b,bl(a,b),1));
 for(let c=0;c<n;c++){const sp2=adj[c].some(x=>ord[c+'_'+x]>=1.5)||(adj[c].length===3&&ar[c]);const th=(sp2?120:109.5)*Math.PI/180;
  for(let i=0;i<adj[c].length;i++)for(let j=i+1;j<adj[c].length;j++){const a=adj[c][i],b=adj[c][j],l1=bl(c,a),l2=bl(c,b);set(a,b,Math.sqrt(l1*l1+l2*l2-2*l1*l2*Math.cos(th)),.8);}}
 rings6(n,adj,ar).forEach(r=>{for(let i=0;i<6;i++)for(let j=i+1;j<6;j++){const k=Math.min(j-i,6-(j-i));set(r[i],r[j],2*1.40*Math.sin(k*Math.PI/6),1);}});
 let s=seed||7;const rnd=()=>{s|=0;s=s+0x6D2B79F5|0;let t=Math.imul(s^s>>>15,1|s);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296};
 const P=Array.from({length:n},()=>[rnd()*6-3,rnd()*6-3,rnd()*6-3]);
 for(let it=0;it<900;it++){const lr=.08*(1-it/1000);const G=P.map(()=>[0,0,0]);
  for(let a=0;a<n;a++)for(let b=a+1;b<n;b++){const dx=P[a][0]-P[b][0],dy=P[a][1]-P[b][1],dz=P[a][2]-P[b][2];const d=Math.sqrt(dx*dx+dy*dy+dz*dz)||1e-6,t=D[a][b];
   if(W[a][b]<.1&&d>t)continue;const f=W[a][b]*(d-t)/d;G[a][0]+=f*dx;G[a][1]+=f*dy;G[a][2]+=f*dz;G[b][0]-=f*dx;G[b][1]-=f*dy;G[b][2]-=f*dz;}
  for(let a=0;a<n;a++){P[a][0]-=lr*G[a][0];P[a][1]-=lr*G[a][1];P[a][2]-=lr*G[a][2];}}
 const cx=P.reduce((q,p)=>q+p[0],0)/n,cy=P.reduce((q,p)=>q+p[1],0)/n,cz=P.reduce((q,p)=>q+p[2],0)/n;P.forEach(p=>{p[0]-=cx;p[1]-=cy;p[2]-=cz;});
 let best=0,bi=0;for(let k=0;k<24;k++){const a=k*Math.PI/12;let mn=1e9,mx=-1e9;P.forEach(p=>{const v=p[0]*Math.cos(a)+p[1]*Math.sin(a);mn=Math.min(mn,v);mx=Math.max(mx,v)});if(mx-mn>best){best=mx-mn;bi=a}}
 const c=Math.cos(-bi),sn=Math.sin(-bi);P.forEach(p=>{const x=p[0]*c-p[1]*sn,y=p[0]*sn+p[1]*c;p[0]=x;p[1]=y;});
 return{at,bd,P,ar,adj};}
function draw(cv,m,rx,ry){const dpr=2,W=cv.clientWidth||560,H=cv.clientHeight||300;if(cv.width!==W*dpr){cv.width=W*dpr;cv.height=H*dpr;}
 const g=cv.getContext('2d');g.setTransform(dpr,0,0,dpr,0,0);g.clearRect(0,0,W,H);
 const cy=Math.cos(ry),sy=Math.sin(ry),cx=Math.cos(rx),sx=Math.sin(rx);const S=Math.min(W/9.5,H/5.2);
 const Q=m.P.map(p=>{const x=p[0]*cy+p[2]*sy;let z=-p[0]*sy+p[2]*cy;const y=p[1]*cx-z*sx;z=p[1]*sx+z*cx;const f=1/(1-z*.035);return{x:W/2+x*S*f,y:H/2+y*S*f,z,f}});
 const items=[];m.bd.forEach(([a,b,o])=>items.push({t:'b',a,b,o,z:(Q[a].z+Q[b].z)/2}));m.at.forEach((a,i)=>items.push({t:'a',i,z:Q[i].z+.3}));items.sort((p,q)=>p.z-q.z);
 const shade=z=>Math.max(.55,Math.min(1,.8+z*.06));
 items.forEach(it=>{if(it.t==='b'){const A=Q[it.a],Bq=Q[it.b],dx=Bq.x-A.x,dy=Bq.y-A.y,L=Math.hypot(dx,dy)||1,nx=-dy/L,ny=dx/L,w=Math.max(2.2,5.5*(A.f+Bq.f)/2);
   const offs=it.o===2?[-w*.55,w*.55]:[0];g.lineCap='round';
   offs.forEach(off=>{const gr=g.createLinearGradient(A.x,A.y,Bq.x,Bq.y);gr.addColorStop(0,COL[m.at[it.a].el]||'#888');gr.addColorStop(1,COL[m.at[it.b].el]||'#888');g.strokeStyle=gr;g.globalAlpha=shade((A.z+Bq.z)/2);g.lineWidth=it.o===2?w*.5:w;g.beginPath();g.moveTo(A.x+nx*off,A.y+ny*off);g.lineTo(Bq.x+nx*off,Bq.y+ny*off);g.stroke();});
   if(it.o===1.5){g.globalAlpha=.5*shade(A.z);g.setLineDash([4,4]);g.strokeStyle='#fff';g.lineWidth=1.4;g.beginPath();g.moveTo(A.x,A.y);g.lineTo(Bq.x,Bq.y);g.stroke();g.setLineDash([]);}g.globalAlpha=1;}
  else{const p=Q[it.i],el=m.at[it.i].el,r=(el==='C'?5.5:7)*p.f*(RAD[el]||1);g.globalAlpha=shade(p.z);const gr=g.createRadialGradient(p.x-r*.3,p.y-r*.3,r*.1,p.x,p.y,r);gr.addColorStop(0,'#fff');gr.addColorStop(.25,COL[el]||'#888');gr.addColorStop(1,COL[el]||'#888');g.fillStyle=gr;g.beginPath();g.arc(p.x,p.y,r,0,7);g.fill();g.globalAlpha=1;}});}
const MODELS={};
U.mount3d=function(root){(root||document).querySelectorAll('canvas.x-v3d').forEach(cv=>{if(cv._m3)return;const smi=cv.dataset.smiles;if(!smi)return;const m=MODELS[smi]||(MODELS[smi]=embed(smi,7));cv._m3=1;
  let rx=-.35,ry=.5,drag=null;const auto=!matchMedia('(prefers-reduced-motion: reduce)').matches;
  let seen=false,wait=0;const tick=()=>{if(!cv.isConnected){if(seen||++wait>120)return;return requestAnimationFrame(tick)}seen=true;if(auto&&!drag)ry+=.012;draw(cv,m,rx,ry);requestAnimationFrame(tick)};tick();
  cv.addEventListener('pointerdown',e=>{drag=[e.clientX,e.clientY];cv.setPointerCapture(e.pointerId)});
  cv.addEventListener('pointermove',e=>{if(!drag)return;ry+=(e.clientX-drag[0])*.01;rx+=(e.clientY-drag[1])*.01;drag=[e.clientX,e.clientY]});
  cv.addEventListener('pointerup',()=>{drag=null});});};
U.embed3d=embed;
U.B.viewer=b=>`<figure class="x-fig" style="margin:0"${b.region?` data-region="${b.region}"`:''}><div class="ft"><span class="ty">Structure</span>${b.title}</div><div class="x-v3dw"><canvas class="x-v3d" data-smiles="${b.smiles||''}" aria-label="3D structure"></canvas>${b.score?`<span class="x-v3s">${b.score}</span>`:''}<span class="x-v3h">heavy atoms · drag to rotate</span></div>${b.caption?`<div class="fc">${b.caption}</div>`:''}</figure>`;
})();
