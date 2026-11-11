import json,time,resource,warnings
from pathlib import Path
import numpy as np
import torch
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score,average_precision_score
from sklearn.exceptions import ConvergenceWarning
import finetune_pretrained_vs_scratch as F
p=Path('/audit/restored_input_20261108');p.mkdir(exist_ok=True)
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
import knowledge_channel as K
# Historical local resources only: fit_bases must not refresh TF data from S3.
K._s3=lambda src,dst: Path(dst).is_file()
bases=K.fit_bases(ck['cfg_meta']['hvg_names'],'/workspace/fs_long/work')
assert bases['n_know']==ck['cfg_meta']['mod_dims']['knowledge']==768
sc=np.load('/audit/input_artifacts/stream_hvg_scaler.npz')
assert list(sc['hvg_names'].astype(str))==list(ck['cfg_meta']['hvg_names'])
assert np.isfinite(sc['mean']).all() and np.isfinite(sc['scale']).all() and (sc['scale']>0).all()
(p/'artifact_metadata.json').write_text(json.dumps(dict(scaler_keys=sc.files,staleness=str(sc['staleness']) if 'staleness' in sc else 'unknown',n_know=bases['n_know'],n_pathways=len(bases['pathways']),n_tf=len(bases['tf'])),indent=2))
np.savez_compressed(p/'knowledge_membership.npz',**{f'p{i}':v for i,v in enumerate(bases['pathways'])},**{f't{i}':v for i,v in enumerate(bases['tf'])})
splits=np.load('/audit/normalization_20261108/split_indices.npz');preds={};records=[]
def embed(model,cfg,a,knowledge=False):
 out=[]
 with torch.no_grad():
  for i in range(0,len(a),512):
   t=torch.from_numpy(a[i:i+512]).cuda();b=len(t)
   mods={'rna':t};masks={'rna':torch.ones(b,1,device='cuda')}
   if knowledge:
    mods['knowledge']=torch.from_numpy(K.transform(a[i:i+512],bases)).cuda();masks['knowledge']=torch.ones(b,1,device='cuda')
   out.append(model(torch.zeros(b,cfg['seqlen'],dtype=torch.long,device='cuda'),mods,masks,t)['z'].cpu().numpy())
 return np.concatenate(out)
for seed in [0,1,2]:
 for fold in range(3):
  stem=f's{seed}_f{fold}';sub=splits[stem+'_labelled'];te=splits[stem+'_test'];tr=splits[stem+'_normalization_fit']
  assert not set(tr)&set(te) and set(sub)<=set(tr)
  mu=sc['mean'];sd=sc['scale']
  a=((x[sub]-mu)/sd).astype(np.float32);b=((x[te]-mu)/sd).astype(np.float32)
  for feature in ['raw','pretrained_z','pretrained_z_knowledge','random_z_knowledge']:
   if feature=='raw':aa,bb=a,b
   else:
    model,cfg=F.build(ck,feature.startswith('pretrained_z'),seed);model.cuda().eval()
    aa=embed(model,cfg,a,feature.endswith('_knowledge'));bb=embed(model,cfg,b,feature.endswith('_knowledge'));del model;torch.cuda.empty_cache()
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
 (p/'results.json').write_text(json.dumps(dict(protocol='approximate_corpus_scaler_preserved_knowledge_fixed_grid',results=results,fit_records=records),indent=2))
(p/'memory.json').write_text(json.dumps(dict(seconds=time.time()-start,maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,cuda_peak_allocated=torch.cuda.max_memory_allocated()),indent=2))
print('PROBE_COMPLETE',flush=True)
