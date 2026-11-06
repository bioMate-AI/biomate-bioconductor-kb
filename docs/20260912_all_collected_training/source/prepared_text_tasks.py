"""Verified prepared text iterator; explicit cursor for joint checkpoint phase."""
from pathlib import Path
import json,hashlib
import numpy as np
import torch
from text_knowledge_tasks import FrozenTextAlignment

def iter_prepared_text(manifest_path,*,start_chunk=0,start_row=0,batch_rows=64,heldout_article_ids=frozenset(),require_complete=True):
 path=Path(manifest_path);m=json.loads(path.read_text())
 if require_complete and not m['complete']:raise ValueError('Text preparation incomplete')
 if batch_rows<=0:raise ValueError('Positive text batch rows required')
 for ci,c in enumerate(m['chunks']):
  if ci<start_chunk:continue
  p=path.parent/c['path']
  if hashlib.sha256(p.read_bytes()).hexdigest()!=c['sha256']:raise ValueError('Text chunk hash mismatch')
  with np.load(p,allow_pickle=False) as d:
   vectors=d['vectors'];offsets=d['gene_offsets'];indices=d['gene_indices'];provenance=[json.loads(x) for x in d['provenance']]
   if len(vectors)!=c['rows'] or len(offsets)!=len(vectors)+1 or offsets[0]!=0 or offsets[-1]!=len(indices) or (np.diff(offsets)<=0).any():raise ValueError('Ragged text schema invalid')
   begin=start_row if ci==start_chunk else 0
   for lo in range(begin,len(vectors),batch_rows):
    hi=min(lo+batch_rows,len(vectors));use=[i for i in range(lo,hi) if provenance[i]['article_id'] not in heldout_article_ids]
    items=[{'gene_indices':indices[offsets[i]:offsets[i+1]].tolist(),'eligible_alignment':True,'text':'','provenance':provenance[i]} for i in use]
    # Empty heldout-only batches still carry progress; caller checkpoints skip, no optimizer exposure.
    yield items,vectors[use],{'phase':'text','next_chunk':ci,'next_row':hi,'manifest_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

def prepared_text_loss(adapter,items,vectors,*,heldout_article_ids):
 return adapter(items,lambda _:vectors,heldout_article_ids=heldout_article_ids)
