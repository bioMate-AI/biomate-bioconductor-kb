"""Independent raw-pseudobulk reconstruction of guide and donor-transfer metrics."""
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr, spearmanr
P=Path(__file__).resolve().parent

def normalized(counts):
    counts=np.asarray(counts,dtype=np.float64)
    return np.log1p(counts/counts.sum()*10000)

def metrics(a,b):
    valid=np.ptp(a)>0 and np.ptp(b)>0
    return {'mse':float(sum((float(x)-float(y))**2 for x,y in zip(a,b))/len(a)), 'pearson':float(pearsonr(a,b).statistic) if valid else None,'spearman':float(spearmanr(a,b).statistic) if valid else None}

checks=0

def compare(actual,expected):
    global checks
    for key,value in expected.items():
        if value is None: assert actual[key] is None
        else: np.testing.assert_allclose(actual[key],value,rtol=1e-10,atol=1e-12)
        checks+=1

def summary(rows,field):
    result={}
    for arm in rows[0][field]:
        result[arm]={}
        for metric in ['pearson','spearman','mse']:
            values=[row[field][arm][metric] for row in rows if row[field][arm][metric] is not None]
            result[arm][metric]=sum(values)/len(values) if values else None
    return result

def check_summary(actual, rows, field):
    for arm, values in summary(rows,field).items():compare(actual[arm],values)

with np.load(P/'pseudobulk.npz',allow_pickle=False) as z:d=dict(z)
r=json.loads((P/'results.json').read_text());tr=json.loads((P/'donor_transfer.json').read_text())
assert r['input_sha256']==tr['input_sha256']==hashlib.sha256((P/'pseudobulk.npz').read_bytes()).hexdigest()
np.testing.assert_array_equal(d['counts'].sum(axis=1),d['library_counts'])
assert np.isfinite(d['counts']).all() and (d['counts']>=0).all()
genes=d['gene_symbols'];donors=sorted(set(d['donor_id']));conditions=sorted(set(d['culture_condition']))
alltargets=sorted(set(d['target'])-{'NonTarget'});targets=[t for t in alltargets if t in genes]
assert r['excluded_targets_unresolved_gene_mapping']==[str(t) for t in alltargets if t not in genes]
control_guides=set(d['guide_id'][d['target']=='NonTarget'])
ordered=sorted(control_guides,key=lambda g:hashlib.sha256(('external-control-split-20260912:'+str(g)).encode()).hexdigest())
assignment={str(g):('feature' if i%2==0 else 'reference') for i,g in enumerate(ordered)}
assert assignment==r['control_guide_assignment'] and len(ordered)==8
assert len({g for g,pool in assignment.items() if pool=='feature'})==4
refs={};cpms=[];effects={};groups={}
for donor in donors:
 for condition in conditions:
  ctrl=[i for i,t in enumerate(d['target']) if t=='NonTarget' and d['donor_id'][i]==donor and d['culture_condition'][i]==condition]
  assert len(ctrl)==8 and set(d['guide_id'][ctrl])==control_guides
  counts=d['counts'][ctrl].sum(0);cpms.append(counts/counts.sum()*1e6)
  baseline=normalized(counts)
  for pool in ['feature','reference']:
   ids=[i for i in ctrl if assignment[str(d['guide_id'][i])]==pool]
   assert len(ids)==4
   refs[donor,condition,pool]=normalized(d['counts'][ids].sum(0))
  for target in targets:
   ids=[i for i,t in enumerate(d['target']) if t==target and d['donor_id'][i]==donor and d['culture_condition'][i]==condition]
   assert len(ids)==2 and len(set(d['guide_id'][ids]))==2
   ids.sort(key=lambda i:d['guide_id'][i]);groups[target,donor,condition]=ids
   effects[donor,condition,target]=normalized(d['counts'][ids].sum(0))-baseline
