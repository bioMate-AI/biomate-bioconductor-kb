"""Common-mask target specificity using frozen predictions and attenuation."""
import json,hashlib
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent

def main():
 with np.load(P.parent/'downstream_only_evaluation/predictions.npz',allow_pickle=False) as z:d=dict(z)
 with np.load(P.parent/'benchmark_shrinkage/predictions.npz',allow_pickle=False) as z:sh=dict(z)
 fits=json.loads((P.parent/'benchmark_shrinkage/results.json').read_text())['folds']
 np.testing.assert_array_equal(d['Y'],sh['Y']);mask=~np.isin(d['genes'],d['target']);assert mask.sum()==116
 rows=[];saved={};checks=0
 for fit in fits:
  donor=fit['test_donor'];ix=d[donor+'__test_rows'];np.testing.assert_array_equal(ix,sh[donor+'__test_rows'])
  truth=d['Y'][ix][:,mask];alpha=np.array([fit['coefficients'][c] for c in d['condition'][ix]])[:,None]
  arms={name:d[donor+'__'+name][:,mask] for name in ['no_change','condition_mean','target_condition_mean','target_condition','baseline_state','shuffled_state']}
  for name in ['condition_mean','target_condition_mean','target_condition','baseline_state','shuffled_state']:arms['shrunk_'+name]=alpha*arms[name]
  np.testing.assert_allclose(arms['shrunk_target_condition_mean'],sh[donor+'__guide_shrunk_target_condition_mean'][:,mask],rtol=0,atol=0)
  # Match alternatives only within donor/condition, never across conditions.
  wrong_expected=[];wrong_mean=[]
  for j,i in enumerate(ix):
   candidates=np.flatnonzero((d['condition'][ix]==d['condition'][i])&(d['target'][ix]!=d['target'][i]));assert len(candidates)==15
   assert len(set(d['target'][ix[candidates]]))==15
   wrong=arms['shrunk_target_condition_mean'][candidates];wrong_expected.append(float(np.mean((wrong-truth[j])**2)));wrong_mean.append(wrong.mean(0));checks+=len(candidates)
  arms['shrunk_other_target_mean']=np.array(wrong_mean)
  for name,a in arms.items():assert a.shape==truth.shape and np.isfinite(a).all();saved[donor+'__'+name]=a
  for j,i in enumerate(ix):
   metrics={name:float(np.mean((a[j]-truth[j])**2)) for name,a in arms.items()};metrics['shrunk_all_mismatches_expected_mse']=wrong_expected[j]
   rows.append({'donor':str(donor),'condition':str(d['condition'][i]),'target':str(d['target'][i]),'mse':metrics})
 def summarize(rr):return {name:float(np.mean([r['mse'][name] for r in rr])) for name in rr[0]['mse']}
 by_donor={str(donor):summarize([r for r in rows if r['donor']==donor]) for donor in sorted(set(d['donor']))}
 summary={name:float(np.mean([v[name] for v in by_donor.values()])) for name in rows[0]['mse']}
 result={'protocol_sha256':hashlib.sha256((P/'protocol.md').read_bytes()).hexdigest(),'readouts':int(mask.sum()),'excluded_gene_symbols':d['genes'][~mask].tolist(),'alternative_identity_checks':checks,'equal_donor_mse':summary,'by_donor':by_donor,'by_condition':{str(c):summarize([r for r in rows if r['condition']==c]) for c in sorted(set(d['condition']))},'by_target':{str(t):summarize([r for r in rows if r['target']==t]) for t in sorted(set(d['target']))},'rows':rows,'input_sha256':{name:hashlib.sha256((P.parent/name).read_bytes()).hexdigest() for name in ['downstream_only_evaluation/predictions.npz','benchmark_shrinkage/predictions.npz','benchmark_shrinkage/results.json']}}
 np.savez_compressed(P/'predictions.npz',mask=mask,**saved)
 (P/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
