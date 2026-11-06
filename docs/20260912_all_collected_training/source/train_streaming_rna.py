"""S1 streaming native-count RNA pretraining; no H1 perturbation labels.

Manifest: {vocab:[canonical IDs], shards:[{path,study_id,split,gene_ids:[IDs]}]}.
NPZ shards use scipy CSR schema data/indices/indptr/shape. Shards may have
library_counts but objective uses log1p full-library CP10k derived from all genes.
Only one sparse shard is loaded at a time; rows become bounded token minibatches.
"""
import argparse
import json
import random
from pathlib import Path
import numpy as np
import scipy.sparse as sp
import torch
from torch import nn
from resumable_checkpoint import save_checkpoint,load_checkpoint,manifest_hash

def read_manifest(path):
 m=json.loads(Path(path).read_text());v=m['vocab']
 if m.get('training_ready') is not True:raise ValueError('Manifest requires verified training_ready=true from ingestion audit')
 if not v or any(not isinstance(g,str) or not g for g in v) or len(v)!=len(set(v)):raise ValueError('Vocabulary must contain unique nonempty canonical identifiers')
 lookup={g:i for i,g in enumerate(v)};studies={}
 if not m['shards']:raise ValueError('No shards')
 for s in m['shards']:
  if s['split'] not in ('train','validation','test') or not s['study_id']:raise ValueError('Explicit split and canonical study required')
  if s['study_id'] in studies and studies[s['study_id']]!=s['split']:raise ValueError('Study leakage across splits')
  studies[s['study_id']]=s['split']
  if len(s['gene_ids'])!=len(set(s['gene_ids'])) or any(g not in lookup for g in s['gene_ids']):raise ValueError('Shard gene mapping must be unique and covered by vocabulary')
  if not Path(s['path']).is_absolute():s['path']=str((Path(path).parent/s['path']).resolve())
 if not any(s['split']=='train' for s in m['shards']):raise ValueError('No training shards')
 return m

def batches(manifest,split,batch_size,max_tokens,epoch,seed):
 lookup={g:i for i,g in enumerate(manifest['vocab'])};padding=len(lookup)
 shards=[s for s in manifest['shards'] if s['split']==split]
 order=np.random.default_rng(seed+epoch).permutation(len(shards)) if split=='train' else range(len(shards))
 ids=[];values=[];valid=[];total_rows=0
 for si in order:
  s=shards[int(si)]
  with np.load(s['path'],allow_pickle=False) as z:
   shape=tuple(z['shape']);x=sp.csr_matrix((z['data'],z['indices'],z['indptr']),shape=shape)
   if x.shape[1]!=len(s['gene_ids']) or not x.has_canonical_format or not np.isfinite(x.data).all() or (x.data<0).any() or not np.equal(x.data,np.floor(x.data)).all():raise ValueError('Require canonical CSR native nonnegative integer counts')
   libraries=np.asarray(x.sum(1)).ravel().astype(np.float64)
   if 'library_counts' in z and not np.array_equal(z['library_counts'],libraries):raise ValueError('Library totals mismatch full shard count schema')
  mapping=np.array([lookup[g] for g in s['gene_ids']],dtype=np.int64)
  rows=np.random.default_rng(seed+epoch*1000003+int(si)).permutation(x.shape[0]) if split=='train' else range(x.shape[0])
  for row in rows:
   a,b=x.indptr[row:row+2];count=x.data[a:b].astype(np.float64);columns=x.indices[a:b];positive=count>0;count=count[positive];columns=columns[positive]
   if not len(count):continue
   # Stable descending abundance / canonical-ID tie break, bounded top-gene tokens.
   rank=np.lexsort((mapping[columns],-count))[:max_tokens];g=mapping[columns[rank]];y=np.log1p(count[rank]/libraries[row]*1e4).astype(np.float32)
   ii=np.full(max_tokens,padding,np.int64);vv=np.zeros(max_tokens,np.float32);mm=np.zeros(max_tokens,bool);ii[:len(g)]=g;vv[:len(g)]=y;mm[:len(g)]=True
   ids.append(ii);values.append(vv);valid.append(mm);total_rows+=1
   if len(ids)==batch_size:
    yield torch.from_numpy(np.stack(ids)),torch.from_numpy(np.stack(values)),torch.from_numpy(np.stack(valid));ids=[];values=[];valid=[]
 if ids:yield torch.from_numpy(np.stack(ids)),torch.from_numpy(np.stack(values)),torch.from_numpy(np.stack(valid))

