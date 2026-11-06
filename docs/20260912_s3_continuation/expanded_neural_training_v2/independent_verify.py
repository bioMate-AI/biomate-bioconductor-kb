"""Rebuild labels/panels/priors and replay saved MLPs without importing training code."""
from pathlib import Path
import json,hashlib
import numpy as np
import torch
P=Path(__file__).resolve().parent
R=P.parent
def load(p):
 with np.load(p,allow_pickle=False) as z:return dict(z)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def run():
 old=load(R/'full_readout_reliability/targets.npz');new=load(R/'basic_qc_panel/targets.npz');c=load(R/'full_readout_reliability/controls.npz')
 raw={k:np.concatenate([old[k],new[k]]) for k in ['counts','library_counts','donor_id','culture_condition','perturbed_gene_name','guide_id']};genes=old['gene_symbols']
 ctrl={}
 for key in sorted(set(zip(c['donor_id'],c['culture_condition'],c['pool']))):
  ix=(c['donor_id']==key[0])&(c['culture_condition']==key[1])&(c['pool']==key[2]);ctrl[key]=np.log1p(c['counts'][ix].sum(0).astype(float)*1e4/c['library_counts'][ix].sum())
 keys=sorted(set(zip(raw['donor_id'],raw['culture_condition'],raw['perturbed_gene_name'])))
 donor=np.array([k[0] for k in keys]);cond=np.array([k[1] for k in keys]);target=np.array([k[2] for k in keys]);y=[];state=[]
 for key in keys:
  ix=(raw['donor_id']==key[0])&(raw['culture_condition']==key[1])&(raw['perturbed_gene_name']==key[2]);assert ix.sum()==2
  y.append(np.log1p(raw['counts'][ix].sum(0).astype(float)*1e4/raw['library_counts'][ix].sum())-ctrl[key[0],key[1],'reference']);state.append(ctrl[key[0],key[1],'feature'])
 y=np.array(y);state=np.array(state);tc=sorted(set(target));cc=sorted(set(cond));fixed=load(R/'target_state_data/targets.npz')['gene_symbols'];stateix=np.array([np.flatnonzero(genes==g)[0] for g in fixed])
 def select(fit):
  ci=np.isin(c['donor_id'],donor[fit]);cpm=c['counts'][ci].sum(0).astype(float)*1e6/c['library_counts'][ci].sum();v=np.var([y[fit[(target[fit]==t)&(cond[fit]==co)]].mean(0) for t in tc for co in cc],axis=0);eligible=np.flatnonzero((cpm>=1)&~np.isin(genes,tc));return eligible[np.lexsort((genes[eligible],-v[eligible]))[:512]]
 def coeff(fit,g):
  result={}
  for co in cc:
   num=den=0.
   for d in sorted(set(donor[fit])):
    for t in tc:
     ix=(raw['donor_id']==d)&(raw['culture_condition']==co)&(raw['perturbed_gene_name']==t)
     expr=np.log1p(raw['counts'][ix].astype(float)/raw['library_counts'][ix,None]*1e4)[:,g];f=ctrl[d,co,'feature'][g];r=ctrl[d,co,'reference'][g]
     for a,b in [(expr[0]-f,expr[1]-r),(expr[1]-r,expr[0]-f),(expr[0]-r,expr[1]-f),(expr[1]-f,expr[0]-r)]:num+=np.dot(a,b);den+=np.dot(a,a)
   result[co]=float(np.clip(num/den,0,1)) if den else 0.
  return result
 saved=load(P/'predictions.npz');res=json.loads((P/'results.json').read_text());maxdiff=0.;n=0;metrics=0;panels=0
 for rec in res['folds']:
  d=rec['test_donor'];fit=np.flatnonzero(donor!=d);test=np.flatnonzero(donor==d);g=select(fit);panels+=1
  np.testing.assert_array_equal(g,saved[d+'__genes']);np.testing.assert_allclose(y[test][:,g],saved[d+'__truth'],rtol=1e-12,atol=1e-12)
  for vd in sorted(set(donor[fit])):
   ig=select(fit[donor[fit]!=vd]);assert len(ig)==512 and not set(genes[ig])&set(tc);panels+=1
  cf=coeff(fit,g);tm=np.array([y[fit[(target[fit]==target[i])&(cond[fit]==cond[i])]][:,g].mean(0) for i in test]);prior=tm*np.array([cf[co] for co in cond[test]])[:,None]
  np.testing.assert_allclose(prior,saved[d+'__guide_shrinkage'],rtol=1e-11,atol=1e-12)
  for co in cc:np.testing.assert_allclose(cf[co],rec['prior_coefficients'][co],rtol=1e-11,atol=1e-12)
  for name,sel in rec['selection'].items():
   stem=P/'checkpoints'/(d+'__'+name);m=json.loads(stem.with_suffix('.json').read_text());np.testing.assert_array_equal(m['fit_rows'],fit);np.testing.assert_array_equal(m['test_rows'],test);np.testing.assert_array_equal(m['gene_indices'],g)
   assert m['target_categories']==tc and m['condition_categories']==cc and m['state_gene_symbols']==fixed.tolist()
   def x(rows):
    blocks=[np.stack([target[rows]==t for t in tc],1).astype(float),np.stack([cond[rows]==co for co in cc],1).astype(float)]
    if m['state']:blocks.append(state[rows][:,stateix])
    return np.concatenate(blocks,1)
   xt=x(fit);mean=xt.mean(0);scale=xt.std(0);scale[scale==0]=1
   np.testing.assert_allclose(mean,m['scaler_mean'],rtol=1e-12,atol=1e-12);np.testing.assert_allclose(scale,m['scaler_scale'],rtol=1e-11,atol=1e-12)
   weights=torch.load(stem.with_suffix('.pt'),map_location='cpu',weights_only=True)
   if m['epochs']==0:
    assert torch.count_nonzero(weights['2.weight'])==0 and torch.count_nonzero(weights['2.bias'])==0
    np.testing.assert_array_equal(saved[d+'__'+name],saved[d+'__guide_shrinkage'])
   xx=torch.tensor((x(test)-np.array(m['scaler_mean']))/np.array(m['scaler_scale']),dtype=torch.float32)
   with torch.no_grad():pred=prior+torch.nn.functional.linear(torch.relu(torch.nn.functional.linear(xx,weights['0.weight'],weights['0.bias'])),weights['2.weight'],weights['2.bias']).numpy()
   diff=float(np.max(np.abs(pred-saved[d+'__'+name])));maxdiff=max(maxdiff,diff);np.testing.assert_allclose(pred,saved[d+'__'+name],rtol=1e-5,atol=2e-7);n+=1
   grid={int(k):float(np.mean([next(h['validation_mse'] for h in hs if h['epoch']==int(k)) for hs in sel['inner_donor_histories']])) for k in sel['mean_inner_mse']};assert min(grid,key=grid.get)==sel['selected_epochs']==m['epochs']
  for name,value in rec['mse'].items():
   actual=float(np.mean((saved[d+'__'+name]-y[test][:,g])**2));np.testing.assert_allclose(actual,value,rtol=1e-12,atol=1e-12);metrics+=1
 for name,value in res['equal_donor_mse'].items():np.testing.assert_allclose(value,np.mean([r['mse'][name] for r in res['folds']]),rtol=1e-12,atol=1e-12)
 deps=Path('/Users/kky/biomate-audit-fix/research/immune_llm_baseline')
 report={'status':'passed','checkpoints_replayed':n,'fold_gene_panels_reconstructed':panels,'outer_metrics_recomputed':metrics,'max_prediction_difference':maxdiff,'independent_label_normalization':True,'fit_only_gene_selection_scalers_and_attenuation_verified':True,'inner_epoch_selection_verified_from_recorded_histories':True,'limitations':'Inner histories were checked for selection consistency, not independently retrained. Outer held-out diagnostic metrics are logged but never used in selection. Four donors are reused across folds.','dependency_sha256':{f:sha(deps/f) for f in ['evaluate_downstream_state.py','evaluate_baseline_state.py']},'artifact_sha256':{f:sha(P/f) for f in ['train.py','predictions.npz','results.json']}}
 (P/'independent_verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':run()
