"""Uncapped CZI native-pseudobulk→measured H1 adapter; remote range-readable.

No efficacy/outcome filter, fake stimulation, clinical label or inferred TCR.
Each target/donor/condition contrast uses disjoint non-targeting guide pools:
feature pool for input, reference pool for effect. Full-library normalization.
"""
import argparse,hashlib,json
from pathlib import Path
from contextlib import contextmanager
import numpy as np
import h5py

SOURCE='s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'

def column(group,name):
 x=group[name]
 if isinstance(x,h5py.Group):
  codes=x['codes'][:]
  if (codes<0).any():raise ValueError(f'Missing categorical field {name}')
  categories=x['categories'];values=categories.asstr()[:] if categories.dtype.kind in 'OSU' else categories[:]
  return values[codes]
 return x.asstr()[:] if x.dtype.kind in 'OSU' else x[:]

@contextmanager
def open_source(path):
 if path.startswith('s3://'):
  import s3fs
  fs=s3fs.S3FileSystem(anon=False,default_block_size=262144);key=path[5:];before=fs.info(key)
  if not before.get('ETag'):raise ValueError('S3 object ETag required')
  with fs.open(key,'rb',block_size=262144,cache_type='blockcache') as stream,h5py.File(stream,'r') as h:yield h,{'uri':path,'etag':before['ETag'],'size':before['size']}
  after=fs.info(key,refresh=True)
  if (after.get('ETag'),after['size'])!=(before['ETag'],before['size']):raise ValueError('Source changed during extraction')
 else:
  stat=Path(path).stat()
  with h5py.File(path,'r') as h:yield h,{'uri':str(Path(path).resolve()),'size':stat.st_size,'mtime_ns':stat.st_mtime_ns}
  after=Path(path).stat()
  if (after.st_size,after.st_mtime_ns)!=(stat.st_size,stat.st_mtime_ns):raise ValueError('Local source changed')

def metadata(h):
 if h['X'].attrs['encoding-type']!='csr_matrix':raise ValueError('Native CSR counts required')
 o={k:column(h['obs'],k) for k in ['donor_id','culture_condition','guide_type','guide_id','perturbed_gene_name','keep_min_cells','keep_total_counts','n_cells','total_counts']}
 for name in ['keep_min_cells','keep_total_counts']:
  if np.asarray(o[name]).dtype!=bool:raise ValueError('QC flags must be Boolean')
 genes=column(h['var'],'_index').astype(str);symbols=column(h['var'],'gene_name').astype(str)
 if len(set(genes))!=len(genes):raise ValueError('Canonical source gene IDs must be unique')
 ptr=h['X/indptr'][:];shape=tuple(h['X'].attrs['shape'])
 if shape!=(len(o['donor_id']),len(genes)) or len(ptr)!=shape[0]+1 or (np.diff(ptr)<0).any():raise ValueError('CSR metadata mismatch')
 return o,genes,symbols,ptr

def sum_rows(h,rows,ptr,n_genes,totals):
 counts=np.zeros(n_genes,np.float64);library=0.
 for row in rows:
  a,b=map(int,ptr[row:row+2]);v=h['X/data'][a:b].astype(np.float64);ix=h['X/indices'][a:b]
  if not np.isfinite(v).all() or (v<0).any() or not np.equal(v,np.floor(v)).all() or (ix<0).any() or (ix>=n_genes).any():raise ValueError('Invalid native counts')
  if v.sum()!=totals[row]:raise ValueError('Native full-library total disagrees with source observation')
  np.add.at(counts,ix,v);library+=v.sum()
 if library<=0:raise ValueError('Empty pooled library')
 return np.log1p(counts/library*1e4),library

