"""Independent checks against saved source labels and all reevaluated predictions."""
import json,hashlib
from pathlib import Path
import numpy as np
from scipy.stats import spearmanr
base=Path('/Users/kky/biomate-audit-fix/out');root=base/'20260912_perturbation_reevaluation';r=json.loads((root/'results.json').read_text());checks=[];pooled={k:[] for k in ['ERM','IRM','shuffled_ERM','condition_mean']}
with np.load(base/'20260911_h1_perturbation_pilot/prepared.npz',allow_pickle=False) as source:
 y=np.where(source['observed'],source['Y'],np.nan);cond=source['conditions']
 for row in r['runs']:
  stem=f"{row['arm']}_seed{row['seed']}"
  with np.load(root/(stem+'.npz'),allow_pickle=False) as z:
   tr=z['train_indices'];te=z['test_indices'];assert not set(source['targets'][tr])&set(source['targets'][te]);np.testing.assert_array_equal(z['target'],y[te]);p=z['prediction'];rho=[]
   for pp,yy,mask in zip(p,z['target'],z['observed']):
    rho.append(float(spearmanr(pp[mask],yy[mask]).statistic))
   assert round(float(np.mean(rho)),4)==row['rho']['mean'];assert abs(float(((p-z['target'])[z['observed']]**2).mean())-row['mse'])<1e-6;pooled[row['arm']].extend(rho)
   if row['arm']=='ERM':
    cp=np.stack([np.nanmean(y[tr][cond[tr]==c],axis=0) for c in cond[te]])
    br=[float(spearmanr(pp[mask],yy[mask]).statistic) for pp,yy,mask in zip(cp,z['target'],z['observed'])];pooled['condition_mean'].extend(br)
   checks.append({'run':stem,'source_labels':'pass','split_separation':'pass','metrics':'pass'})
result={'runs':checks,'pooled_row_spearman':{k:float(np.mean(v)) for k,v in pooled.items()},'note':'Development subset; overlapping test targets across seeds; not independent cohort uncertainty'}
Path(__file__).with_name('verification.json').write_text(json.dumps(result,indent=2));print(result['pooled_row_spearman'])
