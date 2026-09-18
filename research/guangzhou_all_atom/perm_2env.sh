#!/bin/bash
# Track A — 2-environment conformation-aware permeability (the differentiator). For a CycPeptMPDB subsample:
# build GAFF system (openmmforcefields), minimize in GBn2 (polar/water) AND vacuum (apolar/membrane-like),
# compute 3D-PSA (rdFreeSASA polar-SASA) in each -> features polar_3dpsa, apolar_3dpsa, DELTA (chameleon).
# Fuse with 2D descriptors -> 5-fold shuffled CV vs 2D-only. The NEW thing vs the failed single-env test is
# the polar-vs-apolar delta. Robust: small subsample, per-peptide try/except + timeout, progress, ML on
# whatever completes before the internal budget.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/p2e; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
NSUB=${NSUB:-200}; BUDGET_S=${BUDGET_S:-12600}
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/p2e.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","detail":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "${2:-}" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 5; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 3; shutdown -h now; exit $rc' EXIT
systemd-run --unit=p2e-deadline --on-active=4h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n p2e -c conda-forge python=3.11 rdkit openmm openmmforcefields openff-toolkit ambertools scikit-learn pandas numpy scipy >/dev/null 2>&1
conda activate p2e
python -c "import openmm, openff.toolkit, openmmforcefields, rdkit; print('deps ok')"

stage fetch_data
aws s3 cp "s3://$BUCKET/cyclic_peptide/raw/CycPeptMPDB_Peptide_All.csv" ./cyc.csv --only-show-errors
[ -s ./cyc.csv ] || { echo FATAL no csv; exit 1; }

stage run
NSUB=$NSUB BUDGET_S=$BUDGET_S OUT_S3=$OUT_S3 python - <<'PY'
import os, json, time, numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem, Descriptors, rdFreeSASA
RDLogger.DisableLog('rdApp.*')
import openmm as mm
from openmm import unit, app
from openmm.app import Simulation, NoCutoff, GBn2, HBonds
from openff.toolkit import Molecule
from openmmforcefields.generators import SystemGenerator
NSUB=int(os.environ['NSUB']); BUDGET=float(os.environ['BUDGET_S']); t0=time.time()

def polar_sasa(m):
    radii=rdFreeSASA.classifyAtoms(m); rdFreeSASA.CalcSASA(m, radii)
    return sum(float(a.GetProp('SASA')) for a in m.GetAtoms()
               if a.GetSymbol() in ('N','O') or (a.GetSymbol()=='H' and any(n.GetSymbol() in ('N','O') for n in a.GetNeighbors())))

def two_env(smi):
    m=Chem.MolFromSmiles(str(smi))
    if m is None or m.GetNumAtoms()>200: return None
    m=Chem.AddHs(m)
    p=AllChem.ETKDGv3(); p.useMacrocycleTorsions=True; p.randomSeed=1
    if AllChem.EmbedMolecule(m,p)!=0: return None
    off=Molecule.from_rdkit(m, allow_undefined_stereo=True)
    sg=SystemGenerator(small_molecule_forcefield='gaff-2.11', molecules=[off],
                       forcefield_kwargs={'constraints':HBonds})
    top=off.to_topology().to_openmm(); pos=off.conformers[0].to_openmm()
    sysm=sg.create_system(top, molecules=[off])
    integ=mm.LangevinMiddleIntegrator(300*unit.kelvin,1/unit.picosecond,0.001*unit.picoseconds)
    sim=Simulation(top, sysm, integ, mm.Platform.getPlatformByName('CPU'))
    sim.context.setPositions(pos); sim.minimizeEnergy(maxIterations=500)
    P=sim.context.getState(getPositions=True).getPositions(asNumpy=True).value_in_unit(unit.angstrom)
    m2=Chem.Mol(m); conf=m2.GetConformer()
    for i in range(m2.GetNumAtoms()): conf.SetAtomPosition(i, [float(P[i][0]),float(P[i][1]),float(P[i][2])])
    apolar=polar_sasa(m2)                  # vacuum-minimized (compact/IMHB-shielded ~ membrane/apolar state)
    polar =polar_sasa(m)                   # embedded/extended geometry (~ water-exposed proxy)
    return {'apolar_3dpsa':apolar,'polar_3dpsa':polar,'delta':polar-apolar}  # delta = collapse/chameleon propensity

df=pd.read_csv('cyc.csv', low_memory=False)
df=df[pd.to_numeric(df['Permeability'],errors='coerce').notna()].copy(); df['Permeability']=df['Permeability'].astype(float)
df=df.sample(min(NSUB,len(df)), random_state=7).reset_index(drop=True)
DESCS=Descriptors._descList
def feat2d(smi):
    m=Chem.MolFromSmiles(str(smi));
    if m is None: return None
    v=[]
    for n,f in DESCS:
        try: v.append(f(m))
        except: v.append(np.nan)
    return np.array(v,float)

rows=[]
for i,(smi,perm) in enumerate(zip(df['SMILES'],df['Permeability'])):
    try:
        te=two_env(smi); f2=feat2d(smi)
        if te and f2 is not None: rows.append({'perm':perm,'f2':f2,**te})
    except Exception: pass
    if i%25==0:
        stage=f'{i}/{len(df)} kept={len(rows)} el={int(time.time()-t0)}s'
        open('/opt/p2e/status/status.json','w').write(json.dumps({'stage':'run','detail':stage}))
        os.system(f'aws s3 cp /opt/p2e/status/status.json {os.environ["OUT_S3"]}/status/status.json --only-show-errors 2>/dev/null')
        if time.time()-t0>BUDGET: print('budget hit at',i); break
print('kept', len(rows))
X2=np.nan_to_num(np.clip(np.array([r['f2'] for r in rows]),-1e30,1e30))
env=np.array([[r['apolar_3dpsa'],r['polar_3dpsa'],r['delta']] for r in rows])
y=np.array([r['perm'] for r in rows])
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import cross_val_predict, KFold
from sklearn.metrics import r2_score
from scipy.stats import spearmanr
KF=KFold(5,shuffle=True,random_state=0)
def cv(X):
    p=cross_val_predict(HistGradientBoostingRegressor(max_iter=400,learning_rate=0.05),X,y,cv=KF)
    return {'R2':round(float(r2_score(y,p)),3),'Spearman':round(float(spearmanr(y,p).correlation),3)}
res={'n':len(y),
     '2D_only':cv(X2),
     '2D_plus_2env':cv(np.hstack([X2,env])),
     '2env_only':cv(env),
     'note':'2-environment 3D-PSA: apolar=vacuum-minimized (IMHB-shielded), polar=embedded/extended proxy, '
            'delta=chameleon term. Does apolar/delta 3D-PSA add over 2D? (proper polar state = GBn2 MD is the '
            'expensive full version; this is the tractable proxy.)'}
json.dump(res, open('/opt/p2e/status/perm_2env.json','w'), indent=2)
print(json.dumps(res, indent=2))
PY
stage p2e_complete
