import json,hashlib
from pathlib import Path
import numpy as np
p=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/baseline_state_data');d=np.load(p/'baseline_aggregates.npz');profiles=np.load(p/'controls.npz');rows=[]
x=np.log1p(1e4*d['counts']/d['library_counts'][:,None])
for donor in sorted(set(d['donor'])):
 for condition in sorted(set(d['condition'])):
  inds=[int(np.flatnonzero((d['donor']==donor)&(d['condition']==condition)&(d['pool']==pool))[0]) for pool in ['feature','reference']];a,b=x[inds];r={'donor':str(donor),'condition':str(condition),'mse_across_132_genes':float(np.mean((a-b)**2)),'pearson_across_132_genes':float(np.corrcoef(a,b)[0,1]),'measured_genes':len(a),'feature_detected_genes':int((d['counts'][inds[0]]>0).sum()),'reference_detected_genes':int((d['counts'][inds[1]]>0).sum())}
  for pool,i in zip(['feature','reference'],inds):
   mask=(profiles['donor_id']==donor)&(profiles['culture_condition']==condition)&(profiles['pool']==pool);r[pool+'_profiles']=int(mask.sum());r[pool+'_guides']=len(set(profiles['guide_id'][mask]));r[pool+'_cells']=int(d['n_cells'][i]);r[pool+'_full_library_umis']=int(d['library_counts'][i])
  rows.append(r)
r={'transform':'natural log1p(10000 * aggregated raw gene counts / aggregated full18129-gene library UMIs)','comparison':'feature-control versus disjoint-guide reference-control pool, within same donor/condition','rows':rows,'mean_mse':float(np.mean([r['mse_across_132_genes'] for r in rows])),'mean_pearson':float(np.mean([r['pearson_across_132_genes'] for r in rows])),'mse_range':[min(r['mse_across_132_genes'] for r in rows),max(r['mse_across_132_genes'] for r in rows)],'pearson_range':[min(r['pearson_across_132_genes'] for r in rows),max(r['pearson_across_132_genes'] for r in rows)],'limitations':['Expression-profile correlations are dominated by shared gene abundance and are not perturbation effect prediction metrics.','Pools share donors and conditions; they are not independent biological cohorts.','Unequal retained guide/cell counts can change pool agreement.','This does not validate independence of source QC flags from response selection.'],'input_sha256':hashlib.sha256((p/'baseline_aggregates.npz').read_bytes()).hexdigest()};(p/'control_quality.json').write_text(json.dumps(r,indent=2));print(json.dumps({k:v for k,v in r.items() if k not in ['rows','limitations']}))
