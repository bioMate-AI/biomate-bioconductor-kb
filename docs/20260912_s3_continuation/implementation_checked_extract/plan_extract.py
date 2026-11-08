import s3fs,h5py,numpy as np,json
from pathlib import Path
fs=s3fs.S3FileSystem(anon=False,default_block_size=262144);p='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'
def col(g,k):
 v=g[k]
 if isinstance(v,h5py.Group):
  ca=v['categories'].asstr()[:];co=v['codes'][:];assert(co>=0).all();return ca[co].astype(str)
 return v.asstr()[:].astype(str) if v.dtype.kind in 'OSU' else v[:]
source_info=fs.info(p)
if not source_info.get('ETag'):raise ValueError('Source ETag unavailable')
with fs.open(p,'rb') as f,h5py.File(f,'r') as h:
 o={k:col(h['obs'],k) for k in ['_index','donor_id','culture_condition','guide_type','guide_id','keep_for_DE','n_cells','total_counts']};idx=np.flatnonzero((o['guide_type']=='non-targeting')&o['keep_for_DE']);ptr=h['X/indptr'][:];chunks=np.unique(np.concatenate([np.arange(ptr[r]//42464,(ptr[r+1]-1)//42464+1) for r in idx]));runs=np.split(idx,np.flatnonzero(np.diff(idx)>1)+1)
 print(json.dumps({'n_selected':len(idx),'n_runs':len(runs),'longest_run':max(map(len,runs)),'selected_nnz':int(sum(ptr[idx+1]-ptr[idx])),'chunks':len(chunks),'uncompressed_chunk_bytes':int(len(chunks)*42464*16),'compression':h['X/data'].compression,'sample_rows':idx[:30].tolist()}))
 out=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/implementation_checked_extract');out.mkdir(exist_ok=True);after=fs.info(p,refresh=True)
 if (after.get('ETag'),after['size'])!=(source_info['ETag'],source_info['size']):raise ValueError('Source changed during metadata planning')
 np.savez_compressed(out/'control_metadata.npz',source_uri=np.array(p),source_etag=np.array(source_info['ETag']),source_size=np.array(source_info['size']),**{k:v[idx] for k,v in o.items()},source_rows=idx,indptr=ptr,source_gene_symbols=col(h['var'],'gene_name'))
