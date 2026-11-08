from pathlib import Path
import numpy as np,pandas as pd,json,hashlib
p=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation'); a=p/'guide_run_audit'
with np.load(a/'metadata.npz',allow_pickle=False) as z:df=pd.DataFrame({k:z[k] for k in z.files})
r=json.loads((a/'results.json').read_text())
assert df.groupby(['donor_id','culture_condition'])['10xrun_id'].nunique().eq(1).all()
assert len(df.groupby(['donor_id','culture_condition']))==12
assert not df.duplicated(['donor_id','culture_condition','guide_id']).any()
t=df[df.guide_type.eq('targeting')]
h=t.groupby('perturbed_gene_name').guide_id.nunique().value_counts().sort_index()
assert {str(k):int(v) for k,v in h.items()}==r['source_guides_per_target_histogram']
qc=t[t.keep_min_cells & t.keep_total_counts]
n=qc.groupby(['perturbed_gene_name','guide_id']).apply(lambda x:len(x[['donor_id','culture_condition']].drop_duplicates()),include_groups=False)
complete=n[n.eq(12)].groupby(level=0).size()
assert int(complete.ge(2).sum())==r['basic_QC_complete_targets_with_2_guides']
assert int(complete.ge(3).sum())==r['basic_QC_complete_targets_with_3_guides']
for target in r['frozen_panel']:
 f=t[t.perturbed_gene_name.eq(target['target'])]
 assert f.guide_id.nunique()-2==target['extra_guide_count']
 for g in target['guides']:
  x=f[f.guide_id.eq(g['guide'])]; q=x.keep_min_cells & x.keep_total_counts
  assert len(x)==g['profiles'] and int(q.sum())==g['basic_qc'] and int(x.keep_for_DE.sum())==g['DE_eligible']
  assert int((q & ~x.keep_for_DE).sum())==g['basic_qc_but_not_DE']
with np.load('/Users/kky/biomate-audit-fix/out/20260911_h1_perturbation_pilot/prepared.npz') as z:excluded=set(z['targets'])
order=lambda x:hashlib.sha256(('basic-qc-expansion-20260912:'+x).encode()).hexdigest()
chosen=sorted(set(complete[complete.ge(2)].index)-excluded,key=order)[:16]
selected={g:sorted([guide for gene,guide in n[n.eq(12)].index if gene==g],key=order)[:2] for g in chosen}
s=json.loads((p/'basic_qc_panel/selection.json').read_text());assert selected==s['targets']
rows=qc.index[[g in selected and v in selected[g] for g,v in zip(qc.perturbed_gene_name,qc.guide_id)]].sort_values().tolist()
assert rows==s['rows'] and len(rows)==384
assert len(set(complete[complete.ge(2)].index)-excluded)==s['eligible_targets']
out={'status':'passed','donor_condition_groups':12,'runs_per_donor_condition':1,'existing_donor_condition_control_matching_already_matches_run':True,'duplicate_guide_donor_condition_rows':0,'source_guides_per_target_histogram':{str(k):int(v) for k,v in h.items()},'basic_qc_complete_2guide_targets':int(complete.ge(2).sum()),'basic_qc_complete_3guide_targets':int(complete.ge(3).sum()),'frozen_32_guide_counts_verified':True,'basic_qc_selection_independently_recomputed':True,'basic_qc_selected_targets':chosen,'basic_qc_selected_rows':len(rows),'basic_qc_selected_outside_previous_panel':True,'basic_qc_selection_uses_no_efficacy_or_expression':True,'limitation':'Metadata and selection verification only; newly extracted counts are not checked here.'}
(a/'verification.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
