"""Descriptive cell support for frozen guide pairs, no label-based filtering."""
import json
from pathlib import Path
import numpy as np
from scipy.stats import spearmanr
P=Path(__file__).resolve().parent
with np.load(P.parent/'target_state_data/targets.npz',allow_pickle=False) as z:t={k:z[k] for k in z.files}
r=json.loads((P.parent/'guide_reliability/results.json').read_text());rows=[]
for pair in r['rows']:
 ix=np.flatnonzero((t['perturbed_gene_name']==pair['target'])&(t['donor_id']==pair['donor'])&(t['culture_condition']==pair['condition']));assert len(ix)==2
 cells=t['n_cells'][ix].astype(float);libs=t['library_counts'][ix].astype(float)
 rows.append({'target':pair['target'],'donor':pair['donor'],'condition':pair['condition'],'minimum_cells':float(cells.min()),'cell_ratio':float(cells.max()/cells.min()),'minimum_library':float(libs.min()),'disjoint_pearson':float(np.mean([pair[n]['pearson'] for n in ['disjoint_forward','disjoint_swapped']]))})
result={'pairs':len(rows),'cell_support':{k:{'min':float(np.min([r[k] for r in rows])),'median':float(np.median([r[k] for r in rows])),'max':float(np.max([r[k] for r in rows]))} for k in ['minimum_cells','cell_ratio','minimum_library']},'descriptive_spearman_with_guide_agreement':{k:float(spearmanr([r[k] for r in rows],[r['disjoint_pearson'] for r in rows]).statistic) for k in ['minimum_cells','cell_ratio','minimum_library']},'caveat':'Original132 panel; repeated donors/targets, confounded observational associations; no p-values, causal attribution, or filtering decisions','rows':rows}
(P/'guide_support.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='rows'},indent=2))
