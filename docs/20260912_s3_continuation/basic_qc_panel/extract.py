"""Frozen hash-selected basic-QC panel; no efficacy or expression-based selection."""
import json,hashlib,collections
from pathlib import Path
import numpy as np,h5py,s3fs
P=Path(__file__).resolve().parent
SOURCE='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'
def order(x):return hashlib.sha256(('basic-qc-expansion-20260912:'+str(x)).encode()).hexdigest()
def main():
 with np.load(P.parent/'guide_run_audit/metadata.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
 with np.load('/Users/kky/biomate-audit-fix/out/20260911_h1_perturbation_pilot/prepared.npz',allow_pickle=False) as z:excluded=set(z['targets'])
 qc=(d['guide_type']=='targeting')&d['keep_min_cells']&d['keep_total_counts']
 coverage=collections.defaultdict(set);indices=collections.defaultdict(list)
 for i in np.flatnonzero(qc):
  key=(d['perturbed_gene_name'][i],d['guide_id'][i]);coverage[key].add((d['donor_id'][i],d['culture_condition'][i]));indices[key].append(int(i))
 eligible=collections.defaultdict(list)
 for (gene,guide),groups in coverage.items():
  if len(groups)==12 and gene not in excluded:eligible[gene].append(guide)
 selected={g:sorted(eligible[g],key=order)[:2] for g in sorted([g for g in eligible if len(eligible[g])>=2],key=order)[:16]}
 assert len(selected)==16
 rows=np.array(sorted(i for g,guides in selected.items() for guide in guides for i in indices[(g,guide)]));assert len(rows)==384
 selection={'targets':selected,'excluded_previous_panel_targets':len(excluded),'eligible_targets':sum(len(gs)>=2 for gs in eligible.values()),'rows':rows.tolist(),'rule':'First16 SHA256 ordered targets outside previous117-target panel with >=2 guides basic-QC complete across12 donor-condition groups; first2 hash-ordered guides. No efficacy/test-gene/DE or expression values used. Coverage selection remains.','source_metadata_sha256':hashlib.sha256((P.parent/'guide_run_audit/metadata.npz').read_bytes()).hexdigest()}
 (P/'selection.json').write_text(json.dumps(selection,indent=2)+'\n');print('selected',list(selected),flush=True)
 source=json.loads((P.parent/'guide_run_audit/manifest.json').read_text());fs=s3fs.S3FileSystem(anon=False,default_block_size=65536);before=fs.info(SOURCE,refresh=True)
 assert (source['etag'],source['size'])==(before['ETag'],before['size'])
 with fs.open(SOURCE,'rb',cache_type='readahead',block_size=65536) as f,h5py.File(f,'r') as h:
  assert h['X'].attrs['encoding-type']=='csr_matrix';genes=h['var/gene_name'].asstr()[:].astype(str);assert len(set(genes))==len(genes)
  np.testing.assert_array_equal(h['obs/_index'].asstr()[:][rows],d['_index'][rows])
  ptr=h['X/indptr'][:];logical=int(sum(ptr[rows+1]-ptr[rows]))*16;assert logical<150*1024**2
  counts=np.zeros((len(rows),len(genes)),dtype=np.int64)
  for j,r in enumerate(rows):
   a,b=map(int,ptr[r:r+2]);ix=h['X/indices'][a:b];v=h['X/data'][a:b]
   assert np.isfinite(v).all() and (v>=0).all() and (v==np.floor(v)).all() and len(set(ix))==len(ix) and ((ix>=0)&(ix<len(genes))).all()
   counts[j,ix]=v
   if j%100==0:print('profiles',j,len(rows),flush=True)
  np.testing.assert_array_equal(counts.sum(1),d['total_counts'][rows])
 after=fs.info(SOURCE,refresh=True);assert (after['ETag'],after['size'])==(before['ETag'],before['size'])
 np.savez_compressed(P/'targets.npz',counts=counts,library_counts=counts.sum(1),gene_symbols=genes,source_rows=rows,**{k:d[k][rows] for k in d})
 manifest={'source':'s3://'+SOURCE,'etag':before['ETag'],'size':before['size'],'profiles':len(rows),'genes':len(genes),'targets':len(selected),'logical_sparse_bytes':logical,'DE_eligible_profiles':int(d['keep_for_DE'][rows].sum()),'basic_qc_not_DE':int((~d['keep_for_DE'][rows]).sum()),'full_library_sums_exact':True,'sha256':hashlib.sha256((P/'targets.npz').read_bytes()).hexdigest()}
 (P/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))
if __name__=='__main__':main()
