"""Independent scalar attenuation and predictions from raw counts."""
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr, spearmanr
P=Path(__file__).resolve().parent
with np.load(P/'pseudobulk.npz',allow_pickle=False) as z:d=dict(z)
r=json.loads((P/'shrinkage_baseline.json').read_text())
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
ordered=sorted(set(d['guide_id'][d['target']=='NonTarget']),key=lambda g:hashlib.sha256(('external-control-split-20260912:'+str(g)).encode()).hexdigest())
assert len(ordered)==8
pool={g:('feature' if i%2==0 else 'reference') for i,g in enumerate(ordered)}
fit_cache={};alpha_checks=0
for fit in r['fits']:
    test,train,cond,panel=[fit[k] for k in ['test_donor','train_donor','condition','panel']]
    assert test!=train and {test,train}==set(donors)
    ranked,_,_=cache[train,cond]
    chosen=[j for j in (range(len(genes)) if panel=='all' else ranked[:int(panel)]) if genes[j] not in targets]
    assert fit['genes']==genes[chosen].tolist() and fit['readouts']==len(chosen)
    ids=[i for i in range(len(d['counts'])) if d['donor_id'][i]==train and d['culture_condition'][i]==cond]
    refs={}
    for p in ['feature','reference']:
        ctrl=[i for i in ids if d['target'][i]=='NonTarget' and pool[d['guide_id'][i]]==p]
        assert len(ctrl)==4
        refs[p]=norm(d['counts'][ctrl].sum(0))[chosen]
    numerator=0.;denominator=0.
    for target in targets:
        ix=sorted([i for i in ids if d['target'][i]==target],key=lambda i:d['guide_id'][i]);assert len(ix)==2
        a,b=[norm(d['counts'][i])[chosen] for i in ix]
        # Algebraically sum both predictor directions for each disjoint-reference orientation.
        for u,v in [(a-refs['feature'],b-refs['reference']),(a-refs['reference'],b-refs['feature'])]:
            numerator+=2*float(np.sum(u*v));denominator+=float(np.sum(u*u)+np.sum(v*v))
    alpha=max(0.,min(1.,numerator/denominator)) if denominator>0 else 0.
    np.testing.assert_allclose(fit['alpha'],alpha,rtol=1e-10,atol=1e-12);alpha_checks+=1
    key=test,cond,panel;assert key not in fit_cache;fit_cache[key]=(chosen,alpha)
assert alpha_checks==12
checks=0

def compare(actual,expected):
    global checks
    for metric,value in expected.items():
        if value is None:assert actual[metric] is None
        else:np.testing.assert_allclose(actual[metric],value,rtol=1e-10,atol=1e-12)
        checks+=1
seen=set()
for row in r['rows']:
    test,train,cond,panel,target=[row[k] for k in ['test_donor','train_donor','condition','panel','target']]
    assert test!=train and {test,train}==set(donors)
    key=test,cond,panel,target;assert key not in seen;seen.add(key)
    chosen,alpha=fit_cache[test,cond,panel];np.testing.assert_allclose(row['alpha'],alpha,rtol=1e-10,atol=1e-12)
    mismatch=targets[(targets.index(target)+1)%len(targets)]
    effects=cache[train,cond][2];truth=cache[test,cond][2][target][chosen]
    mean=np.array([sum(effects[t][j] for t in targets)/len(targets) for j in chosen])
    pred=effects[target][chosen];wrong=effects[mismatch][chosen]
    arms={'no_change':np.zeros(len(chosen)),'condition_mean':mean,'matched_observed_target':pred,'shrunk_matched':alpha*pred,'shrunk_mismatched':alpha*wrong}
    row['_verified']={}
    for arm,pred in arms.items():
        valid=np.ptp(pred)>0 and np.ptp(truth)>0
        values={'mse':float(np.mean((pred-truth)**2)),'pearson':float(pearsonr(pred,truth).statistic) if valid else None,'spearman':float(spearmanr(pred,truth).statistic) if valid else None}
        compare(row['metrics'][arm],values);row['_verified'][arm]=values
assert len(seen)==240

def check_summary(actual,rows):
    for arm in rows[0]['_verified']:
        expected={}
        for metric in ['mse','pearson','spearman']:
            values=[row['_verified'][arm][metric] for row in rows if row['_verified'][arm][metric] is not None]
            expected[metric]=sum(values)/len(values) if values else None
            expected[metric+'_valid_rows']=len(values)
        compare(actual[arm],expected)
for panel in ['all','128','512']:
    check_summary(r['by_panel'][panel],[row for row in r['rows'] if row['panel']==panel])
    for donor in donors:check_summary(r['by_panel_test_donor'][panel][donor],[row for row in r['rows'] if row['panel']==panel and row['test_donor']==donor])
output={'status':'passed','independently_reconstructed_coefficients':alpha_checks,'rows_verified':len(seen),'metric_summary_and_denominator_comparisons':checks,'gene_exclusion':'All20 target genes excluded from every fit/prediction/readout panel','fit':'Independently summed symmetrized cross-products and squared predictors from training-donor disjoint guide/reference pools, clipped to [0,1]','leakage_review':'No test-donor outcomes used in selection or alpha fitting; top panels reconstructed from train donor only. Exploratory adaptation after prior results, shared references, selection bias and only2 donor labels prevent confirmation/generalization claims.','correlation_denominators':'Every valid_rows count checked; zero alpha gives undefined correlations. Use MSE comparison.','input_sha256':r['input_sha256']}
(P/'shrinkage_verification.json').write_text(json.dumps(output,indent=2)+'\n');print(json.dumps(output,indent=2))
