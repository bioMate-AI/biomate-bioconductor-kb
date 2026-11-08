import json,hashlib
from pathlib import Path
import numpy as np
from scipy.linalg import solve
from scipy.stats import rankdata
P=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/downstream_only_evaluation')
r=json.loads((P/'results.json').read_text())
with np.load(P/'predictions.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
y=d['Y'];maxerr=0.;fits=0

def rho(p,t):
 out=[]
 for a,b in zip(p,t):
  if np.ptp(a)>1e-8 and np.ptp(b)>1e-8:out.append(float(np.corrcoef(rankdata(a),rankdata(b))[0,1]))
 return float(np.mean(out)) if out else None

def fit(train,test,alpha,variant):
 global fits
 fits+=1
 cats=[sorted(set(d[k][train])) for k in ['target','condition']]
 def x(ix):return np.concatenate([np.column_stack([d[k][ix]==v for v in vs]) for k,vs in zip(['target','condition'],cats)],1).astype(float)
 xt,xe=x(train),x(test)
 if variant!='target_condition':
  st=d['state'][train]
  if variant=='shuffled_state':
   donors=np.array(sorted(set(d['donor'][train])));order=donors[np.random.default_rng(0).permutation(len(donors))];mapping=dict(zip(order,np.roll(order,1)))
   st=np.array([d['state'][np.where((d['donor']==mapping[d['donor'][i]])&(d['condition']==d['condition'][i]))[0][0]] for i in train])
  xt=np.column_stack([xt,st]);xe=np.column_stack([xe,d['state'][test]])
 mu=xt.mean(0);sd=xt.std(0);sd[sd<1e-14]=1.;xt=(xt-mu)/sd;xe=(xe-mu)/sd
 out=np.empty((len(test),y.shape[1]));groups={}
 for j,g in enumerate(d['genes']):groups.setdefault(tuple(np.flatnonzero(d['target'][train]!=g)),[]).append(j)
 for ids,cols in groups.items():
  ids=np.array(ids);dr=d['donor'][train[ids]];w=np.array([1/np.count_nonzero(dr==v) for v in dr]);w*=len(w)/w.sum()
  xx=xt[ids];yy=y[train[ids]][:,cols];xm=np.average(xx,axis=0,weights=w);ym=np.average(yy,axis=0,weights=w);xc=xx-xm
  beta=solve(xc.T@(w[:,None]*xc)+alpha*np.eye(xx.shape[1]),xc.T@(w[:,None]*(yy-ym)),assume_a='pos')
  out[:,cols]=(xe-xm)@beta+ym
 return out

for fold in r['outer_folds']:
 donor=fold['test_donor'];test=np.array(fold['test_rows']);train=np.flatnonzero(d['donor']!=donor);mask=d['genes'][None,:]!=d['target'][test,None]
 np.testing.assert_array_equal(mask,d[donor+'__mask']);assert mask.sum()==len(test)*(y.shape[1]-1)
 for variant,selection in fold['selection'].items():
  pred=fit(train,test,selection['selected_alpha'],variant);saved=d[donor+'__'+variant];assert np.isnan(saved[~mask]).all();maxerr=max(maxerr,float(np.max(np.abs(pred[mask]-saved[mask]))));np.testing.assert_allclose(pred[mask],saved[mask],rtol=1e-9,atol=1e-10)
  for grid in selection['grid']:
   vals=[]
   for vd in sorted(set(d['donor'][train])):
    tr=train[d['donor'][train]!=vd];va=train[d['donor'][train]==vd];m=d['genes'][None,:]!=d['target'][va,None];p=fit(tr,va,grid['alpha'],variant);vals.append(float(np.mean((p[m]-y[va][m])**2)))
   np.testing.assert_allclose(vals,grid['inner_donor_mse'],rtol=1e-9,atol=1e-10);np.testing.assert_allclose(np.mean(vals),grid['mean_mse'],rtol=1e-9,atol=1e-10)
  assert selection['selected_alpha']==min(selection['grid'],key=lambda g:g['mean_mse'])['alpha']
 for i,row in enumerate(test):
  for j,gene in enumerate(d['genes']):
   if gene==d['target'][row]:continue
   means=[];same=[]
   for td in sorted(set(d['donor'][train])):
    ix=train[(d['donor'][train]==td)&(d['condition'][train]==d['condition'][row])&(d['target'][train]!=gene)]
    if len(ix):means.append(y[ix,j].mean())
    ix2=ix[d['target'][ix]==d['target'][row]]
    same.extend(y[ix2,j].tolist())
   np.testing.assert_allclose(d[donor+'__condition_mean'][i,j],np.mean(means),rtol=1e-12,atol=1e-12)
   np.testing.assert_allclose(d[donor+'__target_condition_mean'][i,j],np.mean(same),rtol=1e-12,atol=1e-12)
   assert d[donor+'__no_change'][i,j]==0.
 for method,metrics in fold['metrics'].items():
  pred=d[donor+'__'+method];actual=metrics['excluding_perturbed_readout'];pp=pred[mask].reshape(len(test),-1);tt=y[test][mask].reshape(len(test),-1)
  np.testing.assert_allclose(np.mean((pp-tt)**2),actual['mse'],rtol=1e-12,atol=1e-12)
  rr=rho(pp,tt)
  if rr is None:assert actual['spearman'] is None
  else:np.testing.assert_allclose(rr,actual['spearman'],rtol=1e-12,atol=1e-12)
  for condition,metrics2 in metrics['by_condition'].items():
   ix=d['condition'][test]==condition;np.testing.assert_allclose(np.mean((pp[ix]-tt[ix])**2),metrics2['mse'],rtol=1e-12,atol=1e-12)
   rr=rho(pp[ix],tt[ix])
   if rr is None:assert metrics2['spearman'] is None
   else:np.testing.assert_allclose(rr,metrics2['spearman'],rtol=1e-12,atol=1e-12)
for method,summary in r['summary_equal_weight_donors'].items():
 for metric,expected in summary['excluding_perturbed_readout'].items():
  vals=[f['metrics'][method]['excluding_perturbed_readout'][metric] for f in r['outer_folds'] if f['metrics'][method]['excluding_perturbed_readout'][metric] is not None]
  if not vals:assert expected is None
  else:np.testing.assert_allclose(np.mean(vals),expected,rtol=1e-12,atol=1e-12)
result={'status':'passed','independent_ridge_fits':fits,'maximum_prediction_absolute_error':maxerr,'all_baseline_predictions_recomputed':True,'all_inner_alpha_grids_recomputed':True,'all_saved_final_ridge_predictions_verified':True,'masks_and_all_direct_prediction_nans_checked':True,'overall_and_condition_metrics_recomputed':True,'equal_donor_summaries_recomputed':True,'implementation':'Weighted centered ridge normal equations; no driver fit or score functions used','prediction_sha256':hashlib.sha256((P/'predictions.npz').read_bytes()).hexdigest(),'results_sha256':hashlib.sha256((P/'results.json').read_bytes()).hexdigest()}
(P/'independent_verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
