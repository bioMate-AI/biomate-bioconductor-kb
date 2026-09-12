"""Fit nonnegative attenuation from training-donor guide agreement only."""
import json,hashlib,importlib.util
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('train_select',P/'train_selected_transfer.py');s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
def fit_attenuation(pairs):
 numerator=sum(float(a@b) for a,b in pairs);denominator=sum(float(a@a) for a,b in pairs)
 return float(np.clip(numerator/denominator,0,1)) if denominator>0 else 0.
def main():
 with np.load(P/'pseudobulk.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
 genes,targets,donors,conditions,effects,cpms=s.build(d);x=s.m.norm(d['counts'],d['library_counts']);pool=json.loads((P/'results.json').read_text())['control_guide_assignment'];rows=[];fits=[]
 downstream=~np.isin(genes,targets)
 for test in donors:
  train=next(v for v in donors if v!=test)
  for condition in conditions:
   group=(d['donor_id']==train)&(d['culture_condition']==condition);refs={}
   for p in ['feature','reference']:
    ix=group&np.isin(d['guide_id'],[g for g in pool if pool[g]==p]);assert ix.sum()==4
    refs[p]=s.m.norm(d['counts'][ix].sum(0),d['library_counts'][ix].sum())
   for label,k in [('all',None),('128',128),('512',512)]:
    if k is None:chosen=np.flatnonzero(downstream)
    else:
     chosen,_=s.select(genes,targets,effects,cpms,train,condition,k);chosen=chosen[downstream[chosen]]
    # Symmetrize guide ordering and reference orientation; intercept fixed at zero.
    pairs=[]
    for target in targets:
     ix=np.flatnonzero(group&(d['target']==target));assert len(ix)==2;ix=sorted(ix,key=lambda i:d['guide_id'][i]);a,b=x[ix][:,chosen];f,r=refs['feature'][chosen],refs['reference'][chosen]
     pairs.extend([(a-f,b-r),(b-r,a-f),(a-r,b-f),(b-f,a-r)])
    alpha=fit_attenuation(pairs)
    fits.append({'test_donor':str(test),'train_donor':str(train),'condition':str(condition),'panel':label,'alpha':alpha,'readouts':len(chosen),'genes':genes[chosen].tolist()})
    trainmean=np.mean([effects[train,condition,t][chosen] for t in targets],axis=0)
    for i,target in enumerate(targets):
     mismatch=targets[(i+1)%len(targets)];truth=effects[test,condition,target][chosen];pred=effects[train,condition,target][chosen];wrong=effects[train,condition,mismatch][chosen]
     arms={'no_change':np.zeros(len(chosen)),'condition_mean':trainmean,'matched_observed_target':pred,'shrunk_matched':alpha*pred,'shrunk_mismatched':alpha*wrong}
     rows.append({'test_donor':str(test),'train_donor':str(train),'condition':str(condition),'panel':label,'target':str(target),'alpha':alpha,'metrics':{name:s.m.metrics(value,truth) for name,value in arms.items()}})
 def summary(rr):
  out={}
  for name in rows[0]['metrics']:
   out[name]={}
   for metric in ['mse','pearson','spearman']:
    values=[r['metrics'][name][metric] for r in rr if r['metrics'][name][metric] is not None];out[name][metric]=float(np.mean(values)) if values else None;out[name][metric+'_valid_rows']=len(values)
  return out
 out={'protocol':'Exploratory development baseline after inspecting unattenuated errors. All20 perturbed target genes excluded from every arm and coefficient fit. For each training donor/condition, fit one zero-intercept slope from symmetrized guide/reference-disjoint effects, clipped[0,1]. Apply to observed aggregated target effect in other donor. Fixed all/top128/top512 panels, no heldout outcome selection, no choice of winning panel. Shared controls and gene selection can bias training-guide calibration; only2 donor labels, no significance or promotion claim. Correlations summarize only defined rows; alpha0 yields undefined correlations and changes denominators, so compare MSE and inspect valid_rows rather than claiming correlation improvement.','fits':fits,'by_panel':{k:summary([r for r in rows if r['panel']==k]) for k in ['all','128','512']},'by_panel_test_donor':{k:{str(d):summary([r for r in rows if r['panel']==k and r['test_donor']==d]) for d in donors} for k in ['all','128','512']},'rows':rows,'input_sha256':hashlib.sha256((P/'pseudobulk.npz').read_bytes()).hexdigest()}
 (P/'shrinkage_baseline.json').write_text(json.dumps(out,indent=2,allow_nan=False)+'\n');print(json.dumps(out['by_panel'],indent=2));print('alphas',[round(f['alpha'],4) for f in fits])
if __name__=='__main__':main()
