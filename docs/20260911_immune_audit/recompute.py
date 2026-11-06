"""Read-only independent audit; does not import the training metric functions."""
import ast, hashlib, json, warnings
from pathlib import Path
import numpy as np
from scipy.stats import spearmanr
from sklearn.metrics import average_precision_score
ROOT=Path('/Users/kky/biomate-audit-fix')
OUT=Path(__file__).resolve().parent
report={'source_inventory':[], 'runs':[], 'artifact_errors':[], 'split_checks':[]}
for p in sorted((ROOT/'research/immune_llm_baseline').rglob('*')):
 if not p.is_file() or '__pycache__' in p.parts:continue
 row={'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 if p.suffix=='.py':
  try:
   tree=ast.parse(p.read_text()); row['syntax']='pass';row['broad_exception_handlers']=sum(isinstance(n,ast.ExceptHandler) and (n.type is None or isinstance(n.type,ast.Name) and n.type.id=='Exception') for n in ast.walk(tree))
  except Exception as e:row['syntax']=str(e)
 report['source_inventory'].append(row)
def mse(p,y):return float(np.mean((p.astype('float64')-y)**2))
def verify(value,expected,label,tol=2e-6):
 if not np.isfinite(value) or abs(value-expected)>tol*max(1.,abs(expected)):raise AssertionError((label,value,expected))
def protein(p,y,s):
 verify(mse(p,y),s['mse'],'MSE')
 valid=(np.ptp(p,axis=0)>1e-8)&(np.ptp(y,axis=0)>1e-8)
 rs=[np.corrcoef(p[:,j].astype(float),y[:,j].astype(float))[0,1] for j in np.where(valid)[0]]
 verify(float(np.mean(rs)),s['mean_pearson'],'Pearson')
 return {'mse':mse(p,y),'pearson':float(np.mean(rs))}
for name in ['shared_omic_training_pilot','donor_normalization_pilot','mosaic_rna_protein_atac_kg','h1_perturbation_pilot']:
 root=ROOT/'out'/('20260911_'+name);out=root if name.startswith('shared') else root/'training'
 runs=json.loads((out/'results.json').read_text())['runs']
 with np.load(root/'prepared.npz',allow_pickle=False) as d:
  if name.startswith('shared'):
   assert not set(d['train'])&set(d['validation'])
  elif name.startswith('h1'):
   groups=[set(d['targets'][d['split']==k]) for k in ['train','validation','test']]
   assert all(not groups[i]&groups[j] for i,j in [(0,1),(0,2),(1,2)])
  else:
   field='donor' if 'donor' in d.files else 'donors'
   if field in d.files:
    groups=[set(d[field][d['split']==k]) for k in ['train','validation','test']]
    assert all(not groups[i]&groups[j] for i,j in [(0,1),(0,2),(1,2)])
   assert set(d['split'])=={'train','validation','test'}
   if name.startswith('mosaic'):
    groups=[set(d[k]) for k in ['atac_train','atac_validation','atac_test']]
    assert all(not groups[i]&groups[j] for i,j in [(0,1),(0,2),(1,2)])
  report['split_checks'].append({'pilot':name,'status':'pass','prepared_fields':d.files})
 for r in runs:
  stem=f"{r['arm']}_seed{r['seed']}";entry={'pilot':name,'arm':r['arm'],'seed':r['seed']}
  if name.startswith('shared'):f=out/(stem+'_external.npz')
  elif name.startswith('donor'):f=out/(r['target_task']+'_'+stem+'_test.npz');entry['task']=r['target_task']
  elif name.startswith('mosaic'):f=out/(stem+'_predictions.npz')
  else:f=out/(stem+'_evaluation.npz')
  with np.load(f,allow_pickle=False) as z:
   for k in z.files:
    try:
     a=z[k]
     if a.dtype.kind in 'fc' and not np.isfinite(a).all():report['artifact_errors'].append({'path':str(f),'field':k,'error':'nonfinite'})
    except ValueError as e:report['artifact_errors'].append({'path':str(f),'field':k,'error':str(e)})
   if name.startswith('mosaic'):
    entry['protein']=protein(z['protein_prediction'],z['protein_target'],r['protein'])
    if r['arm']!='extra_RNA_only':
     y=z['atac_target'];p=z['atac_prediction'];valid=(y.sum(0)>0)&(y.sum(0)<len(y));ap=float(np.mean([average_precision_score(y[:,j],p[:,j]) for j in np.where(valid)[0]]));verify(ap,r['atac']['mean_peak_average_precision'],'peak AP');entry['atac_AP']=ap
   elif name.startswith('h1'):
    y=z['target'][z['test']];mask=z['observed'][z['test']];p=z['prediction'];v=mse(p[mask],y[mask]);verify(v,r['test']['mse'],'H1 MSE');rs=[]
    for pp,yy,o in zip(p,y,mask):
     if o.sum()>=3 and np.ptp(yy[o])>=1e-12:rs.append(0. if np.ptp(pp[o])<1e-12 else float(spearmanr(pp[o],yy[o]).statistic))
    rho=float(np.mean(rs));verify(rho,r['test']['mean_row_spearman'],'H1 rho');entry.update(mse=v,rho=rho)
    if r['arm']=='encoder_features' and r['seed']==0:
     target=z['target'];obs=z['observed'];tr=z['train'];conds=z['conditions'];meanpred=np.stack([np.where(obs[tr&(conds==c)],target[tr&(conds==c)],np.nan).mean(0) for c in conds[z['test']]])
     baseline=json.loads((out/'baselines.json').read_text())['training_condition_mean'];verify(mse(meanpred[mask],y[mask]),baseline['mse'],'condition mean baseline');verify(float(np.mean([spearmanr(pp[o],yy[o]).statistic for pp,yy,o in zip(meanpred,y,mask)])),baseline['mean_row_spearman'],'condition rho');report['h1_baseline_recomputed']=baseline
   else:entry['protein']=protein(z['prediction'],z['target'],r['external'] if name.startswith('shared') else r['test'])
  entry['status']='metrics_match';entry['prediction_sha256']=hashlib.sha256(f.read_bytes()).hexdigest();report['runs'].append(entry)
report['summary']={'inventory_files':len(report['source_inventory']),'python_files':sum('syntax' in r for r in report['source_inventory']),'syntax_failures':sum(r.get('syntax','pass')!='pass' for r in report['source_inventory']),'runs_verified':len(report['runs']),'artifact_errors':len(report['artifact_errors'])}
(OUT/'recomputed_results.json').write_text(json.dumps(report,indent=2,allow_nan=False));print(json.dumps(report['summary'],indent=2))
