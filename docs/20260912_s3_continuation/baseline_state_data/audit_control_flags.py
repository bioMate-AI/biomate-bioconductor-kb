import h5py,s3fs,numpy as np,json
from pathlib import Path
fs=s3fs.S3FileSystem(anon=False,default_block_size=262144);source='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'
with fs.open(source,'rb') as f,h5py.File(f,'r') as h:
 g=h['obs/guide_type'];cats=g['categories'].asstr()[:];codes=g['codes'][:];nt=cats[codes]=='non-targeting';keys=['keep_min_cells','keep_total_counts','keep_effective_guides','keep_test_genes','keep_for_DE'];flags={k:h['obs'][k][:].astype(bool) for k in keys};qc=flags['keep_min_cells']&flags['keep_total_counts'];r={'non_targeting_profiles':int(nt.sum()),'non_targeting_pass_counts':{k:int(v[nt].sum()) for k,v in flags.items()},'non_targeting_basic_qc_pass':int((nt&qc).sum()),'non_targeting_basic_qc_differs_keep_for_DE':int((nt&(qc!=flags['keep_for_DE'])).sum()),'non_targeting_all4flags_equal_keep_for_DE':bool(np.array_equal(np.logical_and.reduce([flags[k][nt] for k in keys[:-1]]),flags['keep_for_DE'][nt]))}
p=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/baseline_state_data/control_flag_audit.json');p.write_text(json.dumps(r,indent=2));print(json.dumps(r))
