"""Independent saved-metric reconstruction using scipy Pearson and explicit tie ranks."""
import json
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr
P=Path(__file__).resolve().parent;R=P.parent
T=np.load(R/'target_state_data/targets.npz',allow_pickle=False)
C=np.load(R/'baseline_state_data/controls.npz',allow_pickle=False)
def ranks(x):
    order=np.argsort(x,kind='stable');out=np.zeros(len(x));i=0
    while i<len(x):
        j=i+1
        while j<len(x) and x[order[j]]==x[order[i]]:j+=1
        out[order[i:j]]=(i+j-1)/2+1;i=j
    return out
def expression(counts,library):return np.log(1+10000*np.asarray(counts,dtype=float)/float(library))
checks=0
for row in json.loads((P/'results.json').read_text())['rows']:
    keep=T['gene_symbols']!=row['target'];xx=[]
    for guide in row['guides']:
        m=(T['guide_id']==guide)&(T['donor_id']==row['donor'])&(T['culture_condition']==row['condition']);ix=np.flatnonzero(m);assert len(ix)==1
        xx.append(expression(T['counts'][ix[0]],T['library_counts'][ix[0]])[keep])
    controls=[]
    for pool in ['feature','reference']:
        m=(C['donor_id']==row['donor'])&(C['culture_condition']==row['condition'])&(C['pool']==pool)
        controls.append(expression(C['counts'][m].sum(0),C['library_counts'][m].sum())[keep])
    u,v=xx;f,r=controls
    for name,(a,b) in {'profile':(u,v),'shared_feature_reference':(u-f,v-f),'shared_reference_reference':(u-r,v-r),'disjoint_forward':(u-f,v-r),'disjoint_swapped':(u-r,v-f)}.items():
        np.testing.assert_allclose(float(pearsonr(a,b).statistic),row[name]['pearson'],atol=1e-12)
        np.testing.assert_allclose(float(pearsonr(ranks(a),ranks(b)).statistic),row[name]['spearman'],atol=1e-12);checks+=2
out={'pearson_and_spearman_values_independently_recomputed':checks,'source':'individual raw control counts, not saved aggregates; explicit tie ranks; log instead of log1p','passed':True}
(P/'verification.json').write_text(json.dumps(out,indent=2)+'\n');print(out)