def prepare(source,out,donor_splits,*,metadata_only=False):
 out=Path(out);out.mkdir(parents=True,exist_ok=True)
 unsupported=[];records=[]
 with open_source(source) as (h,identity):
  o,genes,symbols,ptr=metadata(h);donors=sorted(set(o['donor_id']));conditions=sorted(set(o['culture_condition']))
  if set(donor_splits)!=set(donors) or not set(donor_splits.values())<= {'train','validation','test'} or 'train' not in donor_splits.values() or not ({'validation','test'}&set(donor_splits.values())):raise ValueError('Explicit isolated donor splits covering every source donor required')
  qc=o['keep_min_cells']&o['keep_total_counts']&(o['n_cells']>0)&(o['total_counts']>0)
  nt=qc&(o['guide_type']=='non-targeting');target=qc&(o['guide_type']=='targeting');guides=sorted(set(o['guide_id'][nt]),key=lambda g:hashlib.sha256(str(g).encode()).hexdigest())
  if len(guides)<2:raise ValueError('Need two disjoint non-targeting guide pools')
  pools={g:('feature' if i%2==0 else 'reference') for i,g in enumerate(guides)}
  if set(o['guide_id'][nt])&set(o['guide_id'][target]):raise ValueError('Control/target guide identities overlap')
  names=sorted(set(o['perturbed_gene_name'][target]));categories=names+['condition:'+c for c in conditions];vocab=['RNA:'+g for g in genes]
  plan={'source':identity,'scope':'all basic-QC targets, all source readout genes; no efficacy filter','rows':len(ptr)-1,'genes':len(genes),'targets':len(names),'donors':donor_splits,'conditions':conditions,'eligible_profiles':int(target.sum()),'eligible_controls':int(nt.sum()),'control_pools':pools,'normalization':'aggregate native counts then full-library log1pCP10k','conditioning':'matched donor and recorded culture condition, explicit target+condition one-hot','no_scaler_or_label_prior_fit':True}
  (out/'plan.json').write_text(json.dumps(plan,indent=2))
  if metadata_only:return plan
  controls={}
  for donor in donors:
   for condition in conditions:
    for pool in ('feature','reference'):
     rows=np.flatnonzero(nt&(o['donor_id']==donor)&(o['culture_condition']==condition)&np.array([pools.get(g)==pool for g in o['guide_id']]))
     if len(rows):controls[donor,condition,pool]=sum_rows(h,rows,ptr,len(genes),o['total_counts'])[0]
  groups={}
  for row in np.flatnonzero(target):groups.setdefault((str(o['donor_id'][row]),str(o['culture_condition'][row]),str(o['perturbed_gene_name'][row])),[]).append(int(row))
  for number,((donor,condition,name),rows) in enumerate(sorted(groups.items())):
   if any((donor,condition,pool) not in controls for pool in ('feature','reference')):
    unsupported.append({'donor':donor,'condition':condition,'target':name,'reason':'missing disjoint donor-condition control pool','profiles':len(rows)});continue
   if not (symbols==name).any():unsupported.append({'donor':donor,'condition':condition,'target':name,'reason':'direct-target gene cannot be mapped for exclusion'});continue
   measured,_=sum_rows(h,rows,ptr,len(genes),o['total_counts']);delta=measured-controls[donor,condition,'reference'];observed=(symbols!=name)
   u=np.zeros((1,len(categories)),np.float32);u[0,names.index(name)]=1;u[0,len(names)+conditions.index(condition)]=1
   path=out/f'contrast_{number:07d}.npz';np.savez_compressed(path,ids=np.arange(len(genes),dtype=np.int64)[None],values=controls[donor,condition,'feature'][None].astype(np.float32),valid=np.ones((1,len(genes)),bool),modality=np.zeros((1,len(genes)),np.int64),perturbation=u,h1_delta=delta[None].astype(np.float32),h1_observed=observed[None])
   records.append({'path':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source_id':'czi_h1','study_id':'CZI_GWCD4i','donor_id':donor,'split':donor_splits[donor],'split_unit':'donor','token_window':512,'window_label_objectives':['h1_transcription_delta'],'source_rows':rows,'target':name,'condition':condition,'guides':sorted(set(map(str,o['guide_id'][rows]))),'objectives':{'h1_transcription_delta':1.},'labels':{'h1_transcription_delta':{'value':'h1_delta','observed':'h1_observed'}}})
  manifest={'vocab':vocab,'measured_sources':records,'source_ledger':[{'source_id':'czi_h1','status':'integrated' if not unsupported else 'partially_supported'}],'perturbation_schema':categories,'readout_features':genes.tolist(),'donor_splits':donor_splits,'head_dimensions':{'n_transcripts':len(genes),'perturbation_dim':len(categories)},'unsupported':unsupported,'source':identity,'split_policy':'within-study donor-held-out, not cross-study validation','metadata':plan}
 # Publish final manifest only after source identity postcheck succeeds.
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2));return manifest

def main():
 p=argparse.ArgumentParser();p.add_argument('--source',default=SOURCE);p.add_argument('--out',required=True);p.add_argument('--donor-splits',required=True);p.add_argument('--metadata-only',action='store_true');a=p.parse_args();prepare(a.source,a.out,json.loads(Path(a.donor_splits).read_text()),metadata_only=a.metadata_only)
if __name__=='__main__':main()
