"""Bounded metadata-selected target-guide pilot extraction; full-row libraries."""
import json,hashlib,h5py,s3fs,numpy as np
from pathlib import Path
OUT=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/target_state_data');OUT.mkdir(exist_ok=True)
SOURCE='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'
def col(g,key):
 v=g[key]
 if isinstance(v,h5py.Group):
  cats=v['categories'].asstr()[:];c=v['codes'][:];return np.where(c<0,'MISSING',cats[np.maximum(c,0)])
 return v.asstr()[:] if v.dtype.kind in 'OS' else v[:]
def order(s):return hashlib.sha256(('target-state-pilot-20260912:'+str(s)).encode()).hexdigest()
with np.load('/Users/kky/biomate-audit-fix/out/20260911_h1_perturbation_pilot/prepared.npz',allow_pickle=False) as z:panel=set(z['targets']);readouts=z['readouts'].astype(str)
fs=s3fs.S3FileSystem(anon=False,default_block_size=65536);info=fs.info(SOURCE)
with fs.open(SOURCE,'rb',cache_type='readahead',block_size=65536) as f,h5py.File(f,'r') as h:
 assert h['X'].attrs['encoding-type']=='csr_matrix';shape=list(map(int,h['X'].attrs['shape']));symbols=col(h['var'],'gene_name');lookup={s:i for i,s in enumerate(symbols) if np.count_nonzero(symbols==s)==1};assert all(s in lookup for s in readouts);mapping=np.full(len(symbols),-1);mapping[[lookup[s] for s in readouts]]=np.arange(len(readouts))
 keys=['donor_id','culture_condition','guide_id','perturbed_gene_name','guide_type','keep_for_DE','_index','n_cells','total_counts'];m={k:col(h['obs'],k) for k in keys};eligible=(m['guide_type']=='targeting')&m['keep_for_DE'].astype(bool)&np.isin(m['perturbed_gene_name'],list(panel));groups={(d,c) for d in set(m['donor_id']) for c in set(m['culture_condition'])};selected={}
 for gene in sorted(panel,key=order):
  ix=np.where(eligible&(m['perturbed_gene_name']==gene))[0];guides=sorted(set(m['guide_id'][ix]),key=order);complete=[]
  for guide in guides:
   gi=ix[m['guide_id'][ix]==guide];coverage=set(zip(m['donor_id'][gi],m['culture_condition'][gi]))
   if coverage==groups:complete.append(guide)
  if len(complete)>=2:selected[gene]=complete[:2]
  if len(selected)==16:break
 assert len(selected)>=8,('too few complete targets',len(selected))
 chosen=set(g for gs in selected.values() for g in gs);rows=np.where(eligible&np.isin(m['guide_id'],list(chosen)))[0];ptr=h['X/indptr'][:];nnz=int(sum(ptr[rows+1]-ptr[rows]));assert nnz*16<150*1024**2
 counts=np.zeros((len(rows),len(readouts)),dtype=np.int64);lib=np.zeros(len(rows),dtype=np.int64);print('targets',len(selected),'guides',len(chosen),'profiles',len(rows),'logical sparse bytes',nnz*16,flush=True)
 (OUT/'selection.json').write_text(json.dumps({'targets_and_guides':selected,'profiles':len(rows),'source_rows':rows.tolist(),'selection':'Frozen earlier117-target development panel; first16 hash-ordered targets with >=2 metadata-eligible guides complete across all12 donor-condition groups; first2 guides per target','selected_row_uncompressed_bytes':nnz*16},indent=2))
 for j,r in enumerate(rows):
  a,b=map(int,ptr[r:r+2]);ix=h['X/indices'][a:b];v=h['X/data'][a:b];assert np.isfinite(v).all() and (v>=0).all() and (v==np.floor(v)).all();assert len(set(ix))==len(ix) and ((ix>=0)&(ix<len(symbols))).all();lib[j]=v.sum();keep=mapping[ix]>=0;counts[j,mapping[ix[keep]]]=v[keep]
  if j%50==0:print('read',j,'/',len(rows),flush=True)
 assert (lib>0).all() and (m['n_cells'][rows]>0).all();np.testing.assert_array_equal(lib,m['total_counts'][rows]);assert len(set(m['_index'][rows]))==len(rows)
 after=fs.info(SOURCE,refresh=True)
 if not info.get('ETag') or (after.get('ETag'),after['size'])!=(info.get('ETag'),info['size']):raise ValueError('Source changed during target extraction or ETag unavailable')
 np.savez_compressed(OUT/'targets.npz',counts=counts,library_counts=lib,gene_symbols=readouts,source_rows=rows,**{k:(m[k][rows] if k=='n_cells' else m[k][rows].astype(str)) for k in ['donor_id','culture_condition','guide_id','perturbed_gene_name','_index','n_cells']})
 manifest={'source':'s3://'+SOURCE,'source_size':info['size'],'source_etag':info.get('ETag'),'targets':selected,'profiles':len(rows),'genes':len(readouts),'counts_validated':True,'full_library_matches_metadata':True,'source_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'prepared_sha256':hashlib.sha256((OUT/'targets.npz').read_bytes()).hexdigest(),'limits':['Small metadata-complete16-target/2guide-per-target pilot','Previously outcome-selected target panel; keep_for_DE also includes guide eligibility','Coverage selected across donors; not prospective unselected coverage','No labels or values used for target/guide hash ranking','Pseudobulk deltas are not publication DE log fold changes']};(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2));print('target extraction complete',flush=True)
