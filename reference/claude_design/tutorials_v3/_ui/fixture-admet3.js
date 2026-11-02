/* Problem 2 acceptance fixture — docs/qa/20261003-tutorial-release/{toxicity_report,qc_metrics}.json.
   Every value below is read from those two files. Nothing is invented; illustrative STATES are built in the page and labelled. */
(function(){
const U=window.BMUI,F=U.fd;
const roster=[F.E('asp','Aspirin','SMILES','CC(=O)Oc1ccccc1C(=O)O'),F.E('caf','Caffeine','SMILES','CN1C=NC2=C1C(=O)N(C(=O)N2C)C'),F.E('ibu','Ibuprofen','SMILES','CC(C)Cc1ccc(C(C)C(=O)O)cc1')];
const P='tox';
const dili={value:0.5,label:'threshold',origin:'default',source:'qc_metrics.json · dili_probability_threshold'};
const ids=['asp','caf','ibu'];
const per=(key,name,vals,o={})=>vals.map((v,i)=>F.rec(ids[i],'per_entity',key,name,v,{p:P,m:Object.assign({kind:'predicted',order:o.order||0},o.units?{units:o.units}:{}),a:o.a&&o.a(v,i),region:o.region&&o.region+'-'+ids[i]}));
const records=[]
 .concat(per('dili','DILI probability',['0.855','0.875','0.487'],{order:1,region:'r-dili',a:v=>({threshold:dili,flag:+v>0.5?'liability':'pass',interpretation:+v>0.5?'above the DILI probability threshold':'below the DILI probability threshold'})}))
 .concat(per('herg_ic50','hERG IC₅₀',['52.725','6633.041','5.227'],{order:2,units:'µM'}))
 .concat(per('herg_p','hERG inhibition (prob.)',['0.0034','0.1149','0.0084'],{order:3}))
 .concat(per('oral','Oral bioavailability (prob.)',['0.8729','0.9363','0.945'],{order:4}))
 .concat(per('bbb','BBB penetration (prob.)',['0.811','0.9698','0.5107'],{order:5}))
 .concat(per('clintox','ClinTox (prob.)',['0.1371','0.0716','0.0118'],{order:6}))
 .concat(per('ppb','Plasma protein binding',['73.1803','29.1686','90.7489'],{order:7,units:'%'}))
 .concat(per('logp','logP',['1.31','-1.03','3.07'],{order:8}))
 .concat(per('mw','Molecular weight',['180.2','194.2','206.3'],{order:9}))
 .concat([
  F.rec('batch','batch','herg_ic50_b','hERG IC₅₀',  '432.4246',{p:'qc',m:{units:'µM',kind:'predicted'},region:'r-batch-herg',a:{threshold:{label:'safe at',comparator:'>',value:10,units:'µM',origin:'default',source:'qc_metrics.json · herg_safe_above_10uM'},flag:'pass',interpretation:'batch value is above 10 µM'}}),
  F.rec('batch','batch','dili_b','DILI probability (worst compound)','0.875',{p:'qc',m:{kind:'predicted'},a:{threshold:dili,flag:'liability',interpretation:'the worst compound exceeds the threshold'}}),
  F.rec('batch','batch','ames_b','Ames probability','0.1',{p:'qc',m:{kind:'predicted'},a:{flag:'neutral',interpretation:'negative; no criterion applied'}})]);
U.fixtures=U.fixtures||{};
U.fixtures.admet3={status:'ready',entityType:'compound',
 summary:'<b>Aspirin and caffeine are flagged on DILI probability; ibuprofen is below the threshold.</b> The batch hERG IC₅₀ passes its criterion.',
 scopeLine:'3 compounds · ADMET-AI (Chemprop MPNN) · predicted values',
 entityRoster:roster,records,
 provenance:{tox:{id:'tox',source:{file:'toxicity_report.json',locator:'per_compound[i]'},producer:{step:'Predict ADMET properties',tool:'ADMET-AI',model:'Chemprop MPNN'},evidenceClass:'Table',outputRef:'toxicity_report.json'},
  qc:{id:'qc',source:{file:'qc_metrics.json'},producer:{step:'Predict ADMET properties',tool:'ADMET-AI'},evidenceClass:'Table',outputRef:'qc_metrics.json'}},
 citations:['Redfern 2003','Kazius 2005','Mulliner 2016'],
 caveats:['The batch hERG IC₅₀ (432.4246 µM) is not one of the per-compound values; toxicity_report.json does not record how it was aggregated.','Batch DILI probability is the worst compound in the panel (dili_aggregation: worst_compound_in_panel).']};
})();
