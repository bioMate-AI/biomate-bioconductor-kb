"""Aggregate externally stored single-guide T cells; validate count semantics first."""
import json,hashlib,collections
from pathlib import Path
import h5py,numpy as np,s3fs
P=Path(__file__).resolve().parent
SOURCE='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/scperturb/ShifrutMarson2018.h5ad'
def col(g,k):
 v=g[k]
 if isinstance(v,h5py.Group):
  codes=v['codes'][:];cat=v['categories'];cats=cat.asstr()[:] if cat.dtype.kind in 'OS' else cat[:]
  return np.array([str(cats[x]) if x>=0 else '__MISSING__' for x in codes])
 return v.asstr()[:].astype(str) if v.dtype.kind in 'OS' else v[:]
def main():
 fs=s3fs.S3FileSystem(anon=False,default_block_size=262144);before=fs.info(SOURCE,refresh=True)
 with fs.open(SOURCE,'rb',cache_type='readahead',block_size=262144) as f,h5py.File(f,'r') as h:
  d={k:col(h['obs'],k) for k in ['patient','sample','target','guide_id','perturbation','nperts','ncounts','perturbation_2']}
  print('var fields',list(h['var']),flush=True)
  vkey=h['var'].attrs.get('_index','_index');genes=col(h['var'],vkey).astype(str)
  assert len(set(genes))==len(genes)
  nperts=d['nperts'].astype(float);valid=(d['perturbation']!='__MISSING__')&(d['target']!='__MISSING__')&(d['guide_id']!='NA')
  assert all(str(d['guide_id'][i]).split('.')[2]==d['target'][i] for i in np.flatnonzero(valid))
  keys=sorted(set(zip(d['patient'][valid],d['sample'][valid],d['target'][valid],d['guide_id'][valid])));lookup={k:i for i,k in enumerate(keys)}
  groups=np.full(len(valid),-1,dtype=int)
  for i in np.flatnonzero(valid):groups[i]=lookup[(d['patient'][i],d['sample'][i],d['target'][i],d['guide_id'][i])]
  assert h['X'].attrs['encoding-type']=='csr_matrix';ptr=h['X/indptr'][:]
  # Read contiguous row blocks, aggregating only known single-guide cells.
  total=int(ptr[-1])*(h['X/data'].dtype.itemsize+h['X/indices'].dtype.itemsize);assert total<2*1024**3
  pilot=h['X/data'][:10000];assert np.isfinite(pilot).all() and (pilot>=0).all() and (pilot==np.floor(pilot)).all(), 'X is not raw integer counts; stop'
  selection={'assigned_guide_cells':int(valid.sum()),'excluded_cells':int((~valid).sum()),'groups':len(keys),'genes':len(genes),'logical_sparse_scan_bytes':total,'rule':'All cells with a single assigned guide annotation and consistent target; no efficacy/expression filtering. Missing guide labels excluded. nperts includes TCR stimulation and is not used as a guide-count filter','gene_index_field':str(vkey),'nperts_by_sample':{str(sample):{str(n):int(((d['sample']==sample)&(nperts==n)&valid).sum()) for n in np.unique(nperts)} for sample in np.unique(d['sample'])}}
  (P/'selection.json').write_text(json.dumps(selection,indent=2)+'\n');print(json.dumps(selection),flush=True)
  counts=np.zeros((len(keys),len(genes)),dtype=np.int64);cells=np.zeros(len(keys),dtype=np.int64);metadata_library=np.zeros(len(keys),dtype=np.float64);checked=0
  for start in range(0,len(valid),2000):
   end=min(start+2000,len(valid));a,b=map(int,[ptr[start],ptr[end]]);ix=h['X/indices'][a:b];values=h['X/data'][a:b]
   assert np.isfinite(values).all() and (values>=0).all() and (values==np.floor(values)).all() and ((ix>=0)&(ix<len(genes))).all()
   for i in range(start,end):
    if groups[i]<0:continue
    left,right=map(int,ptr[i:i+2]-a);jj=ix[left:right];vv=values[left:right];assert len(set(jj))==len(jj)
    assert vv.sum()==float(d['ncounts'][i]),'Raw library does not equal ncounts'
    counts[groups[i],jj]+=vv.astype(np.int64);cells[groups[i]]+=1;metadata_library[groups[i]]+=float(d['ncounts'][i]);checked+=1
   print('cells scanned',end,len(valid),flush=True)
  np.testing.assert_array_equal(counts.sum(1),metadata_library);assert checked==valid.sum() and (cells>0).all()
 after=fs.info(SOURCE,refresh=True);assert before.get('ETag') and (after['ETag'],after['size'])==(before['ETag'],before['size'])
 np.savez_compressed(P/'pseudobulk.npz',counts=counts,library_counts=counts.sum(1),n_cells=cells,gene_symbols=genes,donor_id=np.array([k[0] for k in keys]),culture_condition=np.array([k[1].split('_',1)[1] for k in keys]),target=np.array([k[2] for k in keys]),guide_id=np.array([k[3] for k in keys]))
 (P/'manifest.json').write_text(json.dumps({'source':'s3://'+SOURCE,'etag':before['ETag'],'size':before['size'],'selection':selection,'full_library_matches_ncounts':True,'sha256':hashlib.sha256((P/'pseudobulk.npz').read_bytes()).hexdigest()},indent=2)+'\n')
if __name__=='__main__':main()
