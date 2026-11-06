"""Uncapped same-row paired RNA/protein or RNA/ATAC token windows."""
import argparse,hashlib,json,shutil,tempfile
from pathlib import Path
import h5py,numpy as np,scipy.sparse as sp
from anndata.io import sparse_dataset,read_elem
from ingest_rna_queue import sha,write,vector

def matrix(h,path):return sparse_dataset(h[path]) if isinstance(h[path],h5py.Group) else h[path]
def names(values):
 a=[str(x).strip() for x in values]
 if not a or any(not x for x in a) or len(set(a))!=len(a):raise ValueError('Missing/duplicate feature IDs')
 return a
def describe(config):
 for field in ['path','source_id','study_id','split','count_provenance','pairing_provenance','donor_id']:
  if not config.get(field):raise ValueError('Missing reviewed source provenance: '+field)
 if config['split'] not in ('train','validation','test'):raise ValueError('Unknown split')
 with h5py.File(config['path']) as h:
  obs=read_elem(h['obs']);var=read_elem(h['var']);rna=names(vector(var,config.get('gene_column','__index__')))
  if not obs.index.is_unique:raise ValueError('Duplicate paired cell IDs')
  if 'study' in obs and set(obs['study'].astype(str))!={config['study_id']}:raise ValueError('Study metadata conflicts with config')
  if 'feature_is_filtered' in var and var['feature_is_filtered'].any():raise ValueError('Filtered feature masks required')
  kind=config['modality'];m=1 if kind=='protein' else 2 if kind=='ATAC' else None
  if m is None:raise ValueError('Only paired protein or ATAC supported')
  key='protein_names' if m==1 else 'atac_peak_names';other=names(read_elem(h['uns'][key]))
  if m==2:
   if read_elem(h['uns']['atac_repr'])!='peak_counts':raise ValueError('ATAC representation must be peak_counts')
   genome=str(read_elem(h['uns']['genome_build']));other=[genome+':'+x for x in other]
  rn=matrix(h,config.get('rna_path','layers/counts'));om=matrix(h,'obsm/'+('protein_expression' if m==1 else 'atac_peaks'))
  if rn.shape!=(len(obs),len(rna)) or om.shape!=(len(obs),len(other)):raise ValueError('RNA/other row/feature alignment mismatch')
  tokens=['RNA:'+x for x in rna]+[kind+':'+x for x in other]
  return {'tokens':tokens,'n_rna':len(rna),'n_other':len(other),'n_cells':len(obs),'modality':m,'source_sha256':sha(config['path'])}
def native(block):
 a=block.toarray() if sp.issparse(block) else np.asarray(block)
 if not np.isfinite(a).all() or (a<0).any() or not np.equal(a,np.floor(a)).all() or (a>2**53).any():raise ValueError('Invalid native count values')
 return a.astype(np.float64)

def tokenize(configs,out,max_tokens=1024,cell_chunk=16):
 out=Path(out)
 if out.exists():raise ValueError('Refusing existing output')
 if max_tokens<2 or cell_chunk<1:raise ValueError('Positive cell chunk and >=2 tokens required')
 descriptions=[describe(c) for c in configs];vocab=sorted({t for d in descriptions for t in d['tokens']});lookup={t:i for i,t in enumerate(vocab)}
 # Never allow one reviewed study to appear in multiple splits.
 study_splits={}
 for c in configs:
  if c['study_id'] in study_splits and study_splits[c['study_id']]!=c['split']:raise ValueError('Study appears across splits')
  study_splits[c['study_id']]=c['split']
 out.parent.mkdir(parents=True,exist_ok=True);stage=Path(tempfile.mkdtemp(prefix=out.name+'.partial-',dir=out.parent));streams=[];ledger=[]
 try:
  for si,(config,d) in enumerate(zip(configs,descriptions)):
   with h5py.File(config['path']) as h:
    rn=matrix(h,config.get('rna_path','layers/counts'));om=matrix(h,'obsm/'+('protein_expression' if d['modality']==1 else 'atac_peaks'));obs=read_elem(h['obs'])
    # Round-robin preserves all features; short protein panels are not duplicated to fill windows.
    a=list(range(d['n_rna']));b=list(range(d['n_rna'],len(d['tokens'])));order=[]
    for k in range(max(len(a),len(b))):
     if k<len(a):order.append(a[k])
     if k<len(b):order.append(b[k])
    batches=0;observed_tokens=0
    for start in range(0,d['n_cells'],cell_chunk):
     stop=min(start+cell_chunk,d['n_cells']);r=native(rn[start:stop]);o=native(om[start:stop]);values=np.concatenate([np.log1p(r),np.log1p(o) if d['modality']==1 else (o>0).astype(float)],axis=1)
     for wi,offset in enumerate(range(0,len(order),max_tokens)):
      ix=np.array(order[offset:offset+max_tokens]);n=stop-start;width=len(ix)
      ids=np.zeros((n,max_tokens),np.int64);vals=np.zeros((n,max_tokens),np.float32);valid=np.zeros((n,max_tokens),bool);mod=np.zeros((n,max_tokens),np.int64)
      ids[:,:width]=np.array([lookup[d['tokens'][i]] for i in ix]);vals[:,:width]=values[:,ix];valid[:,:width]=True;mod[:,:width]=np.where(ix<d['n_rna'],0,d['modality'])
      name=f's{si:03d}_r{start:09d}_w{wi:05d}.npz';np.savez_compressed(stage/name,ids=ids,values=vals,valid=valid,modality=mod,source_rows=np.arange(start,stop),cell_ids=np.asarray(obs.index[start:stop],dtype=str))
      streams.append({'path':str((out/name).resolve()),'sha256':sha(stage/name),'source_id':config['source_id'],'study_id':config['study_id'],'donor_id':config['donor_id'],'split':config['split'],'rows':n,'tokens':width});batches+=1;observed_tokens+=n*width
   if sha(config['path'])!=d['source_sha256']:raise ValueError('Source changed during tokenization')
   ledger.append({**config,**d,'tokens':None,'written_windows':batches,'observed_token_entries':observed_tokens,'expected_token_entries':d['n_cells']*(d['n_rna']+d['n_other']),'cell_cap':None,'feature_cap':None,'status':'all_stored_source_cells_features_tokenized'})
  manifest={'schema_version':1,'vocab':vocab,'streams':streams,'batches':streams,'sources':ledger,'training_ready':True,'all_collected_omics_included':False,'modality_schema':{'0':{'name':'RNA','transform':'log1p native counts'},'1':{'name':'protein','transform':'log1p native antibody counts'},'2':{'name':'ATAC','transform':'binary native peak accessibility; genome-qualified intervals'}},'limitations':['Whole-source tokenization is not complete original-study acquisition.','Feature windows restrict cross-feature attention; every measured zero remains valid.','Same-cell pairing only within each source; no triple-paired cells asserted.','No automatic gene symbol/Ensembl or antibody alias reconciliation; vocabulary identity remains explicit.']}
  write(stage/'manifest.json',manifest);stage.rename(out);return manifest
 except BaseException:shutil.rmtree(stage,ignore_errors=True);raise

def main():
 p=argparse.ArgumentParser();p.add_argument('--configs',required=True);p.add_argument('--out',required=True);p.add_argument('--max-tokens',type=int,default=1024);p.add_argument('--cell-chunk',type=int,default=16);a=p.parse_args();m=tokenize(json.loads(Path(a.configs).read_text()),a.out,a.max_tokens,a.cell_chunk);print(json.dumps({'streams':len(m['streams']),'sources':len(m['sources']),'vocab':len(m['vocab'])}))
if __name__=='__main__':main()
