/* BioMate screen kit — renderers. One run spec → every screen; one block catalog → Summary, chat answer, previews and the report.
   Block kinds: prose · tiles(keyResult) · table · figure · figs(row) · callout · citations · kv.  See README in this folder. */
(function(){
const BMUI=window.BMUI=window.BMUI||{runs:{}};
BMUI.logo=BMUI.logo||'../assets/biomate-logo.png';
const esc=s=>String(s==null?'':s);
const R=(r,s)=>r?` data-region="${r}"`:'';
const OUT={pass:'Pass',flag:'Flagged',adv:'Advisory',ne:'Not evaluated',unav:'Unavailable'};
const out=o=>{if(!o)return'';if(typeof o==='string')o={o};return `<span class="x-out ${o.o}">${o.label||OUT[o.o]}</span>`;};
const pv=o=>o?`<span class="x-pv ${o.replace(/\s+/g,'-')}">${o}</span>`:'';
/* utils */
BMUI.rng=a=>()=>{a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};
BMUI.gauss=r=>{let u=0,v=0;while(!u)u=r();while(!v)v=r();return Math.sqrt(-2*Math.log(u))*Math.cos(2*Math.PI*v);};
/* ---------- figures ---------- */
const svg=(w,h,s)=>`<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet">${s}</svg>`;
const FIG={
 scatter(d){const w=400,h=300,P=40,lo=d.lo,hi=d.hi,X=v=>P+(v-lo)/(hi-lo)*(w-P-8),Y=v=>h-P+4-(v-lo)/(hi-lo)*(h-P-6);let s='';
  for(let t=Math.ceil(lo);t<=hi;t++)s+=`<line class="gl" x1="${X(t)}" x2="${X(t)}" y1="${Y(hi)}" y2="${Y(lo)}"/><line class="gl" x1="${X(lo)}" x2="${X(hi)}" y1="${Y(t)}" y2="${Y(t)}"/><text class="lb" x="${X(t)}" y="${Y(lo)+15}" text-anchor="middle">${t}</text><text class="lb" x="${P-8}" y="${Y(t)+4}" text-anchor="end">${t}</text>`;
  s+=`<line class="ax" x1="${X(lo)}" x2="${X(hi)}" y1="${Y(lo)}" y2="${Y(lo)}"/><line class="ax" x1="${X(lo)}" x2="${X(lo)}" y1="${Y(lo)}" y2="${Y(hi)}"/><line class="ln" x1="${X(lo)}" y1="${Y(lo)}" x2="${X(hi)}" y2="${Y(hi)}"/>`;
  d.x.forEach((v,j)=>s+=`<circle class="pt" style="--i:${j}" cx="${X(v).toFixed(1)}" cy="${Y(d.y[j]).toFixed(1)}" r="4.5"/>`);
  s+=`<text class="lb2" x="${(X(lo)+X(hi))/2}" y="${h}" text-anchor="middle">${d.xl}</text><text class="lb2" transform="translate(9 ${(Y(lo)+Y(hi))/2}) rotate(-90)" text-anchor="middle">${d.yl}</text>`;
  return svg(w,h+4,s);},
 hist(d){const w=400,h=120,b=[];for(let x=d.lo;x<d.hi-1e-9;x+=d.step)b.push(d.values.filter(v=>v>=x&&v<x+d.step).length);const mx=Math.max(...b),bw=(w-20)/b.length;let s='';
  b.forEach((c,j)=>{const bh=(h-30)*c/mx;s+=`<rect class="bar" style="--i:${j}" x="${10+j*bw+2}" y="${h-20-bh}" width="${bw-4}" height="${bh}" rx="2"/>`;});
  s+=`<line class="ax" x1="6" x2="${w-6}" y1="${h-20}" y2="${h-20}"/>`;for(let t=Math.ceil(d.lo);t<=d.hi;t++)s+=`<text class="lb" x="${10+(t-d.lo)/d.step*bw}" y="${h-5}" text-anchor="middle">${t}</text>`;
  return svg(w,h,s);},
 domain(d){const w=400,h=300,X=v=>v*w,Y=v=>v*h,H=d.hull;let s=`<ellipse class="hull" cx="${X(H.cx)}" cy="${Y(H.cy)}" rx="${X(H.rx)}" ry="${Y(H.ry)}" transform="rotate(${H.rot} ${X(H.cx)} ${Y(H.cy)})"/>`;
  d.train.forEach((p,j)=>s+=`<circle class="pt tr" style="--i:${j}" cx="${X(p[0]).toFixed(1)}" cy="${Y(p[1]).toFixed(1)}" r="4"/>`);
  d.queries.forEach(q=>{const cls=q.o==='in'?'q-in':'q-out';s+=q.o==='in'?`<circle class="${cls}" data-q="${q.id}" cx="${X(q.x)}" cy="${Y(q.y)}" r="6.5"/>`:`<rect class="${cls}" data-q="${q.id}" x="${X(q.x)-6}" y="${Y(q.y)-6}" width="12" height="12" rx="2"/>`;if(q.label)s+=`<text class="ql ${q.o}" x="${X(q.x)+10}" y="${Y(q.y)+4}">${q.id}</text>`;});
  s+=`<text class="lb2" x="8" y="${h-6}">${d.note||''}</text>`;return svg(w,h,s);}
};
BMUI.FIG=FIG;
/* ---------- blocks ---------- */
function liftConst(b){const cols=b.columns.map(c=>Object.assign({},c,{_h:''})),rows=b.rows,lifted=[];
 if(rows.length>1)for(let c=cols.length-1;c>=0;c--){const col=cols[c];if(col.kind==='entity'||col.keep)continue;const vals=rows.map(r=>JSON.stringify(r[col.key]));if(vals.every(v=>v===vals[0])){const v=rows[0][col.key];const txt=typeof v==='object'&&v?(v.label||OUT[v.o]||v.v):v;
  const into=col.into&&cols.find(x=>x.key===col.into);if(into)into._h=(into._h||'')+` <span class="c">· ${col.label} ${txt}</span>`;else lifted.push(`${col.label}${BMUI.lang==='zh'?'：':': '}${txt}`);cols.splice(c,1);}}
 return{cols,lifted};}
function td(c,v){
 if(c.kind==='entity'){v=typeof v==='string'?{name:v}:v;return `<th scope="row"${R(v.region)}><b>${esc(v.name)}</b>${v.smiles?`<span class="x-smi">${v.smiles}</span>`:''}</th>`;}
 if(c.kind==='outcome')return `<td>${out(v)}</td>`;
 if(c.kind==='num')return `<td class="x-n">${v&&v.v!==undefined?`<span class="v">${v.v}</span>${out(v.out)}`:`<span class="v">${esc(v)}</span>`}</td>`;
 if(c.kind==='bar'){const p=Math.round(100*v/c.max);return `<td class="x-n"><span class="x-bar" style="width:${p*0.9}px"></span>${v}</td>`;}
 if(c.kind==='mono')return `<td class="x-n">${esc(v)}</td>`;
 return `<td>${esc(v)}</td>`;}
const B={
 prose:b=>`<div${R(b.region)}><p class="x-ans">${b.text}</p>${b.scope?`<div class="x-scope">${b.scope}</div>`:''}</div>`,
 tiles:b=>`<div class="x-sect"${R(b.region)}>${b.title?`<div class="hd"><span class="x-k">${b.title}</span>${b.aside?`<span class="aside">${b.aside}</span>`:''}</div>`:''}<div class="x-tiles" style="--n:${b.items.length}">${b.items.map((t,j)=>`<div class="x-tile"${R(t.region||(b.region+'-'+(j+1)))}><span class="k">${t.metric}</span><span class="v">${t.value}${t.unit?`<small>${t.unit}</small>`:''}</span><span class="c">${t.criterion?t.criterion+' · ':''}${out(t.outcome)}</span></div>`).join('')}</div></div>`,
 table(b){const{cols,lifted}=liftConst(b);const cap=(b.title||lifted.length)?`<caption>${b.title?`<b>${b.title}</b>`:''}${lifted.join(' · ')}</caption>`:'';
  return `<div${R(b.region)}><table class="x-tbl"${b.region?` data-region="${b.region}-t"`:''}>${cap}<thead><tr>${cols.map(c=>`<th>${c.label}${c.unit?` <span class="c">${c.unit}</span>`:''}${c._h||''}</th>`).join('')}</tr></thead><tbody>${b.rows.map(r=>`<tr${R(r._region)}>${cols.map(c=>td(c,r[c.key])).join('')}</tr>`).join('')}</tbody></table>${b.more?`<div class="x-more">${b.more}</div>`:''}</div>`;},
 figure:b=>`<figure class="x-fig" style="margin:0"${R(b.region)}><div class="ft"><span class="ty">Figure</span>${b.title}</div>${FIG[b.kind](b.data)}${b.caption?`<div class="fc">${b.caption}</div>`:''}</figure>`,
 figs:b=>`<div class="x-figs" style="--n:${b.items.length}"${R(b.region)}>${b.items.map(B.figure).join('')}</div>`,
 callout:b=>`<div class="x-callout ${b.severity||''}"${R(b.region)}>${out({o:b.severity||'ne',label:b.label})}<span><b>${b.title}</b>${b.body?` ${b.body}`:''}</span></div>`,
 kv:b=>`<dl class="x-kv"${R(b.region)}>${b.items.map(([k,v,rg])=>`<dt>${k}</dt><dd${R(rg)}>${v}</dd>`).join('')}</dl>`,
 citations:b=>`<div${R(b.region)} style="font-size:12.5px;color:var(--tx2)">${b.items.join(' · ')}</div>`
};
BMUI.B=B;BMUI.out=out;BMUI.block=b=>B[b.k](b);
BMUI.blocks=list=>list.map(BMUI.block).join('');
const sources=(run,list)=>{if(BMUI.fd&&BMUI.fd.__sources&&list.some(b=>b.k==='findings'))return BMUI.fd.__sources(run,list);const s=[...new Set(list.map(b=>b.source).concat(...list.filter(b=>b.items).map(b=>b.items.map(i=>i.source))).filter(Boolean))];
 return s.length?`<div class="x-src" data-region="sources"><span>Sources</span>${s.map(f=>`<span class="f">${f} ↗</span>`).join('')}${run.citations?`<span>${run.citations.join(' · ')}</span>`:''}</div>`:'';};
BMUI.sources=sources;
/* ---------- chrome ---------- */
const nSteps=run=>run.phases.reduce((a,p)=>a+p.steps.length,0);
function state(run,o){const n=nSteps(run);const p=o.progress==null?(o.state==='ready'?0:n+1):o.progress;return{n,p,ready:p===0,done:p>n,running:p>0&&p<=n};}
function chat(run,st){const u=run.user;let lines=[],ref;
 const U=run.updates.map((x,j)=>Array.isArray(x)?x:[Math.round((j+1)*st.n/run.updates.length),x]);
 if(st.running){lines=U.filter(x=>x[0]<st.p).map(x=>x[1]);const cs=run.phases.flatMap(p=>p.steps)[st.p-1];if(cs)lines.push(`<span class="now">${cs.name}${cs.live?' · '+cs.live:''}…</span>`);}
 if(st.done)lines=U.map(x=>x[1]);
 if(st.ready)ref=`<span class="st"><i class="x-dot"></i>Ready</span><a>Review in panel →</a>`;
 else if(st.running)ref=`<span class="st"><i class="x-dot run"></i>Running · step ${st.p} of ${st.n}</span><a>Open run →</a>`;
 else ref=`<span class="st"><i class="x-dot ok"></i>Completed</span><a>Open run →</a>`;
 const ans=st.done&&run.chatAnswer?BMUI.blocks(run.chatAnswer)+(run.chatAnswer.some(b=>b.k==='findings')?'':sources(run,run.chatAnswer)):'';
 return `<div class="x-chat"><div class="x-thread" data-region="chat-thread"><div class="x-user" data-region="chat-user">${u.files?`<div class="x-att">${u.files.map(f=>`<span class="x-file">${f.ext||f.name.includes('.')?`<i>${(f.ext||f.name.split('.').pop()).toUpperCase().slice(0,4)}</i>`:''}<b>${f.name}</b><span>${f.meta}</span></span>`).join('')}</div>`:''}<span>${u.text}</span></div>
 <span class="x-who">BIOMATE</span><div class="x-stream" data-region="chat-stream"><div class="plan">${run.plan}</div>${lines.map(l=>`<div>${l}</div>`).join('')}</div>
 <div data-region="chat-reply" style="display:flex;flex-direction:column;gap:12px"><div class="x-runref" data-region="chat-runref">${ref}</div>${ans?`<div data-region="chat-answer" style="display:flex;flex-direction:column;gap:10px">${ans}</div>`:''}</div></div><div class="x-composer"><span>Message BioMate…</span><span style="color:var(--ac);font-weight:600">↵</span></div></div>`;}
function head(run,st){const rb=st.ready?`<span class="sw"><i class="x-dot"></i>Ready</span><span class="bar"><i style="width:0"></i></span><span class="meta">nothing has run</span>`
 :st.running?`<span class="sw"><i class="x-dot run"></i>Running</span><span class="bar"><i style="width:${Math.round(100*(st.p-1)/st.n)}%"></i></span><span class="meta">${st.p-1}/${st.n} steps</span>`
 :`<span class="sw"><i class="x-dot ok"></i>Completed</span><span class="bar"><i style="width:100%"></i></span><span class="meta">${st.n}/${st.n} · findings ready</span>`;
 return `<div class="x-ph" data-region="p-head"><div class="nm">${run.title}</div><div class="sub">${run.method}</div><div class="x-runbar${st.done?' done':''}" data-region="p-runbar">${rb}</div></div>`;}
const SEC=['Workflow settings','Phases','After run'],SUB=['Summary','Outputs','Reproducibility record'];
const secbar=(i,done)=>`<div class="x-sec">${SEC.map((x,j)=>`<span class="${j===i?'on':''}${j===2&&!done?' off':''}">${x}${j===2&&done?'<i class="rd"></i>':''}</span>`).join('')}</div>`;
const subbar=i=>`<div class="x-sub">${SUB.map((x,j)=>`<span class="${j===i?'on':''}">${x}</span>`).join('')}</div>`;
function foot(st){return st.ready?`<div class="x-pf" data-region="foot"><span class="note" data-region="p-note">Nothing runs until you confirm.</span><span class="x-btn pri" data-region="confirm">Confirm and run workflow</span></div>`
 :st.running?`<div class="x-pf" data-region="foot"><span class="x-btn">Cancel run</span></div>`:`<div class="x-pf" data-region="foot"><span class="x-btn" data-region="run-again">Run again</span></div>`;}
const shell=(run,o,st,panel)=>`<div class="bmx" data-run="${run.id}" data-screen="${o.screen}" style="${o.w?`--w:${o.w}px;--cw:${o.cw||330}px;`:''}--h:${(h=>h==='auto'?'auto':h+'px')(o.h||'auto')}"><div class="x-top"><img src="${BMUI.logo}" alt=""/><b style="color:var(--tx)">BioMate</b><span class="sep">/</span><span>${run.project}</span><span class="sep">/</span><span>Chat</span></div><div class="x-cols">${chat(run,st)}<div class="x-panel">${head(run,st)}${panel}</div></div></div>`;
/* ---------- screens ---------- */
function inputCard(inp,i){return `<div class="x-ds" data-region="in-${i+1}"><div class="hd"><b>${inp.file}</b><span class="meta">${inp.meta}</span>${pv(inp.origin)}</div><div class="bd">
 ${inp.roles?`<div class="x-roles" data-region="in-${i+1}-roles">${inp.roles.map(r=>`<span class="x-role"><i>${r[0]}</i><code>${r[1]}</code></span>`).join('')}</div>`:''}
 ${inp.preview||inp.figure||inp.checks?`<div class="two"><div>${inp.preview?BMUI.block(Object.assign({k:'table',region:`in-${i+1}-preview`},inp.preview)):''}</div><div style="display:flex;flex-direction:column;gap:10px">${inp.figure?BMUI.block(Object.assign({k:'figure',region:`in-${i+1}-fig`},inp.figure)):''}${inp.checks?`<div data-region="in-${i+1}-checks"><div class="x-k" style="margin-bottom:4px">Input checks</div>${inp.checks.map((c,j)=>`<div class="x-chk${c[2]==='adv'?' adv':''}" data-region="in-${i+1}-chk-${j+1}"><span class="ic${c[2]==='adv'?' adv':''}"></span><span>${c[0]}</span><span class="r">${c[1]}</span></div>`).join('')}</div>`:''}</div></div>`:''}
 </div></div>`;}
function settings(run,o){const st=state(run,{state:'ready'});return shell(run,o,st,`${secbar(0,false)}<div class="x-pb">
 <div class="x-sect" data-region="p-inputs"><div class="hd"><span class="x-k">Inputs</span><span class="aside">${run.inputsAside||''}</span></div>${run.inputs.map(inputCard).join('')}</div>
 <div class="x-sect" data-region="p-params"><div class="hd"><span class="x-k">Parameters and criteria</span><span class="aside">origin shown on every value</span></div><div class="x-rows">${run.params.map((p,j)=>`<div class="x-row" data-region="param-${j+1}"><span class="lbl">${p[0]}</span><span class="v">${p[1]}</span><span>${pv(p[2])}${p[3]?` <span class="x-why">why</span>`:''}</span><span class="ed">edit</span></div>`).join('')}</div></div>
 </div>${foot(st)}`);}
function phases(run,o){const st=state(run,o);let k=0;
 return shell(run,o,st,`${secbar(1,st.done)}<div class="x-pb" style="gap:10px">${run.phases.map((ph,pi)=>{const first=k+1,last=k+ph.steps.length;const pst=st.p>last?'done':st.p>=first&&st.p<=last?'running':'';
  const steps=ph.steps.map(s=>{k++;const c=st.p>k?'st-d':st.p===k?'st-r':'';const chip=st.ready?'':c==='st-d'?'Done':c==='st-r'?'Running':'Queued';
   return `<div class="x-step ${c}" data-region="step-${k}"><span class="sn">${s.name}</span>${chip?`<span class="x-chip">${chip}</span>`:''}<div class="sm">${s.tool?`<span>${s.tool}</span>`:''}${(s.params||[]).map(p=>`<span>${p[0]} <b style="font-weight:500">${p[1]}</b></span>${p[2]?pv(p[2]):''}`).join('')}${c==='st-d'?run.outputs.filter(f=>f.step.endsWith(s.name)).map(f=>`<span class="o">${f.name}</span>`).join(''):''}${c==='st-r'&&s.live?`<span style="color:var(--aci)">${s.live}</span>`:''}</div></div>`;}).join('');
  const uni=ph.qc&&ph.qc.rows.every(q=>q[3]===ph.qc.rows[0][3]);const qc=ph.qc?`<div class="x-qcb" data-region="qc-${ph.letter}"><div class="hd"><span class="x-k">QC checks · ${ph.qc.rows.length}</span><span class="aside">${ph.qc.aside||''}</span></div>${ph.qc.rows.map((q,j)=>{const shown='<span class="dpg">'+(uni?'':q[3]||'')+'</span>'+(q[2]?'<span class="dpo">'+out(q[2])+'</span>':'');const gate=q[3]&&/gate/.test(q[3]);return `<div class="x-qr" data-region="qc-${ph.letter}-${j+1}"><span>${q[0]}</span><span class="cr">${q[1]}</span><span class="dp${gate?' gate':''}">${shown}</span></div>`;}).join('')}</div>`:'';
  return `<div class="x-phase ${pst}" data-region="phase-${ph.letter}"><div class="hd"><span class="lt">${ph.letter}</span><div><div class="t">${ph.name}</div><div class="s">${ph.steps.length} steps${ph.note?' · '+ph.note:''}</div></div><span class="pc">${Math.max(0,Math.min(ph.steps.length,st.p-first))}/${ph.steps.length}</span></div>${steps}${qc}</div>`;}).join('')}</div>${foot(st)}`);}
function summary(run,o){const st=state(run,{state:'done'});const bl=run.summary;return shell(run,o,st,`${secbar(2,true)}${subbar(0)}<div class="x-pb">${BMUI.blocks(bl.map(b=>b.k==='findings'?Object.assign({},b,{sources:false}):b))}${sources(run,bl)}</div>${foot(st)}`);}
function fileRow(f,sel){return `<div class="x-fr${f.name===sel?' on':''}" data-region="file-${f.name}"><span class="fn">${f.name}</span><span class="sz">${f.size&&f.size!=='—'?f.size:''}</span><span class="x-ty ${f.type}">${f.type}</span></div>`;}
function outputs(run,o){const st=state(run,{state:'done'});const sel=o.screen.split(':')[1]||run.outputs[0].name,f=run.outputs.find(x=>x.name===sel);const groups=[...new Set(run.outputs.map(x=>x.step))];
 const prev=f.type==='Report'?report(run,{inner:true}):`<div class="x-prev" data-region="preview"><div class="hd"><span class="fn">${f.name}</span><span class="meta">${f.type}${f.size&&f.size!=='—'?' · '+f.size:''} · from ${f.step} · version ${f.version||'<span style="color:var(--di)">not recorded</span>'}</span><span class="acts"><span class="x-btn sm">Open in Files</span><span class="x-btn sm">Download</span></span></div><div class="bd">${f.preview?BMUI.blocks(f.preview):'<span style="color:var(--di)">No preview for this file type.</span>'}</div></div>`;
 return shell(run,o,st,`${secbar(2,true)}${subbar(1)}<div class="x-pb"><div class="x-files"><div class="x-flist" data-region="o-list">${groups.map(g=>`<div class="x-fg">${g}</div>${run.outputs.filter(x=>x.step===g).map(x=>fileRow(x,sel)).join('')}`).join('')}</div>${prev}</div></div>${foot(st)}`);}
function record(run,o){const st=state(run,{state:'done'}),r=run.record;
 return shell(run,o,st,`${secbar(2,true)}${subbar(2)}<div class="x-pb" style="gap:10px"><div class="x-rhead"><div><b data-region="r-orig">Run original · ${r.id}</b><span>immutable · manifest and ${run.outputs.length} outputs · <span data-region="r-cks">SHA-256 not yet computed · <a>Compute</a></span></span></div><span class="x-btn sm">Download record (JSON)</span></div>
 <div class="x-acc">${r.sections.map(s=>`<div data-region="r-${s.id}"><div class="x-ah"><span class="car">${s.open?'▾':'▸'}</span>${s.name}${!s.open&&s.preview?`<span class="pv">${s.preview}</span>`:''}</div>${s.open?`<div class="x-ab">${BMUI.blocks(s.blocks)}</div>`:''}</div>`).join('')}</div></div>${foot(st)}`);}
/* the unified report: Question · Answer · Data · Method · Results · Quality checks · Caveats · Citations + provenance */
function report(run,o){const d=run.report,sec=(id,n,body)=>body?`<section class="x-ds2" data-region="doc-${id}"><h2>${n}</h2>${body}</section>`:'';
 const doc=`<div class="x-doc" data-region="doc"><div class="tb"><span class="fn">${d.file}</span><span class="ver">v1</span><span class="acts"><span class="x-btn sm" data-region="doc-edit">Edit</span><span class="x-btn sm">Ask BioMate to edit</span><span class="x-btn sm" data-region="doc-download">Download ▾</span></span></div><div class="pg">
 <h1 data-region="doc-title">${d.title}</h1><div class="dm"><span>${run.method}</span></div>
 ${sec('question','Question',`<blockquote>${run.user.text}</blockquote>`)}
 ${sec('answer','Answer',`<p>${d.answer}</p>`)}
 ${sec('data','Data',BMUI.blocks(d.data))}
 ${sec('method','Method',`<p>${d.method}</p>`)}
 ${sec('results','Results',BMUI.blocks(d.results.map(b=>b.k==='findings'?Object.assign({},b,{sources:false}):b))+sources(run,d.results))}
 ${sec('qc','Quality checks',BMUI.blocks(d.qc))}
 ${sec('caveats','Caveats',d.caveats&&d.caveats.length?`<ul>${d.caveats.map(c=>`<li>${c}</li>`).join('')}</ul>`:'')}
 ${sec('citations','Citations',`<p>${(run.citations||[]).join(' · ')}</p>`)}
 <div class="pf" data-region="doc-prov"><span>run original ${run.record.id}</span><span>${run.outputs.length} outputs</span><span>Reproducibility record ↗</span></div></div></div>`;
 if(o.inner)return doc;const st=state(run,{state:'done'});
 return shell(run,o,st,`${secbar(2,true)}${subbar(1)}<div class="x-pb"><a style="font-size:12px">← All outputs</a>${doc}</div>${foot(st)}`);}

/* ---------- i18n: chrome strings are translated at render time; run content comes from the run spec ---------- */
BMUI.lang=BMUI.lang||'en';
const ZH={'3D structure viewer · the pose and its score travel together':'三维结构查看器 · 构象与得分一起显示','Structure':'结构','Edge':'边','Formulation':'制剂','Pose':'构象','Model':'模型','Sample':'样品','Variant':'变异','Entity':'实体','Candidate':'候选分子','Protein':'蛋白','illustrative — not a validated result':'示意数据 — 非已验证结果','No criterion applied':'未应用判据','Batch · whole panel':'批次 · 整组','version not recorded':'版本未记录','Run':'运行','Metric':'指标','Compound':'化合物','Gene':'基因','Analyzing outputs…':'正在分析输出…','unattributed':'未归属','Model quality · Phase A':'模型质量 · 阶段 A','Ready':'就绪','Review in panel →':'在面板中核对 →','Open run →':'打开运行 →','Completed':'已完成','Running':'运行中','nothing has run':'尚未运行','Workflow settings':'工作流设置','Phases':'阶段','After run':'运行后','Summary':'摘要','Outputs':'输出','Reproducibility record':'可复现记录','Nothing runs until you confirm.':'确认之前不会运行任何内容。','Confirm and run workflow':'确认并运行工作流','Cancel run':'取消运行','Run again':'再次运行','Inputs':'输入','Parameters and criteria':'参数与判据','origin shown on every value':'每个值都标明来源','why':'原因','edit':'编辑','Input checks':'输入检查','Done':'完成','Queued':'排队中','Open in Files':'在文件中打开','Download':'下载','not recorded':'未记录','Compute':'计算','Download record (JSON)':'下载记录（JSON）','Edit':'编辑','Ask BioMate to edit':'让 BioMate 修改','Download ▾':'下载 ▾','Question':'问题','Answer':'结论','Data':'数据','Method':'方法','Results':'结果','Quality checks':'质量检查','Caveats':'注意事项','Citations':'引用','Reproducibility record ↗':'可复现记录 ↗','← All outputs':'← 全部输出','Message BioMate…':'给 BioMate 发消息…','Sources':'来源','Figure':'图','Table':'表格','Report':'报告','Log':'日志','Pass':'通过','Flagged':'已标记','Advisory':'提示','Not evaluated':'未评估','Unavailable':'不可用','from your message':'来自你的消息','from your file':'来自你的文件','recommended':'推荐','default':'默认','Chat':'对话','No preview for this file type.':'此文件类型暂无预览。','SHA-256 not yet computed ·':'SHA-256 尚未计算 ·','finding':'发现','no criterion':'不设判据','2 structures':'2 个结构','3 structures':'3 个结构','Cycle closure':'循环闭合'};
const NZ={edge:'边',formulation:'制剂',candidate:'候选分子',compound:'化合物',gene:'基因',variant:'变异',protein:'蛋白',sample:'样本',model:'模型',edge:'边',pose:'构象',entity:'实体',term:'条目',condition:'条件'};
const ZHR=[[/^(Table|Figure|Report|Log|Structure) · from (.+) · version$/,(m,a,b)=>({Table:'表格',Figure:'图',Report:'报告',Log:'日志',Structure:'结构'}[a])+' · 来自 '+b+' · 版本'],[/^Per (\w[\w ]*) · (\d+)$/,(m,a,b)=>'逐个'+(NZ[a]||a)+' · '+b],[/^not attributed to any one (\w[\w ]*)$/,(m,a)=>'不归属于任何单个'+(NZ[a]||a)],[/^\+ (\d+) more · all in (.+)$/,'另有 $1 项 · 全部见 $2'],[/^\+ (\d+) more$/,'另有 $1 项'],[/^Running · step (\d+) of (\d+)$/,'运行中 · 第 $1/$2 步'],[/^(\d+)\/(\d+) steps$/,'$1/$2 步'],[/^(\d+)\/(\d+) · findings ready$/,'$1/$2 · 结果已就绪'],[/^(\d+) steps(.*)$/,'$1 个步骤$2'],[/^QC checks · (\d+)$/,'QC 检查 · $1'],[/^Run original · (.+)$/,'运行原件 · $1'],[/^immutable · manifest and (\d+) outputs ·$/,'不可变 · 清单与 $1 个输出 ·'],[/^from run (.+) · the run keeps v1$/,'来自运行 $1 · 运行保留 v1'],[/^(\d+) outputs$/,'$1 个输出'],[/^run original (.+)$/,'运行原件 $1'],[/^(Table|Figure|Report|Log) · (.+) · from (.+) · version$/,(m,a,b,c)=>ZH[a]+' · '+b+' · 来自 '+c+' · 版本'],[/^(.+) · Running$/,'$1 · 运行中']];
BMUI.t=s=>{if(BMUI.lang!=='zh')return s;if(ZH[s]!=null)return ZH[s];for(const[re,rp]of ZHR)if(re.test(s))return s.replace(re,rp);return s;};
function tr(html){const t=document.createElement('template');t.innerHTML=html;t.content.querySelectorAll('[class]').forEach(e=>{const v=e.getAttribute('class').split(/\s+/).filter(Boolean).map(k=>k.startsWith('x-')||k==='bmx'?k:'x_'+k).join(' ');e.setAttribute('class',v);});if(BMUI.lang!=='zh')return t.innerHTML;const w=document.createTreeWalker(t.content,NodeFilter.SHOW_TEXT);let n;while(n=w.nextNode()){const raw=n.nodeValue,s=raw.trim();if(!s)continue;let v=ZH[s];if(v==null)for(const[re,rp]of ZHR)if(re.test(s)){v=s.replace(re,rp);break;}if(v!=null)n.nodeValue=raw.replace(s,v);}return t.innerHTML;}
BMUI.tr=h=>tr(h);BMUI.ZH=ZH;BMUI.ZHR=ZHR;
const SC={settings,phases,running:phases,summary,outputs,record,report};BMUI.SC=SC;
BMUI.screen=(runId,screen,o={})=>{const run=BMUI.runs[runId];const base=screen.split(':')[0];o=Object.assign({screen},o);if(base==='phases'&&o.progress==null)o.state='ready';if(base==='running'&&o.progress==null)o.progress=run.runningAt||2;return tr(SC[base](run,o));};
BMUI.stepCount=id=>nSteps(BMUI.runs[id]);
})();
