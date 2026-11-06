"""Uncapped source queue; conservative provenance/primary gates and persistent dedup."""
import argparse,gzip,hashlib,json,re,shutil,sqlite3,tempfile
from pathlib import Path
import h5py,numpy as np,scipy.sparse as sp
from anndata.io import read_elem,sparse_dataset

def sha(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(8*1024*1024),b''):h.update(b)
 return h.hexdigest()
def write(p,x):
 q=p.with_suffix(p.suffix+'.tmp');q.write_text(json.dumps(x,sort_keys=True,indent=2,allow_nan=False)+'\n');q.replace(p)
def split(study):
 n=int(hashlib.sha256(('immune-fullscale-study-v1:'+study).encode()).hexdigest()[:8],16)%100
 return 'test' if n<10 else ('validation' if n<20 else 'train')
def vector(frame,key):
 a=frame.index if key=='__index__' else frame[key] if key in frame else None
 if a is None or a.isna().any():raise ValueError('Missing identity metadata: '+key)
 a=np.array([str(v).strip() for v in a],dtype=str)
 if (a=='').any():raise ValueError('Empty identity metadata: '+key)
 return a

def schema(h,config):
 obs=read_elem(h['obs']);uns=h.get('uns');citation=read_elem(uns['citation']) if uns is not None and 'citation' in uns else ''
 study=config.get('study_id')
 if not study:
  publication=re.search(r'Publication:\s*(https://doi.org/[^\s]+)',citation)
  collection=re.search(r'https://cellxgene.cziscience.com/collections/([A-Za-z0-9-]+)',citation)
  if publication:study=publication.group(1).rstrip('.')
  elif collection:study='cellxgene-collection:'+collection.group(1)
  else:raise ValueError('Unresolved study provenance; dataset ID cannot substitute')
 layer=config.get('count_layer');provenance=config.get('count_provenance')
 if not layer or not provenance:raise ValueError('Explicit count_layer and count_provenance required; never infer counts from integers')
 key='raw/X' if layer=='raw.X' else ('X' if layer=='X' else 'layers/'+layer)
 if key not in h:raise ValueError('Declared count layer absent')
 var=read_elem(h['raw/var' if layer=='raw.X' else 'var']);genes=vector(var,config.get('gene_column','__index__'))
 if len(set(genes))!=len(genes):raise ValueError('Duplicate gene IDs')
 for vv in [var]+([read_elem(h['var'])] if layer=='raw.X' else []):
  if 'feature_is_filtered' in vv:
   f=vv['feature_is_filtered']
   if f.dtype.kind!='b' or f.isna().any() or (f.any() and not (layer=='raw.X' and config.get('feature_filter_semantics')=='normalized_X_only')):raise ValueError('Filtered feature observation semantics unresolved')
 if 'is_primary_data' not in obs or obs['is_primary_data'].dtype.kind!='b' or obs['is_primary_data'].isna().any():raise ValueError('Primary-data status unknown')
 donors=vector(obs,config.get('donor_column','donor_id'));cells=vector(obs,config.get('cell_column','__index__'))
 if any(v.lower() in ('unknown','na','nan','none') for v in donors):raise ValueError('Donor identities unresolved')
 join=None
 if config.get('joinid_namespace'):
  join=vector(obs,config.get('joinid_column','observation_joinid'))
 matrix=sparse_dataset(h[key]) if isinstance(h[key],h5py.Group) else h[key]
 if matrix.shape!=(len(obs),len(genes)):raise ValueError('Count axes mismatch')
 return obs,genes,donors,cells,join,matrix,study,citation

