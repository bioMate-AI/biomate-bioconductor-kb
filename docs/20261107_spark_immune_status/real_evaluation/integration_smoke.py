import os, time, json, resource, hashlib
from pathlib import Path
import numpy as np
import anndata as ad
ad.settings.allow_write_nullable_strings = True
import torch
import finetune_pretrained_vs_scratch as F
start=time.time(); out=Path('/audit'); ckpath='/workspace/fs_long/work/hybrid_model.pt'
ck=F.load_ckpt(ckpath)
model,cfg=F.build(ck,True,0)
print('CHECKPOINT_LOAD_OK',len(ck['trainable_state_dict']),flush=True)
a=ad.read_h5ad('/workspace/step0/GSE261278_D534.paired.h5ad',backed='r')
ix=np.sort(np.random.RandomState(0).choice(a.n_obs,min(1024,a.n_obs),replace=False))
b=a[ix].to_memory(); a.file.close(); b.write_h5ad(out/'sample_1024.h5ad'); del b,a
panel=json.load(open('/audit/panel_overlap.json'))
x,p,y,g=F.data_gse261278(str(out/'sample_1024.h5ad'),cfg['hvg_names'],panel)
from sklearn.model_selection import GroupKFold
from sklearn.metrics import roc_auc_score
tr,te=next(GroupKFold(n_splits=2).split(x,y,g))
xtr,xte=F.fold_standardize(x[tr],x[te]); ptr,pte=F.fold_standardize(p[tr],p[te])
results=[]
for inp in ['rna','rna_protein']:
 for arm in ['pretrained_frozen','pretrained','scratch']:
  model,cfg=F.build(ck,arm!='scratch',0)
  clf=F.Clf(model,cfg,inp=='rna_protein')
  torch.cuda.reset_peak_memory_stats()
  pred=F.fit_predict(clf,arm,xtr,ptr if inp=='rna_protein' else None,y[tr],xte,pte if inp=='rna_protein' else None,1,3e-4,0,'cuda')
  assert np.isfinite(pred).all()
  row=dict(input=inp,arm=arm,n_train=len(tr),n_test=len(te),auroc=float(roc_auc_score(y[te],pred)),cuda_peak_allocated_bytes=torch.cuda.max_memory_allocated(),cuda_peak_reserved_bytes=torch.cuda.max_memory_reserved())
  results.append(row); print(json.dumps(row),flush=True)
  del clf,model; torch.cuda.empty_cache()
r=dict(protocol='integration_only_one_group_fold_1024_cells_one_epoch_not_biological_evaluation',checkpoint_sha256=hashlib.sha256(Path(ckpath).read_bytes()).hexdigest(),results=results,elapsed_seconds=time.time()-start,process_maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
(out/'integration_smoke.json').write_text(json.dumps(r,indent=2)); print('INTEGRATION_PASS',flush=True)
