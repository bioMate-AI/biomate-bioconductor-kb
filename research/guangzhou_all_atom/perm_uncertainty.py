#!/usr/bin/env python3
"""P2 committee fix: bootstrap 95% CIs on the small-n comparisons (Reviewers A & B: 'no error bars').
Local, on committed result JSONs. Honest expectation: small n -> WIDE CIs -> strong claims must be softened."""
import json, numpy as np
from scipy.stats import spearmanr
rng=np.random.default_rng(0)
src=open('perm_generation_v3.py').read().split('def parse_cif')[0]
ns={}; exec(src, ns); cyclic_mol=ns['cyclic_mol']
def nh(s):
    m=cyclic_mol(s); return m.GetNumHeavyAtoms() if m else None

def ci(vals, stat=np.mean, B=10000):
    vals=np.array(vals,float); bs=[stat(rng.choice(vals,len(vals),replace=True)) for _ in range(B)]
    return round(float(np.percentile(bs,2.5)),3), round(float(np.percentile(bs,97.5)),3)

out={}
for tgt in ('1yf4','1u8p'):
    dg=json.load(open(f'results/v3verify_mmgbsa_{tgt}.json'))
    byid={d['id']:d for d in json.load(open(f'results/perm_generation_v3_{tgt}.json'))['designs']}
    perm=[r['id'] for r in sorted(byid.values(),key=lambda r:-r['perm_score'])[:8]]
    bg  =[r['id'] for r in sorted(byid.values(),key=lambda r:r['bg_rank'])[:8]]
    def le(ids): return [dg[i]['dG']/nh(dg[i]['seq']) for i in ids if i in dg and nh(dg[i]['seq'])]
    lp, lb = le(perm), le(bg)
    # bootstrap CI on the DIFFERENCE of mean LE (perm - default)
    diffs=[np.mean(rng.choice(lp,len(lp),True))-np.mean(rng.choice(lb,len(lb),True)) for _ in range(10000)]
    out[tgt]={'mean_LE_perm':round(float(np.mean(lp)),3),'CI_perm':ci(lp),
              'mean_LE_default':round(float(np.mean(lb)),3),'CI_default':ci(lb),
              'LE_diff_perm_minus_default':round(float(np.mean(diffs)),3),
              'LE_diff_95CI':[round(float(np.percentile(diffs,2.5)),3),round(float(np.percentile(diffs,97.5)),3)]}

# iptm vs physics: bootstrap Spearman CI on pooled union
pool=[]
for tgt in ('1yf4','1u8p'):
    dg=json.load(open(f'results/v3verify_mmgbsa_{tgt}.json'))
    byid={d['id']:d for d in json.load(open(f'results/perm_generation_v3_{tgt}.json'))['designs']}
    for i,d in dg.items():
        if i in byid and nh(d['seq']): pool.append((byid[i]['iptm'], d['dG'], d['dG']/nh(d['seq'])))
ip=np.array([p[0] for p in pool]); raw=np.array([p[1] for p in pool]); le=np.array([p[2] for p in pool])
def sp_ci(a,b,B=10000):
    idx=np.arange(len(a)); rs=[spearmanr(a[s],b[s]).correlation for s in (rng.choice(idx,len(idx),True) for _ in range(B))]
    rs=[r for r in rs if r==r]
    return round(float(spearmanr(a,b).correlation),3),[round(float(np.percentile(rs,2.5)),3),round(float(np.percentile(rs,97.5)),3)]
r_raw,ci_raw=sp_ci(ip,raw); r_le,ci_le=sp_ci(ip,le)
out['iptm_vs_physics']={'n':len(pool),'spearman_iptm_rawdG':r_raw,'CI':ci_raw,
                        'spearman_iptm_LE':r_le,'CI_LE':ci_le}
out['note']=('Bootstrap 95% CIs (10k resamples). Small n -> wide CIs; report these instead of bare point '
             'estimates. If a LE-diff CI spans 0, the perm-vs-default LE difference is not significant at this n.')
json.dump(out, open('results/perm_uncertainty.json','w'), indent=2)
print(json.dumps(out, indent=2))
