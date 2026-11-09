import runpy,sys,resource,time,json
import torch
start=time.time()
sys.argv=['finetune_pretrained_vs_scratch.py','--dataset','gse261278','--data','/workspace/step0/GSE261278_D534.paired.h5ad','--ckpt','/workspace/fs_long/work/hybrid_model.pt','--panel','/audit/panel_overlap.json','--seeds','0','--budgets','0.1,1.0','--epochs','3','--folds','3','--device','cuda','--save-oof','/audit/gse261278_3fold_oof.npz','--out','/audit/gse261278_3fold.json']
runpy.run_path('finetune_pretrained_vs_scratch.py',run_name='__main__')
r=dict(elapsed_seconds=time.time()-start,process_maxrss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,cuda_peak_allocated_bytes=torch.cuda.max_memory_allocated(),cuda_peak_reserved_bytes=torch.cuda.max_memory_reserved())
open('/audit/folds_memory.json','w').write(json.dumps(r,indent=2));print(r,flush=True)
