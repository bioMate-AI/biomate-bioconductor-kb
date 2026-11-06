"""Independently reconstruct exact benchmark labels, coefficients and predictions."""
import hashlib,json
from pathlib import Path
import numpy as np
from scipy.stats import spearmanr
P=Path(__file__).resolve().parent;ROOT=P.parent
paths={'targets':ROOT/'target_state_data/targets.npz','baseline':ROOT/'baseline_state_data/baseline_aggregates.npz','controls':ROOT/'baseline_state_data/controls.npz','prior_predictions':ROOT/'downstream_only_evaluation/predictions.npz'}
r=json.loads((P/'results.json').read_text())
def load(p):
 with np.load(p,allow_pickle=False) as z:return dict(z)
for name,p in paths.items():assert hashlib.sha256(p.read_bytes()).hexdigest()==r['input_sha256'][name]
t,b,c,prior=[load(paths[k]) for k in ['targets','baseline','controls','prior_predictions']];saved=load(P/'predictions.npz')
genes=t['gene_symbols'];np.testing.assert_array_equal(genes,b['gene_symbols']);np.testing.assert_array_equal(genes,c['gene_symbols']);np.testing.assert_array_equal(genes,prior['genes'])
assert set(c['guide_id'][c['pool']=='feature']).isdisjoint(set(c['guide_id'][c['pool']=='reference']))
def norm(counts,lib):return np.log1p(10000*np.asarray(counts,dtype=float)/lib)
refs={}
for i in range(len(b['counts'])):
 key=tuple(str(b[k][i]) for k in ['donor','condition','pool'])
 ix=[j for j in range(len(c['counts'])) if (c['donor_id'][j],c['culture_condition'][j],c['pool'][j])==key]
 np.testing.assert_array_equal(c['counts'][ix].sum(0),b['counts'][i]);assert c['library_counts'][ix].sum()==b['library_counts'][i]
 refs[key]=norm(b['counts'][i],b['library_counts'][i])
keys=sorted(set(zip(t['donor_id'],t['culture_condition'],t['perturbed_gene_name'])));labels=[];groups={}
for donor,cond,target in keys:
 ix=[i for i in range(len(t['counts'])) if (t['donor_id'][i],t['culture_condition'][i],t['perturbed_gene_name'][i])==(donor,cond,target)]
 assert len(ix)==2 and len(set(t['guide_id'][ix]))==2;groups[donor,cond,target]=ix
 labels.append(norm(t['counts'][ix].sum(0),t['library_counts'][ix].sum())-refs[donor,cond,'reference'])
y=np.array(labels);np.testing.assert_array_equal(y,saved['Y']);np.testing.assert_array_equal(y,prior['Y'])
for axis,key in enumerate(['donor','condition','target']):np.testing.assert_array_equal([k[axis] for k in keys],prior[key])
excluded=set(prior['target']);fitkeep=np.array([g not in excluded for g in genes]);assert len(excluded)==16
coefchecks=0;predictionchecks=0;metricchecks=0
for fold in r['folds']:
 testdonor=fold['test_donor'];train=sorted(set(prior['donor'])-{testdonor});test=np.array([i for i,k in enumerate(keys) if k[0]==testdonor]);mask=genes[None,:]!=prior['target'][test,None]
 np.testing.assert_array_equal(test,saved[testdonor+'__test_rows']);np.testing.assert_array_equal(mask,saved[testdonor+'__mask']);np.testing.assert_array_equal(mask,prior[testdonor+'__mask'])
 coeff={}
 for cond,value in fold['coefficients'].items():
  num=0.;den=0.
  for donor in train:
   f=refs[donor,cond,'feature'][fitkeep];ref=refs[donor,cond,'reference'][fitkeep]
   for target in sorted(excluded):
    a,bv=[norm(t['counts'][i],t['library_counts'][i])[fitkeep] for i in groups[donor,cond,target]]
    for u,v in [(a-f,bv-ref),(a-ref,bv-f)]:num+=2*float(np.sum(u*v));den+=float(np.sum(u*u)+np.sum(v*v))
  coeff[cond]=max(0,min(1,num/den)) if den>0 else 0.
  np.testing.assert_allclose(value,coeff[cond],rtol=1e-12,atol=1e-12);coefchecks+=1
 for arm,metrics in fold['metrics'].items():
  pred=saved[testdonor+'__'+arm];assert np.isnan(pred[~mask]).all()
  if arm!='guide_shrunk_target_condition_mean':np.testing.assert_array_equal(pred,prior[testdonor+'__'+arm])
  else:
   expected=prior[testdonor+'__target_condition_mean']*np.array([coeff[keys[i][1]] for i in test])[:,None]
   np.testing.assert_allclose(pred,expected,rtol=1e-12,atol=1e-12,equal_nan=True)
  predictionchecks+=1
  errors=[];rhos=[];cp=ct=short=0
  for p,truth,keep in zip(pred,y[test],mask):
   errors.append(float(np.mean((p[keep]-truth[keep])**2)))
   if sum(keep)<3:short+=1;continue
   pc=np.ptp(p[keep])<=1e-8;tc=np.ptp(truth[keep])<=1e-8;cp+=int(pc);ct+=int(tc)
   if not(pc or tc):rhos.append(float(spearmanr(p[keep],truth[keep]).statistic))
  actual={'mse':sum(errors)/len(errors),'spearman':sum(rhos)/len(rhos) if rhos else None,'rows':len(test),'mse_rows':len(errors),'spearman_rows':len(rhos),'constant_prediction_rows':cp,'constant_target_rows':ct,'fewer_than_three_readouts':short}
  for key,value in actual.items():
   if value is None:assert metrics[key] is None
   else:np.testing.assert_allclose(metrics[key],value,rtol=1e-12,atol=1e-12)
   metricchecks+=1
for arm,value in r['equal_donor_mse'].items():np.testing.assert_allclose(value,sum(f['metrics'][arm]['mse'] for f in r['folds'])/4,rtol=1e-12,atol=1e-12)
out={'status':'passed','coefficients_verified':coefchecks,'prediction_arrays_verified':predictionchecks,'fold_metric_and_count_comparisons':metricchecks,'exact_label_equality':'All192x132 labels rebuilt from raw aggregated targets minus reference-only controls; bitwise match to current and prior saved labels','prior_baselines':'All12 prior baseline arrays exactly unchanged, including direct-output NaNs','control_aggregates':'All24 baseline groups exactly reconstructed from native controls, guide pools disjoint','mask':'Same per-row downstream masks as prior benchmark; all16 target genes excluded only for coefficient fitting','leakage_review':'Coefficient fitting uses training donors only; held-out target/reference values only used as truth. Reused development benchmark; no ridge rerun or independent confirmation.','prediction_sha256':hashlib.sha256((P/'predictions.npz').read_bytes()).hexdigest(),'results_sha256':hashlib.sha256((P/'results.json').read_bytes()).hexdigest()}
(P/'independent_verification.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
