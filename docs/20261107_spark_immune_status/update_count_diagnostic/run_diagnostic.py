"""Exploratory matched-update diagnostic; no selection on outer-fold results."""
import json, hashlib, time, resource
from pathlib import Path
import numpy as np
import torch
from sklearn.model_selection import GroupKFold
from sklearn.metrics import roc_auc_score, average_precision_score
import finetune_pretrained_vs_scratch as F

out=Path('/audit/update_count');out.mkdir(exist_ok=True)
torch.set_num_threads(2)
start=time.time();ckpath='/workspace/fs_long/work/hybrid_model.pt'
ck=F.load_ckpt(ckpath);panel=json.load(open('/audit/panel_overlap.json'))
x,_,y,g=F.data_gse261278('/workspace/step0/GSE261278_D534.paired.h5ad',ck['cfg_meta']['hvg_names'],panel)
folds=list(GroupKFold(3).split(x,y,g)); predictions={};records=[];splits={}
def steps_per_epoch(n):
 return sum(min(256,n-i)>=4 for i in range(0,n,256))
assert steps_per_epoch(514)==2 and steps_per_epoch(516)==3
for seed in [0,1,2]:
 for arm in ['pretrained','scratch']:
  preds={mode:np.full(len(y),np.nan) for mode in ['fixed_epochs','matched_full_label_updates']}
  for fold,(tr,te) in enumerate(folds):
   rng=np.random.RandomState(seed);sub=[]
   for c in (0,1):
    ids=tr[y[tr]==c];n=min(max(2,int(round(.1*len(ids)))),len(ids));sub.append(rng.choice(ids,n,replace=False))
   sub=np.concatenate(sub)
   assert not set(sub)&set(te) and not set(g[tr])&set(g[te])
   splitkey=f's{seed}_f{fold}';splits[splitkey+'_labelled']=sub;splits[splitkey+'_test']=te
   xr,xe=F.fold_standardize(x[sub],x[te])
   model,cfg=F.build(ck,arm=='pretrained',seed);clf=F.Clf(model,cfg,False).cuda()
   torch.manual_seed(seed);rng=np.random.RandomState(seed)
   opt=torch.optim.AdamW(clf.parameters(),lr=3e-4,weight_decay=1e-4)
   lossfn=torch.nn.BCEWithLogitsLoss(pos_weight=torch.tensor([(y[sub]==0).sum()/max(1,(y[sub]==1).sum())],device='cuda',dtype=torch.float32))
   xt=torch.from_numpy(xr);yt=torch.from_numpy(y[sub].astype(np.float32))
   checkpoints={12*steps_per_epoch(len(sub)):'fixed_epochs',12*steps_per_epoch(len(tr)):'matched_full_label_updates'}
   count=0;clf.train()
   while count<max(checkpoints):
    perm=rng.permutation(len(sub))
    for i in range(0,len(sub),256):
     b=perm[i:i+256]
     if len(b)<4:continue
     opt.zero_grad();loss=lossfn(clf(xt[b].cuda()),yt[b].cuda())
     if not torch.isfinite(loss):raise ValueError('Nonfinite loss')
     loss.backward()
     if any(p.grad is not None and not torch.isfinite(p.grad).all() for p in clf.parameters()):raise ValueError('Nonfinite gradient')
     opt.step();count+=1
     if count in checkpoints:
      mode=checkpoints[count];clf.eval();parts=[]
      with torch.no_grad():
       for j in range(0,len(te),1024):parts.append(torch.sigmoid(clf(torch.from_numpy(xe[j:j+1024]).cuda())).cpu().numpy())
      pred=np.concatenate(parts);assert np.isfinite(pred).all();preds[mode][te]=pred
      records.append(dict(seed=seed,arm=arm,fold=fold,mode=mode,updates=count,n_labelled=len(sub),n_outer_train=len(tr),n_test=len(te),last_training_loss=float(loss.detach()),labelled_index_sha256=hashlib.sha256(sub.tobytes()).hexdigest()))
      print(json.dumps(records[-1]),flush=True);clf.train()
     if count>=max(checkpoints):break
   del model,clf,opt;torch.cuda.empty_cache()
  for mode,pred in preds.items():
   assert np.isfinite(pred).all();predictions[f'{arm}__{seed}__{mode}']=pred
  np.savez_compressed(out/'predictions.npz',y=y,grp=g.astype(str),**predictions)
  np.savez_compressed(out/'split_indices.npz',**splits)
  results=[dict(key=k,auroc=float(roc_auc_score(y,p)),auprc=float(average_precision_score(y,p))) for k,p in predictions.items()]
  (out/'results.json').write_text(json.dumps(dict(protocol='exploratory_fixed_10pct_labels_matched_updates',results=results,fold_records=records),indent=2))
(out/'memory.json').write_text(json.dumps(dict(elapsed_seconds=time.time()-start,maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,cuda_peak_allocated_bytes=torch.cuda.max_memory_allocated(),cuda_peak_reserved_bytes=torch.cuda.max_memory_reserved()),indent=2))
print('DIAGNOSTIC_COMPLETE',flush=True)
