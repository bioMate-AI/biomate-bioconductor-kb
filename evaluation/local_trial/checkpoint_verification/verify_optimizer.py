import torch, json, math, hashlib
from pathlib import Path
from collections import Counter
import argparse
parser=argparse.ArgumentParser(description="Audit saved recovery2 optimizer states without unsafe pickle loading")
parser.add_argument("root",type=Path)
root=parser.parse_args().root
report={'run_id':'full_concept_recovery2_20261003','load_mode':'torch.load(weights_only=True, map_location=cpu)','stages':{}}
def tensors(obj,path=''):
    if isinstance(obj,torch.Tensor): yield path,obj
    elif isinstance(obj,dict):
        for k,v in obj.items(): yield from tensors(v,f'{path}/{k}')
    elif isinstance(obj,(list,tuple)):
        for k,v in enumerate(obj): yield from tensors(v,f'{path}/{k}')
for stage,expected in [('midtrain',50),('sft',10)]:
    opt=torch.load(root/stage/'optimizer.pt',weights_only=True,map_location='cpu')
    sch=torch.load(root/stage/'scheduler.pt',weights_only=True,map_location='cpu')
    ts=list(tensors(opt)); states=opt['state']; steps=Counter(float(x['step']) for x in states.values())
    bad=[p for p,t in ts if not torch.isfinite(t).all().item()]
    moments=[(p,t) for p,t in ts if p.endswith('/state1') or p.endswith('/state2')]
    nonzero=sum(bool(torch.count_nonzero(t).item()) for p,t in moments)
    result={'expected_updates':expected,'parameter_states':len(states),'optimizer_step_counts':dict(steps),'optimizer_tensor_count':len(ts),'optimizer_tensor_elements':sum(t.numel() for _,t in ts),'nonfinite_tensor_paths':bad,'optimizer_format':'bitsandbytes quantized state','moment_tensors':len(moments),'nonzero_moment_tensors':nonzero,'scheduler_state':sch,'optimizer_group_lrs':[g['lr'] for g in opt['param_groups']],'sha256':{name:hashlib.sha256((root/stage/name).read_bytes()).hexdigest() for name in ['optimizer.pt','scheduler.pt']}}
    scales=[t for p,t in ts if p.endswith('/absmax1') or p.endswith('/absmax2')]
    result['scale_tensors']=len(scales)
    result['checks']={'optimizer_states_present':bool(states),'all_optimizer_tensors_finite':not bad,'all_optimizer_steps_match':set(steps)=={float(expected)},'all_quantized_moment_tensors_nonzero':nonzero==len(moments) and bool(moments),'all_scales_positive_finite':bool(scales) and all(bool(torch.isfinite(t).all() and (t>0).all()) for t in scales),'scheduler_last_epoch_matches':sch.get('last_epoch')==expected,'scheduler_step_count_matches':sch.get('_step_count')==expected+1}
    result['passed']=all(result['checks'].values()); report['stages'][stage]=result
report['passed']=all(r['passed'] for r in report['stages'].values())
(root/'optimizer_integrity_report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))

raise SystemExit(0 if report["passed"] else 1)
