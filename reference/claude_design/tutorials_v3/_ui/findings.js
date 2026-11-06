/* BioMate findings primitive — renders one FindingsDocument (docs/alignment/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md
   + the design's requested additions C1–C8 in 20261025_DESIGN_ALIGNMENT_FINDINGS.md). Load after bm-ui.js.
   One renderer for every domain: no per-workflow layouts, nothing hard-coded.
   Block: {k:'findings', doc, mode:'panel'|'chat'|'report', region?, moreFile?}
   Helpers: BMUI.fd.qc(doc) → QC-audit table block · BMUI.fd.E / rec → spec builders. */
(function(){
const U=window.BMUI,B=U.B,out=U.out;
const FLAG={pass:'pass',liability:'flag',advisory:'adv',neutral:'ne',unknown:'unav'};
const CMP={'<':'<','<=':'≤','>':'>','>=':'≥','~':'~','=':''};
const NOUN={compound:'compound',gene:'gene',variant:'variant',protein:'protein',peptide:'peptide',cell_type:'cell type',taxon:'taxon',go_term:'term',pathway:'pathway',particle:'particle',map:'map',residue:'residue',feature:'feature',clonotype:'clonotype',allele:'allele',dose:'dose',sample:'sample',model:'model',edge:'edge',pose:'pose',batch:'batch',condition:'condition',none:'entity'};
const R=r=>r?` data-region="${r}"`:'';
const cap=s=>s.charAt(0).toUpperCase()+s.slice(1);
const val=m=>`${m.comparator&&m.comparator!=='='?CMP[m.comparator]+' ':''}${m.value}`;
const crit=a=>a&&a.threshold?[a.threshold.label,a.threshold.comparator?CMP[a.threshold.comparator]:'',a.threshold.value+(a.threshold.units?' '+a.threshold.units:'')].filter(Boolean).join(' '):'';
const conf=c=>!c?'':c.kind==='ci'||c.kind==='sem'?`<span class="x-fd-pm">± ${c.value}</span>`:`<span class="x-fd-chip ${c.kind}">${c.kind==='ood'?'OOD':c.kind==='applicability'?'AD':'p'} ${c.value}</span>`;
function ent(id,roster){const r=roster.find(x=>x.id===id)||{label:id};
 return r.identitySource==='unresolved'?`<b class="x-fd-unres">${r.identifier?r.identifier.value:r.label}</b><span class="x-fd-chip un">unattributed</span>`
  :`<b>${r.label}</b>${r.identifier?`<span class="x-smi">${r.identifier.value}</span>`:''}`;}
function cell(rec,showUnits){if(!rec||rec.metric.value==null)return `<td class="x-n x-fd-miss">—</td>`;const m=rec.metric,a=rec.assessment,c=m.confidence,pm=c&&(c.kind==='ci'||c.kind==='sem');
 return `<td class="x-n${String(m.value).length>24?' x-fd-long':''}"${R(rec.region)}><span class="v" data-prov="${rec.provenanceRef}" tabindex="0">${val(m)}</span>${pm?conf(c):''}${showUnits&&m.units?`<span class="x-fd-u"> ${m.units}</span>`:''}${pm?'':conf(c)}${a&&a.flag?out(a.label?{o:FLAG[a.flag],label:a.label}:FLAG[a.flag]):''}</td>`;}
const gatedKey=(recs,k)=>recs.some(r=>r.metric.key===k&&r.assessment&&r.assessment.threshold);
const mlabel=(r,short)=>{const c=short?'':crit(r.assessment),u=r.metric.units;return `${r.metric.name}${u?` <span class="c">${u}</span>`:''}${c?` <span class="c">· ${c}</span>`:''}`;};
/* ONE matrix for all per-entity records. Larger dimension on rows. Metrics with a recorded criterion come first;
   when metrics are rows, a divider separates "no criterion applied". Shared criterion/unit live in the header. */
function matrix(d,recs,o){const roster=d.entityRoster.filter(e=>recs.some(r=>r.entity.id===e.id));
 const tp=!o.entityRows&&new Set(recs.map(r=>r.metric.key)).size>roster.length;let mk=[...new Map(recs.map(r=>[r.metric.key,r])).values()].sort((a,b)=>(tp?(gatedKey(recs,b.metric.key)-gatedKey(recs,a.metric.key)):0)||((a.metric.order||0)-(b.metric.order||0)));
 if(o.metrics)mk=mk.filter(r=>o.metrics.includes(r.metric.key));
 const get=(e,k)=>recs.find(r=>r.entity.id===e.id&&r.metric.key===k);const max=o.max||8;let head,body,more='',hidden=0;
 const eh=cap(d.entityNoun||NOUN[d.entityType]||'entity');
 if(mk.length>roster.length&&!o.entityRows){const rows=mk.slice(0,max);hidden=mk.length-rows.length;const nG=rows.filter(r=>gatedKey(recs,r.metric.key)).length;
  head=`<tr><th>Metric</th>${roster.map(e=>`<th class="x-fd-eh">${ent(e.id,d.entityRoster)}</th>`).join('')}</tr>`;
  const tr=r=>`<tr><th scope="row" class="x-fd-mh">${mlabel(r)}</th>${roster.map(e=>cell(get(e,r.metric.key),false)).join('')}</tr>`;
  body=(nG?`<tbody${R(o.region&&o.region+'-gated')}>${rows.slice(0,nG).map(tr).join('')}</tbody>`:'')+(rows.length>nG?`<tbody${R(o.region&&o.region+'-desc')}>${nG?`<tr class="x-fd-div"><td colspan="${roster.length+1}">No criterion applied</td></tr>`:''}${rows.slice(nG).map(tr).join('')}</tbody>`:'');body='\u0000'+body;}
 else{const rows=roster.slice(0,max);hidden=roster.length-rows.length;
  head=`<tr><th>${eh}</th>${mk.map(r=>`<th>${mlabel(r,o.compact)}</th>`).join('')}</tr>`;
  body=rows.map(e=>`<tr${R(o.region&&o.region+'-'+e.id)}><th scope="row">${o.compact?`<b>${(d.entityRoster.find(x=>x.id===e.id)||{}).label}</b>`:ent(e.id,d.entityRoster)}</th>${mk.map(r=>cell(get(e,r.metric.key),false)).join('')}</tr>`).join('');}
 if(o.compact){const cs=mk.filter(r=>crit(r.assessment)).map(r=>`${r.metric.name} ${crit(r.assessment)}`);if(cs.length)more=cs.join(' · ');}
 else if(hidden>0)more=`+ ${hidden} more${o.moreFile?` · all in ${o.moreFile}`:''}`;else if(o.moreNote)more=o.moreNote;
 return `<table class="x-tbl x-fd-m"${R(o.region&&o.region+'-t')}><thead>${head}</thead>${body[0]==='\u0000'?body.slice(1):`<tbody>${body}</tbody>`}</table>${more?`<div class="x-more">${more}</div>`:''}`;}
function noteList(d,recs){const L=recs.filter(r=>r.assessment&&(r.assessment.flag==='liability'||r.assessment.flag==='advisory'));if(!L.length)return '';
 return `<ul class="x-fd-why">${L.map(r=>{const e=d.entityRoster.find(x=>x.id===r.entity.id);return `<li>${out(FLAG[r.assessment.flag])}<span><b>${e?e.label:r.entity.scope==='global'?'Run':'Batch'}</b> · ${r.metric.name} <span class="x-n">${val(r.metric)}${r.metric.units?' '+r.metric.units:''}</span>${crit(r.assessment)?` vs ${crit(r.assessment)}`:''} — ${r.assessment.interpretation}</span></li>`;}).join('')}</ul>`;}
function sourcesLine(d,used){const ids=[...new Set(used)].filter(id=>d.provenance&&d.provenance[id]);if(!ids.length)return '';
 return `<div class="x-src x-fd-src" data-region="sources"><span>Sources</span>${ids.map(id=>{const p=d.provenance[id];return `<span class="x-fd-sf" data-prov="${id}"><span class="x-ty ${p.evidenceClass}">${p.evidenceClass}</span><span class="f">${p.source.file}</span><span class="x-fd-ver">${p.source.version||'version not recorded'}</span></span>`;}).join('')}${d.citations&&d.citations.length?`<span>${d.citations.join(' · ')}</span>`:''}</div>`;}
function tiles(d,recs){return `<div class="x-tiles" style="--n:${recs.length}">${recs.map(r=>`<div class="x-tile"${R(r.region)}><span class="k">${r.metric.name}</span><span class="v"><span data-prov="${r.provenanceRef}">${val(r.metric)}</span>${r.metric.confidence&&r.metric.confidence.kind!=='ood'?`<small>± ${r.metric.confidence.value}</small>`:''}${r.metric.units?`<small>${r.metric.units}</small>`:''}</span><span class="c">${crit(r.assessment)?crit(r.assessment)+' · ':''}${r.assessment&&r.assessment.flag?out(FLAG[r.assessment.flag]):out({o:'ne',label:'no criterion'})}</span></div>`).join('')}</div>`;}
function findings(b){const d=b.doc,mode=b.mode||'panel',g=b.region||'fd';
 if(d.status==='generating')return `<div class="x-fd-state gen"${R(g)}><i></i><span>Analyzing outputs…</span></div>`;
 if(d.status==='unavailable')return `<div class="x-fd-state un"${R(g)}><span><b>Analysis not available</b> — ${d.unavailableReason==='outputs_unreadable'?'the outputs could not be read. The run is still Completed; open Outputs to inspect the files.':'the workflow did not complete. Partial outputs stay in Outputs.'}</span></div>`;
 const recs=d.records,glob=recs.filter(r=>r.entity.scope==='global'),batch=recs.filter(r=>r.entity.scope==='batch'),per=recs.filter(r=>r.entity.scope==='per_entity');
 const noun=d.entityNoun||NOUN[d.entityType]||'entity',nE=d.entityRoster.length;let h=`<div class="x-fd"${R(g)}>`;
 const il='';
 if(mode!=='report')h+=`<div${R(g+'-answer')}><p class="x-ans">${mode==='chat'&&d.chatSummary?d.chatSummary:d.summary}${il}</p>`+`${d.scopeLine&&mode==='panel'?`<div class="x-scope">${d.scopeLine}</div>`:''}</div>`;
 else if(d.illustrative)h+=`<div${R(g+'-il')}>${il}</div>`;
 if(glob.length&&mode!=='chat')h+=`<div class="x-sect"${R(g+'-global')}><div class="hd"><span class="x-k">${d.globalTitle||'Run'}</span></div>${tiles(d,glob)}</div>`;
 if(d.partial&&mode!=='chat')h+=`<div class="x-fd-partial"${R(g+'-partial')}>${d.partial.missing} of ${d.partial.of} ${noun}s could not be read — ${d.partial.reason||'see Log'}</div>`;
 if(mode==='chat'&&per.length&&nE>1){const ks=[...new Map(per.map(r=>[r.metric.key,r])).values()].sort((a,c)=>(a.metric.order||0)-(c.metric.order||0)).map(r=>r.metric.key);
  const lines=d.entityRoster.map(e=>{const rs=per.filter(r=>r.entity.id===e.id);const fl=rs.find(r=>r.assessment&&(r.assessment.flag==='liability'||r.assessment.flag==='advisory'));const m=fl||rs.find(r=>r.metric.key===ks[0])||rs[0];if(!m)return '';const fg=fl||rs.find(r=>r.metric.key===m.metric.key&&r.assessment&&r.assessment.flag)||rs.find(r=>r.assessment&&r.assessment.flag);const sh=fg&&fg.assessment&&(fg.assessment.flag!=='neutral'||fg.assessment.label);
   return '<li'+R(g+'-l-'+e.id)+'><b>'+e.label+'</b><span class="x-n">'+m.metric.name+' '+val(m.metric)+(m.metric.units?' '+m.metric.units:'')+'</span>'+(sh?out(fg.assessment.label?{o:FLAG[fg.assessment.flag],label:fg.assessment.label}:FLAG[fg.assessment.flag]):'')+'</li>';}).filter(Boolean);
  const cap=5;h+='<ul class="x-fd-brief"'+R(g+'-brief')+'>'+lines.slice(0,cap).join('')+'</ul>'+(lines.length>cap?'<div class="x-more">+ '+(lines.length-cap)+' more · all in '+((d.provenance&&d.provenance[per[0].provenanceRef]||{source:{}}).source.file||'the run')+'</div>':'');}
 else if(per.length){const single=nE===1;
  h+=`<div class="x-sect"${R(g+'-entities')}><div class="hd"><span class="x-k">${single?d.entityRoster[0].label:`Per ${noun} · ${(d.entityTotal||nE).toLocaleString('en-US')}`}</span>${d.selection?`<span class="aside">${d.selection.label}</span>`:single&&d.entityRoster[0].identifier?`<span class="aside x-smi">${d.entityRoster[0].identifier.value}</span>`:''}</div>`;
  if(single)h+=`<table class="x-tbl"><tbody>${per.map(r=>`<tr><th scope="row">${r.metric.name}${crit(r.assessment)?` <span class="c">· ${crit(r.assessment)}</span>`:''}</th>${cell(r,true)}</tr>`).join('')}</tbody></table>`;
  else{const ks=[...new Map(per.map(r=>[r.metric.key,r])).values()].sort((a,c)=>(a.metric.order||0)-(c.metric.order||0)).map(r=>r.metric.key),gk=ks.filter(k=>gatedKey(per,k));const chatKeys=mode==='chat'?[...new Set([ks[0]].concat(gk))].slice(0,3):null;b._shown=chatKeys;
   h+=matrix(d,per,{region:g+'-m',max:mode==='chat'?5:(b.max||8),moreFile:b.moreFile||d.moreFile||(d.provenance&&d.provenance[per[0].provenanceRef]||{source:{}}).source.file,moreNote:d.moreNote,metrics:chatKeys,entityRows:d.entityRows||mode==='chat',compact:mode==='chat'});}
  if(mode!=='chat')h+=noteList(d,per);h+='</div>';}
 if(batch.length&&mode!=='chat')h+=`<div class="x-sect"${R(g+'-batch')}><div class="hd"><span class="x-k">Batch · whole panel</span><span class="aside">not attributed to any one ${noun}</span></div><table class="x-tbl"><tbody>${batch.map(r=>`<tr${R(r.region)}><th scope="row">${r.metric.name}${crit(r.assessment)?` <span class="c">· ${crit(r.assessment)}</span>`:''}</th>${cell(r,true)}</tr>`).join('')}</tbody></table>${noteList(d,batch)}</div>`;
 if(mode==='panel'&&d.caveats&&d.caveats.length)h+=`<ul class="x-fd-cav"${R(g+'-caveats')}>${d.caveats.map(c=>`<li>${c}</li>`).join('')}</ul>`;
 if(b.sources===false)return h+'</div>';
 const shown=mode==='chat'?per.filter(r=>!b._shown||b._shown.includes(r.metric.key)):recs;
 h+=sourcesLine(d,shown.map(r=>r.provenanceRef).concat(mode==='chat'?[]:(d.extraSources||[])));
 return h+'</div>';}
B.findings=findings;U.fd=U.fd||{};
/* one merged sources line for a list of blocks (findings provenance + figure/table sources) */
U.fd.__sources=(run,list)=>{const items=[],seen=new Set();list.forEach(b=>{if(b.k==='findings'&&b.doc.provenance)Object.values(b.doc.provenance).forEach(p=>{if(!seen.has(p.source.file)){seen.add(p.source.file);items.push(p);}});const add=s=>{if(s&&!seen.has(s)){seen.add(s);items.push({source:{file:s},evidenceClass:/\.(svg|png)$/.test(s)?'Figure':/\.md$/.test(s)?'Report':'Table'});}};add(b.source);(b.items||[]).forEach(i=>add(i.source));});
 const cit=(list.find(b=>b.k==='findings')||{doc:{}}).doc.citations||run.citations||[];
 return items.length?`<div class="x-src x-fd-src" data-region="sources"><span>Sources</span>${items.map(p=>`<span class="x-fd-sf"><span class="x-ty ${p.evidenceClass}">${p.evidenceClass}</span><span class="f">${p.source.file}</span><span class="x-fd-ver">${p.source.version||'version not recorded'}</span></span>`).join('')}${cit.length?`<span>${cit.join(' · ')}</span>`:''}</div>`:'';};
U.fd=U.fd||{};Object.assign(U.fd,{
 qc(doc){const rows=doc.records.filter(r=>r.assessment&&r.assessment.threshold).map(r=>{const e=doc.entityRoster.find(x=>x.id===r.entity.id);
  return{c:r.metric.name,s:r.entity.scope==='batch'?'Batch':r.entity.scope==='global'?'Run':(e?e.label:'—'),v:val(r.metric)+(r.metric.units?' '+r.metric.units:''),cr:crit(r.assessment),o:FLAG[r.assessment.flag],x:r.execution||'finding',_region:r.qcRegion};});
  return{k:'table',region:'tbl-qc',columns:[{key:'c',label:'Check'},{key:'s',label:'Scope',kind:'entity'},{key:'v',label:'Measured',kind:'mono'},{key:'cr',label:'Criterion',kind:'mono'},{key:'o',label:'Outcome',kind:'outcome'},{key:'x',label:'Execution'}],rows};},
 E:(id,label,scheme,value,src,type)=>({id,type:type||'compound',label,identifier:value?{scheme,value}:undefined,identitySource:src||'input_mapping'}),
 rec:(eid,scope,key,name,value,o={})=>({entity:{id:eid,scope},metric:Object.assign({key,name,value},o.m||{}),assessment:o.a,provenanceRef:o.p,region:o.region,execution:o.x,qcRegion:o.qr}),
 /* compact builder: per-entity table → records.  cols:[{key,name,units,kind,order,a:(v,i)=>assessment}] rows:[[eid,...values]] */
 table(cols,rows,p){const out=[];rows.forEach(row=>cols.forEach((c,j)=>{const v=row[j+1];if(v===undefined)return;out.push(U.fd.rec(row[0],'per_entity',c.key,c.name,v,{p,m:{units:c.units,kind:c.kind||'predicted',order:c.order!=null?c.order:j,comparator:c.cmp&&c.cmp(v)},a:c.a&&c.a(v,row[0]),region:c.region&&c.region+'-'+row[0]}));}));return out;}
});
})();
