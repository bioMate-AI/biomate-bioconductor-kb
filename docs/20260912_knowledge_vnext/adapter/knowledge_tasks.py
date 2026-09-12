"""Current collected-knowledge objectives; positive facts only, explicit split groups."""
from pathlib import Path
import hashlib,re
import numpy as np
import pandas as pd
import torch
from torch import nn

def load_knowledge(prepared, mapkg=None):
 p=Path(prepared);rows=[]
 def add(source,task,left_type,left,right_type,right,relation,value=None,observed=True,confidence=1.,provenance=None):
  # Reciprocal edges share split identity; source-independent identity limits cross-source leakage.
  ends=sorted([f'{left_type}:{left}',f'{right_type}:{right}'])
  group=hashlib.sha256('|'.join(ends).encode()).hexdigest()
  rows.append((source,task,left_type,str(left),right_type,str(right),relation,value,observed,confidence,group,provenance))
 for name in ['reactome','kegg','go_bp']:
  d=pd.read_parquet(p/(name+'_memberships.parquet'))
  for r in d.itertuples():add(name,'membership','gene/protein',r.gene,'pathway',name+':'+r.pathway,'member_of')
 d=pd.read_parquet(p/'collectri_signed.parquet')
 for r in d.itertuples():
  add('collectri','relation','gene/protein',r.source,'gene/protein',r.target,'regulates')
  add('collectri','sign','gene/protein',r.source,'gene/protein',r.target,'regulates',float(r.weight),str(r.sign_decision)=='PMID',provenance=str(r.sign_decision)+' | '+str(r.resources)+' | '+str(r.references))
 d=pd.read_parquet(p/'genetics_disease_specific.parquet')
 for r in d.itertuples():add('genetics','prior','gene/protein',r.gene,'disease',r.mondo,'genetic_prior',float(r.prior))
 d=pd.read_parquet(p/'primekg_typed.parquet')
 for r in d.itertuples():add('primekg','relation',r.x_type,r.x_name,r.y_type,r.y_name,r.relation)
 if mapkg:
  d=pd.read_parquet(mapkg).drop_duplicates()
  for r in d.itertuples():
   confidence=float(re.search(r'\((?:with confidence: )?([0-9.eE+-]+)\)',r.relation).group(1))
   rel=re.sub(r'\(with confidence: [^)]+\)|\([0-9.eE+-]+\)','(confidence)',r.relation)
   add('mapkg','relation','gene/protein',r.i_symbol,'gene/protein',r.j_symbol,rel,confidence=confidence)
 out=pd.DataFrame(rows,columns=['source','task','left_type','left','right_type','right','relation','value','value_observed','confidence','split_group','provenance'])
 # Stable IDs refer to normalized facts; original raw payloads remain independently versioned.
 out['record_id']=[hashlib.sha256(str(tuple(r)).encode()).hexdigest() for r in out.itertuples(index=False,name=None)]
 return out

