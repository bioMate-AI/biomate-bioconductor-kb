"""Source-bound obs inventory; no expression/count matrix reads."""
import json,hashlib
from pathlib import Path
import h5py,numpy as np,s3fs
P=Path(__file__).resolve().parent
SOURCE='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.pseudobulk_merged.h5ad'
def col(g,k):
 v=g[k]
 if isinstance(v,h5py.Group):
  codes=v['codes'][:];cats=v['categories'].asstr()[:]
  return np.array([cats[x] if x>=0 else '__MISSING__' for x in codes],dtype=str)
 return v.asstr()[:].astype(str) if v.dtype.kind in 'OS' else v[:]
def main():
 fs=s3fs.S3FileSystem(anon=False,default_block_size=262144);before=fs.info(SOURCE,refresh=True)
 with fs.open(SOURCE,'rb') as f,h5py.File(f,'r') as h:
  fields=list(h['obs']);print('obs fields',fields,flush=True)
  data={k:col(h['obs'],k) for k in fields}
 after=fs.info(SOURCE,refresh=True);assert before.get('ETag') and (before['ETag'],before['size'])==(after['ETag'],after['size'])
 np.savez_compressed(P/'metadata.npz',**data)
 result={'source':'s3://'+SOURCE,'etag':before['ETag'],'size':before['size'],'fields':{k:{'dtype':str(v.dtype),'unique':len(np.unique(v)),'examples':[str(x) for x in np.unique(v)[:8]]} for k,v in data.items()},'profiles':len(data['_index']),'metadata_sha256':hashlib.sha256((P/'metadata.npz').read_bytes()).hexdigest()}
 (P/'manifest.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
