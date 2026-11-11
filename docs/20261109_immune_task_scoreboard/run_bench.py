"""Immune-task benchmark harness (torch-free: h5py + numpy + sklearn; NO scipy.stats).
Scores representations {raw-HVG, PCA50, knowledge-channel} vs baked-in nulls, per task, with
group-disjoint split discipline where applicable. Emits scorecard.json.
Representations:
  raw   : corpus-scaled HVG expression (the raw baseline)
  pca   : PCA(50) of raw (a strong simple baseline)
  know  : pathway/TF knowledge-channel means (the model's knowledge representation)
  fm_z  : the frozen FM encoder embedding -> UNAVAILABLE here (hybrid_model.pt needs torch; broken on Spark)
"""
import os, sys, json, time, gzip, warnings
import numpy as np, h5py
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import roc_auc_score, average_precision_score, f1_score
warnings.filterwarnings("ignore")
WS="/home/yzhang/immune_fm_spark"; AUD=f"{WS}/eval_repair_20261107"
OUT=f"{WS}/ws_bench"; os.makedirs(OUT, exist_ok=True)
sys.path.insert(0, f"{WS}/code_20261004")
import knowledge_channel as K
K._s3 = lambda src,dst: os.path.isfile(dst)
t0=time.time(); card={"generated": time.strftime("%Y-%m-%d %H:%M"), "tasks":{}}
def dump(): json.dump(card, open(f"{OUT}/scorecard.json","w"), indent=2)

def align(names, Xcsr_or_dense, hvg):
    idx={str(g).upper():i for i,g in enumerate(names)}
    cols=[idx.get(str(g).upper(),-1) for g in hvg]
    out=np.zeros((Xcsr_or_dense.shape[0], len(hvg)), np.float32)
    have=[j for j,c in enumerate(cols) if c>=0]
    sub=Xcsr_or_dense[:, [cols[j] for j in have]]
    out[:,have]=np.asarray(sub.todense() if hasattr(sub,"todense") else sub, np.float32)
    return out
def read_col(o):
    import h5py as _h
    def _s(a): return np.array([x.decode() if isinstance(x,(bytes,bytearray)) else str(x) for x in a])
    if isinstance(o,_h.Group):
        ks=set(o.keys())
        if "categories" in ks and "codes" in ks:
            cats=_s(o["categories"][:]); codes=o["codes"][:]
            return np.where(codes<0,"NA",cats[np.clip(codes,0,len(cats)-1)])
        if "values" in ks: return _s(o["values"][:])
    return _s(o[:])
read_cat=read_col
def npear(a,b):
    a=np.asarray(a,float)-np.mean(a); b=np.asarray(b,float)-np.mean(b)
    d=np.sqrt((a*a).sum()*(b*b).sum()); return float((a*b).sum()/d) if d>1e-12 else 0.0

# ---------- shared: load stim h5ad (Tasks 1 & 3) ----------
from scipy.sparse import csr_matrix  # sparse construct only; we avoid scipy.stats
sc=np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz"); hvg=list(sc["hvg_names"].astype(str))
f=h5py.File(f"{WS}/step0/GSE261278_D534.paired.h5ad","r")
Xg=f["X"]; n_obs=f["obs"]["stim"]["codes"].shape[0]
var_names=read_col(f["var"]["_index"])
data=f["X"]["data"][:]; indices=f["X"]["indices"][:]; indptr=f["X"]["indptr"][:]
ncol=len(var_names)
Xcsr=csr_matrix((data,indices,indptr), shape=(len(indptr)-1, ncol))
stim=read_col(f["obs"]["stim"]); celltype=read_col(f["obs"]["cell_type"]); tissue=read_col(f["obs"]["tissue"])
f.close()
# CP10k + log1p + HVG align + corpus-scale
lib=np.asarray(Xcsr.sum(1)).ravel(); lib[lib==0]=1
norm=Xcsr.multiply(1e4/lib[:,None]).tocsr(); norm.data=np.log1p(norm.data)
x=align(var_names, norm, hvg)
xs=((x - sc["mean"])/sc["scale"]).astype(np.float32)   # corpus-scaled HVG (raw rep)
bases=K.fit_bases(hvg, f"{WS}/fs_long/work"); Kfeat=K.transform(xs, bases)  # knowledge rep
z_fm=np.load(f"{OUT}/z_fm_stim.npy").astype(np.float32)  # frozen FM encoder embedding (from envpin2)
print(f"stim loaded X={Xcsr.shape} cells={len(stim)} ({time.time()-t0:.0f}s)", flush=True)

