"""Actual donor-held-out residual MLP training on expanded CZI data."""
import os
os.environ.setdefault('OMP_NUM_THREADS','2')
import json,hashlib,sys
from pathlib import Path
import numpy as np,torch
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
sys.path.insert(0,'/Users/kky/biomate-audit-fix/research/immune_llm_baseline')
import evaluate_downstream_state as base
P=Path(__file__).resolve().parent
ROOT=P.parent
EPOCHS=(0,1,5,10,25,50,200)

def load(path):
 with np.load(path,allow_pickle=False) as z:return dict(z)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def prepare():
 old=load(ROOT/'full_readout_reliability/targets.npz');new=load(ROOT/'basic_qc_panel/targets.npz');c=load(ROOT/'full_readout_reliability/controls.npz')
 np.testing.assert_array_equal(old['gene_symbols'],new['gene_symbols']);np.testing.assert_array_equal(old['gene_symbols'],c['gene_symbols'])
 raw={k:np.concatenate([old[k],new[k]]) for k in ['counts','library_counts','donor_id','culture_condition','perturbed_gene_name','guide_id','source_rows','n_cells']};raw['gene_symbols']=old['gene_symbols']
 agg={'counts':[],'library_counts':[],'donor':[],'condition':[],'pool':[],'gene_symbols':old['gene_symbols']}
 for donor,condition,pool in sorted(set(zip(c['donor_id'],c['culture_condition'],c['pool']))):
  ix=(c['donor_id']==donor)&(c['culture_condition']==condition)&(c['pool']==pool)
  agg['counts'].append(c['counts'][ix].sum(0));agg['library_counts'].append(c['library_counts'][ix].sum());agg['donor'].append(donor);agg['condition'].append(condition);agg['pool'].append(pool)
 agg={k:np.asarray(v) for k,v in agg.items()};base.validate_controls(raw,agg,c);d=base.prepare(raw,agg)
 d['raw']=raw;d['control_raw']=c;d['all_targets']=sorted(set(d['target']));d['all_conditions']=sorted(set(d['condition']))
 fixed=load(ROOT/'target_state_data/targets.npz')['gene_symbols'];d['state_indices']=np.array([np.flatnonzero(d['genes']==g)[0] for g in fixed]);assert len(d['Y'])==384 and len(d['all_targets'])==32
 return d

def select_genes(d,train):
 donors=sorted(set(d['donor'][train]));c=d['control_raw'];ix=np.isin(c['donor_id'],donors);cpm=c['counts'][ix].sum(0)/c['library_counts'][ix].sum()*1e6
 # One training-donor-averaged vector per target/condition, all targets excluded below.
 vectors=[d['Y'][train[(d['target'][train]==t)&(d['condition'][train]==cc)]].mean(0) for t in d['all_targets'] for cc in d['all_conditions']]
 variance=np.var(vectors,axis=0);eligible=(cpm>=1)&~np.isin(d['genes'],d['all_targets']);idx=np.flatnonzero(eligible);chosen=idx[np.lexsort((d['genes'][idx],-variance[idx]))[:512]]
 if len(chosen)!=512:raise ValueError('Insufficient training readouts')
 return chosen

def attenuation(d,fit,genes):
 donors=sorted(set(d['donor'][fit]));raw=d['raw'];coeff={}
 for cond in d['all_conditions']:
  numerator=0.;denominator=0.
  for donor in donors:
   for target in d['all_targets']:
    ix=np.flatnonzero((raw['donor_id']==donor)&(raw['culture_condition']==cond)&(raw['perturbed_gene_name']==target));assert len(ix)==2
    a,b=base.transformed(raw['counts'][ix].astype(float),raw['library_counts'][ix].astype(float))[:,genes];f=d['control'][donor,cond,'feature'][genes];r=d['control'][donor,cond,'reference'][genes]
    for x,y in [(a-f,b-r),(b-r,a-f),(a-r,b-f),(b-f,a-r)]:numerator+=x@y;denominator+=x@x
  coeff[cond]=float(np.clip(numerator/denominator,0,1)) if denominator else 0.
 return coeff

