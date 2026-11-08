"""Reconstruct every coefficient, selected gene, prediction and summary from counts."""
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr,spearmanr
P=Path(__file__).resolve().parent;ROOT=P.parent.parent
r=json.loads((P/'results.json').read_text())
def load(path):
 with np.load(path,allow_pickle=False) as z:return dict(z)
paths={'selected':ROOT/'full_readout_reliability/targets.npz','basic_qc':ROOT/'basic_qc_panel/targets.npz','controls':ROOT/'full_readout_reliability/controls.npz'}
for name,path in paths.items():assert r['input_sha256'][name]==hashlib.sha256(path.read_bytes()).hexdigest()
c=load(paths['controls']);datasets={name:load(path) for name,path in paths.items() if name!='controls'}
excluded=set.union(*(set(d['perturbed_gene_name']) for d in datasets.values()));assert sorted(excluded)==r['excluded_target_genes']
assert set(c['guide_id'][c['pool']=='feature']).isdisjoint(set(c['guide_id'][c['pool']=='reference']))
def norm(counts,library):
 return np.log1p(10000*np.asarray(counts,dtype=float)/library)
refs={};baseline={};cpms={}
for donor in sorted(set(c['donor_id'])):
 for condition in sorted(set(c['culture_condition'])):
  ids=[i for i in range(len(c['counts'])) if c['donor_id'][i]==donor and c['culture_condition'][i]==condition]
  raw=c['counts'][ids].sum(axis=0);lib=c['library_counts'][ids].sum();baseline[donor,condition]=norm(raw,lib);cpms[donor,condition]=1e6*raw/lib
  for pool in ['feature','reference']:
   ix=[i for i in ids if c['pool'][i]==pool];assert ix
   refs[donor,condition,pool]=norm(c['counts'][ix].sum(0),c['library_counts'][ix].sum())
checks=0;fit_checks=0;row_checks=0

def compare(actual,expected):
 global checks
 for metric,value in expected.items():
  if value is None:assert actual[metric] is None
  else:np.testing.assert_allclose(actual[metric],value,rtol=1e-10,atol=1e-12)
  checks+=1

def summary(actual,rows):
 for arm in rows[0]['_verified']:
  for metric in ['mse','pearson','spearman']:
   values=[row['_verified'][arm][metric] for row in rows if row['_verified'][arm][metric] is not None]
   compare(actual[arm][metric],{'mean':sum(values)/len(values) if values else None,'valid_count':len(values),'total_count':len(rows)})

for name,t in datasets.items():
 np.testing.assert_array_equal(t['gene_symbols'],c['gene_symbols'])
 data=r['datasets'][name];genes=t['gene_symbols'];targets=sorted(set(t['perturbed_gene_name']));donors=sorted(set(t['donor_id']));conditions=sorted(set(t['culture_condition']))
 effects={};guides={}
 for donor in donors:
  for cond in conditions:
   for target in targets:
    ids=[i for i in range(len(t['counts'])) if t['donor_id'][i]==donor and t['culture_condition'][i]==cond and t['perturbed_gene_name'][i]==target]
    assert len(ids)==2 and len(set(t['guide_id'][ids]))==2;ids.sort(key=lambda i:t['guide_id'][i])
    guides[donor,cond,target]=[norm(t['counts'][i],t['library_counts'][i]) for i in ids]
    effects[donor,cond,target]=norm(t['counts'][ids].sum(0),t['library_counts'][ids].sum())-baseline[donor,cond]
 fitted={}
 for fit in data['fits']:
  test,cond,panel=[fit[k] for k in ['test_donor','condition','panel']];train=sorted(set(donors)-{test});assert fit['train_donors']==train and len(train)==3
  # Average donors for each target, then target variance; independent gene-name sorting.
  targetmeans=np.array([sum((effects[d,cond,target] for d in train))/len(train) for target in targets])
  if panel=='all':chosen=[j for j,g in enumerate(genes) if g not in excluded]
  else:
   expression=sum((cpms[d,cond] for d in train))/len(train)
   variance=np.var(targetmeans,axis=0,ddof=0)
   eligible=[j for j,g in enumerate(genes) if g not in excluded and expression[j]>=1 and np.isfinite(variance[j])]
   chosen=sorted(eligible,key=lambda j:(-variance[j],str(genes[j])))[:int(panel)]
  assert fit['genes']==genes[chosen].tolist() and fit['readouts']==len(chosen)
  numerator=0.;denominator=0.
  for donor in train:
   f=refs[donor,cond,'feature'][chosen];ref=refs[donor,cond,'reference'][chosen]
   for target in targets:
    a,b=[g[chosen] for g in guides[donor,cond,target]]
    for u,v in [(a-f,b-ref),(a-ref,b-f)]:
     numerator+=2*float(np.sum(u*v));denominator+=float(np.sum(u*u)+np.sum(v*v))
  alpha=max(0,min(1,numerator/denominator)) if denominator else 0.
  compare(fit,{'numerator':numerator,'denominator':denominator,'alpha':alpha});fit_checks+=1
  key=test,cond,panel;assert key not in fitted;fitted[key]=(chosen,alpha,targetmeans[:,chosen])
 assert len(fitted)==36
 seen=set()
 for row in data['rows']:
  test,cond,panel,target=[row[k] for k in ['test_donor','condition','panel','target']];key=test,cond,panel,target;assert key not in seen;seen.add(key)
  chosen,alpha,means=fitted[test,cond,panel];assert row['readouts']==len(chosen);np.testing.assert_allclose(row['alpha'],alpha,rtol=1e-10,atol=1e-12)
  i=targets.index(target);wrong=(i+1)%len(targets);assert row['mismatched_target']==targets[wrong]
  truth=effects[test,cond,target][chosen]
  arms={'no_change':np.zeros(len(chosen)),'condition_mean':sum(means)/len(targets),'matched_observed_target':means[i],'shrunk_matched':alpha*means[i],'shrunk_mismatched':alpha*means[wrong]}
  row['_verified']={}
  for arm,pred in arms.items():
   valid=np.ptp(pred)>0 and np.ptp(truth)>0
   values={'mse':float(np.mean((pred-truth)**2)),'pearson':float(pearsonr(pred,truth).statistic) if valid else None,'spearman':float(spearmanr(pred,truth).statistic) if valid else None}
   compare(row['metrics'][arm],values);row['_verified'][arm]=values
  row_checks+=1
 assert len(seen)==576
 for panel in ['all','128','512']:
  summary(data['by_panel'][panel],[row for row in data['rows'] if row['panel']==panel])
  for donor in donors:summary(data['by_panel_test_donor'][panel][donor],[row for row in data['rows'] if row['panel']==panel and row['test_donor']==donor])
output={'status':'passed','independent_coefficients_and_gene_lists':fit_checks,'prediction_rows_verified':row_checks,'numeric_and_summary_comparisons':checks,'excluded_union_target_genes':len(excluded),'control_reference_verification':'Raw pools disjoint by guide identity; same pooled controls reconstructed within donor/condition','leakage_review':'All coefficient, expression-filter, target-variance and prediction inputs are from3 training donors. Union target identity is shared design information; all32 target genes excluded everywhere. Known-target transfer in same4 donors, shared controls and exploratory reused data do not establish prospective or cross-study prediction.','normalization':'Multiply-then-divide operation order matches documented driver and preserves exact Spearman ties. Full-library sizes retained.','input_sha256':r['input_sha256']}
(P/'independent_verification.json').write_text(json.dumps(output,indent=2)+'\n');print(json.dumps(output,indent=2))
