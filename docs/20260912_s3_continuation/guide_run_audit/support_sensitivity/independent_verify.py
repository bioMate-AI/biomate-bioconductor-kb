"""Independently rebuild eligibility and correlations from native count arrays."""
import json
from collections import defaultdict, Counter
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr, spearmanr
P = Path(__file__).resolve().parent
S = P.parent.parent / 'full_readout_reliability'
r = json.loads((P / 'results.json').read_text())
with np.load(S/'targets.npz') as z: t = dict(z)
with np.load(S/'controls.npz') as z: c = dict(z)
np.testing.assert_array_equal(t['gene_symbols'], c['gene_symbols'])
assert set(c['guide_id'][c['pool']=='feature']).isdisjoint(set(c['guide_id'][c['pool']=='reference']))
groups = defaultdict(list)
for i in range(len(t['counts'])):
    groups[tuple(str(t[f][i]) for f in ['perturbed_gene_name','donor_id','culture_condition'])].append(i)
refs = {}; cpms = []
for d in set(c['donor_id']):
    for cond in set(c['culture_condition']):
        ids = [i for i in range(len(c['counts'])) if c['donor_id'][i] == d and c['culture_condition'][i] == cond]
        cpms.append(c['counts'][ids].sum(axis=0).astype(float) * 1e6 / c['library_counts'][ids].sum())
        for pool in ['feature','reference']:
            j = [i for i in ids if c['pool'][i] == pool]
            refs[d,cond,pool] = np.log1p(c['counts'][j].sum(axis=0).astype(float)/c['library_counts'][j].sum()*10000)
mask = {'all_genes': np.ones(len(t['gene_symbols']),bool), 'control_expressed': np.count_nonzero(np.array(cpms)>=1, axis=0)>=6}
cache = {}
checks = 0
for key, ids in groups.items():
    assert len(ids)==2 and len(set(t['guide_id'][ids]))==2
    ids = sorted(ids,key=lambda i:t['guide_id'][i])
    a,b = [np.log1p(t['counts'][i].astype(float)/t['library_counts'][i]*10000) for i in ids]
    for panel, keep in mask.items():
        k = keep & (t['gene_symbols']!=key[0])
        f = refs[key[1],key[2],'feature']; ref = refs[key[1],key[2],'reference']
        for orientation,x,y in [('disjoint_forward',a-f,b-ref),('disjoint_swapped',a-ref,b-f)]:
            cache[key,panel,orientation] = {'pearson':float(pearsonr(x[k],y[k]).statistic),'spearman':float(spearmanr(x[k],y[k]).statistic)}
for threshold, result in r['thresholds'].items():
    eligible = {key for key,ids in groups.items() if all(t['n_cells'][i]>=int(threshold) for i in ids)}
    cov = result['coverage']
    assert cov['pairs']==len(eligible) and cov['profiles']==2*len(eligible)
    for axis,name in enumerate(['target','donor','condition']):
        counter=Counter(k[axis] for k in eligible)
        assert cov[name+'s']==len(counter)
        assert cov['by_'+name]=={v:counter[v] for v in {k[axis] for k in groups}}
    assert cov['complete_targets_all_12_groups']==sum(v==12 for v in cov['by_target'].values())
    for panel, data in result['panels'].items():
        assert data['genes_before_target_exclusion']==int(mask[panel].sum())
        assert {(row['target'],row['donor'],row['condition']) for row in data['rows']}==eligible
        assert len(data['rows'])==len(eligible)
        for row in data['rows']:
            key=(row['target'],row['donor'],row['condition'])
            assert sorted(row['support']['cells'])==sorted(t['n_cells'][groups[key]].tolist())
            assert row['support']['minimum_cells']==int(min(t['n_cells'][groups[key]]))
            for orientation in ['disjoint_forward','disjoint_swapped']:
                for metric in ['pearson','spearman']:
                    np.testing.assert_allclose(row[orientation][metric],cache[key,panel,orientation][metric],rtol=1e-10,atol=1e-12)
                    checks+=1
        for orientation in ['disjoint_forward','disjoint_swapped']:
            for metric in ['pearson','spearman']:
                expected=sum(cache[key,panel,orientation][metric] for key in eligible)/len(eligible)
                np.testing.assert_allclose(data['mean_metrics'][orientation][metric]['mean'],expected,rtol=1e-10,atol=1e-12)
                assert data['mean_metrics'][orientation][metric]['valid_pairs']==len(eligible)
(P/'verification.json').write_text(json.dumps({'status':'passed','independent_raw_correlations':len(cache)*2,'filtered_row_metric_comparisons':checks,'independent_coverage_checks':'all thresholds and target/donor/condition counts','summary_metrics_checked':40},indent=2)+'\n')
print((P/'verification.json').read_text())
