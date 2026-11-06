"""Directly measure the within-target selector LM's leakage-safe AUC on PADI4.
Reuses cyclic_llm_selector recipe; this time STORES per-seq LLR + 3-mer Jaccard to train binders,
and reports LM vs trivial baselines on full + motif-distinct (sim<0.5) subsets. CPU."""
import gzip, json, random, time
from pathlib import Path
import numpy as np, torch
from sklearn.metrics import roc_auc_score
from sklearn.linear_model import LogisticRegression
import train_cyclic_llm_v2 as v2
from train_cyclic_llm_v2 import AA, TOKS, STOI, PAD, BOS, EOS, make_model, encode
from cyclic_llm_selector import load_target, _bucket, seq_loglik, HI, LO

CSV="data/display/display_ngs_multitarget.csv.gz"; T="PADI4"; DEV="cpu"; BLOCK=32
recs=load_target(CSV,T); random.Random(0).shuffle(recs)
n_test=max(200,int(len(recs)*0.2)); test,train=recs[:n_test],recs[n_test:]
if len(test)>4000:
    b=[r for r in test if r["is_binder"]]; nb=[r for r in test if not r["is_binder"]]
    test=b+nb[:max(0,4000-len(b))]; random.Random(1).shuffle(test)
# traj-train bucketing (reproduce the 'trajtrain' variant)
blob=json.load(open("results/trajectory_PADI4.json"))
clean=set(blob.get("clean_binder_seqs",[])); jack=set(blob.get("jackpot_binder_seqs",[]))
for r in train:
    r["enr_b"]="hi" if r["seq"] in clean else ("mid" if r["seq"] in jack else _bucket(r["enr"]))
tr=[r for r in train if r["enr_b"] in ("hi","lo","mid")]; his=[r for r in tr if r["enr_b"]=="hi"]
tr_os=tr+his*7
print(f"n_total={len(recs)} train={len(tr)} hi={len(his)} test={len(test)} test_binders={sum(r['is_binder'] for r in test)} clean={len(clean)} jack={len(jack)}",flush=True)
torch.manual_seed(0)
m=make_model(len(TOKS),d_model=256,n_layer=6,n_head=8,block=BLOCK).to(DEV)
opt=torch.optim.AdamW(m.parameters(),lr=3e-4,weight_decay=0.1,betas=(0.9,0.95)); pad=STOI[PAD]
def batch():
    ids=[encode(tr_os[random.randrange(len(tr_os))],BLOCK) for _ in range(128)]
    mx=max(len(x) for x in ids); X=torch.full((len(ids),mx),pad,dtype=torch.long)
    for i,s in enumerate(ids): X[i,:len(s)]=torch.tensor(s)
    return X.to(DEV)
m.train(); t0=time.time()
for step in range(1,2001):
    X=batch(); lg=m(X[:,:-1]); loss=torch.nn.functional.cross_entropy(lg.reshape(-1,lg.size(-1)),X[:,1:].reshape(-1),ignore_index=pad)
    opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(m.parameters(),1.0); opt.step()
    if step%400==0: print(f"  step {step}/2000 loss {loss.item():.3f} {(time.time()-t0)/step:.3f}s/it",flush=True)
m.eval()
# 3-mer Jaccard to train binders
def ks(s,k=3): return {s[i:i+k] for i in range(len(s)-k+1)}
tb=[ks(r["seq"]) for r in train if r["is_binder"]]
def maxjac(s):
    a=ks(s); best=0.0
    for b in tb:
        u=len(a|b); best=max(best,len(a&b)/u) if u else best
    return best
rows=[]
for r in test:
    hs,n=seq_loglik(m,r["seq"],"hi",DEV); ls,_=seq_loglik(m,r["seq"],"lo",DEV)
    rows.append({"seq":r["seq"],"is_binder":int(r["is_binder"]),"llr_raw":hs-ls,"llr_norm":(hs-ls)/max(1,n),
                 "maxjac_trainbinder":round(maxjac(r["seq"]),4)})
Path("results").mkdir(exist_ok=True)
json.dump(rows,open("results/cyclic_llm_selector_PADI4_perseq_scores.json","w"))
y=np.array([x["is_binder"] for x in rows]); norm=np.array([x["llr_norm"] for x in rows]); sim=np.array([x["maxjac_trainbinder"] for x in rows])
def lift(score,frac):
    k=max(1,int(len(score)*frac)); idx=np.argsort(-score)[:k]; br=y.mean()
    return round(float(y[idx].mean())/br,2) if br>0 else None
# baselines on same split
AAL="ACDEFGHIKLMNPQRSTVWY"; km=sorted({a+b for a in AAL for b in AAL}); ki={k:i for i,k in enumerate(km)}
def comp(s):
    v=np.zeros(20); 
    for c in s: v[AAL.index(c)]+=1
    return v/max(1,len(s))
def kv(s):
    v=np.zeros(len(km))
    for i in range(len(s)-1): v[ki[s[i:i+2]]]+=1
    return v/max(1,len(s)-1)
ytr=np.array([int(r["is_binder"]) for r in train])
lrc=LogisticRegression(max_iter=2000,class_weight="balanced").fit(np.array([comp(r["seq"]) for r in train]),ytr)
lrk=LogisticRegression(max_iter=2000,class_weight="balanced").fit(np.array([kv(r["seq"]) for r in train]),ytr)
comp_s=lrc.predict_proba(np.array([comp(x["seq"]) for x in rows]))[:,1]
km_s=lrk.predict_proba(np.array([kv(x["seq"]) for x in rows]))[:,1]
# subsets: full; motif-distinct = positives with sim<0.5 vs all negatives
pos_md=(y==1)&(sim<0.5); neg=(y==0)
def auc_sub(score,mask_pos):
    yy=np.r_[np.ones(mask_pos.sum()),np.zeros(neg.sum())]; sc=np.r_[score[mask_pos],score[neg]]
    return round(roc_auc_score(yy,sc),4)
out={"n_test":len(rows),"test_binders":int(y.sum()),"motif_distinct_binders":int(pos_md.sum()),
 "FULL":{"LM_norm":round(roc_auc_score(y,norm),4),"2mer":round(roc_auc_score(y,km_s),4),"comp":round(roc_auc_score(y,comp_s),4),
         "LM_lift5":lift(norm,0.05),"LM_lift10":lift(norm,0.10)},
 "MOTIF_DISTINCT_sim<0.5":{"LM_norm":auc_sub(norm,pos_md),"2mer":auc_sub(km_s,pos_md),"comp":auc_sub(comp_s,pos_md)}}
print("RESCORE_RESULT",json.dumps(out),flush=True)
json.dump(out,open("results/cyclic_llm_selector_PADI4_leakagesafe.json","w"),indent=2)
