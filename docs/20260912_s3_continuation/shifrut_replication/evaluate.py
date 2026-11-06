"""Descriptive external guide agreement; no fitted model or pooled donor claim."""
import json,hashlib,importlib.util
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('metrics',P.parent/'guide_reliability/evaluate.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def main():
 with np.load(P/'pseudobulk.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
 genes=d['gene_symbols'];np.testing.assert_array_equal(d['counts'].sum(1),d['library_counts'])
 ctrl=d['target']=='NonTarget';guides=sorted(set(d['guide_id'][ctrl]),key=lambda g:hashlib.sha256(('external-control-split-20260912:'+str(g)).encode()).hexdigest());assert len(guides)==8
 pool={g:('feature' if i%2==0 else 'reference') for i,g in enumerate(guides)};refs={};cpm=[]
 for donor in sorted(set(d['donor_id'])):
  for condition in sorted(set(d['culture_condition'])):
   ix=ctrl&(d['donor_id']==donor)&(d['culture_condition']==condition);assert ix.sum()==8
   cpm.append(d['counts'][ix].sum(0)/d['library_counts'][ix].sum()*1e6)
   for p in ['feature','reference']:
    ii=ix&np.isin(d['guide_id'],[g for g in pool if pool[g]==p]);assert ii.sum()==4
    refs[(donor,condition,p)]=m.norm(d['counts'][ii].sum(0),d['library_counts'][ii].sum())
 panels={'all_genes':np.ones(len(genes),dtype=bool),'control_expressed':(np.asarray(cpm)>=1).sum(0)>=2}
 x=m.norm(d['counts'],d['library_counts']);results={};missing=[str(t) for t in sorted(set(d['target'][~ctrl])) if t not in genes]
 for pname,panel in panels.items():
  rows=[]
  for target in sorted(set(d['target'][~ctrl])):
   if target in missing:continue
   for donor in sorted(set(d['donor_id'])):
    for condition in sorted(set(d['culture_condition'])):
     ix=np.flatnonzero((d['target']==target)&(d['donor_id']==donor)&(d['culture_condition']==condition));assert len(ix)==2;ix=sorted(ix,key=lambda i:d['guide_id'][i])
     keep=panel&(genes!=target);u,v=x[ix][:,keep];f=refs[(donor,condition,'feature')][keep];r=refs[(donor,condition,'reference')][keep]
     rows.append({'target':str(target),'donor':str(donor),'condition':str(condition),'minimum_cells':int(d['n_cells'][ix].min()),'readouts':int(keep.sum()),'profile':m.metrics(u,v),'shared_feature_reference':m.metrics(u-f,v-f),'shared_reference_reference':m.metrics(u-r,v-r),'disjoint_forward':m.metrics(u-f,v-r),'disjoint_swapped':m.metrics(u-r,v-f)})
  def summary(rr):
   return {n:{k:float(np.mean([r[n][k] for r in rr if r[n][k] is not None])) if any(r[n][k] is not None for r in rr) else None for k in ['pearson','spearman','mse']} for n in ['profile','shared_feature_reference','shared_reference_reference','disjoint_forward','disjoint_swapped']}
  results[pname]={'genes_before_target_exclusion':int(panel.sum()),'n_pairs':len(rows),'mean_metrics':summary(rows),'by_donor':{str(v):summary([r for r in rows if r['donor']==v]) for v in sorted(set(d['donor_id']))},'by_condition':{str(v):summary([r for r in rows if r['condition']==v]) for v in sorted(set(d['culture_condition']))},'support_sensitivity':{str(th):{'pairs':sum(r['minimum_cells']>=th for r in rows),'metrics':summary([r for r in rows if r['minimum_cells']>=th])} for th in [10,25,50,100]},'rows':rows}
 out={'panels':results,'control_guide_assignment':pool,'excluded_targets_unresolved_gene_mapping':missing,'protocol':'Within-experiment guide agreement, two donor labels/two conditions; no model training or cross-study effect validation. Direct target excluded by exact gene symbol. Source processed cell inclusion not re-audited. All annotated-guide cells; 27142 missing guide labels excluded. Control expression filter uses all samples for description only.','input_sha256':hashlib.sha256((P/'pseudobulk.npz').read_bytes()).hexdigest()}
 (P/'results.json').write_text(json.dumps(out,indent=2,allow_nan=False)+'\n');print(json.dumps({k:{'genes':v['genes_before_target_exclusion'],'pairs':v['n_pairs'],'metrics':v['mean_metrics']} for k,v in results.items()},indent=2));print('unresolved targets',missing)
if __name__=='__main__':main()
