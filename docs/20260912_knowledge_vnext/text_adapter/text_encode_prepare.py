"""Prepare ALL current collected text windows with existing frozen MiniLM.

Execute on training host with storage for outputs. No model/corpus download is
performed merely by importing. Required immutable encoder revision and mapping.
"""
import argparse,json,hashlib,os
from pathlib import Path
from collections import Counter
import numpy as np
from text_knowledge_tasks import text_sources,stream_records,windows
MODEL='sentence-transformers/all-MiniLM-L6-v2'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def atomic_json(p,value):
 tmp=p.with_suffix('.tmp');tmp.write_text(json.dumps(value,indent=2)+'\n');os.replace(tmp,p)
def write_chunk(out,number,items,vectors):
 if not len(items) or vectors.ndim!=2 or len(vectors)!=len(items) or not np.isfinite(vectors).all():raise ValueError('Invalid encoded chunk')
 flat=[];offsets=[0]
 for item in items:flat.extend(item['gene_indices']);offsets.append(len(flat))
 p=out/f'chunk_{number:06d}.npz'
 with p.with_suffix('.tmp').open('wb') as f:np.savez_compressed(f,vectors=np.asarray(vectors,np.float32),gene_indices=np.asarray(flat,np.int64),gene_offsets=np.asarray(offsets,np.int64),provenance=np.asarray([json.dumps(x['provenance'],sort_keys=True) for x in items]))
 os.replace(p.with_suffix('.tmp'),p)
 return {'path':p.name,'sha256':sha(p),'rows':len(items),'dimension':vectors.shape[1]}
def main():
 p=argparse.ArgumentParser();p.add_argument('--inventory',required=True);p.add_argument('--gene-map',required=True);p.add_argument('--revision',required=True);p.add_argument('--out',required=True);p.add_argument('--device',default='cpu');p.add_argument('--chunk-windows',type=int,default=256);p.add_argument('--resume',action='store_true');a=p.parse_args()
 if len(a.revision)!=40 or any(c not in '0123456789abcdef' for c in a.revision):raise ValueError('Pin encoder to immutable 40-character HF commit')
 if a.chunk_windows<=0:raise ValueError('Positive chunk size required')
 from sentence_transformers import SentenceTransformer
 import boto3
 encoder=SentenceTransformer(MODEL,revision=a.revision,device=a.device);encoder.eval()
 for param in encoder.parameters():param.requires_grad_(False)
 tok=encoder.tokenizer;limit=encoder.max_seq_length-tok.num_special_tokens_to_add(pair=False)
 if limit<=0:raise ValueError('No model context available')
 sources=text_sources(json.loads(Path(a.inventory).read_text()));mapping=json.loads(Path(a.gene_map).read_text());out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
 identity={'model':MODEL,'revision':a.revision,'inventory_sha256':sha(a.inventory),'mapping_sha256':sha(a.gene_map),'window_tokens':limit,'chunk_windows':a.chunk_windows,'tokenizer_sha256':hashlib.sha256(tok.backend_tokenizer.to_str().encode()).hexdigest()}
 state_path=out/'manifest.json';chunks=[];skip=0;ledger=Counter();source_counts=Counter()
 if state_path.exists():
  if not a.resume:raise ValueError('Output exists; require resume')
  old=json.loads(state_path.read_text())
  if old['identity']!=identity:raise ValueError('Preparation identity changed')
  chunks=old['chunks'];skip=old['eligible_windows_committed']
  for c in chunks:
   if sha(out/c['path'])!=c['sha256']:raise ValueError('Prepared chunk changed')
 client=boto3.client('s3');batch=[];eligible_seen=0
 def commit(complete=False):
  atomic_json(state_path,{'identity':identity,'scope':'CURRENT collected text; frozen mention alignment, not biological labels','sources':sources,'chunks':chunks,'eligible_windows_committed':sum(c['rows'] for c in chunks),'ledger':dict(ledger),'eligible_by_source':dict(source_counts),'complete':complete,'optimizer_exposure':0})
 for item in stream_records(client,'knowledge-datasets-1759951976',sources,ledger):
  for w in windows(item,tok,mapping,limit,ledger):
   if not w['eligible_alignment']:continue
   eligible_seen+=1;source_counts[w['provenance']['source_key']]+=1
   if eligible_seen<=skip:continue
   # Decode/re-encode may change segmentation; fail instead of silently truncate.
   if len(tok.encode(w['text'],add_special_tokens=True))>encoder.max_seq_length:raise ValueError('Decoded window exceeds frozen model context')
   batch.append(w)
   if len(batch)==a.chunk_windows:
    vec=encoder.encode([x['text'] for x in batch],batch_size=min(64,len(batch)),normalize_embeddings=True,show_progress_bar=False);chunks.append(write_chunk(out,len(chunks),batch,vec));batch=[];commit()
 if batch:
  vec=encoder.encode([x['text'] for x in batch],batch_size=min(64,len(batch)),normalize_embeddings=True,show_progress_bar=False);chunks.append(write_chunk(out,len(chunks),batch,vec))
 commit(True)
if __name__=='__main__':main()
