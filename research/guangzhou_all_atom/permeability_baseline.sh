#!/bin/bash
# Permeability differentiator — STEP 1: fix the R^2=0.23 floor with a proper descriptor+GBM baseline on
# CycPeptMPDB (survey's #1 recommendation: boosted-trees-on-descriptors is the bar; DMPNN R^2~0.555 is
# the field yardstick). Honest splits (random AND scaffold). CPU, self-terminating.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/perm; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/perm.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 5; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 3; shutdown -h now; exit $rc' EXIT
systemd-run --unit=perm-deadline --on-active=1h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n perm -c conda-forge python=3.11 rdkit scikit-learn pandas numpy scipy >/dev/null 2>&1
conda activate perm
python -c "import rdkit, sklearn, pandas; print('deps ok', sklearn.__version__)"

stage fetch_data
# CycPeptMPDB is staged at cyclic_peptide/raw/ (not datasets/); direct cp, with a broad search fallback
CSV=./cyc.csv
aws s3 cp "s3://$BUCKET/cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv" "$CSV" --only-show-errors 2>/dev/null || true
if [ ! -s "$CSV" ]; then
  KEY=$(aws s3 ls "s3://$BUCKET/cyclic_peptide/" --recursive | grep -iE "cycpept.*peptide.*\.csv" | awk '{print $4}' | head -1)
  [ -n "$KEY" ] && aws s3 cp "s3://$BUCKET/$KEY" "$CSV" --only-show-errors
fi
[ -s "$CSV" ] || { echo "FATAL: CycPeptMPDB csv not found in S3"; exit 1; }
wc -l ./cyc.csv; head -1 ./cyc.csv | tr ',' '\n' | head -40

stage train
python - <<'PY'
import json, numpy as np, pandas as pd
from rdkit import Chem
from rdkit.Chem import AllChem, Descriptors, rdMolDescriptors
from rdkit.Chem.Scaffolds import MurckoScaffold
from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestRegressor
from sklearn.metrics import r2_score, mean_squared_error
from scipy.stats import spearmanr

df=pd.read_csv('cyc.csv')
cols={c.lower():c for c in df.columns}
# find SMILES + permeability columns robustly
# CycPeptMPDB: 'Permeability' is the dense main log-Papp target (all rows); 'PAMPA' the largest assay.
smi_col='SMILES' if 'SMILES' in df.columns else next((cols[k] for k in cols if 'smiles' in k), None)
perm_col=('Permeability' if 'Permeability' in df.columns else
          'PAMPA' if 'PAMPA' in df.columns else
          next((cols[k] for k in cols if k in ('pampa','logpapp','papp')), None))
print('smiles col:', smi_col, ' perm col:', perm_col)
assert smi_col and perm_col, f"columns not found: {list(df.columns)[:30]}"
df=df[pd.to_numeric(df[perm_col],errors='coerce').notna()].copy(); df[perm_col]=df[perm_col].astype(float)
print('rows with numeric perm:', len(df))

# RICH features: CycPeptMPDB ships ~150 precomputed RDKit descriptors incl computed 3D-PSA variants
# (_3DPSA, CHCl3_3DPSA, H2O_3DPSA) — a proper baseline vs the thin Morgan+10 that only reached ~0.29.
# Drop IDs/labels/assays and EPSA (experimental/sparse) to avoid leakage; keep computed descriptors.
drop=set(['ID','Source','Year','Version','Original_Name_in_Source_Literature','Structurally_Unique_ID',
          'Same_Peptides_ID','Same_Peptides_Source','Same_Peptides_Permeability','Same_Peptides_Assay',
          'SMILES','HELM','HELM_URL','Sequence','Molecule_Shape','Permeability','PAMPA','Caco2','MDCK',
          'RRCK','Detection_Limit_1','Detection_Limit_2','R_PAMAP','R_Caco2','R_MDCK','R_RRCK','T_PAMPA',
          'EPSA','NULL'])
feat_cols=[c for c in df.columns if c not in drop]
Xdf=df[feat_cols].apply(pd.to_numeric, errors='coerce')
Xdf=Xdf.dropna(axis=1, how='all')                      # drop all-NaN cols
Xdf=Xdf.fillna(Xdf.median(numeric_only=True))
threeD=[c for c in Xdf.columns if 'PSA' in c or '3D' in c.upper()]
print('rich feature count:', Xdf.shape[1], '| 3D/PSA features:', threeD)
X=Xdf.values.astype(float); y=df[perm_col].values.astype(float)
from rdkit.Chem.Scaffolds import MurckoScaffold
def _scaf(smi):
    m=Chem.MolFromSmiles(str(smi));
    return MurckoScaffold.MurckoScaffoldSmiles(mol=m) if m else 'NA'
scaf=np.array([_scaf(s) for s in df[smi_col]])
print('featurized (rich):', X.shape, ' target range', round(float(y.min()),2), round(float(y.max()),2))

def evaluate(tr,te,name):
    res={}
    for mdl,tag in [(HistGradientBoostingRegressor(max_iter=500,learning_rate=0.05),'HistGBM'),
                    (RandomForestRegressor(n_estimators=300,n_jobs=-1),'RF')]:
        mdl.fit(X[tr],y[tr]); p=mdl.predict(X[te])
        res[tag]={'R2':round(float(r2_score(y[te],p)),3),
                  'RMSE':round(float(mean_squared_error(y[te],p)**0.5),3),
                  'Spearman':round(float(spearmanr(y[te],p).correlation),3)}
    return res

rng=np.random.RandomState(42); idx=rng.permutation(len(y)); cut=int(0.8*len(y))
report={'n':len(y),'prior_baseline_R2':0.231,'field_yardstick_DMPNN_R2':0.555,
        'random_split': evaluate(idx[:cut], idx[cut:], 'random')}
# scaffold split: hold out whole scaffolds (leak-free)
uniq=list(pd.unique(scaf)); rng.shuffle(uniq); test_sc=set(uniq[:max(1,int(0.2*len(uniq)))])
te=np.array([i for i in range(len(y)) if scaf[i] in test_sc]); tr=np.array([i for i in range(len(y)) if scaf[i] not in test_sc])
report['scaffold_split']= evaluate(tr, te, 'scaffold') if len(te)>10 and len(tr)>10 else 'insufficient scaffolds'
report['note']=('Descriptor(Morgan1024+10 RDKit)+GBM permeability baseline on CycPeptMPDB. Random split '
                'is optimistic; scaffold split is the honest generalization number. Beating the prior '
                'R2=0.231 confirms the floor was features/model, not data; MD-ensemble descriptors (CREMP) '
                'are the next lift for OOD per the transfer survey.')
json.dump(report, open('/opt/perm/status/permeability_baseline.json','w'), indent=2)
print(json.dumps(report, indent=2))
PY
stage perm_complete