class RNAEncoder(nn.Module):
 def __init__(self,vocab,dim=128,layers=4,heads=4):
  super().__init__();self.genes=nn.Embedding(vocab+1,dim,padding_idx=vocab);self.value=nn.Linear(1,dim);self.mask=nn.Parameter(torch.zeros(dim))
  layer=nn.TransformerEncoderLayer(dim,heads,dim*4,dropout=.1,batch_first=True,norm_first=True)
  self.encoder=nn.TransformerEncoder(layer,layers,enable_nested_tensor=False);self.readout=nn.Linear(dim,1)
 def forward(self,ids,values,valid,masked):
  if valid.dtype!=torch.bool or masked.dtype!=torch.bool or values.shape!=ids.shape or valid.shape!=ids.shape or masked.shape!=ids.shape or (masked&~valid).any():raise ValueError('Aligned token/observation/masking tensors required')
  clean=torch.where(masked,torch.zeros_like(values),values)
  h=self.genes(ids)+self.value(clean.unsqueeze(-1))+masked.unsqueeze(-1)*self.mask
  h=self.encoder(h,src_key_padding_mask=~valid)
  return self.readout(h).squeeze(-1), (h*valid.unsqueeze(-1)).sum(1)/valid.sum(1,keepdim=True)

def masked_loss(model,batch,mask_fraction=.15):
 ids,values,valid=batch;mask=(torch.rand_like(values)<mask_fraction)&valid
 # Every nonempty row contributes at least one target, including low-depth cells.
 empty=~mask.any(1);first=valid.long().argmax(1);mask[torch.arange(len(mask),device=mask.device)[empty],first[empty]]=True
 pred,_=model(ids,values,valid,mask);loss=(pred[mask]-values[mask]).square().mean()
 if not torch.isfinite(loss):raise ValueError('Nonfinite masked expression loss')
 return loss,int(mask.sum())

def main():
 p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--out',required=True);p.add_argument('--epochs',type=int,default=6);p.add_argument('--batch',type=int,default=32);p.add_argument('--max-tokens',type=int,default=512);p.add_argument('--dim',type=int,default=128);p.add_argument('--layers',type=int,default=4);p.add_argument('--heads',type=int,default=4);p.add_argument('--lr',type=float,default=3e-4);p.add_argument('--seed',type=int,default=0);p.add_argument('--device',default='cpu');p.add_argument('--checkpoint-every',type=int,default=100);p.add_argument('--resume',action='store_true');p.add_argument('--max-steps',type=int,default=None,help='Explicit integration-test cap only, never full-run default');a=p.parse_args()
 if min(a.epochs,a.batch,a.max_tokens,a.dim,a.layers,a.heads,a.checkpoint_every)<=0 or a.dim%a.heads:raise ValueError('Invalid training dimensions')
 random.seed(a.seed);np.random.seed(a.seed);torch.manual_seed(a.seed);torch.use_deterministic_algorithms(True)
 m=read_manifest(a.manifest);out=Path(a.out);out.mkdir(parents=True,exist_ok=True);cfg={k:v for k,v in vars(a).items() if k not in ('resume','out','manifest','max_steps')}
 identity={'source_manifest_hash':manifest_hash(m),'schema_hash':manifest_hash({'vocab':m['vocab'],'target':'log1p-full-library-CP10k','token_policy':'top-positive-count-then-canonical-id'}),'config_hash':manifest_hash(cfg)}
 model=RNAEncoder(len(m['vocab']),a.dim,a.layers,a.heads).to(a.device);opt=torch.optim.AdamW(model.parameters(),lr=a.lr);start_epoch=0;start_batch=0;steps=0
 if a.resume:
  state=load_checkpoint(out/'checkpoint.pt',model=model,optimizer=opt,identity=identity);start_epoch=state['epoch'];start_batch=state['next_batch'];steps=state['sampler_state']['steps']
 def checkpoint(epoch,next_batch):save_checkpoint(out/'checkpoint.pt',model=model,optimizer=opt,identity=identity,epoch=epoch,next_batch=next_batch,sampler_state={'steps':steps,'ordering':'seed+epoch indexed shard/row permutation'})
 protocol={'stage':'S1 RNA masked-expression self-supervision; not H1-H4 supervision','identity':identity,'config':cfg,'train_shards':sum(s['split']=='train' for s in m['shards']),'source_cap':None,'max_steps':a.max_steps,'parameters':sum(p.numel() for p in model.parameters())};(out/'protocol.json').write_text(json.dumps(protocol,indent=2))
 stopped=False
 with (out/'training.jsonl').open('a') as log:
  for epoch in range(start_epoch,a.epochs):
   for bi,batch in enumerate(batches(m,'train',a.batch,a.max_tokens,epoch,a.seed)):
    if epoch==start_epoch and bi<start_batch:continue
    model.train();batch=tuple(x.to(a.device) for x in batch);opt.zero_grad();loss,n=masked_loss(model,batch);loss.backward();nn.utils.clip_grad_norm_(model.parameters(),1.);opt.step();steps+=1
    record={'epoch':epoch,'batch':bi,'step':steps,'cells':len(batch[0]),'masked_tokens':n,'loss':float(loss.detach())};log.write(json.dumps(record)+'\n');log.flush()
    if steps%a.checkpoint_every==0:checkpoint(epoch,bi+1)
    if a.max_steps is not None and steps>=a.max_steps:checkpoint(epoch,bi+1);stopped=True;break
   if stopped:break
   checkpoint(epoch+1,0)
 (out/'status.json').write_text(json.dumps({'status':'integration_cap_reached' if stopped else 'completed','steps':steps,'stage':'S1 only'},indent=2))
if __name__=='__main__':main()
