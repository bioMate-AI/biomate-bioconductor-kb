import json,struct,hashlib,math
from pathlib import Path
from safetensors import safe_open
import torch
import argparse
parser=argparse.ArgumentParser(description="Audit downloaded recovery2 checkpoint adapters against the merged-base header")
parser.add_argument("root",type=Path)
p=parser.parse_args().root
b=(p/'base-header.bin').read_bytes(); n=struct.unpack('<Q',b[:8])[0]; h=json.loads(b[8:8+n]); tensors={k:v for k,v in h.items() if k!='__metadata__'}
end=0
for k,v in sorted(tensors.items(),key=lambda x:x[1]['data_offsets'][0]):
 a,z=v['data_offsets']; assert a==end,(k,a,end)
 size={'BF16':2,'F16':2,'F32':4,'I64':8}[v['dtype']]
 assert z-a==math.prod(v['shape'])*size,k
 end=z
assert end+8+n==8044982080
report={'run':'full_concept_recovery2_20261003','scope':'Downloaded adapter tensor integrity and merged-base header compatibility; not full model inference or optimizer resume','base':{'tensor_count':len(tensors),'file_bytes':end+8+n,'contiguous_offsets_valid':True},'stages':{}}
for stage,step in [('midtrain',50),('sft',10)]:
 f=p/stage/'adapter_model.safetensors'; c=p/stage/f'checkpoint-{step}'/'adapter_model.safetensors'
 sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest()
 assert sha(f)==sha(c)
 state=json.loads((c.parent/'trainer_state.json').read_text()); assert state['global_step']==state['max_steps']==step
 entries=[x for x in state['log_history'] if 'loss' in x]
 assert entries[-1]['step']==step
 assert all(math.isfinite(x['loss']) and math.isfinite(x['grad_norm']) and x['grad_norm']>0 for x in entries)
 nonzero_b=0
 with safe_open(f,framework='pt') as st:
  keys=list(st.keys())
  for k in keys:
   t=st.get_tensor(k); assert torch.isfinite(t).all(),k
   if '.lora_A.' in k:
    base=k.removeprefix('base_model.model.').replace('.lora_A.weight','.weight')
    bk=k.replace('.lora_A.','.lora_B.'); bt=st.get_tensor(bk)
    assert tensors[base]['shape']==[bt.shape[0],t.shape[1]],base
    assert t.shape[0]==bt.shape[1]==16
   else:
    assert '.lora_B.' in k,k
    nonzero_b+=bool(torch.count_nonzero(t))
 assert nonzero_b==len(keys)//2
 report['stages'][stage]={'global_step':step,'sha256':sha(f),'final_equals_step_checkpoint':True,'tensor_count':len(keys),'all_tensors_finite':True,'nonzero_lora_B_tensors':nonzero_b,'all_adapter_shapes_match_base':True,'first_logged_loss':entries[0]['loss'],'last_logged_loss':entries[-1]['loss'],'finite_positive_logged_gradients':True}
report['adapter_integrity_passed']=True
(p/'verification_report.json').write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps(report,indent=2))
