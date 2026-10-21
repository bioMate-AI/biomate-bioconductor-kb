"""C4-forward: explicit conformer-ENSEMBLE (chameleon-dynamics) permeability features vs the
single-point 3D-PSA proxy (R2=0.301) and static ECFP (R2=0.237).

Honest scope: RDKit ETKDGv3 gas-phase ensembles (CPU, no GPU) — real flexibility/shielding dynamics,
NOT explicit membrane-vs-water MD (GPU next lever). CACHED + RESUMABLE (featurization is ~9 s/mol →
~21 h for full 8466, exceeds one window), so repeated runs accumulate. CV runs once >=MIN_CV cached.
Same leak-free Murcko scaffold folds + HistGBM as the C4 baseline, same-subset apples-to-apples.
"""
import csv, os, json, time, random, hashlib, numpy as np
from rdkit import Chem
from rdkit.Chem import AllChem, rdFingerprintGenerator, Descriptors3D
from rdkit.Chem.Scaffolds import MurckoScaffold
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import r2_score, mean_absolute_error
from scipy.stats import spearmanr

CSV="research/guangzhou_all_atom/data/raw/CycPeptMPDB_Peptide_All.csv"
CACHE="research/guangzhou_all_atom/results/c4_ensemble_cache.jsonl"
KCONF=20; MIN_CV=600            # need >=600 cached before a (less-underpowered) CV
TIME_BUDGET=6000               # seconds of featurization per invocation, then stop (resumable)
random.seed(0)
FP=rdFingerprintGenerator.GetMorganGenerator(radius=2,fpSize=2048)
def num(x):
    try: return float(x)
    except: return np.nan
def key(s): return hashlib.md5(s.encode()).hexdigest()[:16]

# ---- load dataset (full, shuffled deterministically) ----
raw=[]
for r in csv.DictReader(open(CSV)):
    smi=(r.get("SMILES") or "").strip()
    try: perm=float(r.get("Permeability",""))
    except: continue
    if smi: raw.append((smi,perm,r))
random.shuffle(raw)

# ---- load cache ----
cache={}
if os.path.exists(CACHE):
    for line in open(CACHE):
        try:
            d=json.loads(line); cache[d["k"]]=d
        except: pass
print(f"dataset={len(raw)}  cached={len(cache)}",flush=True)

def ihb(mol,conf):
    pos=conf.GetPositions(); dH=[]; acc=[]
    for a in mol.GetAtoms():
        if a.GetSymbol() in("N","O"):
            acc.append(a.GetIdx())
            for nb in a.GetNeighbors():
                if nb.GetSymbol()=="H": dH.append((nb.GetIdx(),a.GetIdx()))
    n=0
    for hi,di in dH:
        for ai in acc:
            if ai==di or mol.GetBondBetweenAtoms(di,ai): continue
            if np.linalg.norm(pos[hi]-pos[ai])<2.5: n+=1
    return n

def ens(smi):
    m=Chem.MolFromSmiles(smi)
    if m is None: return None
    m=Chem.AddHs(m)
    p=AllChem.ETKDGv3(); p.randomSeed=0; p.useRandomCoords=True; p.useMacrocycleTorsions=True
    p.maxIterations=200; p.numThreads=0
    cids=AllChem.EmbedMultipleConfs(m,numConfs=KCONF,params=p)
    if len(cids)<3: return None
    rg=[];hb=[];asph=[];npr=[];ecc=[]
    for c in cids:
        try:
            rg.append(Descriptors3D.RadiusOfGyration(m,confId=c)); asph.append(Descriptors3D.Asphericity(m,confId=c))
            npr.append(Descriptors3D.NPR1(m,confId=c)); ecc.append(Descriptors3D.Eccentricity(m,confId=c))
            hb.append(ihb(m,m.GetConformer(c)))
        except: continue
    if len(rg)<3: return None
    rg=np.array(rg,float); hb=np.array(hb,float)
    return [rg.mean(),rg.std(),rg.max()-rg.min(),hb.mean(),hb.std(),hb.max(),hb.min(),
            float(np.mean(asph)),float(np.std(asph)),float(np.mean(npr)),float(np.std(npr)),
            float(np.mean(ecc)),len(cids)]

