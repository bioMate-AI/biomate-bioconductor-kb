#!/bin/bash
# 3rd selection axis: predict permeability for the 8 1yf4 designs and do 3-objective selection
# (bind iptm x physics MM-GBSA dG x permeability). Consistent feature space: train the GBM on
# RDKit-computed descriptors from CycPeptMPDB SMILES (NOT the precomputed columns), then apply the
# SAME descriptor computation to the designs' HEAD-TO-TAIL-CYCLIZED mols (linear features would be
# useless — cyclization is the permeability lever). CPU, self-terminating.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/p3; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/p3.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 5; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 3; shutdown -h now; exit $rc' EXIT
systemd-run --unit=p3-deadline --on-active=1h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n p3 -c conda-forge python=3.11 rdkit scikit-learn pandas numpy scipy >/dev/null 2>&1
conda activate p3
python -c "import rdkit; from rdkit.Chem import Descriptors; print('rdkit ok')"

stage fetch_data
aws s3 cp "s3://$BUCKET/cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv" ./cyc.csv --only-show-errors
[ -s ./cyc.csv ] || { echo FATAL no csv; exit 1; }

stage run
python - <<'PY'
import json, numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, AllChem
RDLogger.DisableLog('rdApp.*')

# designs: (seq, iptm, MM-GBSA dG)  -- from the wired-loop join
DESIGNS=[("GSGLLKS",0.74047,-36.57),("SPSINGPMI",0.57666,-39.69),("SSLLFVPG",0.55327,-42.43),
         ("SFEASGFAPM",0.63599,-43.33),("SIYGTGLVPL",0.53307,-40.23),("YSGGGGV",0.6348,-24.27),
         ("FSRNVGDPY",0.73927,-52.71),("YVAGQPDPK",0.57895,-35.71)]

DESC=[n for n,_ in Descriptors._descList]
def desc_from_mol(m):
    try:
        vals=[]
        for n,f in Descriptors._descList:
            try: v=f(m)
            except Exception: v=np.nan
            vals.append(v)
        return np.array(vals,dtype=float)
    except Exception: return None

def feats_from_smiles(smi):
    m=Chem.MolFromSmiles(str(smi))
    return desc_from_mol(m) if m is not None else None

def cyclize(seq):
    # linear peptide -> head-to-tail macrocycle: bond C-term carbonyl C to N-term amine N, drop OH
    m=Chem.MolFromSequence(seq)
    if m is None: return None
    rw=Chem.RWMol(m)
    # N-terminal primary amine N
    nterm=[a.GetIdx() for a in rw.GetAtoms() if a.GetSymbol()=='N' and a.GetTotalNumHs()>=2 and
           not any(nb.GetSymbol()=='C' and any(b.GetBondTypeAsDouble()==2 for b in nb.GetBonds()) for nb in a.GetNeighbors())]
    # C-terminal carboxyl: C(=O)OH
    patt=Chem.MolFromSmarts('[CX3](=[OX1])[OX2H1]')
    cm=rw.GetSubstructMatches(patt)
    if not nterm or not cm: return None
    nidx=nterm[0]; cC,cO_dbl,cO_h = cm[-1]
    rw.RemoveAtom(cO_h)                       # remove -OH oxygen (indices may shift; remove highest first not needed: single)
    # after removal indices > cO_h shift by -1
    def adj(i): return i-1 if i>cO_h else i
    rw.AddBond(adj(cC), adj(nidx), Chem.BondType.SINGLE)
    mol=rw.GetMol()
    try: Chem.SanitizeMol(mol)
    except Exception: return None
    return mol

# --- train permeability GBM on RDKit descriptors from CycPeptMPDB SMILES (consistent space) ---
df=pd.read_csv('cyc.csv', low_memory=False)
df=df[pd.to_numeric(df['Permeability'],errors='coerce').notna()].copy(); df['Permeability']=df['Permeability'].astype(float)
# subsample for speed (representative)
df=df.sample(min(4000,len(df)), random_state=42)
X=[];y=[]
for smi,val in zip(df['SMILES'],df['Permeability']):
    f=feats_from_smiles(smi)
    if f is not None: X.append(f); y.append(val)
X=np.array(X); y=np.array(y)
X=np.nan_to_num(np.clip(X,-1e30,1e30), nan=0.0)
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import cross_val_predict, KFold
from sklearn.metrics import r2_score
from scipy.stats import spearmanr
mdl=HistGradientBoostingRegressor(max_iter=400,learning_rate=0.05)
p=cross_val_predict(mdl,X,y,cv=KFold(5,shuffle=True,random_state=42))
cvR2=round(float(r2_score(y,p)),3); cvSp=round(float(spearmanr(y,p).correlation),3)
print(f"perm model (RDKit-desc, n={len(y)}): CV R2={cvR2} Spearman={cvSp}")
mdl.fit(X,y)

# --- predict permeability for the cyclized designs ---
rows=[]
for seq,iptm,dg in DESIGNS:
    cm=cyclize(seq)
    if cm is None: perm=None
    else:
        f=desc_from_mol(cm)
        perm=float(mdl.predict(np.nan_to_num(np.clip(f.reshape(1,-1),-1e30,1e30),nan=0.0))[0]) if f is not None else None
    rows.append({'seq':seq,'iptm':iptm,'dG':dg,'perm_pred':round(perm,3) if perm is not None else None,'cyclized':cm is not None})

# --- 3-objective selection (maximize iptm, minimize dG, maximize perm_pred = higher logPapp) ---
ok=[r for r in rows if r['perm_pred'] is not None]
def nrm(vals):
    lo,hi=min(vals),max(vals); return [(v-lo)/(hi-lo) if hi>lo else 0.5 for v in vals]
if ok:
    iN=nrm([r['iptm'] for r in ok]); gN=nrm([-r['dG'] for r in ok]); pN=nrm([r['perm_pred'] for r in ok])
    for r,a,b,c in zip(ok,iN,gN,pN): r['combined3']=round(a+b+c,3); r['_i']=a; r['_g']=b; r['_p']=c
    # Pareto over (iptm up, dG down, perm up)
    def dom(a,b): return (b['iptm']>=a['iptm'] and b['dG']<=a['dG'] and b['perm_pred']>=a['perm_pred']) and (b['iptm']>a['iptm'] or b['dG']<a['dG'] or b['perm_pred']>a['perm_pred'])
    for r in ok: r['pareto3']= not any(dom(r,o) for o in ok if o is not r)
    ok.sort(key=lambda x:-x['combined3'])
out={'perm_model_cv':{'R2':cvR2,'Spearman':cvSp,'n':len(y),'features':'RDKit 2D descriptors (%d)'%X.shape[1]},
     'note':'perm_pred = predicted log Papp for the head-to-tail cyclized design (higher = more permeable). '
            '3-objective: bind(iptm) x physics(MM-GBSA dG) x permeability(pred). Perm is a RANKING signal '
            '(model R2~0.3-0.45); designs cyclized in RDKit for consistent featurization.',
     'ranking': [{k:r[k] for k in ('seq','iptm','dG','perm_pred','combined3','pareto3','cyclized')} for r in ok]}
json.dump(out, open('/opt/p3/status/perm3_select.json','w'), indent=2)
print(json.dumps(out, indent=2))
PY
stage p3_complete
