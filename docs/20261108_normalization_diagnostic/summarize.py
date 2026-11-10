from pathlib import Path
import json,numpy as np
p=Path(__file__).resolve().parent
old=p.parent/'20261107_spark_immune_status/update_count_diagnostic'
a=np.load(p/'split_indices.npz');b=np.load(old/'split_indices.npz')
for key in b.files:np.testing.assert_array_equal(a[key],b[key])
for seed in range(3):
 for fold in range(3):
  stem=f's{seed}_f{fold}'
  train=a[stem+'_normalization_fit'];test=a[stem+'_test'];labelled=a[stem+'_labelled']
  assert not set(train)&set(test) and set(labelled)<=set(train)
  assert len(train)+len(test)==15000
z=np.load(p/'predictions.npz');base=np.load(old/'predictions.npz')
np.testing.assert_array_equal(z['y'],base['y']);np.testing.assert_array_equal(z['grp'],base['grp'])
for k in z.files:
 if k not in ['y','grp']:assert z[k].shape==(15000,) and np.isfinite(z[k]).all() and ((z[k]>=0)&(z[k]<=1)).all()
rows=[]
for source,path in [('labelled-only',old),('all-training-features',p)]:
 d=json.loads((path/'results.json').read_text());assert len(d['results'])==12
 for arm in ['pretrained','scratch']:
  for mode in ['fixed_epochs','matched_full_label_updates']:
   v=[r for r in d['results'] if r['key'].startswith(arm+'__') and r['key'].endswith('__'+mode)]
   vals={m:[r[m] for r in v] for m in ['auroc','auprc']}
   row=dict(normalization=source,arm=arm,mode=mode,**{m:float(np.mean(v)) for m,v in vals.items()},**{m+'_sd':float(np.std(v,ddof=1)) for m,v in vals.items()})
   rows.append(row);print(row)
(p/'comparison.json').write_text(json.dumps(rows,indent=2))
print('Split equality, held-out exclusion, label equality, and finite prediction checks passed.')
