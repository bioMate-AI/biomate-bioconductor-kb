"""Measured central-dogma architecture; adapters own features, order and labels.

Shared pointwise decoders avoid dense gene-by-gene output mixing. H2 uses a
specified measured efficiency scale, not transcript abundance as its label.
"""
import torch
from torch import nn
from central_dogma_losses import task_loss

class CentralDogmaHeads(nn.Module):
 def __init__(self,*,cell_dim,perturbation_dim,machinery_dim,n_transcripts,protein_to_transcript,peptide_dim,hla_dim,feature_dim=16,n_registers=9):
  super().__init__()
  if any(type(x) is not int or x<=0 for x in (cell_dim,perturbation_dim,machinery_dim,n_transcripts,peptide_dim,hla_dim,feature_dim,n_registers)):raise ValueError('Dimensions must be positive integers')
  ix=torch.as_tensor(protein_to_transcript)
  if ix.ndim!=1 or not len(ix) or ix.dtype!=torch.long or (ix<0).any() or (ix>=n_transcripts).any():raise ValueError('protein_to_transcript must be valid int64 indices')
  self.register_buffer('protein_to_transcript',ix.clone())
  self.cell_dim=cell_dim;self.perturbation_dim=perturbation_dim;self.n_transcripts=n_transcripts;self.n_proteins=len(ix);self.peptide_dim=peptide_dim;self.hla_dim=hla_dim
  def net(i,o=1):return nn.Sequential(nn.Linear(i,machinery_dim),nn.SiLU(),nn.Linear(machinery_dim,o))
  self.machinery=net(cell_dim+perturbation_dim,machinery_dim)
  self.transcript_embedding=nn.Embedding(n_transcripts,feature_dim);self.protein_embedding=nn.Embedding(len(ix),feature_dim)
  self.h1=net(machinery_dim+feature_dim);self.h2=net(machinery_dim+feature_dim+1);self.h3=net(machinery_dim+feature_dim+2)
  self.presentation_context=net(machinery_dim+peptide_dim+hla_dim+2,machinery_dim)
  self.h4_delta=nn.Linear(machinery_dim,1);self.h4_abundance=nn.Linear(machinery_dim,2);self.register_head=nn.Linear(machinery_dim,n_registers)
  self.detectability=net(peptide_dim)
 @staticmethod
 def check(x,shape,name):
  if not isinstance(x,torch.Tensor) or x.shape!=shape or not x.is_floating_point() or not torch.isfinite(x).all():raise ValueError(f'{name}: require finite floating tensor {shape}')
 def forward(self,z_cell,perturbation,*,baseline_protein_log_abundance=None,peptide_features=None,hla_features=None,source_protein_index=None):
  if not isinstance(z_cell,torch.Tensor) or z_cell.ndim!=2:raise ValueError('z_cell must be matrix')
  b=len(z_cell);self.check(z_cell,(b,self.cell_dim),'z_cell');self.check(perturbation,(b,self.perturbation_dim),'perturbation')
  if perturbation.device!=z_cell.device:raise ValueError('Input devices must match')
  optional=(baseline_protein_log_abundance,peptide_features,hla_features,source_protein_index)
  h4_available=all(t is not None for t in optional)
  if any(t is not None for t in optional) and not h4_available:raise ValueError('Partial H4 context: supply baseline protein, peptide, HLA and source mapping together')
  if h4_available:
   self.check(baseline_protein_log_abundance,(b,self.n_proteins),'baseline protein')
   if not isinstance(peptide_features,torch.Tensor) or peptide_features.ndim!=3 or peptide_features.shape[1]==0:raise ValueError('Peptide features require nonempty [batch,queries,features]')
   q=peptide_features.shape[1];self.check(peptide_features,(b,q,self.peptide_dim),'peptide');self.check(hla_features,(b,q,self.hla_dim),'HLA')
   ix=source_protein_index
   if not isinstance(ix,torch.Tensor) or ix.dtype!=torch.long or ix.shape!=(b,q) or (ix<0).any() or (ix>=self.n_proteins).any():raise ValueError('Source protein mapping requires valid int64 [batch,queries]')
   if any(t.device!=z_cell.device for t in optional):raise ValueError('Input devices must match')
  m=self.machinery(torch.cat([z_cell,perturbation],-1));tm=m[:,None,:].expand(-1,self.n_transcripts,-1);te=self.transcript_embedding.weight[None].expand(b,-1,-1)
  rna=self.h1(torch.cat([tm,te],-1)).squeeze(-1)
  efficiency=self.h2(torch.cat([tm,te,rna.unsqueeze(-1)],-1)).squeeze(-1)
  pm=m[:,None,:].expand(-1,self.n_proteins,-1);pe=self.protein_embedding.weight[None].expand(b,-1,-1);mapping=self.protein_to_transcript
  protein=self.h3(torch.cat([pm,pe,rna[:,mapping,None],efficiency[:,mapping,None]],-1)).squeeze(-1)
  outputs={'machinery_state':m,'h1_transcription_delta':rna,'h2_translation_efficiency':efficiency,'h3_protein_delta':protein}
  if not h4_available:return outputs
  source_delta=protein.gather(1,ix);source_abundance=baseline_protein_log_abundance.gather(1,ix)+source_delta
  context=self.presentation_context(torch.cat([m[:,None,:].expand(-1,q,-1),peptide_features,hla_features,source_delta.unsqueeze(-1),source_abundance.unsqueeze(-1)],-1));absolute=self.h4_abundance(context)
  return {'machinery_state':m,'h1_transcription_delta':rna,'h2_translation_efficiency':efficiency,'h3_protein_delta':protein,'h4_presentation_delta':self.h4_delta(context).squeeze(-1),'h4_log_abundance':{'mean':absolute[...,0],'log_scale':absolute[...,1].clamp(-8,8)},'ms_detectability':self.detectability(peptide_features).squeeze(-1),'class2_register':self.register_head(context)}

def measured_losses(outputs,labels,weights):
 if not weights:raise ValueError('No measured objectives scheduled')
 terms={}
 for name,weight in weights.items():
  if not isinstance(weight,(int,float)) or not 0<weight<float('inf'):raise ValueError('Weights must be finite positive numbers')
  if name not in labels or name not in outputs:raise ValueError(f'Missing scheduled measured objective: {name}')
  terms[name]=task_loss(name,outputs[name],labels[name])
 return sum(weights[k]*v for k,v in terms.items()),terms
