import json,time,resource,warnings
from pathlib import Path
import numpy as np
import torch
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score,average_precision_score
from sklearn.exceptions import ConvergenceWarning
import finetune_pretrained_vs_scratch as F
p=Path('/audit/cp10k_probe_20261108');p.mkdir(exist_ok=True)
torch.set_num_threads(2);start=time.time()
ck=F.load_ckpt('/workspace/fs_long/work/hybrid_model.pt');cfg=None
import anndata as ad
A=ad.read_h5ad('/workspace/step0/GSE261278_D534.paired.h5ad')
counts=A.X.tocsr().astype(np.float64)
assert np.isfinite(counts.data).all() and (counts.data>=0).all() and np.allclose(counts.data,np.round(counts.data))
lib=np.asarray(counts.sum(1)).ravel();lib[lib==0]=1
norm=counts.multiply(1e4/lib[:,None]).tocsr();norm.data=np.log1p(norm.data)
x,ng=F.align_genes(list(A.var_names),norm,ck['cfg_meta']['hvg_names'])
stim=A.obs['stim'].astype(str).to_numpy()
assert set(stim)<=set(['unstimulated','flu','sars'])
y=(stim!='unstimulated').astype(int);g=A.obs['cell_type'].astype(str).to_numpy()
(p/'input_audit.json').write_text(json.dumps(dict(n_cells=len(y),all_nonzero_counts_integer=True,genes_aligned=ng,transform='CP10k over all source genes then log1p then HVG alignment; fold scaling unchanged'),indent=2))
del A,counts,norm
splits=np.load('/audit/normalization_20261108/split_indices.npz');preds={};records=[]
def embed(model,cfg,a):
 out=[]
 with torch.no_grad():
  for i in range(0,len(a),512):
   t=torch.from_numpy(a[i:i+512]).cuda();b=len(t)
   out.append(model(torch.zeros(b,cfg['seqlen'],dtype=torch.long,device='cuda'),{'rna':t},{'rna':torch.ones(b,1,device='cuda')},t)['z'].cpu().numpy())
 return np.concatenate(out)
for seed in [0,1,2]:
 for fold in range(3):
  stem=f's{seed}_f{fold}';sub=splits[stem+'_labelled'];te=splits[stem+'_test'];tr=splits[stem+'_normalization_fit']
  assert not set(tr)&set(te) and set(sub)<=set(tr)
  mu=x[tr].mean(0);sd=x[tr].std(0)+1e-6
  a=((x[sub]-mu)/sd).astype(np.float32);b=((x[te]-mu)/sd).astype(np.float32)
  for feature in ['raw','pretrained_z','random_z']:
   if feature=='raw':aa,bb=a,b
   else:
    model,cfg=F.build(ck,feature=='pretrained_z',seed);model.cuda().eval()
    aa=embed(model,cfg,a);bb=embed(model,cfg,b);del model;torch.cuda.empty_cache()
   # Classifier feature scaling fits only labelled rows for every feature arm.
   scaler=StandardScaler().fit(aa);aa=scaler.transform(aa);bb=scaler.transform(bb)
   for c in [.01,.1,1.,10.]:
    clf=LogisticRegression(C=c,max_iter=2000,tol=1e-6,class_weight='balanced',solver='lbfgs')
    with warnings.catch_warnings(record=True) as w:
     warnings.simplefilter('always',ConvergenceWarning);clf.fit(aa,y[sub])
    converged=not any(issubclass(v.category,ConvergenceWarning) for v in w) and int(clf.n_iter_.max())<2000
    if not converged:raise RuntimeError(f'Unconverged {feature} {seed} {fold} {c}')
    key=f'{feature}__{seed}__C{c}';preds.setdefault(key,np.full(len(y),np.nan));preds[key][te]=clf.predict_proba(bb)[:,1]
    records.append(dict(seed=seed,fold=fold,feature=feature,C=c,iterations=int(clf.n_iter_.max()),converged=converged,n_labelled=len(sub),n_test=len(te)))
   print(json.dumps(records[-1]),flush=True)
 np.savez_compressed(p/'predictions.npz',y=y,grp=g.astype(str),**preds)
 results=[]
 for k,v in preds.items():
  assert np.isfinite(v).all();results.append(dict(key=k,auroc=float(roc_auc_score(y,v)),auprc=float(average_precision_score(y,v))))
 (p/'results.json').write_text(json.dumps(dict(protocol='fixed_grid_no_test_selection',results=results,fit_records=records),indent=2))
(p/'memory.json').write_text(json.dumps(dict(seconds=time.time()-start,maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,cuda_peak_allocated=torch.cuda.max_memory_allocated()),indent=2))
print('PROBE_COMPLETE',flush=True)
