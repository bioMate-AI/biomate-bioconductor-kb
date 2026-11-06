"""Basic-QC panel descriptive comparison; protocol adapted from full-readout evaluation."""
import hashlib,json,importlib.util
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('guide_metrics',P.parent/'guide_reliability/evaluate.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def main():
 def load(p):
  with np.load(p,allow_pickle=False) as z:return {k:z[k] for k in z.files}
 t=load(P/'targets.npz');c=load(P/'controls.npz');old=load(P.parent/'target_state_data/targets.npz')
 np.testing.assert_array_equal(t['gene_symbols'],c['gene_symbols'])
 assert set(c['guide_id'][c['pool']=='feature']).isdisjoint(set(c['guide_id'][c['pool']=='reference']))
 refs={};cpms=[]
 for donor in sorted(set(c['donor_id'])):
  for condition in sorted(set(c['culture_condition'])):
   group=(c['donor_id']==donor)&(c['culture_condition']==condition)
   cpms.append(c['counts'][group].sum(0)/c['library_counts'][group].sum()*1e6)
   for pool in ['feature','reference']:
    ix=group&(c['pool']==pool);assert ix.any()
    refs[(donor,condition,pool)]=m.norm(c['counts'][ix].sum(0),c['library_counts'][ix].sum())
 panels={'frozen132':np.isin(t['gene_symbols'],old['gene_symbols']),'all_genes':np.ones(len(t['gene_symbols']),dtype=bool),'control_expressed':(np.asarray(cpms)>=1).sum(0)>=6}
 x=m.norm(t['counts'],t['library_counts']);results={}
 for panel,mask in panels.items():
  rows=[]
  for target in sorted(set(t['perturbed_gene_name'])):
   guides=sorted(set(t['guide_id'][t['perturbed_gene_name']==target]));assert len(guides)==2
   for donor in sorted(set(t['donor_id'])):
    for condition in sorted(set(t['culture_condition'])):
     ix=[]
     for guide in guides:
      inds=np.flatnonzero((t['perturbed_gene_name']==target)&(t['guide_id']==guide)&(t['donor_id']==donor)&(t['culture_condition']==condition));assert len(inds)==1;ix.append(inds[0])
     keep=mask&(t['gene_symbols']!=target);assert keep.sum()>1
     u,v=x[ix][:,keep];f=refs[(donor,condition,'feature')][keep];r=refs[(donor,condition,'reference')][keep]
     rows.append({'target':str(target),'donor':str(donor),'condition':str(condition),'readouts':int(keep.sum()),'profile':m.metrics(u,v),'shared_feature_reference':m.metrics(u-f,v-f),'shared_reference_reference':m.metrics(u-r,v-r),'disjoint_forward':m.metrics(u-f,v-r),'disjoint_swapped':m.metrics(u-r,v-f)})
  def summary(rr):
   return {name:{metric:float(np.mean([r[name][metric] for r in rr if r[name][metric] is not None])) for metric in ['mse','pearson','spearman']} for name in ['profile','shared_feature_reference','shared_reference_reference','disjoint_forward','disjoint_swapped']}
  results[panel]={'genes_before_target_exclusion':int(mask.sum()),'n_pairs':len(rows),'mean_metrics':summary(rows),'by_donor':{str(d):summary([r for r in rows if r['donor']==d]) for d in sorted(set(t['donor_id']))},'by_condition':{str(c):summary([r for r in rows if r['condition']==c]) for c in sorted(set(t['culture_condition']))},'rows':rows}
 output={'panels':results,'protocol':{'control_expressed':'CPM >=1 in >=6 of12 pooled-control donor-condition groups; descriptive filtering using all donors, not eligible as a training-selected panel','selection':'Fresh16 targets outside previous117 target panel selected only on basic QC and coverage; no efficacy filter. Same four donors, no independent donor replication','all_genes_caveat':'Low/zero expression and ties can distort correlations; compare control-expressed sensitivity panel','unit':'Equal-weight192 target/donor/condition guide pairs; dependent observations','excluded':'All readouts with symbol equal to perturbed target','normalization':'log1p(10000*counts/full-library counts)'},'original_metrics_reproduced':False,'code_sha256':{str(q.relative_to(P.parent)):hashlib.sha256(q.read_bytes()).hexdigest() for q in [Path(__file__),P.parent/'guide_reliability/evaluate.py']},'input_sha256':{n:hashlib.sha256((P/n).read_bytes()).hexdigest() for n in ['targets.npz','controls.npz']}}
 (P/'results.json').write_text(json.dumps(output,indent=2,allow_nan=False)+'\n')
 print(json.dumps({k:{'genes':v['genes_before_target_exclusion'],'metrics':v['mean_metrics']} for k,v in results.items()},indent=2))
if __name__=='__main__':main()
