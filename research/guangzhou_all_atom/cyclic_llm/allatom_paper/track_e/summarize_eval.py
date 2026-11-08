"""EC2-only A6 proposal from frozen baseline outputs; no hybrid numbers read.

Produces complete-grid checks, per-method means/seed SDs and wall timings,
registered shuffled/planted controls, untruncated-reference margins, all-pair
baseline SD proxies for MDE/pass-probability. Power values are normal-location
approximations with t critical values, not a measured hybrid variance or a gate
verdict. All source files are hashed; no private molecule strings are exported.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import math
import numpy as np
from scipy.stats import t, norm

METHODS=('edit_ga','gp_bo','lib_surrogate','random_lib','selfies_ga')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def load_rows(root,mode,fam,methods,seeds):
    rows={}; hashes={}
    expected={f'{m}__s{s}.json' for m in methods for s in seeds}
    files={p.name:p for p in (root/mode/fam).glob('*.json')}
    if set(files)!=expected:
        raise ValueError(f'{mode}/{fam}: missing={sorted(expected-set(files))}; extra={sorted(set(files)-expected)}')
    for name,path in files.items():
        r=json.loads(path.read_text())
        if r['mode']!=mode or r['family']!=fam or name!=f"{r['method']}__s{r['seed']}.json":
            raise ValueError('metadata/name mismatch '+str(path))
        for key in ('auc_topk','final_topk','wall_s'):
            if not math.isfinite(r[key]): raise ValueError('nonfinite '+key+' '+str(path))
        if not 0<=r['calls']<=1000: raise ValueError('oracle budget violated '+str(path))
        rows[r['method'],r['seed']]=r; hashes[str(path.relative_to(root))]=sha(path)
    return rows,hashes


def interval(x):
    x=np.asarray(x,float); n=len(x); mu=float(x.mean()); sd=float(x.std(ddof=1))
    width=float(t.ppf(.975,n-1))*sd/math.sqrt(n)
    return dict(mean=mu,paired_sd=sd,t_ci95=[mu-width,mu+width],n=n)


def field(rows,method,seeds,key): return np.array([rows[method,s][key] for s in seeds],float)

def summarize(root,out):
    report={'status':'PROPOSED_A6_REVIEW_REQUIRED','scope':'baseline/control measurements only; no hybrid study result',
            'primary_gate_ceiling':'INCONCLUSIVE','margin_fraction':.10,'budget':1000,
            'source_hashes':{},'families':{},'controls':{}}
    used=root.parent/'tuned_used.json'
    report['tuned_used_sha256']=sha(used)
    if report['tuned_used_sha256']!='32ec89b0113e4523071419bfa7a5d6642ac7ea866c1d44e7ec9fb3d8f1b7e22f':
        raise ValueError('evaluated configs do not match A5 frozen sha256')
    for fam in ('F1','F2'):
        rows,hashes=load_rows(root,'eval',fam,METHODS,range(10)); report['source_hashes'].update(hashes)
        summary={}; eligible={}
        for method in METHODS:
            rr=[rows[method,s] for s in range(10)]
            good=[r for r in rr if r.get('stop_reason')!='wallclock']
            # Current run records explicit stop reasons; no retrospectively inferred truncation.
            if any('stop_reason' not in r for r in rr): raise ValueError('missing registered truncation record')
            vals=field(rows,method,range(10),'auc_topk')
            held_names={name for r in rr for name in r.get('heldout',{})}
            held={}
            for name in held_names:
                vv=[r.get('heldout',{}).get(name) for r in rr]
                held[name]={'values':[v if isinstance(v,(float,int)) and math.isfinite(v) else None for v in vv],
                            'all_finite':all(isinstance(v,(float,int)) and math.isfinite(v) for v in vv)}
            summary[method]=dict(train_sd_auc_mean=float(vals.mean()),seed_sd=float(vals.std(ddof=1)),
                per_seed_sd_auc=vals.tolist(),wall_seconds=[r['wall_s'] for r in rr],
                wall_seconds_sum=sum(r['wall_s'] for r in rr),calls=[r['calls'] for r in rr],
                stop_reasons=[r['stop_reason'] for r in rr],heldout_final=held,
                untruncated_n=len(good),untruncated_mean=float(np.mean([r['auc_topk'] for r in good])) if good else None)
            if good: eligible[method]=summary[method]['untruncated_mean']
        if 'random_lib' not in eligible or len(eligible)<2: raise ValueError('no margin reference')
        best=max((m for m in eligible if m!='random_lib'),key=lambda m:eligible[m])
        gap=eligible[best]-eligible['random_lib']; margin=.10*gap
        if gap<=0: raise ValueError('nonpositive baseline/random gap; margin rule needs prospective review')
        contrasts={}; powers={}
        for left,right in itertools.combinations(METHODS,2):
            diff=field(rows,left,range(10),'auc_topk')-field(rows,right,range(10),'auc_topk')
            st=interval(diff); contrasts[left+' minus '+right]=st
            se=st['paired_sd']/math.sqrt(10); tc=float(t.ppf(.975,9))
            mde=(tc+float(norm.ppf(.8)))*se
            key=left+' minus '+right
            powers[key]={'proxy':'baseline paired differences, not observed hybrid variance','mde80_approx':mde,
                         'positive_lower_bound_threshold':tc*se,'sensitivity':[]}
            for frac in (.05,.10,.20):
                m=frac*gap
                for attenuation in (.229,.10,0.0):
                    for multiple in (1,2):
                        # Assumed signal attenuation, not a calibrated mapping between verifiers.
                        delta=multiple*m; threshold=max(m,tc*se)
                        prob=float(norm.sf((threshold-attenuation*delta)/se)) if se>0 else float(attenuation*delta>=threshold)
                        powers[key]['sensitivity'].append(dict(fraction=frac,margin=m,lambda_H=attenuation,
                          true_gain_multiple=multiple,pass_probability_normal_approx=prob))
        heldout_contrasts={}
        for left,right in itertools.combinations(METHODS,2):
            names=set(summary[left]['heldout_final']) & set(summary[right]['heldout_final'])
            for name in names:
                lv=summary[left]['heldout_final'][name]; rv=summary[right]['heldout_final'][name]
                if lv['all_finite'] and rv['all_finite']:
                    hs=interval(np.array(lv['values'])-np.array(rv['values']))
                    hs['mde80_approx']=(float(t.ppf(.975,9))+float(norm.ppf(.8)))*hs['paired_sd']/math.sqrt(10)
                    heldout_contrasts[left+' minus '+right+' | '+name]=hs
        report['families'][fam]=dict(methods=summary,best_untruncated_baseline=best,gap_G=gap,
                    margin_sd_auc=margin,baseline_paired_contrasts=contrasts,power_proxy_by_contrast=powers,heldout_final_paired_contrasts=heldout_contrasts)
    methods=[m+'@'+c for m in METHODS+('copy_seed',) for c in ('shuffled','planted')]
    rows,hashes=load_rows(root,'controls','F2',methods,range(5)); report['source_hashes'].update(hashes)
    for method in METHODS+('copy_seed',):
        shuffle=field(rows,method+'@shuffled',range(5),'auc_topk')-field(rows,'random_lib@shuffled',range(5),'auc_topk')
        ci=interval(shuffle); planted=field(rows,method+'@planted',range(5),'final_topk')
        report['controls'][method]=dict(shuffled_vs_floor=ci,shuffled_pass=ci['t_ci95'][0]<=0<=ci['t_ci95'][1],
          planted_final_topk=planted.tolist(),planted_all_seeds_ge_09=bool((planted>=.9).all()),
          calls_planted=[rows[method+'@planted',s]['calls'] for s in range(5)],
          stop_reasons_planted=[rows[method+'@planted',s].get('stop_reason') for s in range(5)])
    report['cost_limits']={'stage01_original_usd':14,'track_E_original_usd':4,'U1_original_usd':2,
       'M3_original_reserve_usd':3.5,'remaining_authorized_budget_verified':False,
       'reason':'launch-only cost rows omit actual billed duration and spot price; run wall_seconds are parallel per-run timings, not instance bills'}
    report['limitations']=['F1 heldout floor failed; replacement VOID; no GO available',
      'SD-AUC optimization margin does not certify heldout verifier validity',
      'MDE/pass approximations depend on each shown baseline variance proxy; no hybrid variance measured',
      'copy-seed plateau requires seed-set size/trajectory audit, not inferred from threshold alone',
      'heldout final scores are not heldout AUC curves',
      'review and commit A6 before any hybrid result; proposed JSON is not a preregistration by itself']
    Path(out).write_text(json.dumps(report,indent=2,allow_nan=False))
    print(json.dumps({'status':report['status'],'files':len(report['source_hashes']),
                     'families':{f:{k:v[k] for k in ('best_untruncated_baseline','gap_G','margin_sd_auc')} for f,v in report['families'].items()}}))


if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('run_dir'); p.add_argument('out'); a=p.parse_args(); summarize(Path(a.run_dir),a.out)
