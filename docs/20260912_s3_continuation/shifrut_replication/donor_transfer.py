"""Known-target observed-effect transfer between donor labels, not model training."""
import json,hashlib,importlib.util
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('metrics',P.parent/'guide_reliability/evaluate.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with np.load(P/'pseudobulk.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
genes=d['gene_symbols'];targets=sorted(t for t in set(d['target']) if t!='NonTarget' and t in genes);donors=sorted(set(d['donor_id']));assert len(donors)==2
conditions=sorted(set(d['culture_condition']));effects={}
for donor in donors:
 for condition in conditions:
  group=(d['donor_id']==donor)&(d['culture_condition']==condition);control=group&(d['target']=='NonTarget');assert control.sum()==8
  baseline=m.norm(d['counts'][control].sum(0),d['library_counts'][control].sum())
  for target in targets:
   ix=group&(d['target']==target);assert ix.sum()==2
   effects[donor,condition,target]=m.norm(d['counts'][ix].sum(0),d['library_counts'][ix].sum())-baseline
rows=[]
for donor in donors:
 train=next(v for v in donors if v!=donor)
 for condition in conditions:
  for i,target in enumerate(targets):
   mismatch=targets[(i+1)%len(targets)];keep=(genes!=target)&(genes!=mismatch);truth=effects[donor,condition,target][keep]
   # Per-output train mean excludes rows directly perturbing that output.
   alltrain=np.array([effects[train,condition,t] for t in targets]);mask=np.array([genes!=t for t in targets]);mean=np.where(mask,alltrain,0).sum(0)/mask.sum(0)
   preds={'no_change':np.zeros(keep.sum()),'condition_mean':mean[keep],'matched_observed_target':effects[train,condition,target][keep],'cyclic_mismatched_target':effects[train,condition,mismatch][keep]}
   rows.append({'test_donor':str(donor),'train_donor':str(train),'condition':str(condition),'target':str(target),'mismatched_target':str(mismatch),'readouts':int(keep.sum()),'metrics':{k:m.metrics(v,truth) for k,v in preds.items()}})
def summarize(rr):
 out={}
 for name in rows[0]['metrics']:
  out[name]={}
  for metric in ['mse','pearson','spearman']:
   values=[r['metrics'][name][metric] for r in rr if r['metrics'][name][metric] is not None];out[name][metric]=float(np.mean(values)) if values else None
 return out
out={'protocol':'Observed known-target effects transferred between2 donor labels in same external experiment. Both guides aggregated, all8 control guides aggregated within donor/condition. Both true-target and mismatched-target readouts excluded from every arm for fair comparison; no fitted model or independent cross-study validation. Two directions reuse same donors. Condition mean excludes direct perturbation per output; cyclic target mismatch fixed lexicographic derangement. Descriptive equal-weight target-condition means, no statistical independence claim.','n_rows':len(rows),'mean_metrics':summarize(rows),'by_test_donor':{d:summarize([r for r in rows if r['test_donor']==d]) for d in donors},'rows':rows,'input_sha256':hashlib.sha256((P/'pseudobulk.npz').read_bytes()).hexdigest()}
(P/'donor_transfer.json').write_text(json.dumps(out,indent=2,allow_nan=False)+'\n');print(json.dumps(out['mean_metrics'],indent=2))