def ingest_local(path,record,config,out,db,chunk_rows=4096):
 ident=hashlib.sha256(record['uri'].encode()).hexdigest()[:20];dest=out/'shards'/ident
 if dest.exists():raise ValueError('Existing source shards require ledger reconciliation')
 staging=Path(tempfile.mkdtemp(prefix=ident+'.partial-',dir=out));items=[];before=sha(path)
 try:
  db.execute('BEGIN IMMEDIATE')
  with h5py.File(path) as h:
   obs,genes,donors,cells,join,matrix,study,citation=schema(h,config)
   counts={'source_cells':len(obs),'nonprimary_excluded':int((~obs['is_primary_data']).sum()),'duplicate_excluded':0,'written_cells':0,'zero_library_excluded':0}
   for start in range(0,len(obs),chunk_rows):
    stop=min(start+chunk_rows,len(obs));selected=[]
    for i in range(start,stop):
     if not obs['is_primary_data'].iloc[i]:continue
     identities=['barcode:'+json.dumps([study,cells[i]],separators=(',',':'))]
     if join is not None:identities.append('joinid:'+json.dumps([config['joinid_namespace'],join[i]],separators=(',',':')))
     if any(db.execute('SELECT 1 FROM identities WHERE id=?',(v,)).fetchone() for v in identities):counts['duplicate_excluded']+=1;continue
     # Validation exceptions roll back all identity reservations from this source.
     for v in identities:db.execute('INSERT INTO identities VALUES (?,?)',(v,record['uri']))
     selected.append(i)
    if not selected:continue
    block=matrix[np.array(selected),:];values=block.data if sp.issparse(block) else np.asarray(block)
    if not np.isfinite(values).all() or (values<0).any() or not np.equal(values,np.floor(values)).all() or (values>2**53).any():raise ValueError('Invalid declared native counts')
    block=sp.csr_matrix(block,dtype=np.float64);block.sum_duplicates();block.eliminate_zeros();library=np.asarray(block.sum(1)).ravel()
    if not np.isfinite(library).all():raise ValueError('Nonfinite library counts')
    keep=library>0;counts['zero_library_excluded']+=int((~keep).sum());block=block[keep];selected=np.asarray(selected)[keep];library=library[keep]
    if not len(selected):continue
    name=f'counts_{len(items):06d}.npz';sp.save_npz(staging/name,block)
    meta=f'obs_{len(items):06d}.json';write(staging/meta,{'source_rows':selected.tolist(),'donor':donors[selected].tolist(),'cell_id':cells[selected].tolist(),'library_counts':library.tolist()})
    items.append({'path':str((dest/name).resolve()),'sha256':sha(staging/name),'metadata_path':str((dest/meta).resolve()),'metadata_sha256':sha(staging/meta),'study_id':study,'split':split(study),'gene_ids':genes.tolist(),'rows':len(selected),'source_uri':record['uri'],'source_sha256':before})
    counts['written_cells']+=len(selected)
  if sha(path)!=before:raise ValueError('Local source changed during ingestion')
  dest.parent.mkdir(parents=True,exist_ok=True);staging.rename(dest)
  result={'status':'ingested' if items else 'excluded_no_eligible_cells','source_uri':record['uri'],'local_source_sha256':before,'coverage':counts,'study_id':study,'split':split(study),'citation':citation,'count_provenance':config['count_provenance'],'shards':items}
  write(dest/'source_result.json',result);db.commit();return result
 except BaseException:
  db.rollback();shutil.rmtree(staging,ignore_errors=True)
  if dest.exists():shutil.rmtree(dest)
  raise

