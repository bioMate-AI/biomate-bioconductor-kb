"""Frozen-panel and genome-wide metadata eligibility audit."""
import json,hashlib,collections
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent
with np.load(P/'metadata.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
with np.load(P.parent/'target_state_data/targets.npz',allow_pickle=False) as z:t={k:z[k] for k in z.files}
with np.load(P.parent/'baseline_state_data/controls.npz',allow_pickle=False) as z:c={k:z[k] for k in z.files}
qc=d['keep_min_cells']&d['keep_total_counts'];targeting=d['guide_type']=='targeting'
counts=collections.Counter(zip(d['donor_id'],d['10xrun_id'],d['culture_condition']))
keys=list(zip(d['guide_id'],d['donor_id'],d['culture_condition']));duplicates=sum(n-1 for n in collections.Counter(keys).values() if n>1)
rows=[]
for gene in sorted(set(t['perturbed_gene_name'])):
 ix=np.flatnonzero(targeting&(d['perturbed_gene_name']==gene));guides=sorted(set(d['guide_id'][ix]));details=[]
 for guide in guides:
  gi=ix[d['guide_id'][ix]==guide]
  details.append({'guide':str(guide),'profiles':len(gi),'basic_qc':int(qc[gi].sum()),'DE_eligible':int(d['keep_for_DE'][gi].sum()),'basic_qc_but_not_DE':int((qc[gi]&~d['keep_for_DE'][gi]).sum()),'runs':sorted(set(d['10xrun_id'][gi])),'min_cells':float(d['n_cells'][gi].min()),'median_cells':float(np.median(d['n_cells'][gi]))})
 rows.append({'target':str(gene),'guides':details,'extra_guide_count':len(set(guides)-set(t['guide_id'][t['perturbed_gene_name']==gene]))})
composition={}
for label,data in [('targets',t),('controls',c)]:
 sr=data['source_rows'];np.testing.assert_array_equal(d['_index'][sr],data['_index'])
 composition[label]=[{'donor':str(a),'run':str(b),'condition':str(cc),'profiles':n} for (a,b,cc),n in sorted(collections.Counter(zip(d['donor_id'][sr],d['10xrun_id'][sr],d['culture_condition'][sr])).items())]
# Count possible targets with >=2 basic-QC-complete guides, no efficacy filter.
coverage=collections.defaultdict(set)
for i in np.flatnonzero(targeting&qc):coverage[(d['perturbed_gene_name'][i],d['guide_id'][i])].add((d['donor_id'][i],d['culture_condition'][i]))
complete=collections.defaultdict(list)
for (gene,guide),groups in coverage.items():
 if len(groups)==12:complete[gene].append(guide)
result={'source_rows':len(keys),'duplicate_guide_donor_condition_rows':duplicates,'source_donor_run_condition_counts':[{'donor':str(a),'run':str(b),'condition':str(cc),'profiles':n} for (a,b,cc),n in sorted(counts.items())],'frozen_panel':rows,'frozen_composition':composition,'basic_QC_complete_targets_with_2_guides':sum(len(gs)>=2 for gs in complete.values()),'basic_QC_complete_targets_with_3_guides':sum(len(gs)>=3 for gs in complete.values()),'source_guides_per_target_histogram':dict(collections.Counter(len(set(d['guide_id'][targeting&(d['perturbed_gene_name']==gene)])) for gene in [])),'metadata_sha256':hashlib.sha256((P/'metadata.npz').read_bytes()).hexdigest()}
# Avoid O(targets*profiles) scan.
guides_by_target=collections.defaultdict(set)
for g,guide in zip(d['perturbed_gene_name'][targeting],d['guide_id'][targeting]):guides_by_target[g].add(guide)
result['source_guides_per_target_histogram']=dict(sorted(collections.Counter(len(gs) for gs in guides_by_target.values()).items()))
(P/'results.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['frozen_panel','frozen_composition']},indent=2));print('extra frozen guides',sum(r['extra_guide_count'] for r in rows))
