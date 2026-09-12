"""Shared modality-token encoder, structural knowledge and canonical-head adapter.

Modality values must be transformed on a documented source-native scale before
this interface. Missing features are valid=False, never measurement targets.
This is a model/loss component; corpus completion is tracked by source ledger.
"""
import torch
from torch import nn
from train_streaming_rna import RNAEncoder
from central_dogma_heads import CentralDogmaHeads,measured_losses

class SharedMultimodalEncoder(RNAEncoder):
 def __init__(self,vocab,dim=128,layers=4,heads=4,n_modalities=3):
  super().__init__(vocab,dim,layers,heads);self.modality=nn.Embedding(n_modalities,dim);self.modality_readout=nn.ModuleList([nn.Linear(dim,1) for _ in range(n_modalities)])
  del self.readout
 def forward(self,ids,values,valid,masked,modality):
  if ids.dtype!=torch.long or modality.dtype!=torch.long or valid.dtype!=torch.bool or masked.dtype!=torch.bool:raise ValueError('Token IDs/modality int64 and masks Boolean required')
  if any(x.shape!=ids.shape for x in (values,valid,masked,modality)) or (masked&~valid).any() or not valid.any(1).all():raise ValueError('Aligned masks and nonempty cell rows required')
  if not torch.isfinite(values[valid]).all() or (modality[valid]<0).any() or (modality[valid]>=len(self.modality_readout)).any():raise ValueError('Invalid observed value/modality')
  # Sanitize absent values and identifiers before any embedding/linear operation.
  ids=torch.where(valid,ids,torch.full_like(ids,self.genes.padding_idx));modality=torch.where(valid,modality,torch.zeros_like(modality))
  clean=torch.where(valid&~masked,values,torch.zeros_like(values))
  h=self.genes(ids)+self.modality(modality)+self.value(clean.unsqueeze(-1))+masked.unsqueeze(-1)*self.mask
  h=self.encoder(h,src_key_padding_mask=~valid)
  all_pred=torch.cat([head(h) for head in self.modality_readout],-1);prediction=all_pred.gather(-1,modality.unsqueeze(-1)).squeeze(-1)
  z=(h*valid.unsqueeze(-1)).sum(1)/valid.sum(1,keepdim=True)
  return prediction,z

def reconstruction(model,batch,mask_fraction=.15):
 ids,values,valid,modality=(batch[k] for k in ('ids','values','valid','modality'))
 masked=(torch.rand_like(values)<mask_fraction)&valid
 # Require at least one observed target of every present assay, avoiding RNA dominance.
 for row in range(len(valid)):
  for assay in modality[row][valid[row]].unique():
   eligible=valid[row]&(modality[row]==assay)
   if not (masked[row]&eligible).any():masked[row,eligible.nonzero()[0,0]]=True
 prediction,z=model(ids,values,valid,masked,modality);terms={}
 for assay in modality[masked].unique():
  ix=masked&(modality==assay);
  if int(assay)==2:
   if ((values[ix]<0)|(values[ix]>1)).any():raise ValueError('ATAC binary targets require [0,1]')
   terms[int(assay)]=nn.functional.binary_cross_entropy_with_logits(prediction[ix],values[ix])
  else:terms[int(assay)]=(prediction[ix]-values[ix]).square().mean()
 if not terms:raise ValueError('No observed reconstruction targets')
 loss=torch.stack(list(terms.values())).mean()
 if not torch.isfinite(loss):raise ValueError('Nonfinite reconstruction')
 return loss,z,terms

def knowledge_regularizer(model,edges):
 """Typed external adapter supplies signed graph/pathway edges in frozen vocab.

 Cosine alignment for positive edges; cosine anti-alignment for negative edges.
 This is a structural prior, not experimentally observed regulatory causality.
 """
 if edges.ndim!=2 or edges.shape[1]!=3 or not len(edges) or not torch.isfinite(edges).all():raise ValueError('Nonempty finite [source,target,signedweight] edges required')
 indices=edges[:,:2]
 if not torch.equal(indices,indices.round()) or (indices<0).any() or (indices>=model.genes.padding_idx).any() or (edges[:,2]==0).any():raise ValueError('Invalid knowledge edge mapping/weight')
 source=model.genes(indices[:,0].long());target=model.genes(indices[:,1].long());similarity=nn.functional.cosine_similarity(source,target,dim=-1)
 weight=edges[:,2].abs();return ((similarity-edges[:,2].sign()).square()*weight).sum()/weight.sum()

class CanonicalAdapter(nn.Module):
 """Shared z_cell conditions measured heads; scheduling labels is explicit."""
 def __init__(self,encoder,head_config):
  super().__init__();self.encoder=encoder;self.heads=CentralDogmaHeads(**head_config)
 def measured_batch(self,batch,perturbation,labels,weights,**context):
  # In supervised tasks expose all observed inputs; avoid task-label leakage in adapter.
  _,z=self.encoder(batch['ids'],batch['values'],batch['valid'],torch.zeros_like(batch['valid']),batch['modality'])
  outputs=self.heads(z,perturbation,**context)
  loss,terms=measured_losses(outputs,labels,weights)
  return loss,terms,outputs
