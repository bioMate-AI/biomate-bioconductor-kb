/* Run specs rendered by bm-ui.js. Each is a typed run (inputs · params · phases · outputs · composed blocks).
   d1: amber "illustrative" values (dataset rows, per-point predictions, analogues) — real workflow values: 200 trees, 5 folds, Morgan r2 1024, CV R² 0.72, RMSE 0.61, criteria R² ≥ 0.5 and n < 50.
   d2: run d0ff684b captured outputs. */
(function(){
const U=window.BMUI;
/* ---------- d1 · QSAR train → score analogues ---------- */
const r=U.rng(7),n=42;let m=[...Array(n)].map(()=>U.gauss(r));{const mu=m.reduce((a,b)=>a+b)/n,sd=Math.sqrt(m.reduce((a,b)=>a+(b-mu)**2,0)/n);m=m.map(v=>6.8+(v-mu)/sd*1.153);}
let e=m.map(v=>-.25*(v-6.8)+.4*U.gauss(r));{const em=e.reduce((a,b)=>a+b)/n;e=e.map(v=>v-em);const rms=Math.sqrt(e.reduce((a,b)=>a+b*b,0)/n);e=e.map(v=>v*.61/rms);}
const pred=m.map((v,j)=>v+e[j]),f2=v=>v.toFixed(2);
const SMI=['Cc1ccc(Nc2nccc(-c3cccnc3)n2)cc1','COc1cc2ncnc(Nc3ccc(F)c(Cl)c3)c2cc1OC','CC(C)Nc1ncc(Cl)c(Nc2ccccc2)n1','O=C(Nc1ccccc1)c1ccc(N2CCOCC2)cc1','Cn1cc(-c2cnc3ccccc3n2)cn1'];
const rd=U.rng(21),train=[...Array(42)].map(()=>{const a=U.gauss(rd)*.11,b=U.gauss(rd)*.12;return[.42+a,.55+b*.9-a*.2];});
const IN={o:'pass',label:'In domain'},OUTD={o:'adv',label:'Out of domain'};
const shortCols=[{key:'id',label:'Analogue',kind:'entity'},{key:'p',label:'Predicted pIC50',kind:'num'},{key:'sim',label:'Nearest training similarity',kind:'num'},{key:'d',label:'Applicability domain',kind:'outcome'}];
const shortRows=[{id:{name:'A-07',smiles:'Cc1ccc(Nc2nccc(-c3cccnc3)n2)cc1F',region:'ent-A-07'},p:'7.9',sim:'0.71',d:IN,_region:'row-A-07'},{id:{name:'A-12',smiles:'Cc1ccc(Nc2nccc(-c3ccncc3)n2)cc1Cl'},p:'7.6',sim:'0.64',d:IN},{id:{name:'A-03',smiles:'COc1ccc(Nc2nccc(-c3cccnc3)n2)cc1'},p:'7.4',sim:'0.58',d:IN},{id:{name:'A-19',smiles:'Cc1ccc(Nc2ncc(F)c(-c3cccnc3)n2)cc1'},p:'7.0',sim:'0.52',d:IN},{id:{name:'A-30',smiles:'O=C1CCC(N2C(=O)c3ccccc3C2=O)C(=O)N1'},p:'6.1',sim:'0.21',d:OUTD,_region:'row-A-30'}];
const shortlist={k:'table',region:'tbl-shortlist',title:'Ranked analogues',columns:shortCols,rows:shortRows,more:'Top 5 of 30 · 4 out of domain · all in analogue_predictions.csv',source:'analogue_predictions.csv'};
const quality={k:'tiles',region:'tiles',title:'Model quality · Phase A',items:[{metric:'CV R²',value:'0.72',criterion:'criterion ≥ 0.5',outcome:'pass',source:'qsar_results.json'},{metric:'CV RMSE',value:'0.61',unit:'log units',outcome:{o:'ne',label:'no criterion'}},{metric:'Training compounds',value:'42',criterion:'advisory below 50',outcome:'adv'}]};
const figCV={k:'figure',region:'fig-cv',kind:'scatter',title:'Predicted vs measured · held-out folds',data:{x:m,y:pred,lo:4,hi:10,xl:'measured pIC50',yl:'predicted'},caption:'cv_predicted_vs_measured.svg · 42 compounds, 5 folds',source:'cv_predicted_vs_measured.svg'};
const figAD={k:'figure',region:'fig-ad',kind:'domain',title:'Applicability domain',data:{train,hull:{cx:.42,cy:.55,rx:.27,ry:.3,rot:-14},queries:[{id:'A-07',x:.47,y:.5,o:'in',label:1},{id:'A-12',x:.36,y:.62,o:'in'},{id:'A-03',x:.52,y:.63,o:'in'},{id:'A-19',x:.3,y:.47,o:'in'},{id:'A-30',x:.86,y:.16,o:'out',label:1},{id:'A-22',x:.9,y:.82,o:'out'},{id:'A-25',x:.08,y:.13,o:'out'},{id:'A-28',x:.78,y:.92,o:'out'}],note:'● in domain   ■ out of domain   · training'},caption:'applicability_domain.svg · nearest-neighbour Tanimoto ≥ 0.35',source:'applicability_domain.svg'};
const F1=U.fd,AN=[['A-07','Cc1ccc(Nc2nccc(-c3cccnc3)n2)cc1F','7.9','0.71'],['A-12','Cc1ccc(Nc2nccc(-c3ccncc3)n2)cc1Cl','7.6','0.64'],['A-03','COc1ccc(Nc2nccc(-c3cccnc3)n2)cc1','7.4','0.58'],['A-19','Cc1ccc(Nc2ncc(F)c(-c3cccnc3)n2)cc1','7.0','0.52'],['A-30','O=C1CCC(N2C(=O)c3ccccc3C2=O)C(=O)N1','6.1','0.21']];
const AD={label:'Tanimoto',comparator:'>=',value:0.35,origin:'default',source:'workflow default · applicability domain'};
const fdD1={status:'ready',entityType:'compound',entityTotal:30,
 summary:'<b>A-07, A-12 and A-03 are worth making.</b> Each is predicted at pIC50 7.4–7.9 and sits inside the model’s applicability domain. 4 of 30 analogues are out of domain and are not ranked.',
 chatSummary:'<b>A-07, A-12 and A-03 are worth making</b> — predicted pIC50 7.4–7.9, all in domain.',
 scopeLine:'30 analogues scored · model passed validation (CV R² 0.72 ≥ 0.5) · 1 advisory: 42 training compounds',
 selection:{label:'Top 5 of 30 by predicted pIC50',rule:'rank by predicted pIC50'},moreNote:'Top 5 of 30 · 4 out of domain · all in analogue_predictions.csv',globalTitle:'Model quality · Phase A',
 entityRoster:AN.map(a=>F1.E(a[0],a[0],'SMILES',a[1])),
 records:[F1.rec('run','global','cv_r2','CV R²','0.72',{p:'res',region:'tiles-1',x:'Phase B released',a:{threshold:{comparator:'>=',value:0.5,origin:'default',source:'Golbraikh & Tropsha 2002'},flag:'pass',interpretation:'the model meets its validation criterion'}}),
  F1.rec('run','global','cv_rmse','CV RMSE','0.61',{p:'res',region:'tiles-2',m:{units:'log units'}}),
  F1.rec('run','global','n_train','Training compounds','42',{p:'res',region:'tiles-3',a:{threshold:{label:'advisory below',value:50,origin:'default'},flag:'advisory',interpretation:'cross-validation can be optimistic on a small set'}})]
  .concat(F1.table([{key:'pic50',name:'Predicted pIC50',order:1},{key:'sim',name:'Nearest training similarity',order:2,kind:'derived',a:v=>(+v>=0.35?{threshold:AD,flag:'pass',label:'In domain',interpretation:'inside the applicability domain'}:{threshold:AD,flag:'advisory',label:'Out of domain',interpretation:'outside the applicability domain — an extrapolation, not ranked'})}],AN.map(a=>[a[0],a[2],a[3]]),'pred')),
 provenance:{res:{id:'res',source:{file:'qsar_results.json'},producer:{step:'Phase A · Cross-validate',tool:'scikit-learn RF'},evidenceClass:'Table',outputRef:'qsar_results.json'},
  pred:{id:'pred',source:{file:'analogue_predictions.csv',locator:'row by analogue id'},producer:{step:'Phase B · Predict pIC50',tool:'scikit-learn RF'},evidenceClass:'Table',outputRef:'analogue_predictions.csv'}},
 citations:['Golbraikh & Tropsha 2002'],
 caveats:['Out-of-domain analogues (A-30 and 3 others) are extrapolations and are not ranked.','With 42 training compounds, cross-validation can be optimistic; an external test set is the stronger check.']};
U.findings=U.findings||{};U.findings.d1=fdD1;
const qcD1={k:'table',region:'tbl-qc',columns:[{key:'c',label:'Check'},{key:'s',label:'Scope'},{key:'v',label:'Measured',kind:'mono'},{key:'cr',label:'Criterion',kind:'mono'},{key:'o',label:'Outcome',kind:'outcome'},{key:'x',label:'Execution'}],
 rows:[{c:'CV R²',s:'model',v:'0.72',cr:'≥ 0.5',o:'pass',x:'Phase B released',_region:'qc-r2'},{c:'Training compounds',s:'dataset',v:'42',cr:'advisory below 50',o:'adv',x:'finding',_region:'qc-n'},{c:'Applicability domain',s:'30 analogues',v:'4 out',cr:'Tanimoto ≥ 0.35',o:'adv',x:'finding · not ranked',_region:'qc-ad'}],source:'qsar_results.json'};
U.runs.d1={id:'d1',project:'Kinase series · QSAR',title:'QSAR · random forest → score analogues',method:'Qsar Rf Model · RDKit Morgan r2 1024 · scikit-learn RF · 3 phases',
 heights:{settings:1100,phases:1000,running:1000,summary:1160,report:'auto'},runningAt:4,
 user:{text:'Here are 42 measured compounds and 30 analogues we drew. Which analogues are worth making?',files:[{name:'actives.csv',meta:'42 rows'},{name:'analogues.csv',meta:'30 rows'}]},
 plan:'Plan — train a random forest QSAR on actives.csv (Morgan r2, 1024 bits, 200 trees, 5-fold CV). Phase B scores the 30 analogues only if CV R² ≥ 0.5, with an applicability-domain check, then ranks them. Review the settings and confirm.',
 updates:[[1,'Inputs resolved — 42 measured compounds, 30 analogues.'],[2,'Fingerprints computed · morgan_fp_r2_1024.'],[3,'Random forest trained · 200 trees.'],[4,'Cross-validation · CV R² 0.72 meets ≥ 0.5 — Phase B released.'],[7,'30 analogues scored · 4 out of domain.'],[8,'Report and output files saved.']],
 inputsAside:'2 files · from your message',
 inputs:[{file:'actives.csv',meta:'42 rows · 3 columns · 3.1 KB',origin:'from your message',roles:[['structure','smiles'],['target','pIC50'],['id','id']],
   preview:{title:'Preview',columns:[{key:'id',label:'id',kind:'mono'},{key:'s',label:'smiles',kind:'mono'},{key:'v',label:'pIC50',kind:'num'}],rows:SMI.map((s,j)=>({id:'CPD-00'+(j+1),s:`<span class="x-smi" style="max-width:220px;color:var(--tx2)">${s}</span>`,v:f2(m[j])})),more:'+ 37 more rows'},
   figure:{kind:'hist',title:'pIC50 distribution',data:{values:m,lo:4,hi:10,step:.5}},
   checks:[['Structure column','smiles','pass'],['Target column','pIC50','pass'],['Enough to train','42 ≥ 10','pass'],['Small dataset','42 < 50 · advisory','adv']]},
  {file:'analogues.csv',meta:'30 rows · 2 columns · 1.9 KB',origin:'from your message',roles:[['structure','smiles'],['id','id']],checks:[['Structures parsed','30 / 30','pass']]}],
 params:[['Target','pIC50','from your file'],['Fingerprint','Morgan · radius 2 · 1024 bits','recommended',1],['Trees','200 · fixed seed','default'],['Cross-validation','5 folds','default'],['Model criterion','CV R² ≥ 0.5 · holds Phase B','default'],['Small-data advisory','n < 50','default'],['Applicability domain','nearest-neighbour Tanimoto ≥ 0.35','default']],
 phases:[{letter:'A',name:'Train and validate',steps:[{name:'Validate input',tool:'input check',params:[['n ≥','10']]},{name:'Featurize',tool:'RDKit',params:[['Morgan','r2 · 1024','recommended']]},{name:'Train random forest',tool:'scikit-learn',params:[['trees','200','default']]},{name:'Cross-validate',tool:'scikit-learn',params:[['folds','5','default']],live:'fold 3 / 5 · R² 0.71'}],
   qc:{aside:'gate before Phase B',rows:[['CV R²','≥ 0.5','pass','gate · holds Phase B'],['Training compounds','advisory below 50','adv','finding']]}},
  {letter:'B',name:'Score analogues',note:'starts only if Phase A passes',steps:[{name:'Featurize analogues',tool:'RDKit',params:[['Morgan','r2 · 1024']]},{name:'Predict pIC50',tool:'model from Phase A'},{name:'Applicability domain',tool:'nearest neighbour',params:[['Tanimoto ≥','0.35','default']]}],
   qc:{aside:'per analogue',rows:[['Applicability domain','Tanimoto ≥ 0.35',{o:'adv',label:'4 of 30 out'},'finding']]}},
  {letter:'C',name:'Report',steps:[{name:'Write report',tool:'BioMate'}]}],
 outputs:[
  {name:'qsar_results.json',type:'Table',size:'0.9 KB',step:'Phase A · Cross-validate',preview:[{k:'kv',region:'kv',items:[['featurizer','morgan_fp_r2_1024','kv-featurizer'],['n_compounds','42'],['target','pIC50'],['n_estimators','200'],['cv_folds','5'],['cv_r2_score','0.72','kv-r2'],['cv_rmse','0.61']]}]},
  {name:'cv_predictions.csv',type:'Table',size:'1.6 KB',step:'Phase A · Cross-validate',preview:[{k:'table',columns:[{key:'id',label:'id',kind:'mono'},{key:'m',label:'measured',kind:'num'},{key:'p',label:'predicted (held-out)',kind:'num'},{key:'f',label:'fold',kind:'mono'}],rows:[0,1,2,3,4].map(j=>({id:'CPD-00'+(j+1),m:f2(m[j]),p:f2(pred[j]),f:String(j%5+1)})),more:'+ 37 more rows'}]},
  {name:'cv_predicted_vs_measured.svg',type:'Figure',size:'14 KB',step:'Phase A · Cross-validate',preview:[figCV]},
  {name:'feature_importance.csv',type:'Table',size:'18 KB',step:'Phase A · Cross-validate',preview:[{k:'table',region:'tbl-imp',columns:[{key:'b',label:'Morgan bit',kind:'mono'},{key:'v',label:'Importance',kind:'bar',max:.118}],rows:[[1380,.118],[650,.094],[807,.071],[1152,.058],[314,.049],[926,.041]].map(x=>({b:x[0],v:x[1]})),more:'Top 6 of 1024 bits · open a bit to see its substructure'}]},
  {name:'analogue_predictions.csv',type:'Table',size:'1.3 KB',step:'Phase B · Applicability domain',preview:[shortlist]},
  {name:'applicability_domain.svg',type:'Figure',size:'16 KB',step:'Phase B · Applicability domain',preview:[figAD]},
  {name:'qsar_report.md',type:'Report',size:'6.2 KB',step:'Phase C · Write report'},
  {name:'versions.yml',type:'Log',size:'0.2 KB',step:'Phase C · Write report'}],
 summary:[{k:'findings',doc:fdD1},{k:'figs',region:'figs',items:[figCV,figAD]}],
 chatAnswer:[{k:'findings',doc:fdD1,mode:'chat'}],
 citations:['Golbraikh & Tropsha 2002'],
 record:{id:'qsar-rf · 2026-10-25',sections:[{id:'methods',name:'Methods',preview:'Random forest on Morgan fingerprints; 5-fold CV; gated scoring with applicability domain.'},
  {id:'params',name:'Parameters',open:1,blocks:[{k:'table',columns:[{key:'p',label:'Parameter'},{key:'v',label:'Value',kind:'mono'},{key:'o',label:'Origin'}],rows:[['Target','pIC50','from your file'],['Fingerprint','Morgan r2 · 1024','recommended'],['Trees','200','default'],['CV folds','5','default'],['Domain','Tanimoto ≥ 0.35','default']].map(x=>({p:x[0],v:x[1],o:`<span class="x-pv ${x[2].replace(/ /g,'-')}">${x[2]}</span>`}))}]},
  {id:'software',name:'Software',preview:'RDKit · scikit-learn — versions in versions.yml, not parsed'},
  {id:'citations',name:'Citations',preview:'Golbraikh & Tropsha 2002 · Rogers & Hahn 2010 · Breiman 2001'},
  {id:'qc',name:'QC audit',open:1,blocks:[qcD1]},
  {id:'trajectory',name:'Trajectory',preview:'routed → inputs resolved → Phase A → gate passed → Phase B → report'}]},
 report:{file:'qsar_report.md',title:'Which drawn analogues are worth making? — QSAR random forest',answer:'A-07, A-12 and A-03 are worth making: predicted pIC50 7.4–7.9 and inside the applicability domain. 4 of 30 analogues are out of domain and are not ranked. The model passed validation (CV R² 0.72 against the 0.5 criterion); one advisory is recorded for the small training set (42 compounds).',
  data:[{k:'table',region:'doc-data-t',columns:[{key:'f',label:'File',kind:'mono'},{key:'r',label:'Role'},{key:'n',label:'Rows',kind:'mono'},{key:'c',label:'Columns used',kind:'mono'}],rows:[{f:'actives.csv',r:'measured · training',n:'42',c:'smiles, pIC50'},{f:'analogues.csv',r:'drawn · to score',n:'30',c:'smiles'}]}],
  method:'Phase A trained a random forest (scikit-learn, 200 trees, fixed seed) on 1024-bit Morgan fingerprints (RDKit, radius 2) and assessed it by 5-fold cross-validation. Phase B started only after CV R² met the 0.5 criterion; it scored the 30 analogues and tested each against the applicability domain (nearest training neighbour, Tanimoto ≥ 0.35).',
  results:[{k:'findings',doc:fdD1,mode:'report',region:'rfd'},{k:'figs',items:[figCV,figAD]}],qc:[qcD1],
  caveats:['Out-of-domain analogues (A-30 and 3 others) are extrapolations and are not ranked.','With 42 training compounds, cross-validation can be optimistic; an external test set is the stronger check.']}};

/* ---------- d2 · ADMET deep learning (run d0ff684b) ---------- */
const ASP={name:'Aspirin',smiles:'CC(=O)OC1=CC=CC=C1C(=O)O'},TER={name:'Terfenadine',smiles:'OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)c1ccc(cc1)C(C)(C)C'};
const checks={k:'table',region:'tbl-checks',title:'Checks with a recorded criterion',columns:[{key:'c',label:'Compound',kind:'entity'},{key:'h',label:'hERG IC₅₀',unit:'µM',kind:'num'},{key:'hc',label:'safe at',into:'h'},{key:'d',label:'DILI probability',kind:'num'},{key:'dc',label:'threshold',into:'d'}],
 rows:[{c:ASP,h:{v:'10000',out:'pass'},hc:'≥ 10 µM',d:{v:'0.855',out:'flag'},dc:'0.5'},{c:TER,h:{v:'0.0124',out:'flag'},hc:'≥ 10 µM',d:{v:'0.043',out:'pass'},dc:'0.5'}],source:'toxicity_report.json'};
const eps={k:'table',region:'tbl-endpoints',title:'Other predicted endpoints · no criterion applied',columns:[{key:'e',label:'Endpoint'},{key:'a',label:'Aspirin',kind:'num'},{key:'t',label:'Terfenadine',kind:'num'}],
 rows:[['hERG inhibition (prob.)','0.003','0.974'],['Oral bioavailability','0.873','0.597'],['BBB penetration','0.811','0.714'],['ClinTox','0.137','0.292'],['Plasma protein binding %','73.2','99.1'],['CYP2D6 inhibitor','0.007','0.817']].map(x=>({e:x[0],a:x[1],t:x[2]})),more:'6 of 15 endpoints · all in toxicity_report.json',source:'toxicity_report.json'};
const qcD2={k:'table',region:'tbl-qc',columns:[{key:'c',label:'Check'},{key:'s',label:'Scope',kind:'entity'},{key:'v',label:'Measured',kind:'mono'},{key:'cr',label:'Criterion',kind:'mono'},{key:'o',label:'Outcome',kind:'outcome'},{key:'x',label:'Execution'}],
 rows:[{c:'hERG IC₅₀',s:'Terfenadine',v:'0.0124 µM',cr:'safe at ≥ 10 µM',o:'flag',x:'finding'},{c:'hERG IC₅₀',s:'Aspirin',v:'10000 µM',cr:'safe at ≥ 10 µM',o:'pass',x:'finding'},{c:'DILI probability',s:'Aspirin',v:'0.855',cr:'threshold 0.5',o:'flag',x:'finding'},{c:'DILI probability',s:'Terfenadine',v:'0.043',cr:'threshold 0.5',o:'pass',x:'finding'}],source:'qc_metrics.json'};
const F2=U.fd,H10={label:'safe at',comparator:'>=',value:10,units:'µM',origin:'default',source:'Redfern 2003 · workflow default'},DT={label:'threshold',value:0.5,origin:'default',source:'qc_metrics.json · dili_probability_threshold'};
const fdD2={status:'ready',entityType:'compound',
 summary:'<b>Terfenadine is flagged on hERG; aspirin is flagged on DILI.</b>',scopeLine:'2 compounds · ADMET-AI (Chemprop MPNN) · predicted values',moreNote:'6 of 15 endpoints shown · all in toxicity_report.json',
 entityRoster:[F2.E('asp','Aspirin','SMILES',ASP.smiles,'input_mapping'),F2.E('ter','Terfenadine','SMILES',TER.smiles,'input_mapping')],
 records:F2.table([{key:'herg',name:'hERG IC₅₀',units:'µM',order:1,a:(v,e)=>+v>=10?{threshold:H10,flag:'pass',interpretation:'above the hERG safety criterion'}:{threshold:H10,flag:'liability',interpretation:'below the 10 µM hERG safety criterion'}},
  {key:'dili',name:'DILI probability',order:2,a:v=>+v>0.5?{threshold:DT,flag:'liability',interpretation:'above the DILI probability threshold'}:{threshold:DT,flag:'pass',interpretation:'below the DILI probability threshold'}},
  {key:'herg_p',name:'hERG inhibition (prob.)',order:3},{key:'oral',name:'Oral bioavailability',order:4},{key:'bbb',name:'BBB penetration',order:5},{key:'clintox',name:'ClinTox',order:6},{key:'ppb',name:'Plasma protein binding',units:'%',order:7},{key:'cyp2d6',name:'CYP2D6 inhibitor',order:8}],
  [['asp','10000','0.855','0.003','0.873','0.811','0.137','73.2','0.007'],['ter','0.0124','0.043','0.974','0.597','0.714','0.292','99.1','0.817']],'tox'),
 provenance:{tox:{id:'tox',source:{file:'toxicity_report.json',locator:'per_compound[i]'},producer:{step:'Predict ADMET properties',tool:'ADMET-AI',model:'Chemprop MPNN'},evidenceClass:'Table',outputRef:'toxicity_report.json'}},
 citations:['Redfern 2003','Kazius 2005','Mulliner 2016'],caveats:[]};
U.findings=U.findings||{};U.findings.d2=fdD2;
U.runs.d2={id:'d2',project:'ADMET triage',title:'ADMET property prediction',method:'ADMET-AI · Chemprop MPNN · 1 phase',heights:{settings:860,summary:1000,report:'auto'},runningAt:1,
 user:{text:'Screen aspirin and terfenadine for ADMET — use the deep-learning model.'},
 plan:'Plan — run ADMET-AI (Chemprop MPNN) on the 2 compounds, then report hERG and DILI against the recorded criteria. Review the settings and confirm.',
 updates:[[0,'Input structures resolved — 2 compounds.'],[0,'ADMET inference started on hosted compute.'],[1,'ADMET inference completed.'],[2,'QC metrics generated · 2 findings.'],[2,'Report and output files saved.']],
 inputsAside:'2 structures · from your message',
 inputs:[{file:'2 structures',meta:'parsed from your message',origin:'from your message',preview:{columns:[{key:'c',label:'Compound',kind:'entity'}],rows:[{c:ASP},{c:TER}]},checks:[['Structures parsed','2 / 2','pass']]}],
 params:[['Model type','MPNN','recommended',1],['Shard size','25','default'],['DILI probability threshold','0.5','default'],['hERG IC₅₀ — safe at','≥ 10 µM','default']],
 phases:[{letter:'A',name:'ADMET inference',steps:[{name:'Infer ADMET (sharded)',tool:'ADMET-AI · Chemprop MPNN',params:[['shard size','25','default']],live:'shard 1 of 1'},{name:'Predict ADMET properties',tool:'merge shards'}],
  qc:{aside:'evaluated when step 2 finishes · findings, nothing downstream to hold',rows:[['hERG IC₅₀','safe at ≥ 10 µM',{o:'flag',label:'1 flagged'},'finding'],['CiPA hERG safety margin','≥ 30',null,'finding'],['CiPA qNet — high risk','≥ −30',null,'finding'],['CiPA EAD probability','≥ 0.7',null,'finding'],['DILI probability','threshold 0.5',{o:'flag',label:'1 flagged'},'finding']]}}],
 outputs:[{name:'toxicity_report.json',type:'Table',size:'2.5 KB',step:'Step 2 · Predict ADMET properties',preview:[{k:'table',title:'per_compound · 2 rows',columns:[{key:'c',label:'Compound',kind:'entity'},{key:'l',label:'logP',kind:'num'},{key:'w',label:'MW',kind:'num'},{key:'h',label:'hERG IC₅₀ µM',kind:'num'},{key:'d',label:'DILI',kind:'num'}],rows:[{c:'Aspirin',l:'1.31',w:'180.2',h:'10000',d:'0.855'},{c:'Terfenadine',l:'7.01',w:'499.7',h:'0.0124',d:'0.043'}]},{k:'kv',items:[['herg_aggregation','worst compound in panel (min IC₅₀)'],['model','MPNN']]}]},
  {name:'qc_metrics.json',type:'Table',size:'562 B',step:'Step 2 · Predict ADMET properties',preview:[qcD2]},
  {name:'predict_admet_properties_output.txt',type:'Table',size:'1.1 KB',step:'Step 2 · Predict ADMET properties'},
  {name:'admet_report.md',type:'Report',size:'4.1 KB',step:'Step 2 · Predict ADMET properties'},
  {name:'report.html',type:'Log',size:'2.8 MB',step:'Run · execution'},{name:'timeline.html',type:'Log',size:'246.4 KB',step:'Run · execution'},{name:'versions.yml',type:'Log',size:'159 B',step:'Run · execution'}],
 summary:[{k:'findings',doc:fdD2}],
 chatAnswer:[{k:'findings',doc:fdD2,mode:'chat'}],
 citations:['Redfern 2003','Kazius 2005','Mulliner 2016'],
 record:{id:'d0ff684b',sections:[{id:'methods',name:'Methods',preview:'ADMET-AI (Chemprop MPNN) on parallel shards; hERG and DILI assessed against recorded criteria.'},
  {id:'params',name:'Parameters',open:1,blocks:[{k:'table',columns:[{key:'p',label:'Parameter'},{key:'v',label:'Value',kind:'mono'},{key:'o',label:'Origin'}],rows:[['SMILES','2 structures','from your message'],['Model type','MPNN','recommended'],['Shard size','25','default'],['DILI threshold','0.5','default']].map(x=>({p:x[0],v:x[1],o:`<span class="x-pv ${x[2].replace(/ /g,'-')}">${x[2]}</span>`}))}]},
  {id:'software',name:'Software',preview:'ADMET-AI · Chemprop MPNN — versions in versions.yml, not parsed'},{id:'citations',name:'Citations',preview:'Redfern 2003 · Kazius 2005 · Mulliner 2016'},
  {id:'qc',name:'QC audit',open:1,blocks:[F2.qc(fdD2)]},{id:'trajectory',name:'Trajectory',preview:'routed → inputs resolved → inference → QC findings → outputs saved'}]},
 report:{file:'admet_report.md',title:'ADMET screen — aspirin and terfenadine',answer:'Terfenadine is flagged on hERG (IC₅₀ 0.0124 µM against a safe-at ≥ 10 µM criterion); aspirin is flagged on DILI (probability 0.855 against a 0.5 threshold). Both are model predictions from ADMET-AI.',
  data:[{k:'table',columns:[{key:'c',label:'Compound',kind:'entity'},{key:'src',label:'Source'}],rows:[{c:ASP,src:'your message'},{c:TER,src:'your message'}]}],
  method:'ADMET-AI (Chemprop MPNN) predicted 15 endpoints for each compound on parallel shards (shard size 25). hERG IC₅₀ and DILI probability were assessed against the recorded criteria; the remaining endpoints are reported without a criterion.',
  results:[{k:'findings',doc:fdD2,mode:'report',region:'rfd'}],qc:[F2.qc(fdD2)],caveats:['The batch hERG value uses the worst compound in the panel (min IC₅₀), as recorded in toxicity_report.json.']}};

/* ---------- d2 · 中文: the same run, content translated (chrome strings are translated by the kit) ---------- */
{const X={'hERG inhibition (prob.)':'hERG 抑制（概率）','Oral bioavailability':'口服生物利用度','BBB penetration':'血脑屏障透过','Plasma protein binding':'血浆蛋白结合','CYP2D6 inhibitor':'CYP2D6 抑制剂','above the hERG safety criterion':'高于 hERG 安全判据','below the 10 µM hERG safety criterion':'低于 10 µM 的 hERG 安全判据','above the DILI probability threshold':'高于 DILI 概率阈值','below the DILI probability threshold':'低于 DILI 概率阈值','6 of 15 endpoints shown · all in toxicity_report.json':'显示 15 项中的 6 项 · 全部见 toxicity_report.json','Oral bioavailability':'口服生物利用度','Plasma protein binding':'血浆蛋白结合','Redfern 2003 · workflow default':'Redfern 2003 · 工作流默认','per_compound[i]':'per_compound[i]','Predict ADMET properties':'预测 ADMET 性质','ADMET triage':'ADMET 初筛','ADMET property prediction':'ADMET 性质预测','ADMET-AI · Chemprop MPNN · 1 phase':'ADMET-AI · Chemprop MPNN · 1 个阶段',
'Screen aspirin and terfenadine for ADMET — use the deep-learning model.':'用深度学习模型对阿司匹林和特非那定做 ADMET 筛查。',
'Plan — run ADMET-AI (Chemprop MPNN) on the 2 compounds, then report hERG and DILI against the recorded criteria. Review the settings and confirm.':'计划 — 用 ADMET-AI（Chemprop MPNN）预测这 2 个化合物，并按记录的判据报告 hERG 与 DILI。请核对设置后确认。',
'Input structures resolved — 2 compounds.':'输入结构已解析 — 2 个化合物。','ADMET inference started on hosted compute.':'ADMET 推理已在托管算力上启动。','ADMET inference completed.':'ADMET 推理已完成。','QC metrics generated · 2 findings.':'QC 指标已生成 · 2 项发现。','Report and output files saved.':'报告与输出文件已保存。',
'2 structures · from your message':'2 个结构 · 来自你的消息','2 structures':'2 个结构','parsed from your message':'从你的消息中解析','Compound':'化合物','Structures parsed':'结构已解析',
'Model type':'模型类型','Shard size':'分片大小','DILI probability threshold':'DILI 概率阈值','hERG IC₅₀ — safe at':'hERG IC₅₀ — 安全线',
'ADMET inference':'ADMET 推理','Infer ADMET (sharded)':'推理 ADMET（分片）','Predict ADMET properties':'预测 ADMET 性质','merge shards':'合并分片','shard size':'分片大小','shard 1 of 1':'第 1/1 个分片',
'evaluated when step 2 finishes · findings, nothing downstream to hold':'第 2 步完成时评估 · 作为发现，无下游可暂停','safe at ≥ 10 µM':'安全线 ≥ 10 µM','1 flagged':'1 项标记','finding':'发现',
'CiPA hERG safety margin':'CiPA hERG 安全裕度','CiPA qNet — high risk':'CiPA qNet — 高风险','CiPA EAD probability':'CiPA EAD 概率','DILI probability':'DILI 概率','threshold 0.5':'阈值 0.5',
'Step 2 · Predict ADMET properties':'第 2 步 · 预测 ADMET 性质','Run · execution':'运行 · 执行',
'<b>Terfenadine is flagged on hERG; aspirin is flagged on DILI.</b>':'<b>特非那定在 hERG 上被标记；阿司匹林在 DILI 上被标记。</b>','2 compounds · ADMET-AI (Chemprop MPNN) · predicted values':'2 个化合物 · ADMET-AI(Chemprop MPNN)· 预测值',
'Checks with a recorded criterion':'有记录判据的检查','safe at':'安全线','threshold':'阈值','Other predicted endpoints · no criterion applied':'其他预测终点 · 未应用判据','Endpoint':'终点',
'hERG inhibition (prob.)':'hERG 抑制（概率）','Oral bioavailability':'口服生物利用度','BBB penetration':'血脑屏障透过','Plasma protein binding %':'血浆蛋白结合 %','CYP2D6 inhibitor':'CYP2D6 抑制剂','6 of 15 endpoints · all in toxicity_report.json':'15 项中的 6 项 · 全部见 toxicity_report.json',
'per_compound · 2 rows':'per_compound · 2 行','worst compound in panel (min IC₅₀)':'组内最差化合物（最小 IC₅₀）',
'Check':'检查','Scope':'范围','Measured':'测量值','Criterion':'判据','Outcome':'结果','Execution':'执行','Parameter':'参数','Value':'值','Origin':'来源','DILI threshold':'DILI 阈值','Source':'来源','your message':'你的消息',
'Methods':'方法','Parameters':'参数','Software':'软件','Citations':'引用','QC audit':'QC 审计','Trajectory':'轨迹',
'ADMET-AI (Chemprop MPNN) on parallel shards; hERG and DILI assessed against recorded criteria.':'ADMET-AI（Chemprop MPNN）并行分片推理；按记录判据评估 hERG 与 DILI。',
'ADMET-AI · Chemprop MPNN — versions in versions.yml, not parsed':'ADMET-AI · Chemprop MPNN — 版本见 versions.yml，尚未解析','routed → inputs resolved → inference → QC findings → outputs saved':'路由 → 解析输入 → 推理 → QC 发现 → 保存输出',
'ADMET screen — aspirin and terfenadine':'ADMET 筛查 — 阿司匹林与特非那定',
'Terfenadine is flagged on hERG (IC₅₀ 0.0124 µM against a safe-at ≥ 10 µM criterion); aspirin is flagged on DILI (probability 0.855 against a 0.5 threshold). Both are model predictions from ADMET-AI.':'特非那定在 hERG 上被标记（IC₅₀ 0.0124 µM，判据为安全线 ≥ 10 µM）；阿司匹林在 DILI 上被标记（概率 0.855，阈值 0.5）。两者均为 ADMET-AI 的模型预测。',
'ADMET-AI (Chemprop MPNN) predicted 15 endpoints for each compound on parallel shards (shard size 25). hERG IC₅₀ and DILI probability were assessed against the recorded criteria; the remaining endpoints are reported without a criterion.':'ADMET-AI（Chemprop MPNN）在并行分片上（分片大小 25）为每个化合物预测了 15 个终点。hERG IC₅₀ 与 DILI 概率按记录的判据评估；其余终点不附判据报告。',
'The batch hERG value uses the worst compound in the panel (min IC₅₀), as recorded in toxicity_report.json.':'批次 hERG 值取组内最差化合物（最小 IC₅₀），见 toxicity_report.json 中的记录。'};
const KEEP=new Set(['from your message','recommended','default','from your file','pass','flag','adv','ne','unav','Table','Figure','Report','Log']);
const NM=[['Aspirin','阿司匹林'],['Terfenadine','特非那定']];
const walk=(v,k)=>{if(typeof v==='string'){if(KEEP.has(v)||['o','type','kind','key','region','_region','id','provenanceRef','scope','flag','evidenceClass','identitySource','scheme','comparator','entityType','outputRef','locator','file','qcRegion','origin'].includes(k)||k==='name'&&/\.(csv|json|sdf|txt|md|yml|html|svg|dot|h5)$/.test(v))return v;let s=X[v]!=null?X[v]:v;NM.forEach(([a,b])=>s=s.split(a).join(b));return s;}
 if(Array.isArray(v))return v.map(x=>walk(x));if(v&&typeof v==='object'){const o={};for(const kk in v)o[kk]=walk(v[kk],kk);return o;}return v;};
const z=walk(U.runs.d2);z.id='d2zh';
/* origin badges inside pre-rendered HTML keep their EN class; the kit translates their text */
U.runs.d2zh=z;}

})();
