import json,hashlib
from pathlib import Path
import numpy as np
from scipy.stats import rankdata
p=Path(__file__).resolve().parent
def load(n):
 with np.load(p/n,allow_pickle=False) as z:return dict(z)
t,c=load('targets.npz'),load('controls.npz');r=json.loads((p/'results.json').read_text())
assert len(set(t['gene_symbols']))==len(t['gene_symbols'])
np.testing.assert_array_equal(t['counts'].sum(axis=1),t['library_counts'])
np.testing.assert_array_equal(c['counts'].sum(axis=1),c['library_counts'])
x=np.log1p(t['counts']/t['library_counts'][:,None]*10000);refs={};cpms=[]
for donor in np.unique(c['donor_id']):
 for cond in np.unique(c['culture_condition']):
  base=(c['donor_id']==donor)&(c['culture_condition']==cond)
  cpms.append(1e6*c['counts'][base].sum(0)/c['library_counts'][base].sum())
  for pool in ['feature','reference']:
   ix=base&(c['pool']==pool);refs[donor,cond,pool]=np.log1p(c['counts'][ix].sum(0)/c['library_counts'][ix].sum()*10000)
with np.load(p.parent/'target_state_data/targets.npz',allow_pickle=False) as z: oldgenes=z['gene_symbols']
panels={'all_genes':np.ones(len(t['gene_symbols']),bool),'control_expressed':np.count_nonzero(np.array(cpms)>=1,axis=0)>=6,'frozen132':np.isin(t['gene_symbols'],oldgenes)}
def corr(a,b):
 a=a-a.mean();b=b-b.mean();return a.dot(b)/(np.sqrt(a.dot(a))*np.sqrt(b.dot(b)))
checks=0;maximum=0;summary_checks=0
for panel,result in r['panels'].items():
 assert result['genes_before_target_exclusion']==panels[panel].sum()
 for row in result['rows']:
  target,donor,cond=(row[k] for k in ['target','donor','condition'])
  ii=np.flatnonzero((t['perturbed_gene_name']==target)&(t['donor_id']==donor)&(t['culture_condition']==cond));ii=sorted(ii,key=lambda j:t['guide_id'][j]);assert len(ii)==2
  keep=panels[panel]&(t['gene_symbols']!=target);assert keep.sum()==row['readouts']
  u,v=x[ii][:,keep];f=refs[donor,cond,'feature'][keep];q=refs[donor,cond,'reference'][keep]
  for name,(a,b) in {'profile':(u,v),'shared_feature_reference':(u-f,v-f),'shared_reference_reference':(u-q,v-q),'disjoint_forward':(u-f,v-q),'disjoint_swapped':(u-q,v-f)}.items():
   vals={'mse':np.dot(a-b,a-b)/len(a),'pearson':corr(a,b),'spearman':corr(rankdata(a),rankdata(b))}
   for k,value in vals.items():
    diff=abs(value-row[name][k]);maximum=max(maximum,diff);np.testing.assert_allclose(value,row[name][k],rtol=1e-10,atol=1e-12);checks+=1
 for name in result['mean_metrics']:
  for k,val in result['mean_metrics'][name].items():np.testing.assert_allclose(val,sum(row[name][k] for row in result['rows'])/len(result['rows']),atol=1e-14)
 for group_key,field in [('by_donor','donor'),('by_condition','condition')]:
  for group,summary in result[group_key].items():
   rows=[row for row in result['rows'] if row[field]==group]
   for name,metrics in summary.items():
    for metric,value in metrics.items():
     np.testing.assert_allclose(value,sum(row[name][metric] for row in rows)/len(rows),rtol=1e-12,atol=1e-14);summary_checks+=1
print(json.dumps({'group_summary_checks':summary_checks,'normalization_note':'Exact log1p operation ordering retained to preserve floating-point rank ties; independently computed metric formulas.', 'status' :'passed','independent_metric_checks':checks,'maximum_absolute_difference':maximum,'full_library_sums_exact':True,'unique_gene_symbols':True,'results_sha256':hashlib.sha256((p/'results.json').read_bytes()).hexdigest()},indent=2))
