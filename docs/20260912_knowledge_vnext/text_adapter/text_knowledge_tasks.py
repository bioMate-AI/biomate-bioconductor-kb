"""Uncapped collected literature stream and optional frozen-text alignment.

No corpus/shard/gene/character cap. Token windows bound model context only.
Exact symbol mentions are weak alignment, not factual gene-effect labels.
"""
import gzip,json,hashlib,re
from collections import Counter
import torch
from torch import nn

def text_sources(inventory):
 return sorted([x for v in inventory.values() for x in v.get('items',[]) if '/tracks/text_knowledge/fulltext/shard_' in x['key'] and x['key'].endswith('.jsonl.gz')],key=lambda x:x['key'])

def stream_records(client,bucket,sources,ledger):
 for source in sources:
  response=client.get_object(Bucket=bucket,Key=source['key'])
  if response['ETag']!=source['etag'] or response['ContentLength']!=source['bytes']:raise ValueError('Source identity changed')
  ledger['shards_started']+=1
  try:
   with gzip.GzipFile(fileobj=response['Body']) as fh:
    for number,line in enumerate(fh):
     try:record=json.loads(line)
     except Exception:ledger['malformed_records']+=1;raise ValueError(f'Malformed record {source["key"]}:{number}')
     if not isinstance(record,dict):raise ValueError('Literature row is not an object')
     ledger['records_read']+=1
     yield {'record':record,'source_key':source['key'],'source_etag':source['etag'],'row':number,'raw_sha256':hashlib.sha256(line).hexdigest()}
   ledger['shards_complete']+=1
  finally:response['Body'].close()

def windows(item,tokenizer,gene_to_index,max_tokens,ledger,heldout_article_ids=frozenset()):
 if max_tokens<=0:raise ValueError('Invalid window length')
 r=item['record'];article=str(r.get('pmcid') or r.get('pmid') or item['raw_sha256'])
 if article in heldout_article_ids:ledger['heldout_articles']+=1;return
 # All text fields retained, notably BODY omitted by the legacy L2 routine.
 text='\n'.join(str(r.get(k) or '') for k in ['title','abstract','body'])
 if not text.strip():ledger['empty_text_records']+=1;return
 tokens=tokenizer.encode(text,add_special_tokens=False)
 for start in range(0,len(tokens),max_tokens):
  ids=tokens[start:start+max_tokens];chunk=tokenizer.decode(ids,skip_special_tokens=False)
  hits=sorted(set(re.findall(r'(?<![A-Za-z0-9])[A-Za-z0-9][A-Za-z0-9-]*(?![A-Za-z0-9])',chunk))&set(gene_to_index))
  ledger['windows_seen']+=1;ledger['tokens_seen']+=len(ids)
  provenance={k:v for k,v in item.items() if k!='record'}
  provenance.update({'article_id':article,'license_href':r.get('license_href'),'record_metadata':{k:v for k,v in r.items() if k not in ['title','abstract','body']},'token_start':start,'token_count':len(ids)})
  if not hits:ledger['windows_without_mapped_gene']+=1
  yield {'text':chunk,'gene_indices':[gene_to_index[g] for g in hits],'gene_symbols':hits,'provenance':provenance,'eligible_alignment':bool(hits)}

class FrozenTextAlignment(nn.Module):
 def __init__(self,gene_embedding,text_dimension):
  super().__init__();self.gene_embedding=gene_embedding;self.project=nn.Linear(gene_embedding.embedding_dim,text_dimension);self.exposure=Counter()
 def forward(self,batch,frozen_encode,*,heldout_article_ids):
  for b in batch:
   if b['provenance']['article_id'] in heldout_article_ids:raise ValueError('Held-out article entered alignment')
  use=[b for b in batch if b['eligible_alignment']]
  if not use:raise ValueError('No mapped gene alignment; record unused windows in ledger')
  with torch.no_grad():vectors=torch.as_tensor(frozen_encode([b['text'] for b in use]),device=self.gene_embedding.weight.device,dtype=self.gene_embedding.weight.dtype).detach()
  if vectors.shape!=(len(use),self.project.out_features) or not torch.isfinite(vectors).all() or (vectors.norm(dim=1)==0).any():raise ValueError('Invalid frozen text vectors')
  pred=torch.stack([self.gene_embedding(torch.tensor(b['gene_indices'],device=vectors.device)).mean(0) for b in use]);loss=(1-nn.functional.cosine_similarity(self.project(pred),vectors)).mean()
  counts=Counter(b['provenance']['source_key'] for b in use)
  return loss,{'windows_supervised':len(use),'tokens_supervised':sum(b['provenance']['token_count'] for b in use),'by_source':dict(counts),'weak_mention_alignment':True}
 def record_optimizer_step(self,counters):
  self.exposure.update(counters['by_source']);return dict(self.exposure)
