"""Independent scalar reconstruction from pre-gate frozen predictions."""
import hashlib,json,math
from pathlib import Path
import numpy as np
P=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/target_specificity_gate')
base=np.load(P.parent/'downstream_only_evaluation/predictions.npz',allow_pickle=False)
shr=np.load(P.parent/'benchmark_shrinkage/predictions.npz',allow_pickle=False)
saved=np.load(P/'predictions.npz',allow_pickle=False)
r=json.loads((P/'results.json').read_text()); fits=json.loads((P.parent/'benchmark_shrinkage/results.json').read_text())['folds']
targets=set(map(str,base['target'])); columns=[i for i,g in enumerate(base['genes']) if str(g) not in targets]
assert len(targets)==16 and len(columns)==116
assert set(map(str,r['excluded_gene_symbols']))==targets
assert saved['mask'].tolist()==[i in columns for i in range(len(base['genes']))]
for f,h in r['input_sha256'].items():assert hashlib.sha256((P.parent/f).read_bytes()).hexdigest()==h
assert hashlib.sha256((P/'protocol.md').read_bytes()).hexdigest()==r['protocol_sha256']
np.testing.assert_array_equal(base['Y'],shr['Y'])
armnames=['no_change','condition_mean','target_condition_mean','target_condition','baseline_state','shuffled_state']
metrics={}; alternatives=0; prediction_checks=0
for fold in fits:
 donor=fold['test_donor'];indices=base[donor+'__test_rows'].tolist()
 assert len(indices)==48 and all(str(base['donor'][i])==donor for i in indices)
 assert indices==shr[donor+'__test_rows'].tolist()
 assert len(set((str(base['target'][i]),str(base['condition'][i])) for i in indices))==48
 for row,i in enumerate(indices):
  condition=str(base['condition'][i]);target=str(base['target'][i]);a=fold['coefficients'][condition]
  truth=base['Y'][i,columns].astype(float)
  pred={name:base[donor+'__'+name][row,columns].astype(float) for name in armnames}
  pred.update({'shrunk_'+name:np.array([a*float(x) for x in pred[name]]) for name in armnames if name!='no_change'})
  np.testing.assert_allclose(pred['shrunk_target_condition_mean'],shr[donor+'__guide_shrunk_target_condition_mean'][row,columns],rtol=0,atol=0)
  wrong=[]
  for target2 in sorted(targets-{target}):
   found=[j for j,k in enumerate(indices) if str(base['target'][k])==target2 and str(base['condition'][k])==condition]
   assert len(found)==1
   wrong.append(a*base[donor+'__target_condition_mean'][found[0],columns].astype(float))
  assert len(wrong)==15;alternatives+=15
  pred['shrunk_other_target_mean']=np.array([math.fsum(float(w[g]) for w in wrong)/15 for g in range(116)])
  ms={name:math.fsum((float(x)-float(y))**2 for x,y in zip(p,truth))/116 for name,p in pred.items()}
  ms['shrunk_all_mismatches_expected_mse']=math.fsum((float(w[g])-float(truth[g]))**2 for w in wrong for g in range(116))/(15*116)
  metrics[(donor,condition,target)]=ms
  for name,p in pred.items():
   np.testing.assert_allclose(p,saved[donor+'__'+name][row],rtol=1e-13,atol=1e-15);prediction_checks+=1
assert alternatives==r['alternative_identity_checks']==2880
assert len(metrics)==len(r['rows'])==192
comparisons=0
for row in r['rows']:
 key=(row['donor'],row['condition'],row['target'])
 for name,v in row['mse'].items():
  assert math.isclose(v,metrics[key][name],rel_tol=1e-13,abs_tol=1e-15);comparisons+=1
for field,axis in [('by_donor',0),('by_condition',1),('by_target',2)]:
 for level,values in r[field].items():
  selected=[m for key,m in metrics.items() if key[axis]==level]
  for name,v in values.items():
   mean=math.fsum(m[name] for m in selected)/len(selected)
   assert math.isclose(v,mean,rel_tol=1e-13,abs_tol=1e-15);comparisons+=1
for name,v in r['equal_donor_mse'].items():
 means=[math.fsum(m[name] for key,m in metrics.items() if key[0]==d)/48 for d in sorted(set(base['donor']))]
 assert math.isclose(v,math.fsum(means)/4,rel_tol=1e-13,abs_tol=1e-15);comparisons+=1
consistency={}
for field in ['by_donor','by_condition']:
 consistency[field]={}
 for reference in ['no_change','shrunk_condition_mean','shrunk_target_condition','shrunk_baseline_state','shrunk_shuffled_state','shrunk_other_target_mean','shrunk_all_mismatches_expected_mse']:
  differences={level:values[reference]-values['shrunk_target_condition_mean'] for level,values in r[field].items()}
  consistency[field][reference]={'matched_better_count':sum(x>0 for x in differences.values()),'total':len(differences),'mse_advantage':differences}
# Also inspect each donor-condition stratum rather than marginal consistency alone.
strata={}
for reference in ['shrunk_condition_mean','shrunk_target_condition','shrunk_baseline_state']:
 deltas=[]
 for donor in sorted(set(base['donor'])):
  for cond in sorted(set(base['condition'])):
   subset=[v for (d,c,t),v in metrics.items() if d==donor and c==cond]
   deltas.append(math.fsum(v[reference]-v['shrunk_target_condition_mean'] for v in subset)/len(subset))
 strata[reference]={'matched_better_count':sum(x>0 for x in deltas),'total':len(deltas),'min_mse_advantage':min(deltas),'max_mse_advantage':max(deltas)}
out={'status':'passed','common_readouts':116,'excluded_targets':16,'rows':192,'all_alternative_pairs':alternatives,'prediction_vectors_checked':prediction_checks,'scalar_metrics_checked':comparisons,'hashes_verified':True,'consistency':consistency,'donor_condition_consistency':strata,'limitations':['Reuses four-donor development data; no independent validation.','Applies previously estimated guide attenuation unchanged to every arm; does not independently re-estimate alpha.']}
(P/'verification.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