panels={'all_genes':np.ones(len(genes),bool),'control_expressed':np.count_nonzero(np.array(cpms)>=1,axis=0)>=2}
for panel,data in r['panels'].items():
 assert data['genes_before_target_exclusion']==int(panels[panel].sum())
 assert data['n_pairs']==len(groups)==len(data['rows'])
 seen=set()
 for row in data['rows']:
  key=row['target'],row['donor'],row['condition'];assert key not in seen;seen.add(key)
  ids=groups[key];keep=panels[panel] & (genes!=row['target'])
  assert row['readouts']==keep.sum() and row['minimum_cells']==min(d['n_cells'][ids])
  u,v=[normalized(d['counts'][i])[keep] for i in ids]
  f=refs[key[1],key[2],'feature'][keep];ref=refs[key[1],key[2],'reference'][keep]
  arms={'profile':(u,v),'shared_feature_reference':(u-f,v-f),'shared_reference_reference':(u-ref,v-ref),'disjoint_forward':(u-f,v-ref),'disjoint_swapped':(u-ref,v-f)}
  row['_verified']={arm:metrics(*pair) for arm,pair in arms.items()}
  for arm,values in row['_verified'].items():compare(row[arm],values)
 check_summary(data['mean_metrics'],data['rows'],'_verified')
 for donor in donors:check_summary(data['by_donor'][donor],[row for row in data['rows'] if row['donor']==donor],'_verified')
 for cond in conditions:check_summary(data['by_condition'][cond],[row for row in data['rows'] if row['condition']==cond],'_verified')
 for threshold,sub in data['support_sensitivity'].items():
  selected=[row for row in data['rows'] if min(d['n_cells'][groups[row['target'],row['donor'],row['condition']]])>=int(threshold)]
  assert sub['pairs']==len(selected)
  if selected:check_summary(sub['metrics'],selected,'_verified')
  else:assert all(v is None for a in sub['metrics'].values() for v in a.values())
assert len(donors)==2 and tr['n_rows']==len(targets)*len(donors)*len(conditions)==len(tr['rows'])
seen=set()
for row in tr['rows']:
 donor,train,condition,target=(row[k] for k in ['test_donor','train_donor','condition','target'])
 assert train!=donor and {train,donor}==set(donors)
 key=donor,condition,target;assert key not in seen;seen.add(key)
 mismatch=targets[(targets.index(target)+1)%len(targets)];assert row['mismatched_target']==mismatch and mismatch!=target
 keep=np.array([g!=target and g!=mismatch for g in genes]);assert row['readouts']==sum(keep)
 mean=np.array([sum(effects[train,condition,t][j] for t in targets if t!=g)/sum(t!=g for t in targets) for j,g in enumerate(genes)])
 truth=effects[donor,condition,target][keep]
 arms={'no_change':np.zeros(sum(keep)),'condition_mean':mean[keep],'matched_observed_target':effects[train,condition,target][keep],'cyclic_mismatched_target':effects[train,condition,mismatch][keep]}
 row['_verified']={arm:metrics(pred,truth) for arm,pred in arms.items()}
 for arm,values in row['_verified'].items():compare(row['metrics'][arm],values)
check_summary(tr['mean_metrics'],tr['rows'],'_verified')
for donor in donors:check_summary(tr['by_test_donor'][donor],[row for row in tr['rows'] if row['test_donor']==donor],'_verified')
out={'status':'passed','numeric_metrics_and_summaries_checked':checks,'guide_pairs_per_panel':len(groups),'donor_transfer_rows':len(tr['rows']),'control_split':'Recreated SHA256 assignment; 8 unique guides, 4 per pool in every donor/condition','gene_exclusion':'Every guide metric excludes direct target; every donor-transfer arm excludes both true and mismatched target','condition_mean':'Rebuilt per gene while excluding source rows directly perturbing that gene','pseudobulk_sha256':r['input_sha256']}
(P/'independent_verification.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