class KnowledgeTasks(nn.Module):
 """Uses caller-owned gene embeddings; auxiliary nodes and readout heads are trainable.

 Relation CE distinguishes observed relation labels, never asserts random nonedges false.
 Positive-only membership alignment can collapse in isolation; use alongside biological
 objectives and report ablations, not link-prediction accuracy from training loss.
 """
 def __init__(self, facts, gene_embedding, gene_names=None, gene_to_index=None):
  super().__init__();self.gene_embedding=gene_embedding
  if gene_to_index is None:
   assert len(gene_names)==gene_embedding.num_embeddings and len(set(gene_names))==len(gene_names)
   gene_to_index={str(g):i for i,g in enumerate(gene_names)}
  self.gene_index=dict(gene_to_index)
  assert all(isinstance(i,int) and 0<=i<gene_embedding.num_embeddings for i in self.gene_index.values())
  entities=set(zip(facts.left_type,facts.left))|set(zip(facts.right_type,facts.right))
  self.other_index={key:i for i,key in enumerate(sorted(k for k in entities if not(k[0]=='gene/protein' and k[1] in self.gene_index)))}
  dim=gene_embedding.embedding_dim;self.other=nn.Embedding(max(1,len(self.other_index)),dim)
  self.relations={r:i for i,r in enumerate(sorted(facts.relation.unique()))}
  self.relation_head=nn.Linear(2*dim,len(self.relations));self.prior_head=nn.Linear(2*dim,1);self.sign_head=nn.Linear(2*dim,1)
  self.membership_projection=nn.Linear(dim,dim,bias=False);self.exposure={}
 def embed(self, types, names):
  device=self.gene_embedding.weight.device;vectors=[];shared=0
  for t,n in zip(types,names):
   if t=='gene/protein' and n in self.gene_index:
    vectors.append(self.gene_embedding(torch.tensor(self.gene_index[n],device=device)));shared+=1
   else:vectors.append(self.other(torch.tensor(self.other_index[t,n],device=device)))
  return torch.stack(vectors),shared
 def forward(self,batch,*,heldout_groups,record_exposure=False):
  if not len(batch):raise ValueError('Empty knowledge batch')
  if set(batch.split_group)&set(heldout_groups):raise ValueError('Held-out fact group in training batch')
  if not np.isfinite(batch.confidence).all() or ((batch.confidence<0)|(batch.confidence>1)).any():raise ValueError('Invalid confidence')
  a,n1=self.embed(batch.left_type,batch.left);b,n2=self.embed(batch.right_type,batch.right);x=torch.cat([a,b],1);losses={};supervised={};used=np.zeros(len(batch),dtype=bool)
  for task in ['relation','membership','prior','sign']:
   mask=batch.task.eq(task).to_numpy(copy=True)
   if task in ['prior','sign']:mask &= batch.value_observed.to_numpy(dtype=bool)
   if not mask.any():continue
   ix=torch.as_tensor(np.flatnonzero(mask),device=x.device);weights=torch.tensor(batch.confidence.to_numpy()[mask],device=x.device,dtype=x.dtype)
   if task=='relation':
    target=torch.tensor([self.relations[r] for r in batch.relation[mask]],device=x.device)
    value=nn.functional.cross_entropy(self.relation_head(x[ix]),target,reduction='none')
   elif task=='membership':value=(self.membership_projection(a[ix])-b[ix]).square().mean(1)
   else:
    target=torch.tensor(batch.value.to_numpy()[mask].astype(float),device=x.device,dtype=x.dtype)
    if not torch.isfinite(target).all():raise ValueError('Nonfinite observed target')
    if task=='sign':
     if not ((target==-1)|(target==1)).all():raise ValueError('Invalid sign')
     value=nn.functional.binary_cross_entropy_with_logits(self.sign_head(x[ix]).squeeze(1),(target+1)/2,reduction='none')
    else:value=(self.prior_head(x[ix]).squeeze(1)-target).square()
   if weights.sum()>0:
    losses[task]=(value*weights).sum()/weights.sum();supervised[task]=int((mask & (batch.confidence.to_numpy()>0)).sum());used |= mask & (batch.confidence.to_numpy()>0)
  if not losses:raise ValueError('No observed positive-weight supervision')
  counters={'rows_presented':len(batch),'shared_gene_endpoint_uses':n1+n2,'tasks_supervised':supervised,'by_source':{str(s):int(n) for s,n in batch.source[used].value_counts().items()},'by_source_presented':{str(s):int(n) for s,n in batch.source.value_counts().items()},'inferred_sign_rows_skipped':int((batch.task.eq('sign')&~batch.value_observed).sum())}
  # Caller records only after optimizer.step succeeds; forward does not imply optimization.
  if record_exposure:raise ValueError('Use record_optimizer_step after successful optimizer.step')
  return sum(losses.values()),{k:float(v.detach()) for k,v in losses.items()},counters
 def record_optimizer_step(self,counters):
  for source,n in counters['by_source'].items():self.exposure[source]=self.exposure.get(source,0)+n
  return dict(self.exposure)
