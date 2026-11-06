"""Bridge verified sparse RNA shards to joint-model windows without gene/cell caps."""
import argparse,hashlib,json,shutil,tempfile
from pathlib import Path
import numpy as np,scipy.sparse as sp
from ingest_rna_queue import write,sha
from preflight_all_source_headers import fingerprint

def bridge(native,frozen,out,max_tokens=128,cell_chunk=4):
 out=Path(out)
 if out.exists():raise ValueError('Existing output')
 if max_tokens<1 or cell_chunk<1:raise ValueError('Positive chunk dimensions required')
 vocab=frozen['vocab']
 if len(vocab)!=len(set(vocab)):raise ValueError('Duplicate root vocabulary')
 if frozen.get('vocab_sha256') and frozen['vocab_sha256']!=fingerprint(vocab):raise ValueError('Root vocabulary hash mismatch')
 lookup={v:i for i,v in enumerate(vocab)};streams=[];ledger=[];out.parent.mkdir(parents=True,exist_ok=True);stage=Path(tempfile.mkdtemp(prefix=out.name+'.partial-',dir=out.parent));study_splits={}
 try:
  for si,s in enumerate(native['shards']):
   if s['split'] not in ('train','validation','test'):raise ValueError('Unknown split')
   if s['study_id'] in study_splits and study_splits[s['study_id']]!=s['split']:raise ValueError('Study across splits')
   study_splits[s['study_id']]=s['split'];expected=s.get('sha256')
   if not expected or sha(s['path'])!=expected:raise ValueError('Native shard hash mismatch or missing')
   if s.get('metadata_path') and (not s.get('metadata_sha256') or sha(s['metadata_path'])!=s['metadata_sha256']):raise ValueError('Native metadata hash mismatch')
   genes=s['gene_ids']
   if len(set(genes))!=len(genes):raise ValueError('Duplicate native feature IDs')
   try:ids=np.array([lookup['RNA:'+g] for g in genes],np.int64)
   except KeyError as e:raise ValueError('Native gene absent from frozen vocabulary') from e
   x=sp.load_npz(s['path']).tocsr()
   if x.shape[1]!=len(genes) or x.shape[0]!=s['rows']:raise ValueError('Native shard axes mismatch')
   if not np.isfinite(x.data).all() or (x.data<0).any() or not np.equal(x.data,np.floor(x.data)).all():raise ValueError('Native counts invalid')
   written=0
   for start in range(0,x.shape[0],cell_chunk):
    stop=min(start+cell_chunk,x.shape[0]);n=stop-start
    for offset in range(0,len(genes),max_tokens):
     end=min(offset+max_tokens,len(genes));width=end-offset;vals=np.zeros((n,max_tokens),np.float32);vals[:,:width]=np.log1p(x[start:stop,offset:end].toarray());token_ids=np.zeros((n,max_tokens),np.int64);token_ids[:,:width]=ids[offset:end];valid=np.zeros((n,max_tokens),bool);valid[:,:width]=True
     name=f'rna_s{si:06d}_r{start:07d}_f{offset:07d}.npz';np.savez_compressed(stage/name,ids=token_ids,values=vals,valid=valid,modality=np.zeros_like(token_ids),source_shard_rows=np.arange(start,stop))
     streams.append({'path':str((out/name).resolve()),'sha256':sha(stage/name),'source_id':s['source_uri'],'study_id':s['study_id'],'split':s['split'],'native_shard_sha256':expected,'rows':n,'tokens':width});written+=n*width
   ledger.append({'source_shard':s['path'],'expected_tokens':x.shape[0]*x.shape[1],'written_tokens':written,'feature_cap':None,'cell_cap':None})
  result={'schema_version':1,'vocab':vocab,'vocab_sha256':fingerprint(vocab),'streams':streams,'batches':streams,'source_native_manifest_sha256':fingerprint(native),'root_header_manifest_sha256':frozen.get('header_manifest_sha256'),'coverage':ledger,'modality_schema':{'0':{'name':'RNA','transform':'log1p native counts'}},'training_ready':bool(streams),'all_collected_omics_included':False,'limitations':['Sparse shard is materialized per shard; dense memory only cell_chunk×max_tokens.','Every measured source gene is valid including zeros; unmeasured union genes are absent, not valid-zero padded.','No source or gene cap. Gene windows restrict attention scope.']}
  write(stage/'manifest.json',result);stage.rename(out);return result
 except BaseException:shutil.rmtree(stage,ignore_errors=True);raise

def main():
 p=argparse.ArgumentParser();p.add_argument('--native-manifest',required=True);p.add_argument('--root-vocab',required=True);p.add_argument('--out',required=True);p.add_argument('--max-tokens',type=int,default=128);p.add_argument('--cell-chunk',type=int,default=4);a=p.parse_args()
 m=bridge(json.loads(Path(a.native_manifest).read_text()),json.loads(Path(a.root_vocab).read_text()),a.out,a.max_tokens,a.cell_chunk);print(json.dumps({'streams':len(m['streams'])}))
if __name__=='__main__':main()
