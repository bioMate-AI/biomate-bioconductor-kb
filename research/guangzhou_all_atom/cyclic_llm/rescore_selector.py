"""Leakage-safe within-target selector re-score for ANY display target (CPU).
Usage: PYTHONPATH=cyclic_llm python3 cyclic_llm/rescore_selector.py <TARGET>
Trains display-enrichment-conditioned LM (traj-train if results/trajectory_<T>.json exists, else default
log2fc bucketing), scores held-out seqs by length-normalized LLR, stores per-seq scores + checkpoint, and
reports LM vs 2-mer/composition baselines on full + motif-distinct (3-mer Jaccard<0.5 to train binders)."""
import gzip, json, os, random, sys, time
from pathlib import Path
import numpy as np, torch
from sklearn.metrics import roc_auc_score
from sklearn.linear_model import LogisticRegression
import train_cyclic_llm_v2 as v2
from train_cyclic_llm_v2 import AA, TOKS, STOI, PAD, make_model, encode
from cyclic_llm_selector import load_target, _bucket, seq_loglik

CSV="data/display/display_ngs_multitarget.csv.gz"; T=sys.argv[1] if len(sys.argv)>1 else "PADI4"; DEV="cpu"; BLOCK=32
recs=load_target(CSV,T); random.Random(0).shuffle(recs)
n_test=max(200,int(len(recs)*0.2)); test,train=recs[:n_test],recs[n_test:]
if len(test)>4000:
    b=[r for r in test if r["is_binder"]]; nb=[r for r in test if not r["is_binder"]]
    test=b+nb[:max(0,4000-len(b))]; random.Random(1).shuffle(test)
tj=f"results/trajectory_{T}.json"; traj=os.path.exists(tj)
blob=json.load(open(tj)) if traj else {}
clean=set(blob.get("clean_binder_seqs",[])); jack=set(blob.get("jackpot_binder_seqs",[]))
for r in train:
    if traj and (clean or jack):
        r["enr_b"]="hi" if r["seq"] in clean else ("mid" if r["seq"] in jack else _bucket(r["enr"]))
    else:
        r["enr_b"]=_bucket(r["enr"])
tr=[r for r in train if r["enr_b"] in ("hi","lo","mid")]; his=[r for r in tr if r["enr_b"]=="hi"]; tr_os=tr+his*7
ntb=sum(r["is_binder"] for r in test)
print(f"target={T} traj_train={traj} n_total={len(recs)} train={len(tr)} hi={len(his)} test={len(test)} test_binders={ntb}",flush=True)
if ntb<10:
    print(json.dumps({"target":T,"status":"too_few_test_binders","n":ntb})); sys.exit(0)
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
Path("runs_selector").mkdir(exist_ok=True)
torch.save({"model":m.state_dict(),"target":T,"traj":traj},f"runs_selector/selector_{T}.pt")
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
    rows.append({"seq":r["seq"],"is_binder":int(r["is_binder"]),"llr_raw":hs-ls,"llr_norm":(hs-ls)/max(1,n),"maxjac_trainbinder":round(maxjac(r["seq"]),4)})
json.dump(rows,open(f"results/cyclic_llm_selector_{T}_perseq_scores.json","w"))
y=np.array([x["is_binder"] for x in rows]); norm=np.array([x["llr_norm"] for x in rows]); sim=np.array([x["maxjac_trainbinder"] for x in rows])
def lift(score,frac):
    k=max(1,int(len(score)*frac)); idx=np.argsort(-score)[:k]; br=y.mean()
    return round(float(y[idx].mean())/br,2) if br>0 else None
AAL="ACDEFGHIKLMNPQRSTVWY"; km=sorted({a+b for a in AAL for b in AAL}); kidx={k:i for i,k in enumerate(km)}
def comp(s):
    v=np.zeros(20)
    for c in s: v[AAL.index(c)]+=1
    return v/max(1,len(s))
def kv(s):
    v=np.zeros(len(km))
    for i in range(len(s)-1): v[kidx[s[i:i+2]]]+=1
    return v/max(1,len(s)-1)
ytr=np.array([int(r["is_binder"]) for r in train])
lrc=LogisticRegression(max_iter=2000,class_weight="balanced").fit(np.array([comp(r["seq"]) for r in train]),ytr)
lrk=LogisticRegression(max_iter=2000,class_weight="balanced").fit(np.array([kv(r["seq"]) for r in train]),ytr)
comp_s=lrc.predict_proba(np.array([comp(x["seq"]) for x in rows]))[:,1]
km_s=lrk.predict_proba(np.array([kv(x["seq"]) for x in rows]))[:,1]
pos_md=(y==1)&(sim<0.5); neg=(y==0)
def auc_sub(score):
    yy=np.r_[np.ones(pos_md.sum()),np.zeros(neg.sum())]; sc=np.r_[score[pos_md],score[neg]]
    return round(roc_auc_score(yy,sc),4)
out={"target":T,"traj_train":traj,"cyclization":"thioether_ClAc-Cys" if T in("PADI4","FIKK13") else "see_csv",
 "n_test":len(rows),"test_binders":int(y.sum()),"motif_distinct_binders":int(pos_md.sum()),
 "FULL":{"LM":round(roc_auc_score(y,norm),4),"2mer":round(roc_auc_score(y,km_s),4),"comp":round(roc_auc_score(y,comp_s),4),"LM_lift5":lift(norm,0.05),"LM_lift10":lift(norm,0.10)},
 "MOTIF_DISTINCT":{"LM":auc_sub(norm),"2mer":auc_sub(km_s),"comp":auc_sub(comp_s)}}
print("RESCORE_RESULT",json.dumps(out),flush=True)
json.dump(out,open(f"results/cyclic_llm_selector_{T}_leakagesafe.json","w"),indent=2)
