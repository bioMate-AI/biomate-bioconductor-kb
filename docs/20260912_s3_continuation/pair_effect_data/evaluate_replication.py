"""Read-only known-perturbation transfer between disjoint donor pairs."""
import hashlib, json
from pathlib import Path
import numpy as np
from scipy.stats import spearmanr

ROOT=Path(__file__).resolve().parent

def metrics(pred, target, observed):
    rho=[]; mse=[]; excluded={'fewer_than_three_readouts':0,'constant_prediction':0,'constant_target':0}
    for p,t,m in zip(pred,target,observed):
        p,t=p[m].astype(float),t[m].astype(float)
        if len(p):mse.append(float(np.mean((p-t)**2)))
        if len(p)<3:excluded['fewer_than_three_readouts']+=1;continue
        cp=np.ptp(p)<=1e-8;ct=np.ptp(t)<=1e-8
        excluded['constant_prediction']+=int(cp);excluded['constant_target']+=int(ct)
        if not(cp or ct):rho.append(float(spearmanr(p,t).statistic))
    return {'macro_row_mse':float(np.mean(mse)) if mse else None,'mean_row_spearman':float(np.mean(rho)) if rho else None,'mse_rows':len(mse),'spearman_rows':len(rho),'excluded_flags_overlap':excluded,'observed_entries':int(observed.sum())}

def main():
    with np.load(ROOT/'effects.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
    Y=d['Y'];pairs=d['donor_pairs'];targets=d['targets'];conds=d['conditions']
    assert np.array_equal(d['observed'],np.isfinite(Y)) and not np.isinf(Y).any()
    unique=sorted(set(pairs));members={p:set(p.split('_')) for p in unique}
    assert all(len(v)==2 for v in members.values())
    result=[];saved={}
    for source in unique:
      for dest in unique:
        if members[source]&members[dest]:continue
        si=np.where(pairs==source)[0];ti=np.where(pairs==dest)[0]
        def lookup(ix):
            out={(str(targets[i]),str(conds[i])):int(i) for i in ix}
            if len(out)!=len(ix):raise ValueError('Duplicate target/condition in a donor pair')
            return out
        sl,tl=lookup(si),lookup(ti);keys=sorted(sl.keys()&tl.keys())
        if not keys:raise ValueError('No matched effects')
        a=np.array([sl[k] for k in keys]);b=np.array([tl[k] for k in keys]);prediction=Y[a];truth=Y[b]
        baseline=[];mask=[]
        for i,k in enumerate(keys):
            pool=si[conds[si]==k[1]];valid=np.isfinite(Y[pool]).all(0)
            mean=np.full(Y.shape[1],np.nan);mean[valid]=Y[pool][:,valid].mean(0)
            baseline.append(mean);mask.append(valid&np.isfinite(truth[i]))
        baseline=np.array(baseline);mask=np.array(mask)
        # Common finite axes across all source-condition rows make every null use exactly the same readouts.
        direction=f'{source}__to__{dest}';null=[]
        for seed in range(100):
            rng=np.random.default_rng(seed);shuffled=prediction.copy()
            for c in sorted(set(k[1] for k in keys)):
                local=np.array([j for j,k in enumerate(keys) if k[1]==c]);shuffled[local]=prediction[rng.permutation(local)]
            null.append(metrics(shuffled,truth,mask))
        null_summary={}
        for metric in ['macro_row_mse','mean_row_spearman']:
            values=np.array([r[metric] for r in null if r[metric] is not None])
            null_summary[metric]={'mean':float(values.mean()) if len(values) else None,'q025':float(np.quantile(values,.025)) if len(values) else None,'q975':float(np.quantile(values,.975)) if len(values) else None}
        record={'direction':direction,'source_pair':source,'destination_pair':dest,'matched_rows':len(keys),'source_rows':len(si),'destination_rows':len(ti),'matched_targets':len(set(k[0] for k in keys)),'conditions':{c:sum(k[1]==c for k in keys) for c in sorted(set(conds))},'same_target_transfer':metrics(prediction,truth,mask),'source_condition_mean':metrics(baseline,truth,mask),'shuffled_target_null':null_summary,'null_seed_results':null}
        result.append(record)
        saved[direction+'_source_rows']=a;saved[direction+'_destination_rows']=b;saved[direction+'_mask']=mask
    report={'task':'Known-perturbation replication across complementary nonoverlapping donor pairs','input_sha256':hashlib.sha256((ROOT/'effects.npz').read_bytes()).hexdigest(),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'directions':result,'protocol':{'null_seeds':list(range(100)),'mask':'Finite in destination row and every source-pair row in its condition, identical for transfer, baseline and all null permutations','condition_mean':'All available source-pair effects in the same condition, including matched targets; no destination outcomes','null':'Permute source target assignments among matched targets within each condition, allowing fixed points','mse':'Mean per-row MSE, then equal row mean','spearman':'Per-row Spearman over common finite readout genes; constant or <3-readout rows excluded'},'limitations':['Three complementary partitions and six directions reuse the same four donors; not six independent cohorts','Known perturbations, not unseen-target prediction or causal model validation','QC-selected effects and earlier frozen development target panel','Same deposited DE estimation procedure may yield shared analysis biases','Null quantiles are permutation reference ranges, not biological confidence intervals']}
    (ROOT/'replication_results.json').write_text(json.dumps(report,indent=2,allow_nan=False))
    np.savez_compressed(ROOT/'replication_comparison_masks.npz',**saved)
    lines=['# Donor-pair effect replication — 12 September 2026','','Known-perturbation transfer only. Each direction compares two nonoverlapping donor pairs. The three complementary partitions reuse four donors; directions are not independent cohorts.','','| Source → destination | Matched rows | Transfer MSE | Mean baseline MSE | Transfer Spearman | Baseline Spearman | Shuffled Spearman mean |','|---|---:|---:|---:|---:|---:|---:|']
    for r in result:
        f=lambda v:'undefined' if v is None else f'{v:.6f}'
        x=r['same_target_transfer'];y=r['source_condition_mean'];n=r['shuffled_target_null']
        lines.append(f"| {r['source_pair']} → {r['destination_pair']} | {r['matched_rows']} | {f(x['macro_row_mse'])} | {f(y['macro_row_mse'])} | {f(x['mean_row_spearman'])} | {f(y['mean_row_spearman'])} | {f(n['mean_row_spearman']['mean'])} |")
    lines+=['','Effects and baselines use identical finite readout masks, including all 100 fixed-seed null comparisons. The masks and row indices are saved separately. Full results include constant-row exclusions, coverage and null reference quantiles. A zero correlation is never substituted for an undefined correlation.','','The baseline averages all source-pair effects in the same condition. The null permutes matched source target assignments within condition, allowing fixed points. The same-target source effect is an observed experimental effect, not a learned model prediction. Strong replication would establish available response signal, not predictive generalization.','','Selection is restricted to successful on-target perturbations and the earlier development panel. These results do not establish donor-independent baseline-state modeling; no model was trained.']
    (ROOT/'REPLICATION_REPORT.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps([{k:v for k,v in r.items() if k not in ['null_seed_results']} for r in result],indent=2))
if __name__=='__main__':main()
