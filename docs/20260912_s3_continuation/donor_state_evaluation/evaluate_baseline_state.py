"""Development ridge evaluation of control-assisted known-target donor transfer."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from scipy.stats import spearmanr
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler

ALPHAS=(1.,10.,100.)

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def strings(a,name,n=None):
    a=np.asarray(a)
    if a.ndim!=1 or a.dtype.kind not in 'US' or (n is not None and len(a)!=n) or any(not x.strip() for x in a.tolist()):raise ValueError('Invalid string vector: '+name)
    return a.astype(str)
def count_matrix(x,lib,n_genes):
    x=np.asarray(x);lib=np.asarray(lib)
    if x.ndim!=2 or x.shape[1]!=n_genes or lib.shape!=(len(x),):raise ValueError('Count/library shape mismatch')
    if not np.isfinite(x).all() or (x<0).any() or not np.equal(x,np.floor(x)).all():raise ValueError('Invalid raw counts')
    if not np.isfinite(lib).all() or (lib<=0).any() or not np.equal(lib,np.floor(lib)).all():raise ValueError('Invalid full library')
    if (x.astype(float).sum(1)>lib.astype(float)+1e-6).any():raise ValueError('Panel counts exceed full library')
    return x.astype(np.float64),lib.astype(np.float64)
def transformed(count,lib):return np.log1p(1e4*count/lib[:,None])

def prepare(target,baseline):
    genes=strings(target['gene_symbols'],'gene_symbols')
    if len(set(genes))!=len(genes):raise ValueError('Duplicate genes')
    if not np.array_equal(genes,strings(baseline['gene_symbols'],'baseline gene_symbols')):raise ValueError('Gene panels/order differ')
    count,lib=count_matrix(target['counts'],target['library_counts'],len(genes));n=len(count)
    donors=strings(target['donor_id'],'donor_id',n);conds=strings(target['culture_condition'],'culture_condition',n);names=strings(target['perturbed_gene_name'],'perturbed_gene_name',n);guides=strings(target['guide_id'],'guide_id',n)
    rows=np.asarray(target['source_rows'])
    if rows.shape!=(n,) or rows.dtype.kind not in 'iu' or (rows<0).any() or len(set(rows.tolist()))!=n:raise ValueError('Duplicate/misaligned source rows')
    cells=np.asarray(target['n_cells'])
    if cells.shape!=(n,) or not np.isfinite(cells).all() or (cells<=0).any() or not np.equal(cells,np.floor(cells)).all():raise ValueError('Invalid n_cells')
    bc,bl=count_matrix(baseline['counts'],baseline['library_counts'],len(genes));bn=len(bc)
    bd=strings(baseline['donor'],'baseline donor',bn);cc=strings(baseline['condition'],'baseline condition',bn);pool=strings(baseline['pool'],'pool',bn)
    if set(pool)!={'feature','reference'}:raise ValueError('Require separate feature/reference pools')
    control={}
    for i,key in enumerate(zip(bd,cc,pool)):
        if key in control:raise ValueError('Duplicate baseline key')
        control[key]=transformed(bc[i:i+1],bl[i:i+1])[0]
    records=[];Y=[];state=[];source_groups=[]
    for donor,cond,name in sorted(set(zip(donors,conds,names))):
        ix=np.where((donors==donor)&(conds==cond)&(names==name))[0]
        fkey=(donor,cond,'feature');rkey=(donor,cond,'reference')
        if fkey not in control or rkey not in control:raise ValueError('Missing control pool')
        effect=transformed(count[ix].sum(0)[None,:],np.array([lib[ix].sum()]))[0]-control[rkey]
        records.append({'donor':donor,'condition':cond,'target':name,'profiles':len(ix),'guides':len(set(guides[ix])),'cells':int(cells[ix].sum()),'library':float(lib[ix].sum())})
        Y.append(effect);state.append(control[fkey]);source_groups.append(rows[ix].tolist())
    if not records:raise ValueError('No targets')
    return {'Y':np.array(Y),'state':np.array(state),'donor':np.array([r['donor'] for r in records]),'condition':np.array([r['condition'] for r in records]),'target':np.array([r['target'] for r in records]),'genes':genes,'records':records,'source_groups':source_groups,'control':control}

def validate_controls(target,baseline,controls):
    rows=np.asarray(controls['source_rows']);n=len(rows)
    if rows.dtype.kind not in 'iu' or rows.ndim!=1 or (rows<0).any() or len(set(rows.tolist()))!=n:raise ValueError('Invalid control source rows')
    if set(rows.tolist())&set(np.asarray(target['source_rows']).tolist()):raise ValueError('Control and target source rows overlap')
    if not np.array_equal(controls['gene_symbols'],baseline['gene_symbols']):raise ValueError('Control gene schema differs')
    guides=strings(controls['guide_id'],'control guides',n);pool=strings(controls['pool'],'control pool',n)
    if set(pool)!={'feature','reference'}:raise ValueError('Control pools invalid')
    if set(guides[pool=='feature'])&set(guides[pool=='reference']):raise ValueError('Feature/reference control guides overlap')
    if set(guides)&set(target['guide_id']):raise ValueError('Control and perturbation guides overlap')
    counts,library=count_matrix(controls['counts'],controls['library_counts'],len(baseline['gene_symbols']))
    donor=strings(controls['donor_id'],'control donors',n);condition=strings(controls['culture_condition'],'control condition',n)
    keys=set(zip(donor,condition,pool));expected=set(zip(baseline['donor'],baseline['condition'],baseline['pool']))
    if keys!=expected:raise ValueError('Control aggregate coverage mismatch')
    for i,key in enumerate(zip(baseline['donor'],baseline['condition'],baseline['pool'])):
        ix=(donor==key[0])&(condition==key[1])&(pool==key[2])
        if not np.array_equal(counts[ix].sum(0),baseline['counts'][i]) or library[ix].sum()!=baseline['library_counts'][i]:raise ValueError('Control aggregates differ from raw selected profiles')
    return {'guide_pools_disjoint':True,'control_target_source_rows_disjoint':True,'control_target_guides_disjoint':True,'aggregates_recomputed_exactly':True,'control_profiles':n}

def seen_rows(d,train,test):
    seen=set(zip(d['target'][train],d['condition'][train]))
    return np.array([i for i in test if (d['target'][i],d['condition'][i]) in seen],dtype=int)

def donor_permutation(donors,seed=0):
    donors=sorted(set(donors))
    if len(donors)<2:raise ValueError('Shuffle requires at least two training donors')
    # One derangement reused across all conditions and all targets.
    rng=np.random.default_rng(seed);order=np.array(donors)[rng.permutation(len(donors))]
    return dict(zip(order,np.roll(order,1)))

def features(d,train,evaluate,with_state,shuffle=False):
    cats=[sorted(set(d[k][train])) for k in ('target','condition')]
    def build(ix,state_override=False):
        blocks=[np.stack([d[k][ix]==v for v in vs],axis=1).astype(float) for k,vs in zip(('target','condition'),cats)]
        if with_state:
            state=d['state'][ix]
            if state_override:
                mapping=donor_permutation(d['donor'][train])
                state=np.array([d['control'][(mapping[d['donor'][i]],d['condition'][i],'feature')] for i in ix])
            blocks.append(state)
        return np.concatenate(blocks,axis=1)
    return build(train,shuffle),build(evaluate)

def ridge(d,train,evaluate,alpha,variant):
    if set(d['donor'][train]) & set(d['donor'][evaluate]):raise ValueError('Donors overlap between fit and evaluation')
    xt,xe=features(d,train,evaluate,variant!='target_condition',variant=='shuffled_state')
    scaler=StandardScaler().fit(xt);xt=scaler.transform(xt);xe=scaler.transform(xe)
    donors=d['donor'][train];weights=np.array([1/np.sum(donors==v) for v in donors]);weights*=len(weights)/weights.sum()
    model=Ridge(alpha=alpha).fit(xt,d['Y'][train],sample_weight=weights)
    return model.predict(xe)

def score(pred,truth,mask):
    if pred.shape!=truth.shape or mask.shape!=truth.shape:raise ValueError('Metric shape mismatch')
    if not np.isfinite(pred[mask]).all() or not np.isfinite(truth[mask]).all():raise ValueError('Nonfinite observed effects')
    errors=[];rhos=[];cp=ct=short=0
    for p,t,m in zip(pred,truth,mask):
        if m.any():errors.append(float(np.mean((p[m]-t[m])**2)))
        if m.sum()<3:short+=1;continue
        pc=np.ptp(p[m])<=1e-8;tc=np.ptp(t[m])<=1e-8;cp+=int(pc);ct+=int(tc)
        if not(pc or tc):rhos.append(float(spearmanr(p[m],t[m]).statistic))
    return {'mse':float(np.mean(errors)) if errors else None,'spearman':float(np.mean(rhos)) if rhos else None,'rows':len(pred),'mse_rows':len(errors),'spearman_rows':len(rhos),'constant_prediction_rows':cp,'constant_target_rows':ct,'fewer_than_three_readouts':short}

def mask_without_target(d,ix):return np.array([d['genes']!=d['target'][i] for i in ix])

def baseline_predictions(d,train,test):
    y=d['Y'];out={'no_change':np.zeros_like(y[test])}
    means={c:y[train[d['condition'][train]==c]].mean(0) for c in set(d['condition'][test])}
    out['condition_mean']=np.array([means[d['condition'][i]] for i in test])
    out['target_condition_mean']=np.array([y[train[(d['condition'][train]==d['condition'][i])&(d['target'][train]==d['target'][i])]].mean(0) for i in test])
    return out

def evaluate(d,out):
    donors=sorted(set(d['donor']))
    if len(donors)!=4:raise ValueError('Protocol requires four individual donors')
    results=[];saved={};splits=[]
    for donor in donors:
        train=np.where(d['donor']!=donor)[0];available=np.where(d['donor']==donor)[0];test=seen_rows(d,train,available)
        if not len(test):raise ValueError('No seen-target test coverage')
        predictions=baseline_predictions(d,train,test);selection={};inner=[]
        for valdonor in sorted(set(d['donor'][train])):
            fit=train[d['donor'][train]!=valdonor];candidate=train[d['donor'][train]==valdonor];val=seen_rows(d,fit,candidate)
            if not len(val):raise ValueError('No inner validation coverage')
            assert not(set(d['donor'][fit])&set(d['donor'][val]))
            inner.append((fit,val));splits.append({'outer_test_donor':donor,'inner_validation_donor':valdonor,'fit_rows':fit.tolist(),'validation_rows':val.tolist(),'excluded_validation_rows':sorted(map(int,set(candidate)-set(val)))})
        for variant in ['target_condition','baseline_state','shuffled_state']:
            grid=[]
            for alpha in ALPHAS:
                values=[float(np.mean((ridge(d,f,v,alpha,variant)-d['Y'][v])**2)) for f,v in inner]
                grid.append({'alpha':alpha,'inner_donor_mse':values,'mean_mse':float(np.mean(values))})
            alpha=min(grid,key=lambda x:x['mean_mse'])['alpha'];selection[variant]={'selected_alpha':alpha,'grid':grid};predictions[variant]=ridge(d,train,test,alpha,variant)
        item={'test_donor':donor,'train_donors':sorted(set(d['donor'][train])),'test_rows':test.tolist(),'excluded_unseen_target_condition_rows':sorted(map(int,set(available)-set(test))),'selection':selection,'metrics':{}}
        for name,pred in predictions.items():
            item['metrics'][name]={'all_readouts':score(pred,d['Y'][test],np.ones_like(pred,dtype=bool)),'excluding_perturbed_readout':score(pred,d['Y'][test],mask_without_target(d,test)),'by_condition':{c:score(pred[d['condition'][test]==c],d['Y'][test][d['condition'][test]==c],np.ones_like(pred[d['condition'][test]==c],dtype=bool)) for c in sorted(set(d['condition'][test]))}}
            saved[donor+'__'+name]=pred
        saved[donor+'__test_rows']=test;results.append(item)
    summary={}
    for method in results[0]['metrics']:
        summary[method]={}
        for subset in ['all_readouts','excluding_perturbed_readout']:
            summary[method][subset]={metric:float(np.mean([r['metrics'][method][subset][metric] for r in results if r['metrics'][method][subset][metric] is not None])) if any(r['metrics'][method][subset][metric] is not None for r in results) else None for metric in ['mse','spearman']}
    np.savez_compressed(out/'predictions.npz',Y=d['Y'],state=d['state'],donor=d['donor'],condition=d['condition'],target=d['target'],genes=d['genes'],**saved)
    return {'summary_equal_weight_donors':summary,'outer_folds':results,'inner_splits':splits,'aggregation_rows':d['records'],'source_groups':d['source_groups']}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--targets',required=True);ap.add_argument('--baseline',required=True);ap.add_argument('--controls',required=True);ap.add_argument('--out',required=True);a=ap.parse_args();out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    if (out/'results.json').exists():raise ValueError('Refusing result overwrite')
    with np.load(a.targets,allow_pickle=False) as z:target={k:z[k] for k in z.files}
    with np.load(a.baseline,allow_pickle=False) as z:baseline={k:z[k] for k in z.files}
    with np.load(a.controls,allow_pickle=False) as z:controls={k:z[k] for k in z.files}
    checks=validate_controls(target,baseline,controls)
    d=prepare(target,baseline);results=evaluate(d,out);results['input_verification']=checks
    results['provenance']={'targets_sha256':sha(a.targets),'baseline_sha256':sha(a.baseline),'controls_sha256':sha(a.controls),'script_sha256':sha(__file__)}
    results['protocol']={'task':'Control-assisted seen-target donor transfer; four nested outer donor folds','label':'log1p(10000 * summed target counts / summed full-transcriptome UMI library) minus independent reference-control transform; not deposited DE logFC','state':'Feature-control transform only; no perturbed state input','ridge':'Train-only feature scaling; alpha 1/10/100 selected by equal inner-donor MSE; inverse donor-row-count training weights','selection_metric':'All-readout inner donor MSE, including perturbed target; target-excluded scores are secondary, not independently tuned','aggregation':'Summed target-guide pseudobulk counts, weighting more abundant cells/guides; not equal-guide mean','shuffle':'Fixed training-donor derangement shared across conditions; test state remains correct','limits':['Only four donors; seed or row variation is not donor confidence','Seen target-condition combinations only; no unseen target claim','Baseline provenance must establish separate control guide pools','All counts require measured complete panel; no missing groups zero-filled','Tiny ridge development comparison; no causal or machinery validation']}
    (out/'results.json').write_text(json.dumps(results,indent=2,allow_nan=False));print(json.dumps(results['summary_equal_weight_donors'],indent=2))
if __name__=='__main__':main()
