"""Training-guide attenuation on the exact downstream donor benchmark labels."""
import argparse,json
from pathlib import Path
import numpy as np
import evaluate_downstream_state as base

def attenuation(pairs):
 numerator=0.;denominator=0.
 for a,b in pairs:
  a=np.asarray(a,dtype=np.float64);b=np.asarray(b,dtype=np.float64)
  if a.shape!=b.shape or a.ndim!=1 or not np.isfinite(a).all() or not np.isfinite(b).all():raise ValueError('Invalid guide effects')
  numerator+=float(a@b);denominator+=float(a@a)
 return float(np.clip(numerator/denominator,0,1)) if denominator>0 else 0.

def fit_coefficients(raw,d,train):
 donors=set(d['donor'][train]);genes=d['genes'];keep=~np.isin(genes,d['target']);coeff={}
 for cond in sorted(set(d['condition'][train])):
  pairs=[]
  for donor in sorted(donors):
   for target in sorted(set(d['target'][train])):
    ix=np.flatnonzero((raw['donor_id']==donor)&(raw['culture_condition']==cond)&(raw['perturbed_gene_name']==target))
    if len(ix)!=2 or len(set(raw['guide_id'][ix]))!=2:raise ValueError('Require two guide profiles per training group')
    a,b=base.transformed(raw['counts'][ix].astype(float),raw['library_counts'][ix].astype(float))[:,keep]
    f=d['control'][donor,cond,'feature'][keep];r=d['control'][donor,cond,'reference'][keep]
    pairs.extend([(a-f,b-r),(b-r,a-f),(a-r,b-f),(b-f,a-r)])
  coeff[cond]=attenuation(pairs)
 return coeff

def run(raw,d,out):
 rows=[];saved={};checks=0
 for donor in sorted(set(d['donor'])):
  train=np.flatnonzero(d['donor']!=donor);test=np.flatnonzero(d['donor']==donor);coeff=fit_coefficients(raw,d,train)
  altered={k:v.copy() for k,v in raw.items()};altered['counts']=altered['counts'].astype(float);altered['counts'][raw['donor_id']==donor]=np.nan
  if fit_coefficients(altered,d,train)!=coeff:raise AssertionError('Heldout data affects fit')
  checks+=1;preds=base.baseline_predictions(d,train,test)
  preds['guide_shrunk_target_condition_mean']=preds['target_condition_mean']*np.array([coeff[c] for c in d['condition'][test]])[:,None]
  mask=base.mask_without_target(d,test);metrics={}
  for name,pred in preds.items():
   pred[~mask]=np.nan;metrics[name]=base.score(pred,d['Y'][test],mask);saved[donor+'__'+name]=pred
  rows.append({'test_donor':str(donor),'coefficients':coeff,'metrics':metrics});saved[donor+'__mask']=mask;saved[donor+'__test_rows']=test
 np.savez_compressed(out/'predictions.npz',Y=d['Y'],**saved)
 summary={name:float(np.mean([r['metrics'][name]['mse'] for r in rows])) for name in rows[0]['metrics']}
 return {'equal_donor_mse':summary,'folds':rows,'heldout_nan_corruption_checks':checks,'protocol':'Same frozen132 reference-only labels and downstream score as original benchmark. Per-condition attenuation from training donor guide pairs using disjoint reference pools; all target gene readouts excluded when fitting coefficients. Existing per-row downstream masks retained for scoring. No retuning of previous ridge models, no heldout effect fitting. Reused development benchmark, not promotion or untouched validation. Correlation valid counts retained per fold.'}

def main():
 p=argparse.ArgumentParser();p.add_argument('--targets',required=True);p.add_argument('--baseline',required=True);p.add_argument('--controls',required=True);p.add_argument('--prior-predictions',required=True);p.add_argument('--out',required=True);a=p.parse_args();out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
 if (out/'results.json').exists():raise ValueError('Refusing result overwrite')
 def load(p):
  with np.load(p,allow_pickle=False) as z:return dict(z)
 raw=load(a.targets);baseline=load(a.baseline);controls=load(a.controls);base.validate_controls(raw,baseline,controls);d=base.prepare(raw,baseline);prior=load(a.prior_predictions)
 for key in ['Y','donor','condition','target','genes']:np.testing.assert_array_equal(d[key],prior[key])
 result=run(raw,d,out);result['labels_exactly_match_prior']=True;result['input_sha256']={k:base.sha(getattr(a,k)) for k in ['targets','baseline','controls','prior_predictions']};result['code_sha256']=base.sha(__file__)
 (out/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n');print(json.dumps(result['equal_donor_mse'],indent=2))
if __name__=='__main__':main()