def priors(d,fit,evaluate,genes):
 coeff=attenuation(d,fit,genes);unscaled=[];mean=[]
 for i in evaluate:
  ix=fit[(d['target'][fit]==d['target'][i])&(d['condition'][fit]==d['condition'][i])];assert len(ix)
  unscaled.append(d['Y'][ix][:,genes].mean(0));ci=fit[d['condition'][fit]==d['condition'][i]];mean.append(d['Y'][ci][:,genes].mean(0))
 unscaled=np.asarray(unscaled);return unscaled*np.array([coeff[c] for c in d['condition'][evaluate]])[:,None],unscaled,np.asarray(mean),coeff

def features(d,rows,state):
 blocks=[np.stack([d[k][rows]==v for v in values],axis=1).astype(float) for k,values in [('target',d['all_targets']),('condition',d['all_conditions'])]]
 if state:blocks.append(d['state'][rows][:,d['state_indices']])
 return np.concatenate(blocks,axis=1)

def prepared_fold(d,fit,evaluate):
 genes=select_genes(d,fit);pv,unscaled,mean,coeff=priors(d,fit,evaluate,genes);pt=np.empty((len(fit),len(genes)))
 for donor in sorted(set(d['donor'][fit])):
  local=np.flatnonzero(d['donor'][fit]==donor);others=fit[d['donor'][fit]!=donor];assert len(others)
  pt[local]=priors(d,others,fit[local],genes)[0]
 return {'genes':genes,'fit':fit,'evaluate':evaluate,'train_prior':pt,'val_prior':pv,'target_mean':unscaled,'condition_mean':mean,'coefficients':coeff,'train_y':d['Y'][fit][:,genes],'val_y':d['Y'][evaluate][:,genes]}

def model(n_inputs,n_outputs):
 m=torch.nn.Sequential(torch.nn.Linear(n_inputs,64),torch.nn.ReLU(),torch.nn.Linear(64,n_outputs));torch.nn.init.zeros_(m[-1].weight);torch.nn.init.zeros_(m[-1].bias);return m

def train_one(d,fold,state,seed,max_epochs,checkpoint=None):
 torch.manual_seed(seed);torch.set_num_threads(2)
 scaler=StandardScaler().fit(features(d,fold['fit'],state));xt=torch.tensor(scaler.transform(features(d,fold['fit'],state)),dtype=torch.float32);xv=torch.tensor(scaler.transform(features(d,fold['evaluate'],state)),dtype=torch.float32)
 target=torch.tensor(fold['train_y']-fold['train_prior'],dtype=torch.float32);net=model(xt.shape[1],target.shape[1]);opt=torch.optim.AdamW(net.parameters(),lr=.001,weight_decay=.01);history=[]
 net.eval()
 with torch.no_grad():pred=fold['val_prior']+net(xv).numpy()
 history.append({'epoch':0,'train_residual_mse':float(torch.mean(target**2)),'validation_mse':float(np.mean((pred-fold['val_y'])**2))})
 for epoch in range(1,max_epochs+1):
  net.train();opt.zero_grad();loss=torch.mean((net(xt)-target)**2)
  if not torch.isfinite(loss):raise ValueError('Nonfinite training loss')
  loss.backward();opt.step()
  if (checkpoint is None and epoch in EPOCHS) or epoch==max_epochs:
   net.eval()
   with torch.no_grad():pred=fold['val_prior']+net(xv).numpy()
   history.append({'epoch':epoch,'train_residual_mse':float(loss.detach()),'validation_mse':float(np.mean((pred-fold['val_y'])**2))})
 if checkpoint is not None:
  torch.save(net.state_dict(),checkpoint.with_suffix('.pt'))
  meta={'state':state,'seed':seed,'epochs':max_epochs,'n_inputs':xt.shape[1],'n_outputs':target.shape[1],'hidden':64,'scaler_mean':scaler.mean_.tolist(),'scaler_scale':scaler.scale_.tolist(),'fit_rows':fold['fit'].tolist(),'test_rows':fold['evaluate'].tolist(),'gene_indices':fold['genes'].tolist(),'gene_symbols':d['genes'][fold['genes']].tolist(),'target_categories':d['all_targets'],'condition_categories':d['all_conditions'],'state_gene_symbols':d['genes'][d['state_indices']].tolist(),'prior_coefficients':fold['coefficients']}
  checkpoint.with_suffix('.json').write_text(json.dumps(meta,indent=2)+'\n')
 return pred,history