def run(manifest,configs,out,local_paths=None,chunk_rows=4096):
 if chunk_rows<1:raise ValueError('Positive chunk size required')
 out=Path(out);out.mkdir(parents=True,exist_ok=True)
 # Resume is intentionally fail-closed until source/shard/SQLite transaction reconciliation exists.
 if (out/'coverage_ledger.json').exists() or (out/'identities.sqlite').exists():raise ValueError('Existing run: use a fresh output directory; resume reconciliation required')
 db=sqlite3.connect(out/'identities.sqlite');db.execute('CREATE TABLE identities (id TEXT PRIMARY KEY, source TEXT NOT NULL)');db.commit()
 candidates=[r for r in manifest['objects'] if r['role']=='rna' and r['status']=='candidate' and r['key'].endswith(('.h5ad','.h5ad.gz'))]
 candidate_uris={r['uri'] for r in candidates}
 write(out/'unsupported_objects.json',[{'uri':r['uri'],'role':r['role'],'status':r['status']} for r in manifest['objects'] if r['uri'] not in candidate_uris])
 rows=[];shards=[]
 try:
  for record in candidates:
   uri=record['uri'];config=configs.get(uri,configs.get('default',{}));stage=None
   try:
    if not config.get('count_layer') or not config.get('count_provenance'):raise ValueError('Missing reviewed count-layer provenance configuration')
    if local_paths and uri in local_paths:path=Path(local_paths[uri])
    else:
     import boto3
     stage=Path(tempfile.mkdtemp(prefix='raw-',dir=out));path=stage/'source.h5ad';compressed=uri.endswith('.gz');download=stage/'source.h5ad.gz' if compressed else path
     bucket,key=uri[5:].split('/',1);s3=boto3.client('s3');head=s3.head_object(Bucket=bucket,Key=key)
     if head['ETag']!=record['etag'] or head['ContentLength']!=record['bytes']:raise ValueError('S3 source identity changed')
     if shutil.disk_usage(out).free<record['bytes']*3:raise ValueError('Insufficient bounded staging disk; retry on larger source worker')
     # Range-read HDF5 metadata before moving full uncompressed objects.
     # gzip streams require full staging; their unsupported metadata preflight is explicit.
     if not compressed:
      import s3fs
      fs=s3fs.S3FileSystem()
      with fs.open(bucket+'/'+key,'rb',block_size=262144) as remote,h5py.File(remote,'r') as rh:
       robs,_,_,_,_,_,_,_=schema(rh,config)
       if not robs['is_primary_data'].any():raise ValueError('Remote preflight: all '+str(len(robs))+' observations are nonprimary; full download skipped')
     s3.download_file(bucket,key,str(download),ExtraArgs={'VersionId':head['VersionId']} if head.get('VersionId') else {})
     after=s3.head_object(Bucket=bucket,Key=key)
     if after['ETag']!=head['ETag'] or after['ContentLength']!=head['ContentLength']:raise ValueError('S3 source changed while downloading')
     if compressed:
      with gzip.open(download,'rb') as f,open(path,'wb') as g:shutil.copyfileobj(f,g,8*1024*1024)
    result=ingest_local(path,record,config,out,db,chunk_rows);rows.append(result);shards.extend(result['shards'])
   except Exception as e:rows.append({'source_uri':uri,'status':'blocked_error','error_type':type(e).__name__,'error':str(e)})
   finally:
    if stage is not None:shutil.rmtree(stage,ignore_errors=True)
   write(out/'coverage_ledger.json',{'candidate_sources':len(candidates),'processed_sources':len(rows),'sources':rows,'unsupported_objects_file':'unsupported_objects.json'})
  vocab=sorted({g for s in shards for g in s['gene_ids']});training={'schema_version':1,'vocab':vocab,'shards':shards,'training_ready':bool(shards),'coverage_complete':len(rows)==len(candidates),'blocked_sources':sum(r['status']=='blocked_error' for r in rows),'all_data_trained':False,'deduplication':'SQLite exact study/barcode plus explicitly namespaced joinid; semantic cross-study duplicates unresolved'}
  write(out/'training_manifest.json',training);return training,rows
 finally:db.close()

def main():
 p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--configs',required=True);p.add_argument('--out',required=True);p.add_argument('--local-paths');p.add_argument('--chunk-rows',type=int,default=4096);a=p.parse_args()
 m,r=run(json.loads(Path(a.manifest).read_text()),json.loads(Path(a.configs).read_text()),a.out,json.loads(Path(a.local_paths).read_text()) if a.local_paths else None,a.chunk_rows);print(json.dumps({'shards':len(m['shards']),'blocked_sources':m['blocked_sources'],'training_ready':m['training_ready']}))
if __name__=='__main__':main()