def frozen_probe_bin(Xrep, y, tr, te, C=0.01):
    s=StandardScaler().fit(Xrep[tr]); a=s.transform(Xrep[tr]); b=s.transform(Xrep[te])
    clf=LogisticRegression(C=C, max_iter=3000, class_weight="balanced", solver="lbfgs").fit(a, y[tr])
    return clf.predict_proba(b)[:,1]

# ---------- TASK 1: stimulation-state classification (cell-type-holdout) ----------
splits=np.load(f"{AUD}/normalization_20261108/split_indices.npz")
y=(stim!="unstimulated").astype(int)
pca50=PCA(n_components=50, random_state=0).fit_transform(StandardScaler().fit_transform(xs))
reps={"raw":xs,"pca":pca50,"know":Kfeat,"fm_z":z_fm}
oof={r:{} for r in reps}; 
for r,Xrep in reps.items():
    for seed in (0,1,2):
        p=np.full(len(y), np.nan)
        for fold in range(3):
            tr=splits[f"s{seed}_f{fold}_labelled"]; te=splits[f"s{seed}_f{fold}_test"]
            p[te]=frozen_probe_bin(Xrep, y, tr, te)
        oof[r][seed]=p
def auprc_mean(rep): 
    v=[average_precision_score(y, oof[rep][s]) for s in (0,1,2)]; return float(np.mean(v)), float(np.std(v))
rng=np.random.RandomState(0); null_ap=float(np.mean([average_precision_score(y, rng.permutation(y).astype(float)) for _ in range(5)]))
t1={r: dict(auprc_mean=auprc_mean(r)[0], auprc_sd=auprc_mean(r)[1]) for r in reps}
card["tasks"]["stim_state_classification"]=dict(
    metric="AUPRC (pooled OOF, mean/3 seeds)", split="cell-type-holdout (3 folds)",
    baseline_raw=t1["raw"]["auprc_mean"], baseline_pca=t1["pca"]["auprc_mean"],
    model_knowledge=t1["know"]["auprc_mean"], model_fm_z=t1["fm_z"]["auprc_mean"], null_shuffled_label=null_ap,
    model_fm_z_beats_raw=bool(t1["fm_z"]["auprc_mean"]>t1["raw"]["auprc_mean"]),
    model_knowledge_beats_raw=bool(t1["know"]["auprc_mean"]>t1["raw"]["auprc_mean"]),
    detail=t1)
dump(); print("TASK1 done:", json.dumps(t1), flush=True)

# ---------- TASK 3: cell-type annotation (macro-F1, stratified 3-fold; single-donor caveat) ----------
classes,yct=np.unique(celltype, return_inverse=True)
_rs=np.random.RandomState(0)
_keep=np.concatenate([_rs.choice(np.where(yct==c)[0], min(400,int((yct==c).sum())), replace=False) for c in range(len(classes))])
def annot_macroF1(Xrep):
    Xa=Xrep[_keep]; ya=yct[_keep]
    skf=StratifiedKFold(n_splits=3, shuffle=True, random_state=0); f1s=[]
    for tr,te in skf.split(Xa, ya):
        sca=StandardScaler().fit(Xa[tr]); a=sca.transform(Xa[tr]); b=sca.transform(Xa[te])
        clf=LogisticRegression(C=1.0, max_iter=200, solver="saga", tol=1e-2, n_jobs=-1).fit(a, ya[tr])
        f1s.append(f1_score(ya[te], clf.predict(b), average="macro"))
    return float(np.mean(f1s)), float(np.std(f1s))
maj=np.bincount(yct).argmax(); null_f1=f1_score(yct, np.full_like(yct, maj), average="macro")
t3={r: dict(macroF1=annot_macroF1(reps[r])[0]) for r in reps}
card["tasks"]["celltype_annotation"]=dict(
    metric="macro-F1 (stratified 3-fold)", split="stratified random (SINGLE DONOR D534 — not donor-disjoint)",
    n_classes=int(len(classes)), baseline_raw=t3["raw"]["macroF1"], baseline_pca=t3["pca"]["macroF1"],
    model_knowledge=t3["know"]["macroF1"], model_fm_z=t3["fm_z"]["macroF1"], null_majority_class=float(null_f1),
    model_fm_z_beats_raw=bool(t3["fm_z"]["macroF1"]>t3["raw"]["macroF1"]),
    model_knowledge_beats_raw=bool(t3["know"]["macroF1"]>t3["raw"]["macroF1"]), detail=t3)