def main():
 if (P/'results.json').exists():raise ValueError('Refusing to overwrite completed training')
 d=prepare();saved={};records=[];fits=0;checkpoint_dir=P/'checkpoints';checkpoint_dir.mkdir(exist_ok=True)
 for donor in sorted(set(d['donor'])):
  fit=np.flatnonzero(d['donor']!=donor);test=np.flatnonzero(d['donor']==donor);outer=prepared_fold(d,fit,test);inner=[]
  for val in sorted(set(d['donor'][fit])):
   ff=fit[d['donor'][fit]!=val];vv=fit[d['donor'][fit]==val];inner.append(prepared_fold(d,ff,vv))
  preds={'no_change':np.zeros_like(outer['val_y']),'condition_mean':outer['condition_mean'],'target_condition_mean':outer['target_mean'],'guide_shrinkage':outer['val_prior']}
  scaler=StandardScaler().fit(features(d,fit,False));ridge=Ridge(alpha=10).fit(scaler.transform(features(d,fit,False)),outer['train_y']);preds['ridge_alpha10']=ridge.predict(scaler.transform(features(d,test,False)))
  selection={}
  for state in [False,True]:
   for seed in [0,1]:
    name=('mlp_state' if state else 'mlp_target_condition')+'_seed'+str(seed);histories=[]
    for f in inner:
     _,h=train_one(d,f,state,seed,max(EPOCHS));histories.append(h);fits+=1
    grid={e:float(np.mean([next(h['validation_mse'] for h in hh if h['epoch']==e) for hh in histories])) for e in EPOCHS};epochs=min(EPOCHS,key=lambda e:grid[e]);pred,h=train_one(d,outer,state,seed,epochs,checkpoint_dir/(donor+'__'+name));fits+=1;preds[name]=pred;selection[name]={'selected_epochs':epochs,'inner_donor_histories':histories,'mean_inner_mse':grid,'outer_training_history':h}
    print('trained',donor,name,'epochs',epochs,'test MSE',float(np.mean((pred-outer['val_y'])**2)),flush=True)
  metrics={k:float(np.mean((v-outer['val_y'])**2)) for k,v in preds.items()};records.append({'test_donor':str(donor),'genes':d['genes'][outer['genes']].tolist(),'selection':selection,'mse':metrics,'prior_coefficients':outer['coefficients']})
  for k,v in preds.items():saved[donor+'__'+k]=v
  saved[donor+'__truth']=outer['val_y'];saved[donor+'__test_rows']=test;saved[donor+'__genes']=outer['genes']
  np.savez_compressed(P/'predictions.partial.npz',**saved);(P/'progress.json').write_text(json.dumps({'neural_fits_completed':fits,'outer_folds_completed':len(records)},indent=2)+'\n')
 result={'protocol_sha256':sha(P/'protocol.md'),'neural_fits_completed':fits,'final_checkpoints':16,'zero_epoch_final_checkpoints':sum(v['selected_epochs']==0 for r in records for v in r['selection'].values()),'contrast_rows':len(d['Y']),'target_count':len(d['all_targets']),'donor_count':len(set(d['donor'])),'folds':records,'equal_donor_mse':{k:float(np.mean([r['mse'][k] for r in records])) for k in records[0]['mse']},'input_sha256':{name:sha(ROOT/name) for name in ['full_readout_reliability/targets.npz','basic_qc_panel/targets.npz','full_readout_reliability/controls.npz','target_state_data/targets.npz']},'code_sha256':sha(__file__)}
 (P/'predictions.partial.npz').rename(P/'predictions.npz');(P/'results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result['equal_donor_mse'],indent=2))
if __name__=='__main__':main()
