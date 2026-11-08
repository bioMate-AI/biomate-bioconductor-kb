"""Metadata-only independent-source triage; no expression matrix reads."""
import json
from pathlib import Path
import numpy as np,h5py,s3fs
P=Path(__file__).resolve().parent
fs=s3fs.S3FileSystem(anon=False,default_block_size=65536);out={}
for name in ['ShifrutMarson2018','CuiHacohen2023']:
 source='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/scperturb/'+name+'.h5ad';before=fs.info(source,refresh=True)
 with fs.open(source,'rb',cache_type='readahead',block_size=65536) as f,h5py.File(f,'r') as h:
  fields={}
  for k,v in h['obs'].items():
   if isinstance(v,h5py.Group) and 'categories' in v:
    cat=v['categories'];cats=cat.asstr()[:] if cat.dtype.kind in 'OS' else cat[:];codes=v['codes'][:]
    fields[k]={'categories':list(map(str,cats[:100])),'n_categories':len(cats),'counts':{str(c):int((codes==i).sum()) for i,c in enumerate(cats)} if len(cats)<=100 else {},'missing':int((codes<0).sum())}
   else:
    fields[k]={'dtype':str(v.dtype),'shape':list(v.shape)}
    if v.dtype.kind in 'OS' and k!='_index':
     values=v.asstr()[:];unique,counts=np.unique(values,return_counts=True);fields[k].update(n_unique=len(unique),examples=unique[:50].tolist())
  out[name]={'source':'s3://'+source,'size':before['size'],'etag':before['ETag'],'obs':fields,'var_fields':list(h['var']),'X_encoding':str(h['X'].attrs.get('encoding-type')),'X_shape':list(map(int,h['X'].attrs.get('shape',h['X'].shape if isinstance(h['X'],h5py.Dataset) else []))),'layers':list(h.get('layers',{})),'raw_available':'raw' in h}
 after=fs.info(source,refresh=True);assert (before['ETag'],before['size'])==(after['ETag'],after['size'])
 print(name,'fields',list(fields),flush=True)
(P/'external_metadata.json').write_text(json.dumps(out,indent=2)+'\n')
