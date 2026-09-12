"""Read only observation metadata; do not read expression counts."""
from pathlib import Path
import json,hashlib
import numpy as np,h5py,s3fs
from prepare import col,SOURCE
P=Path(__file__).resolve().parent
fs=s3fs.S3FileSystem(anon=False,default_block_size=65536);before=fs.info(SOURCE,refresh=True)
with fs.open(SOURCE,'rb',cache_type='readahead',block_size=65536) as f,h5py.File(f,'r') as h:
 d={k:col(h['obs'],k) for k in ['patient','sample','target','guide_id','perturbation','perturbation_2']}
 valid=(d['perturbation']!='__MISSING__')&(d['target']!='__MISSING__')&(d['guide_id']!='NA')
 checks={
 'patient_sample_prefix':sum(str(s).split('_',1)[0]!=str(p) for s,p in zip(d['sample'],d['patient'])),
 'sample_stimulation':sum({'nostim':'control','stim':'stim'}.get(str(s).split('_',1)[1])!=str(p) for s,p in zip(d['sample'],d['perturbation_2'])),
 'assigned_target_perturbation':sum(('control' if t=='NonTarget' else t)!=p for t,p in zip(d['target'][valid],d['perturbation'][valid])),
 'assigned_guide_target':sum(str(g).split('.')[2]!=t for g,t in zip(d['guide_id'][valid],d['target'][valid]))}
 assert not any(checks.values()),checks
 groups=sorted(set(zip(d['patient'][valid],d['sample'][valid],d['target'][valid],d['guide_id'][valid])))
after=fs.info(SOURCE,refresh=True);assert before['ETag']==after['ETag'] and before['size']==after['size']
r={'status':'passed','source':'s3://'+SOURCE,'etag':before['ETag'],'size':before['size'],'expression_counts_read':False,'source_cells':len(valid),'assigned_guide_cells':int(valid.sum()),'assigned_groups':len(groups),'mismatch_counts':{k:int(v) for k,v in checks.items()},'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(P/'metadata_verification.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