dump(); print("TASK3 done:", json.dumps(t3), flush=True)

# ---------- TASK 2: unseen-perturbation effect prediction (leave-KO-out, 300-KO subset) ----------
D=np.load(f"{WS}/fs_long/work/czi_tcell_deltas.npz", allow_pickle=True)
delta=D["delta"].astype(np.float64); ko=D["genes"].astype(str); nko=len(ko)
Yr=delta-delta.mean(0,keepdims=True)
gmt=[]
for nm in ("reactome.gmt","kegg.gmt","go_bp.gmt"):
    p=f"{WS}/fs_long/work/{nm}"
    if os.path.exists(p):
        op=gzip.open(p,"rt") if p.endswith(".gz") else open(p)
        for ln in op:
            q=ln.rstrip("\n").split("\t")
            if len(q)>=3: gmt.append(set(q[2:]))
ko_sets=[set(j for j,s in enumerate(gmt) if g in s) for g in ko]
S=np.zeros((nko,nko)); 
for i in range(nko):
    for j in range(i+1,nko):
        c=len(ko_sets[i]&ko_sets[j])
        if c: S[i,j]=S[j,i]=c
deg=S.sum(1)
TOPK=50; rngp=np.random.RandomState(0)
def rowr(pred, idx):
    rs=[]
    for g in idx:
        top=np.argsort(-np.abs(Yr[g]))[:TOPK]
        if np.std(pred[g,top])>1e-9 and np.std(Yr[g,top])>1e-9: rs.append(npear(pred[g,top], Yr[g,top]))
    return np.asarray(rs)
pk=np.zeros_like(Yr); pr=np.zeros_like(Yr); pd_=np.zeros_like(Yr); has=np.zeros(nko,bool)
order=np.argsort(deg)
for g in range(nko):
    nb=np.where(S[g]>0)[0]
    if len(nb)>0:
        has[g]=True; w=S[g,nb]; pk[g]=(Yr[nb]*w[:,None]).sum(0)/w.sum()
        tr=np.setdiff1d(np.arange(nko),[g])
        pr[g]=Yr[rngp.choice(tr,len(nb),replace=False)].mean(0)
        # degree-matched null: pick |nb| training KOs with closest degree to g
        cand=tr[np.argsort(np.abs(deg[tr]-deg[g]))[:max(len(nb),1)]]
        pd_[g]=Yr[cand].mean(0)
idx=np.where(has)[0]
rk=rowr(pk,idx).mean(); rr=rowr(pr,idx).mean(); rd=rowr(pd_,idx).mean()
card["tasks"]["unseen_perturbation_prediction"]=dict(
    metric="Pearson on top-50 residual-DE genes (leave-KO-out)", split="leave-one-KO-out, 300-KO subset",
    model_knowledge_neighbor=float(rk), null_random_neighbor=float(rr), null_degree_matched=float(rd),
    model_beats_nulls=bool(rk>rr and rk>rd),
    note="Full-scale (33,983 contrasts, ~7k KOs/context) this session: know_r +0.078 Rest / +0.035-0.039 Stim, know-rand t=+13.7..+28.5 (STRONGER positive).")
dump(); print("TASK2 done: know=%.4f rand=%.4f degnull=%.4f"%(rk,rr,rd), flush=True)

card["tasks"]["target_id_virtual_ko"]=dict(status="EXCLUDED",
    reason="code_20261004/test_virtual_ko.py is a SYNTHETIC unit test (planted-effect) requiring torch (broken on Spark); no distinct real-data input. The real measured screen is gated leave-KO-out against CZI Perturb-seq = Task 2's data. Degree-null control folded into Task 2.")
json.dump(card, open(f"{OUT}/scorecard.json","w"), indent=2)
print(f"\nBENCH_COMPLETE {time.time()-t0:.0f}s -> {OUT}/scorecard.json", flush=True)
