"""Metadata-only parallel HDF5 source preflight; every candidate receives a ledger row."""
import argparse,concurrent.futures,hashlib,json,re
from pathlib import Path
import h5py,numpy as np,pandas as pd
from anndata.io import read_elem
from ingest_rna_queue import write,split,vector

def fingerprint(x):return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def narrow_frame(node,columns,load_index=False):
    """Read only selected HDF5 columns, never the entire obs/var dataframe."""
    index_key=node.attrs.get('_index','_index')
    if isinstance(index_key,bytes):index_key=index_key.decode()
    if index_key not in node:raise ValueError('Missing dataframe index metadata')
    index_node=node[index_key]
    if isinstance(index_node,h5py.Dataset):n=index_node.shape[0]
    elif 'values' in index_node:n=index_node['values'].shape[0]
    elif 'codes' in index_node:n=index_node['codes'].shape[0]
    else:raise ValueError('Unsupported dataframe index encoding')
    index=read_elem(index_node) if load_index else pd.RangeIndex(n)
    values={key:read_elem(node[key]) for key in set(columns) if key!='__index__' and key in node}
    for key,value in values.items():
        if len(value)!=n:raise ValueError('Metadata column length mismatch: '+key)
    return pd.DataFrame(values,index=index)

def inspect_handle(h,record,policy):
 obs=narrow_frame(h['obs'],['is_primary_data',policy.get('donor_column','donor_id')]);uns=h.get('uns');version=str(read_elem(uns['schema_version'])) if uns is not None and 'schema_version' in uns else None
 citation=str(read_elem(uns['citation'])) if uns is not None and 'citation' in uns else ''
 match=re.search(r'Publication:\s*(https://doi.org/[^\s]+)',citation);collection=re.search(r'https://cellxgene.cziscience.com/collections/([\w-]+)',citation)
 study=match.group(1).rstrip('.') if match else ('cellxgene-collection:'+collection.group(1) if collection else None)
 review=policy.get('schema_policies',{}).get(version);errors=[]
 if not review or not review.get('provenance_reference'):errors.append('schema count provenance policy unavailable')
 layer=review.get('count_layer') if review else None;var_key='raw/var' if layer=='raw.X' else 'var'
 if layer not in ('raw.X','X'):errors.append('policy requires explicit raw.X or X')
 key='raw/X' if layer=='raw.X' else 'X'
 if key not in h:errors.append('reviewed count representation missing')
 if var_key not in h:var_key='var';errors.append('reviewed feature axis missing')
 gene_column=policy.get('gene_column','__index__')
 var=narrow_frame(h[var_key],[gene_column,'feature_is_filtered'],load_index=gene_column=='__index__');genes=vector(var,gene_column).tolist()
 if len(set(genes))!=len(genes):errors.append('duplicate feature identifiers')
 if not study:errors.append('canonical study unresolved; dataset ID not substituted')
 primary=None
 if 'is_primary_data' in obs and obs['is_primary_data'].dtype.kind=='b' and not obs['is_primary_data'].isna().any():primary=int(obs['is_primary_data'].sum())
 else:errors.append('primary-data status unavailable')
 try:
  donor=vector(obs,policy.get('donor_column','donor_id'))
  if any(v.lower() in ('unknown','na','nan','none') for v in donor):errors.append('unresolved donor identifiers')
  donor_count=len(set(donor))
 except (ValueError,KeyError):donor_count=None;errors.append('donor metadata unavailable')
 for frame in [var]+([narrow_frame(h['var'],['feature_is_filtered'])] if var_key=='raw/var' else []):
  if 'feature_is_filtered' in frame:
   f=frame['feature_is_filtered']
   if f.dtype.kind!='b' or f.isna().any() or (f.any() and not (layer=='raw.X' and review and review.get('feature_filter_semantics')=='normalized_X_only')):errors.append('filtered feature observation-mask semantics unresolved')
 status='blocked' if errors else ('excluded_nonprimary' if primary==0 else 'header_eligible_counts_unvalidated')
 return {'source_uri':record['uri'],'source_object':{k:record.get(k) for k in ['bytes','etag','last_modified','object_identity']},'schema_version':version,'citation':citation,'study_id':study,'split':split(study) if study else None,'source_cells':len(obs),'primary_cells':primary,'donors':donor_count,'feature_ids':genes,'n_features':len(genes),'gene_metadata_path':var_key,'count_layer':layer,'feature_filter_semantics':review.get('feature_filter_semantics') if review else None,'count_provenance':review.get('provenance_reference') if review else None,'status':status,'errors':sorted(set(errors)),'count_values_validated':False,'biological_deduplication_complete':False}

