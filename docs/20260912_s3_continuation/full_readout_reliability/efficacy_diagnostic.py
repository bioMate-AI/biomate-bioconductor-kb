"""Direct-target normalized expression diagnostic; never filters downstream labels."""
import json
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent
with np.load(P/'targets.npz',allow_pickle=False) as z:t={k:z[k] for k in z.files}
with np.load(P/'controls.npz',allow_pickle=False) as z:c={k:z[k] for k in z.files}
np.testing.assert_array_equal(t['gene_symbols'],c['gene_symbols']);rows=[]
for i in range(len(t['counts'])):
 gene=t['perturbed_gene_name'][i];g=np.flatnonzero(t['gene_symbols']==gene);assert len(g)==1;g=int(g[0])
 group=(c['donor_id']==t['donor_id'][i])&(c['culture_condition']==t['culture_condition'][i])
 value=float(t['counts'][i,g]/t['library_counts'][i]*1e6);ratios={}
 for pool in ['feature','reference']:
  ix=group&(c['pool']==pool);base=float(c['counts'][ix,g].sum()/c['library_counts'][ix].sum()*1e6)
  ratios[pool]=value/base if base>0 else None
 rows.append({'target':str(gene),'guide':str(t['guide_id'][i]),'donor':str(t['donor_id'][i]),'condition':str(t['culture_condition'][i]),'target_cpm':value,'target_to_control_ratio':ratios,'both_references_measurable':all(v is not None for v in ratios.values()),'lower_than_both_references':all(v is not None and v<1 for v in ratios.values())})
def summary(rr):return {'profiles':len(rr),'both_references_measurable':sum(r['both_references_measurable'] for r in rr),'lower_than_both_references':sum(r['lower_than_both_references'] for r in rr),'undefined_reference_ratios':sum(v is None for r in rr for v in r['target_to_control_ratio'].values()),'median_ratio':{p:float(np.median([r['target_to_control_ratio'][p] for r in rr if r['target_to_control_ratio'][p] is not None])) for p in ['feature','reference']}}
out={'overall':summary(rows),'by_target':{g:summary([r for r in rows if r['target']==g]) for g in sorted(set(t['perturbed_gene_name']))},'rows':rows,'caveat':'Descriptive relative abundance, not causal knockdown efficacy or significance; selected source guides, donor/condition controls, compositional normalization; no filtering or training selection'}
(P/'efficacy_diagnostic.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out['overall'],indent=2))
