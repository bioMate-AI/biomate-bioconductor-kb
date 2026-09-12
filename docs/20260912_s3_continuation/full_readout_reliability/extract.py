"""Read all genes for frozen pilot rows; never select rows using new outcomes."""
import hashlib,json
from pathlib import Path
import h5py,numpy as np,s3fs
ROOT=Path(__file__).resolve().parent.parent
OUT=Path(__file__).resolve().parent
SOURCE='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'
def col(g,k):
 v=g[k]
 if isinstance(v,h5py.Group):
  codes=v['codes'][:];cats=v['categories'].asstr()[:]
  if (codes<0).any():raise ValueError('Missing categorical metadata')
  return cats[codes]
 return v.asstr()[:] if v.dtype.kind in 'OS' else v[:]
def main():
 fs=s3fs.S3FileSystem(anon=False,default_block_size=65536);before=fs.info(SOURCE,refresh=True)
 prior=json.loads((ROOT/'target_state_data/manifest.json').read_text())
 assert before['ETag']==prior['source_etag'] and before['size']==prior['source_size']
 outputs={};logical=0
 with fs.open(SOURCE,'rb',cache_type='readahead',block_size=65536) as f,h5py.File(f,'r') as h:
  assert h['X'].attrs['encoding-type']=='csr_matrix'
  genes=col(h['var'],'gene_name');ptr=h['X/indptr'][:]
  for name,path in [('targets','target_state_data/targets.npz'),('controls','baseline_state_data/controls.npz')]:
   with np.load(ROOT/path,allow_pickle=False) as z:d={k:z[k] for k in z.files}
   rows=d['source_rows'];old=d['counts'];assert len(set(rows))==len(rows)
   for k in ['_index','guide_id','donor_id','culture_condition']:
    np.testing.assert_array_equal(col(h['obs'],k)[rows].astype(str),d[k].astype(str))
   counts=np.zeros((len(rows),len(genes)),dtype=np.int64)
   estimate=int(sum(ptr[rows+1]-ptr[rows]))*16;logical+=estimate
   assert logical<180*1024**2
   for j,r in enumerate(rows):
    a,b=map(int,ptr[r:r+2]);ix=h['X/indices'][a:b];v=h['X/data'][a:b]
    assert np.isfinite(v).all() and (v>=0).all() and (v==np.floor(v)).all()
    assert len(set(ix))==len(ix) and ((ix>=0)&(ix<len(genes))).all()
    counts[j,ix]=v
    if j%100==0:print(name,j,len(rows),flush=True)
   np.testing.assert_array_equal(counts.sum(1),d['library_counts'])
   subset=[]
   for gene in d['gene_symbols']:
    ix=np.flatnonzero(genes==gene);assert len(ix)==1;subset.append(ix[0])
   np.testing.assert_array_equal(counts[:,subset],old)
   d.update(counts=counts,gene_symbols=genes.astype(str));outputs[name]=d
 after=fs.info(SOURCE,refresh=True)
 assert (before['ETag'],before['size'])==(after['ETag'],after['size'])
 for name,d in outputs.items():np.savez_compressed(OUT/(name+'.npz'),**d)
 manifest={'source':'s3://'+SOURCE,'etag':before['ETag'],'size':before['size'],'genes':len(genes),'profiles':{n:len(d['counts']) for n,d in outputs.items()},'logical_sparse_bytes':logical,'original_132_gene_counts_exactly_reproduced':True,'full_library_sums_exact':True,'selection':'Frozen original rows, all source genes; no new outcome selection','sha256':{n:hashlib.sha256((OUT/(n+'.npz')).read_bytes()).hexdigest() for n in outputs}}
 (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print(json.dumps(manifest,indent=2))
if __name__=='__main__':main()
