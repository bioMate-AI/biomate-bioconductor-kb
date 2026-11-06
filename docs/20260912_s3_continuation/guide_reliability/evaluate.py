"""Descriptive guide agreement; disjoint control pools are not independent donors."""
import hashlib,json
from pathlib import Path
import numpy as np
from scipy.stats import spearmanr
ROOT=Path(__file__).resolve().parent.parent
OUT=Path(__file__).resolve().parent

def load(name):
    with np.load(ROOT/name,allow_pickle=False) as z:return {k:z[k] for k in z.files}
def norm(c,l):
    c=np.asarray(c,dtype=np.float64);l=np.asarray(l,dtype=np.float64)
    if not np.isfinite(c).all() or not np.isfinite(l).all() or (c<0).any() or (l<=0).any() or (c.sum(-1)>l).any():raise ValueError('invalid counts/library')
    return np.log1p(c/l[...,None]*10000)
def metrics(a,b):
    if a.shape!=b.shape or not np.isfinite(a).all() or not np.isfinite(b).all():raise ValueError('invalid paired vectors')
    valid=np.ptp(a)>1e-12 and np.ptp(b)>1e-12
    return {'mse':float(np.mean((a-b)**2)),'pearson':float(np.corrcoef(a,b)[0,1]) if valid else None,'spearman':float(spearmanr(a,b).statistic) if valid else None,'cosine':float(a@b/(np.linalg.norm(a)*np.linalg.norm(b))) if np.linalg.norm(a)*np.linalg.norm(b)>1e-12 else None}
def main():
    t=load('target_state_data/targets.npz');c=load('baseline_state_data/controls.npz');a=load('baseline_state_data/baseline_aggregates.npz')
    for d in [t,c,a]:
        assert len(set(d['gene_symbols']))==len(d['gene_symbols'])
        np.testing.assert_array_equal(t['gene_symbols'],d['gene_symbols'])
    assert len(set(t['_index']))==len(t['_index'])
    assert set(c['guide_id'][c['pool']=='feature']).isdisjoint(set(c['guide_id'][c['pool']=='reference']))
    lookup={}
    for i in range(len(a['counts'])):
        key=tuple(str(a[k][i]) for k in ['donor','condition','pool']);assert key not in lookup
        m=(c['donor_id']==key[0])&(c['culture_condition']==key[1])&(c['pool']==key[2]);assert m.any()
        np.testing.assert_array_equal(c['counts'][m].sum(0),a['counts'][i]);assert c['library_counts'][m].sum()==a['library_counts'][i]
        lookup[key]=norm(a['counts'][i],a['library_counts'][i])
    x=norm(t['counts'],t['library_counts']);rows=[];effect_arrays=[]
    for target in sorted(set(t['perturbed_gene_name'])):
      guides=sorted(set(t['guide_id'][t['perturbed_gene_name']==target]));assert len(guides)==2
      for donor in sorted(set(t['donor_id'])):
       for condition in sorted(set(t['culture_condition'])):
        indices=[]
        for guide in guides:
            ix=np.flatnonzero((t['perturbed_gene_name']==target)&(t['donor_id']==donor)&(t['culture_condition']==condition)&(t['guide_id']==guide));assert len(ix)==1;indices.append(int(ix[0]))
        keep=t['gene_symbols']!=target;u,v=x[indices][:,keep];f=lookup[(donor,condition,'feature')][keep];r=lookup[(donor,condition,'reference')][keep]
        ef1,ef2,er1,er2=u-f,v-f,u-r,v-r
        # Independent scalar-loop MSE checks, and shared-reference cancellation identity.
        for p,q in [(u,v),(ef1,ef2),(er1,er2),(ef1,er2),(er1,ef2)]:
            np.testing.assert_allclose(metrics(p,q)['mse'],sum((float(i)-float(j))**2 for i,j in zip(p,q))/len(p),rtol=1e-12,atol=1e-14)
        np.testing.assert_allclose(ef1-ef2,u-v,atol=2e-15)
        row={'target':str(target),'donor':str(donor),'condition':str(condition),'guides':guides,'readouts':int(keep.sum()),'perturbed_readout_excluded':bool((~keep).any()),'profile':metrics(u,v),'shared_feature_reference':metrics(ef1,ef2),'shared_reference_reference':metrics(er1,er2),'disjoint_forward':metrics(ef1,er2),'disjoint_swapped':metrics(er1,ef2),'control_pool_difference_mse':float(np.mean((f-r)**2)), 'average_effect_squared':float(np.mean(np.concatenate([ef1,ef2,er1,er2])**2))}
        rows.append(row)
    names=['profile','shared_feature_reference','shared_reference_reference','disjoint_forward','disjoint_swapped']
    def summarize(rs):
        return {name:{metric:float(np.mean([row[name][metric] for row in rs if row[name][metric] is not None])) for metric in ['mse','pearson','spearman','cosine']} for name in names}
    result={'protocol':{'transform':'log1p(10000 * raw counts / full 18129-gene library)', 'unit':'one target x donor x condition, equal weight; 2 individual guide profiles','selection':'previously selected 16-target pilot; not prospective','excluded':'perturbed gene excluded wherever present in frozen 132-gene panel','reference_design':'feature and reference controls use globally disjoint guides, same donor/condition; orientation swapped','inference':'descriptive only; shared donors/controls/targets make 192 rows dependent; no confidence interval or p-value'},'n_pairs':len(rows),'targets':len(set(t['perturbed_gene_name'])),'mean_metrics':summarize(rows),'by_donor':{str(d):summarize([r for r in rows if r['donor']==d]) for d in sorted(set(t['donor_id']))},'by_target':{str(g):summarize([r for r in rows if r['target']==g]) for g in sorted(set(t['perturbed_gene_name']))},'mean_control_pool_difference_mse':float(np.mean([r['control_pool_difference_mse'] for r in rows])),'mean_average_effect_squared':float(np.mean([r['average_effect_squared'] for r in rows])),'rows':rows,'verification':{'raw_control_aggregates_recomputed':True,'control_guides_disjoint':True,'scalar_loop_mse_checks':len(rows)*5,'shared_reference_difference_identity_checks':len(rows)},'input_sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ['target_state_data/targets.npz','baseline_state_data/controls.npz','baseline_state_data/baseline_aggregates.npz']},'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (OUT/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n');print(json.dumps({k:v for k,v in result.items() if k in ['mean_metrics','mean_control_pool_difference_mse','mean_average_effect_squared','n_pairs']},indent=2))
if __name__=='__main__':main()