# ---- featurize (resumable, time-boxed) ----
t0=time.time(); added=0
with open(CACHE,"a") as cf:
    for smi,perm,r in raw:
        k=key(smi)
        if k in cache: continue
        if time.time()-t0>TIME_BUDGET: break
        f=ens(smi)
        if f is None: continue
        rec={"k":k,"smi":smi,"perm":perm,"ens":f,
             "stat":[num(r.get("CHCl3_3DPSA")),num(r.get("H2O_3DPSA")),
                     num(r.get("H2O_3DPSA"))-num(r.get("CHCl3_3DPSA")),num(r.get("_3DPSA")),num(r.get("TPSA"))]}
        cf.write(json.dumps(rec)+"\n"); cf.flush(); cache[k]=rec; added+=1
        if added%50==0: print(f"  +{added} (total {len(cache)}) {time.time()-t0:.0f}s",flush=True)
print(f"featurized +{added}, total cached={len(cache)} ({time.time()-t0:.0f}s)",flush=True)

# ---- CV only when enough cached ----
if len(cache)<MIN_CV:
    print(f"ACCUMULATING: {len(cache)}/{MIN_CV} cached — re-run to continue; CV deferred.",flush=True)
    raise SystemExit(0)

recs=list(cache.values())
y=np.array([d["perm"] for d in recs])
mols=[Chem.MolFromSmiles(d["smi"]) for d in recs]
X_ecfp=np.array([np.frombuffer(FP.GetFingerprint(m).ToBitString().encode(),'u1')-48 for m in mols],dtype=np.int8)
X_stat=np.array([d["stat"] for d in recs],float)
X_ens=np.array([d["ens"] for d in recs],float)
def dropdegen(X):              # HistGBM binning crashes on columns with <2 distinct values
    X=np.asarray(X,float); keep=[j for j in range(X.shape[1]) if np.unique(X[~np.isnan(X[:,j]),j]).size>=2]
    return X[:,keep] if keep else X
scaf=[]
for m in mols:
    try: scaf.append(MurckoScaffold.MurckoScaffoldSmiles(mol=MurckoScaffold.GetScaffoldForMol(m),includeChirality=False))
    except: scaf.append("")
from collections import defaultdict
g=defaultdict(list)
for i,s in enumerate(scaf): g[s].append(i)
folds=[[] for _ in range(5)]
for j,idx in enumerate(sorted(g.values(),key=len,reverse=True)): folds[j%5].extend(idx)
fold=np.zeros(len(y),int)
for k,idx in enumerate(folds):
    for i in idx: fold[i]=k
def cv(X):
    X=dropdegen(X); oof=np.zeros(len(y))
    for k in range(5):
        te=fold==k;tr=~te
        md=HistGradientBoostingRegressor(max_iter=300,learning_rate=0.06,random_state=0)
        md.fit(X[tr],y[tr]); oof[te]=md.predict(X[te])
    return r2_score(y,oof),mean_absolute_error(y,oof),spearmanr(y,oof).correlation
res={}
for name,X in [("ECFP (static baseline)",X_ecfp),("static 3D-PSA proxy",X_stat),
               ("ensemble-dynamics (ETKDG)",X_ens),("ECFP + static-proxy",np.hstack([X_ecfp,X_stat])),
               ("ECFP + ensemble",np.hstack([X_ecfp,X_ens])),("ECFP + static + ensemble",np.hstack([X_ecfp,X_stat,X_ens]))]:
    r2,mae,sp=cv(X); res[name]={"scaffold_r2":round(r2,3),"mae":round(mae,3),"spearman":round(sp,3)}
    print(f"{name:34s} R2={r2:.3f} Spearman={sp:.3f}",flush=True)
json.dump({"n":len(y),"n_scaffolds":len(g),"kconf":KCONF,
           "note":"RDKit ETKDGv3 gas-phase ensembles (CPU); NOT membrane MD; leak-free scaffold folds; same-subset",
           "ref_full8466":{"ECFP":0.237,"ECFP+staticproxy":0.301},"results":res},
          open("research/guangzhou_all_atom/results/c4_ensemble_permeability.json","w"),indent=1)
print("WROTE results/c4_ensemble_permeability.json",flush=True)
