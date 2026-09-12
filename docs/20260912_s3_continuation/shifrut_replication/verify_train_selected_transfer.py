"""Independent per-gene selection and raw-count transfer reconstruction."""
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr, spearmanr
P=Path(__file__).resolve().parent
with np.load(P/'pseudobulk.npz',allow_pickle=False) as z:d=dict(z)
r=json.loads((P/'train_selected_transfer.json').read_text())
assert r['input_sha256']==hashlib.sha256((P/'pseudobulk.npz').read_bytes()).hexdigest()
genes=d['gene_symbols'];targets=sorted(set(d['target'])-{'NonTarget'});assert all(t in genes for t in targets)
donors=sorted(set(d['donor_id']));conditions=sorted(set(d['culture_condition']));assert len(donors)==2

def norm(counts):
    x=np.asarray(counts,dtype=float)
    return np.log1p(x/x.sum()*10000)

def reconstruct_training(donor,condition):
    # Only this donor/condition's rows are read during selection reconstruction.
    ids=[i for i in range(len(d['counts'])) if d['donor_id'][i]==donor and d['culture_condition'][i]==condition]
    ctrl=[i for i in ids if d['target'][i]=='NonTarget'];assert len(ctrl)==8
    counts=d['counts'][ctrl].sum(0);baseline=norm(counts)
    cpm=1e6*counts/counts.sum()
    effects={}
    for target in targets:
        ix=[i for i in ids if d['target'][i]==target];assert len(ix)==2
        effects[target]=norm(d['counts'][ix].sum(0))-baseline
    means=[];variances=[]
    for j,gene in enumerate(genes):
        values=np.array([effects[t][j] for t in targets if t!=gene])
        means.append(np.mean(values));variances.append(np.var(values,ddof=0))
    eligible=[j for j in range(len(genes)) if cpm[j]>=1 and np.isfinite(variances[j])]
    ranked=sorted(eligible,key=lambda j:(-variances[j],str(genes[j])))
    return ranked,np.array(means),effects

cache={(donor,cond):reconstruct_training(donor,cond) for donor in donors for cond in conditions}
selections={}
assert len(r['selections'])==8
for item in r['selections']:
    test,train,condition,k=[item[x] for x in ['test_donor','train_donor','condition','k']]
    assert train!=test and {train,test}==set(donors) and k in [128,512]
    ranked,_,_=cache[train,condition];chosen=ranked[:k]
    assert item['genes']==genes[chosen].tolist()
    key=test,condition,k;assert key not in selections;selections[key]=chosen

checks=0

def compare(a,b):
    global checks
    for metric,value in b.items():
        if value is None:assert a[metric] is None
        else:np.testing.assert_allclose(a[metric],value,rtol=1e-10,atol=1e-12)
        checks+=1

seen=set()
for row in r['rows']:
    test,train,condition,k,target=[row[x] for x in ['test_donor','train_donor','condition','k','target']]
    assert test!=train and {test,train}==set(donors)
    key=test,condition,k,target;assert key not in seen;seen.add(key)
    mismatch=targets[(targets.index(target)+1)%len(targets)];assert row['mismatched_target']==mismatch and target!=mismatch
    chosen=selections[test,condition,k];keep=[j for j in chosen if genes[j] not in [target,mismatch]]
    assert row['readouts']==len(keep)
    _,mean,train_effects=cache[train,condition];test_effects=cache[test,condition][2]
    truth=test_effects[target][keep]
    predictions={'no_change':np.zeros(len(keep)),'condition_mean':mean[keep],'matched_observed_target':train_effects[target][keep],'cyclic_mismatched_target':train_effects[mismatch][keep]}
    row['_verified']={}
    for arm,pred in predictions.items():
        valid=np.ptp(pred)>0 and np.ptp(truth)>0
        values={'mse':sum((float(a)-float(b))**2 for a,b in zip(pred,truth))/len(truth),'pearson':float(pearsonr(pred,truth).statistic) if valid else None,'spearman':float(spearmanr(pred,truth).statistic) if valid else None}
        compare(row['metrics'][arm],values);row['_verified'][arm]=values
assert len(seen)==len(targets)*len(donors)*len(conditions)*2

def summary_check(actual,rows):
    for arm in rows[0]['_verified']:
        values={}
        for metric in ['mse','pearson','spearman']:
            nums=[row['_verified'][arm][metric] for row in rows if row['_verified'][arm][metric] is not None]
            values[metric]=sum(nums)/len(nums) if nums else None
        compare(actual[arm],values)
for k in [128,512]:
    summary_check(r['by_k'][str(k)],[row for row in r['rows'] if row['k']==k])
    for donor in donors:summary_check(r['by_k_test_donor'][str(k)][donor],[row for row in r['rows'] if row['k']==k and row['test_donor']==donor])
output={'status':'passed','selected_lists_verified':len(selections),'rows_verified':len(seen),'metric_and_summary_comparisons':checks,'selection_reconstruction':'Independent per-gene numpy variance over training donor effects; exclude own perturbation; control CPM >=1 from training donor only; Python stable sort by descending variance and gene name','mask_verification':'Both true and mismatched target removed for every arm','leakage_review':'No held-out outcome values enter selection or predictions. Gene/target identities and common coverage are shared design information. This is reused-data development sensitivity, not untouched confirmation. Source inclusion and target availability can still limit generalization.','input_sha256':r['input_sha256']}
(P/'train_selected_verification.json').write_text(json.dumps(output,indent=2)+'\n');print(json.dumps(output,indent=2))