def execute(manifest,policy,out,workers=4,local_paths=None,paired_schema=None):
 if workers<1:raise ValueError('Positive workers required')
 out=Path(out);out.mkdir(parents=True,exist_ok=True)
 if (out/'header_manifest.json').exists():raise ValueError('Frozen header manifest exists')
 candidates=[r for r in manifest['objects'] if r['role']=='rna' and r['status']=='candidate' and r['key'].endswith(('.h5ad','.h5ad.gz'))]
 def one(r):
  try:
   if local_paths and r['uri'] in local_paths:
    with h5py.File(local_paths[r['uri']]) as h:return inspect_handle(h,r,policy)
   if r['key'].endswith('.gz'):raise ValueError('gzip HDF5 requires staging; cannot remote-range raw compressed stream')
   import boto3,s3fs
   bucket,key=r['uri'][5:].split('/',1);client=boto3.client('s3');head=client.head_object(Bucket=bucket,Key=key)
   if head['ETag']!=r['etag'] or head['ContentLength']!=r['bytes']:raise ValueError('Source metadata changed from frozen inventory')
   fs=s3fs.S3FileSystem()
   with fs.open(bucket+'/'+key,'rb',block_size=262144) as f,h5py.File(f) as h:result=inspect_handle(h,r,policy)
   after=client.head_object(Bucket=bucket,Key=key)
   if after['ETag']!=head['ETag'] or after['ContentLength']!=head['ContentLength']:raise ValueError('Source changed during metadata preflight')
   return result
  except Exception as e:return {'source_uri':r['uri'],'status':'blocked','errors':[type(e).__name__+': '+str(e)],'feature_ids':[],'count_values_validated':False}
 rows=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool,open(out/'source_headers.jsonl','w') as progress:
  for row in pool.map(one,candidates):
   rows.append(row);progress.write(json.dumps(row,sort_keys=True)+'\n');progress.flush()
   print(json.dumps({'processed_sources':len(rows),'candidate_sources':len(candidates),'source_uri':row['source_uri'],'status':row['status']}),flush=True)
 # Union includes observed feature axes even if a source is blocked; metadata is not a learned statistic.
 vocab=sorted({'RNA:'+g for row in rows for g in row['feature_ids']}|set((paired_schema or {}).get('vocab',[])))
 result={'schema_version':1,'source_manifest_sha256':manifest.get('manifest_sha256',fingerprint(manifest)),'policy_sha256':fingerprint(policy),'candidate_sources':len(candidates),'reported_sources':len(rows),'sources':rows,'vocab':vocab,'vocab_sha256':fingerprint(vocab),'training_ready':False,'limitations':['Metadata eligibility is not count validation or scientific eligibility.','All sources are reported, including gzip/unknown-schema/provenance failures.','Feature identifiers are namespaced literally; symbol/Ensembl reconciliation remains explicit.','Gene-vocabulary presence does not authorize training on blocked or nonprimary cells.']}
 result['header_manifest_sha256']=fingerprint(result);write(out/'header_manifest.json',result)
 configs={r['source_uri']:{'count_layer':r['count_layer'],'feature_filter_semantics':r['feature_filter_semantics'],'count_provenance':r['count_provenance'],'study_id':r['study_id'],'gene_column':policy.get('gene_column','__index__'),'donor_column':policy.get('donor_column','donor_id')} for r in rows if r['status']=='header_eligible_counts_unvalidated'}
 write(out/'reviewed_source_configs.json',configs);print(json.dumps({'reported_sources':len(rows),'header_eligible':len(configs),'vocab':len(vocab)}));return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--policy',required=True);p.add_argument('--out',required=True);p.add_argument('--workers',type=int,default=4);p.add_argument('--local-paths');p.add_argument('--paired-manifest');a=p.parse_args()
 load=lambda x:json.loads(Path(x).read_text()) if x else None
 execute(load(a.manifest),load(a.policy),a.out,a.workers,load(a.local_paths),load(a.paired_manifest))
if __name__=='__main__':main()
