"""Bounded CSR extraction of frozen-gene, guide-disjoint NT controls."""
import hashlib,json,time
from pathlib import Path
import numpy as np,h5py,s3fs
OUT=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/implementation_checked_extract')
SOURCE='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'
def digest(s):return hashlib.sha256(('control-pools-20260912:'+s).encode()).hexdigest()
def validate_source_binding(metadata,source,info,h,selected):
 required={'source_uri','source_etag','source_size'}
 if not required.issubset(metadata.files):raise ValueError('Unbound metadata cache; rerun plan_extract.py')
 if str(metadata['source_uri'].item())!=source or str(metadata['source_etag'].item())!=info.get('ETag') or int(metadata['source_size'].item())!=info['size']:raise ValueError('Source differs from metadata cache')
 if h['X'].attrs['encoding-type']!='csr_matrix':raise ValueError('Expected CSR source')
 if not np.array_equal(h['X/indptr'][:],metadata['indptr']):raise ValueError('Cached CSR offsets differ from source')
 def col(group,key):
  value=group[key]
  if isinstance(value,h5py.Group):
   codes=value['codes'][:]
   if (codes<0).any():raise ValueError('Missing source metadata')
   return value['categories'].asstr()[:][codes]
  return value.asstr()[:] if value.dtype.kind in 'OSU' else value[:]
 if not np.array_equal(col(h['var'],'gene_name'),metadata['source_gene_symbols']):raise ValueError('Cached gene schema differs from source')
 rows=metadata['source_rows'][selected]
 for key in ['_index','donor_id','culture_condition','guide_id','n_cells','total_counts','guide_type','keep_for_DE']:
  if not np.array_equal(col(h['obs'],key)[rows],metadata[key][selected]):raise ValueError('Cached row metadata differs: '+key)

def main():
 m=np.load(OUT/'control_metadata.npz',allow_pickle=False);guides=m['guide_id'].astype(str);unique=sorted(set(guides),key=digest)
 # Interleaved sorted IDs gives equal sized, globally guide-disjoint pilot pools.
 selected=unique[:32];poolmap={g:('feature' if j%2==0 else 'reference') for j,g in enumerate(selected)};ix=np.flatnonzero(np.isin(guides,selected));rows=m['source_rows'][ix];ptr=m['indptr'];nnz=int(sum(ptr[rows+1]-ptr[rows]));assert nnz*16<150*1024**2,(nnz, 'read budget')
 readouts=np.load('/Users/kky/biomate-audit-fix/out/20260911_h1_perturbation_pilot/prepared.npz',allow_pickle=False)['readouts'].astype(str)
 symbols=m['source_gene_symbols'].astype(str);lookup={g:i for i,g in enumerate(symbols) if np.count_nonzero(symbols==g)==1};assert all(g in lookup for g in readouts),'ambiguous/missing gene'
 cols=np.array([lookup[g] for g in readouts]);mapping=np.full(len(symbols),-1);mapping[cols]=np.arange(len(cols));counts=np.zeros((len(rows),len(cols)),dtype=np.int64);library=np.zeros(len(rows),dtype=np.int64)
 fs=s3fs.S3FileSystem(anon=False,default_block_size=65536);info=fs.info(SOURCE)
 print(json.dumps({'profiles':len(rows),'guides':len(selected),'row_bytes':nnz*16}),flush=True)
 with fs.open(SOURCE,'rb',cache_type='readahead',block_size=65536) as f,h5py.File(f,'r') as h:
  validate_source_binding(m,SOURCE,info,h,ix)
  for j,r in enumerate(rows):
   a,b=map(int,ptr[r:r+2]);ind=h['X/indices'][a:b];v=h['X/data'][a:b]
   assert np.isfinite(v).all() and (v>=0).all() and (v==np.floor(v)).all(),'invalid raw count'
   assert len(np.unique(ind))==len(ind),'duplicate sparse indices';assert ((ind>=0)&(ind<len(symbols))).all()
   library[j]=v.sum();sel=mapping[ind]>=0;counts[j,mapping[ind[sel]]]=v[sel].astype(np.int64)
   if j%50==0:print('read',j,'/',len(rows),flush=True)
 after=fs.info(SOURCE,refresh=True)
 if (after.get('ETag'),after['size'])!=(info.get('ETag'),info['size']):raise ValueError('Source changed during count extraction')
 meta={k:m[k][ix] for k in ['_index','donor_id','culture_condition','guide_id','n_cells','total_counts']};assert (meta['n_cells']>0).all();assert np.allclose(library,meta['total_counts'],rtol=0,atol=0),'library metadata mismatch'
 pools=np.array([poolmap[g] for g in guides[ix]]);aggregate=[];agg_counts=[];agg_lib=[];agg_cells=[]
 for donor in sorted(set(meta['donor_id'])):
  for condition in sorted(set(meta['culture_condition'])):
   for pool in ['feature','reference']:
    mask=(meta['donor_id']==donor)&(meta['culture_condition']==condition)&(pools==pool);assert mask.any()
    aggregate.append({'donor':str(donor),'condition':str(condition),'pool':pool,'profiles':int(mask.sum()),'guides':len(set(meta['guide_id'][mask])),'n_cells':int(meta['n_cells'][mask].sum()),'library_counts':int(library[mask].sum())});agg_counts.append(counts[mask].sum(0));agg_lib.append(library[mask].sum());agg_cells.append(meta['n_cells'][mask].sum())
 np.savez_compressed(OUT/'controls.npz',counts=counts,library_counts=library,pool=pools,source_rows=rows,gene_symbols=readouts,**meta)
 np.savez_compressed(OUT/'baseline_aggregates.npz',counts=np.array(agg_counts),library_counts=np.array(agg_lib),n_cells=np.array(agg_cells),gene_symbols=readouts,donor=np.array([a['donor'] for a in aggregate]),condition=np.array([a['condition'] for a in aggregate]),pool=np.array([a['pool'] for a in aggregate]))
 report={'source':'s3://'+SOURCE,'source_size':info['size'],'source_etag':info.get('ETag'),'metadata_source_binding_verified':True,'matrix_encoding':'csr_matrix','matrix_shape':[278684,18129],'selection':'eligible non-targeting keep_for_DE rows; first32 SHA256-sorted guide IDs, alternating feature/reference pools; all eligible runs retained','pool_salt':'control-pools-20260912:','selected_guides':selected,'eligible_profiles':len(guides),'extracted_profiles':len(rows),'selected_row_uncompressed_bytes':nnz*16,'genes':len(readouts),'raw_integer_nonnegative_finite':True,'full_library_matches_obs_total_counts':True,'aggregates':aggregate,'limitations':['Pilot32-guide subset, not all eligible controls.','Guide-disjoint controls are not independent biological donors.','No perturbed response or donor-specific label extracted.'],'artifact_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [OUT/'controls.npz',OUT/'baseline_aggregates.npz']}}
 (OUT/'provenance.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
if __name__=='__main__':main()
