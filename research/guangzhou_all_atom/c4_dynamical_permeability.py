"""C4: do 3D/conformational (chameleon) features beat the static ECFP permeability ceiling?
Same leak-free Murcko generic-scaffold folds + HistGBM as permeability_predictor.py (scaffold R2=0.231).
Chameleon signal = 3D-PSA shielding (H2O_3DPSA - CHCl3_3DPSA) etc., already computed in CycPeptMPDB."""
import csv, sys, numpy as np
from rdkit import Chem
from rdkit.Chem import rdFingerprintGenerator
from rdkit.Chem.Scaffolds import MurckoScaffold
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import r2_score, mean_absolute_error, mean_squared_error

CSV="research/guangzhou_all_atom/data/raw/CycPeptMPDB_Peptide_All.csv"
FP=rdFingerprintGenerator.GetMorganGenerator(radius=2,fpSize=2048)
D3=["CHCl3_3DPSA","H2O_3DPSA","_3DPSA","PSA","TPSA","MolLogP","MolWt" if False else "TPSA"]
CHAM=["CHCl3_3DPSA","H2O_3DPSA","_3DPSA","PSA","TPSA"]   # computed 3D/2D PSA (chameleon) — NO experimental EPSA
def num(x):
    try: return float(x)
    except: return np.nan
rows=[]
with open(CSV) as f:
    for r in csv.DictReader(f):
        smi=(r.get("SMILES") or "").strip()
        try: perm=float(r.get("Permeability",""))
        except: continue
        m=Chem.MolFromSmiles(smi) if smi else None
        if m is None: continue
        rows.append((m,perm,r))
print(f"n valid = {len(rows)}")
y=np.array([p for _,p,_ in rows])
# ECFP
X_ecfp=np.array([np.frombuffer(FP.GetFingerprint(m).ToBitString().encode(),'u1')-48 for m,_,_ in rows],dtype=np.int8)
# chameleon computed-3D features (+ engineered shielding delta)
def feat(r):
    v=[num(r.get(c)) for c in CHAM]
    c,h=num(r.get("CHCl3_3DPSA")),num(r.get("H2O_3DPSA"))
    v+=[h-c, (h-c)/(h+1e-6)]   # PSA collapse (chameleon) absolute + fractional
    return v
X_cham=np.array([feat(r) for _,_,r in rows],dtype=float)
X_both=np.hstack([X_ecfp,X_cham])
# EPSA-augmented (experimental descriptor; flagged)
X_epsa=np.array([feat(r)+[num(r.get("EPSA"))] for _,_,r in rows],dtype=float)
# scaffold folds (largest-first round-robin, no scaffold crosses folds) — same as baseline
scaf=[]
for m,_,_ in rows:
    try: scaf.append(MurckoScaffold.MurckoScaffoldSmiles(mol=MurckoScaffold.GetScaffoldForMol(m),includeChirality=False))
    except: scaf.append("")
scaf=np.array(scaf)
from collections import defaultdict
g=defaultdict(list)
for i,s in enumerate(scaf): g[s].append(i)
folds=[[] for _ in range(5)]; sz=sorted(g.values(),key=len,reverse=True)
for j,idx in enumerate(sz): folds[j%5].extend(idx)
fold=np.zeros(len(y),int)
for k,idx in enumerate(folds):
    for i in idx: fold[i]=k
print(f"n scaffolds = {len(g)}")
def cv(X):
    oof=np.zeros(len(y))
    for k in range(5):
        te=fold==k; tr=~te
        mdl=HistGradientBoostingRegressor(max_iter=300,learning_rate=0.06,random_state=0)
        mdl.fit(X[tr],y[tr]); oof[te]=mdl.predict(X[te])
    from scipy.stats import spearmanr
    return r2_score(y,oof),mean_absolute_error(y,oof),spearmanr(y,oof).correlation
import json
res={}
for name,X in [("ECFP (static baseline)",X_ecfp),("chameleon-3D (computed, no EPSA)",X_cham),
               ("ECFP + chameleon-3D",X_both),("chameleon-3D + EPSA (experimental)",X_epsa)]:
    r2,mae,sp=cv(X); res[name]={"scaffold_r2":round(r2,3),"mae":round(mae,3),"spearman":round(sp,3)}
    print(f"{name:40s}  R2={r2:.3f}  MAE={mae:.3f}  Spearman={sp:.3f}")
json.dump({"n":len(y),"n_scaffolds":len(g),"baseline_ref_r2":0.231,"results":res},
          open("research/guangzhou_all_atom/results/c4_dynamical_permeability.json","w"),indent=1)
