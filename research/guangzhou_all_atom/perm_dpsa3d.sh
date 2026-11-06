#!/bin/bash
# Build A — EnsembleCycPerm ΔPSA3D permeability, keyed on the CycPeptMPDB-4D dataset (Zenodo 21274695,
# CC-BY-4.0). Adopts the chameleon 2-environment recipe WITHOUT our old per-peptide GAFF/AM1-BCC(sqm)
# parametrization — that step (which produced kept=0 on spot, PROGRAM_STATE 2026-09-19) is REPLACED by the
# dataset's precomputed ensemble-averaged Water_3D_PSA / Hexane_3D_PSA. We only derive ΔPSA3D and fit.
# Controlled: SAME peptides, 5-fold SHUFFLED CV + a SCAFFOLD split, 2D-only vs 2D+ΔPSA3D vs ΔPSA3D-only.
# CPU, cheap, deterministic (no OpenMM / no AmberTools / no sqm). Honest caveat baked into the note.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/dpsa; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
ZENODO_CSV_URL=${ZENODO_CSV_URL:-https://zenodo.org/records/21274695/files/CycPeptMPDB-4D.csv}
CACHE_S3=${CACHE_S3:-s3://$BUCKET/cyclic_peptide/datasets/cycpeptmpdb_4d/CycPeptMPDB-4D.csv}  # mirror once, reuse
BUDGET_S=${BUDGET_S:-3600}
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/dpsa.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","detail":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "${2:-}" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 5; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 3; shutdown -h now; exit $rc' EXIT
systemd-run --unit=dpsa-deadline --on-active=2h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n dpsa -c conda-forge python=3.11 rdkit scikit-learn pandas numpy scipy >/dev/null 2>&1
conda activate dpsa
python -c "import rdkit, sklearn, pandas; from rdkit.Chem import AllChem; print('deps ok')"

stage fetch_data
# Prefer our S3 mirror (CC-BY, attribute upstream); fall back to Zenodo direct, then mirror it for next time.
if aws s3 cp "$CACHE_S3" ./cyc4d.csv --only-show-errors 2>/dev/null && [ -s ./cyc4d.csv ]; then
  echo "loaded CycPeptMPDB-4D.csv from S3 mirror"
else
  curl -fsSL "$ZENODO_CSV_URL" -o ./cyc4d.csv
  [ -s ./cyc4d.csv ] || { echo "FATAL: could not fetch CycPeptMPDB-4D.csv"; exit 1; }
  aws s3 cp ./cyc4d.csv "$CACHE_S3" --only-show-errors || true   # mirror for reuse (dataset is CC-BY-4.0)
fi

stage run
BUDGET_S=$BUDGET_S OUT_S3=$OUT_S3 python - <<'PY'
import os, json, time, numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem, Descriptors, MolToSmiles
from rdkit.Chem.Scaffolds import MurckoScaffold
RDLogger.DisableLog('rdApp.*')
t0=time.time(); BUDGET=float(os.environ['BUDGET_S'])

df=pd.read_csv('cyc4d.csv', low_memory=False)
# target: PAMPA logPapp (the CycPeptMPDB permeability endpoint)
df=df[pd.to_numeric(df['PAMPA'],errors='coerce').notna()].copy()
df['PAMPA']=df['PAMPA'].astype(float)

# ---- 2-environment (chameleon) block: precomputed by CycPeptMPDB-4D, ensemble-averaged over MD ----
# NO per-peptide OpenMM/GAFF/sqm here — that was the kept=0 blocker; the 4D dataset already did it.
env_cols=['Water_3D_PSA','Hexane_3D_PSA','Water_3D_NPSA','Hexane_3D_NPSA',
          'Water_3D_SASA','Hexane_3D_SASA','Water_avgGR','Hexane_avgGR',
          'Water_Desolvation_Free_Energy']
env_cols=[c for c in env_cols if c in df.columns]
for c in env_cols: df[c]=pd.to_numeric(df[c],errors='coerce')
df=df.dropna(subset=['Water_3D_PSA','Hexane_3D_PSA']).reset_index(drop=True)
# THE chameleon term (EnsembleCycPerm ΔPSA3D) + companion deltas
df['dPSA3D']  = df['Water_3D_PSA']  - df['Hexane_3D_PSA']      # polarity shielding on membrane entry
df['dNPSA3D'] = df.get('Water_3D_NPSA',0) - df.get('Hexane_3D_NPSA',0)
df['dSASA3D'] = df.get('Water_3D_SASA',0) - df.get('Hexane_3D_SASA',0)
df['dRg']     = df.get('Water_avgGR',0)   - df.get('Hexane_avgGR',0)
ENV=['dPSA3D','dNPSA3D','dSASA3D','dRg'] + env_cols
Xe=df[ENV].apply(pd.to_numeric,errors='coerce').replace([np.inf,-np.inf],np.nan)
Xe=Xe.fillna(Xe.median(numeric_only=True)).clip(-1e30,1e30).values.astype(float)

# ---- 2D descriptor block (baseline to beat: our R2~0.45 ceiling) ----
DESCS=Descriptors._descList
def feat2d(smi):
    m=Chem.MolFromSmiles(str(smi))
    if m is None: return None
    v=[]
    for _,f in DESCS:
        try: v.append(f(m))
        except: v.append(np.nan)
    return np.array(v,float)
f2=[feat2d(s) for s in df['SMILES']]
keep=[i for i,v in enumerate(f2) if v is not None]
df=df.iloc[keep].reset_index(drop=True); Xe=Xe[keep]
X2=np.nan_to_num(np.clip(np.array([f2[i] for i in keep]),-1e30,1e30))
y=df['PAMPA'].values.astype(float)
print('n peptides:', len(y), '| 2D dims:', X2.shape[1], '| env dims:', Xe.shape[1])

# ---- Bemis-Murcko scaffold labels (for the honest scaffold split) ----
def scaf(smi):
    m=Chem.MolFromSmiles(str(smi))
    if m is None: return 'none'
    try: return MolToSmiles(MurckoScaffold.GetScaffoldForMol(m))
    except: return 'none'
scaffolds=np.array([scaf(s) for s in df['SMILES']])

from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import cross_val_predict, KFold, GroupKFold
from sklearn.metrics import r2_score
from scipy.stats import spearmanr, pearsonr
def mk(): return HistGradientBoostingRegressor(max_iter=400, learning_rate=0.05)
def score(yt,yp): return {'R2':round(float(r2_score(yt,yp)),3),
                          'Pearson':round(float(pearsonr(yt,yp)[0]),3),
                          'Spearman':round(float(spearmanr(yt,yp).correlation),3)}
# random 5-fold (shuffled — the same gotcha we already documented in conformer_permeability.sh)
KF=KFold(5,shuffle=True,random_state=0)
def cv_rand(X): return score(y, cross_val_predict(mk(),X,y,cv=KF))
# scaffold 5-fold via GroupKFold on Murcko scaffolds (the honest generalization number)
n_groups=len(set(scaffolds)); gk=GroupKFold(n_splits=min(5,n_groups))
def cv_scaf(X): return score(y, cross_val_predict(mk(),X,y,groups=scaffolds,cv=gk))

res={'n':len(y),'dataset':'CycPeptMPDB-4D (Zenodo 21274695, CC-BY-4.0)',
     'target':'PAMPA (logPapp)',
     'random_split':{'2D_only':cv_rand(X2),
                     '2D_plus_dPSA3D':cv_rand(np.hstack([X2,Xe])),
                     'dPSA3D_only':cv_rand(Xe)},
     'scaffold_split':{'2D_only':cv_scaf(X2),
                       '2D_plus_dPSA3D':cv_scaf(np.hstack([X2,Xe])),
                       'dPSA3D_only':cv_scaf(Xe)},
     'dPSA3D_vs_target_spearman':round(float(spearmanr(df['dPSA3D'],y).correlation),3),
     'note':('2-environment chameleon dPSA3D adopted from EnsembleCycPerm (JCIM 66:8123, 2026); '
             'Water/Hexane ensemble-avg 3D-PSA are PRECOMPUTED in CycPeptMPDB-4D -> no per-peptide '
             'GAFF/AM1-BCC(sqm) (the kept=0 blocker, PROGRAM_STATE 2026-09-19). Compare vs our 2D R2~0.45 '
             'ceiling. HONEST: EnsembleCycPerm reports random R2 0.70 / scaffold R 0.68; the 13-method '
             'CycPeptMP benchmark best random R2~0.555 with a significant scaffold drop; the survey warns '
             'cheap conformer-VARIANCE features carry <2% signal — the ENSEMBLE-AVERAGED dPSA3D (real '
             'water/hexane MD), not variance, is the term expected to lift. Report the scaffold number as '
             'the real one.')}
json.dump(res, open('/opt/dpsa/status/perm_dpsa3d.json','w'), indent=2)
os.system(f'aws s3 cp /opt/dpsa/status/perm_dpsa3d.json {os.environ["OUT_S3"]}/status/perm_dpsa3d.json --only-show-errors 2>/dev/null')
print(json.dumps(res, indent=2))
PY
stage dpsa_complete
