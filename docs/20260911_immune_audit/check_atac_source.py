import s3fs,h5py,numpy as np,json
from pathlib import Path
source='knowledge-datasets-1759951976/immunology_sc_corpus_broad/multiomic_v1/multiome/GSE269540.h5ad'
fs=s3fs.S3FileSystem(anon=False,default_block_size=1024*1024)
with fs.open(source,'rb') as f,h5py.File(f,'r') as h:
 p=h['obsm/atac_peaks'];print('peak storage',list(p),flush=True);v=p['data'];zero=0;bad=0
 for off in range(0,len(v),1000000):
  a=v[off:off+1000000];zero+=int((a==0).sum());bad+=int((~np.isfinite(a)|(a<0)|(a!=np.floor(a))).sum())
 result={'source':'s3://'+source,'stored_entries':len(v),'explicit_stored_zeros':zero,'invalid_count_entries':bad,'interpretation':'Sparse-zero bug does not alter these source peak counts' if zero==0 else 'Prior binarization affected; rebuild required'}
Path('/Users/kky/biomate-review/docs/20260911_immune_audit/atac_source_storage.json').write_text(json.dumps(result,indent=2));print(result)
