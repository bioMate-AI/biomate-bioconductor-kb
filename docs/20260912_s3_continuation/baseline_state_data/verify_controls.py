import json,hashlib
from pathlib import Path
import numpy as np
p=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/baseline_state_data');d=np.load(p/'controls.npz',allow_pickle=False);a=np.load(p/'baseline_aggregates.npz',allow_pickle=False)
assert np.isfinite(d['counts']).all() and (d['counts']>=0).all() and d['counts'].dtype.kind=='i'
assert len(set(d['_index']))==len(d['_index']);assert set(d['guide_id'][d['pool']=='feature']).isdisjoint(set(d['guide_id'][d['pool']=='reference']))
assert len(a['counts'])==24
for j in range(24):
 mask=(d['donor_id']==a['donor'][j])&(d['culture_condition']==a['condition'][j])&(d['pool']==a['pool'][j]);assert mask.any();np.testing.assert_array_equal(a['counts'][j],d['counts'][mask].sum(0));assert a['library_counts'][j]==d['library_counts'][mask].sum();assert a['n_cells'][j]==d['n_cells'][mask].sum()
assert np.all(d['library_counts']>=d['counts'].sum(1));assert (d['n_cells']>0).all()
r={'profiles':len(d['counts']),'genes':len(d['gene_symbols']),'aggregate_groups':24,'guide_pool_disjoint':True,'aggregates_recomputed_exactly':True,'positive_n_cells':True,'minimum_group_profiles':min(int(((d['donor_id']==a['donor'][j])&(d['culture_condition']==a['condition'][j])&(d['pool']==a['pool'][j])).sum()) for j in range(24))}
(p/'verification.json').write_text(json.dumps(r,indent=2));print(json.dumps(r))
