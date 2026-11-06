#!/bin/bash
# Track A — 2-environment conformation-aware permeability (the differentiator). For a CycPeptMPDB subsample:
# build GAFF system (openmmforcefields), minimize in GBn2 (polar/water) AND vacuum (apolar/membrane-like),
# compute 3D-PSA (rdFreeSASA polar-SASA) in each -> features polar_3dpsa, apolar_3dpsa, DELTA (chameleon).
# Fuse with 2D descriptors -> 5-fold shuffled CV vs 2D-only. The NEW thing vs the failed single-env test is
# the polar-vs-apolar delta. Robust: small subsample, per-peptide try/except + timeout, progress, ML on
# whatever completes before the internal budget.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
export OPENMM_CPU_THREADS=1 OMP_NUM_THREADS=1   # 1 thread/worker (we parallelize over peptides via Pool)
ROOT=/opt/p2e; OUT_S3=${OUT_S3:?}; BUCKET=knowledge-datasets-1759951976
NSUB=${NSUB:-200}; BUDGET_S=${BUDGET_S:-9000}   # 2.5h featurization budget; systemd 4h hard deadline leaves >=1.5h for ML+sync
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/p2e.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","detail":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "${2:-}" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 5; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 3; shutdown -h now; exit $rc' EXIT
systemd-run --unit=p2e-deadline --on-active=4h /sbin/shutdown -h now || true

stage installing
apt-get update -qq && apt-get install -y -qq unzip curl libgomp1 || true   # libgomp1: GNU OpenMP runtime (libgomp.so.1) needed by openmm+sklearn; rolling conda-forge dropped it off the loader path
command -v aws >/dev/null 2>&1 || { curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n p2e -c conda-forge python=3.11 rdkit openmm openmmforcefields openff-toolkit ambertools scikit-learn pandas numpy scipy libgomp llvm-openmp >/dev/null 2>&1
conda activate p2e
export LD_LIBRARY_PATH=/opt/miniconda/envs/p2e/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}   # ensure libgomp.so.1 resolvable in workers (Pool inherits env)
python -c "import ctypes; ctypes.CDLL('libgomp.so.1'); import openmm, openff.toolkit, openmmforcefields, rdkit, sklearn; print('deps ok')"

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

import signal
ITEM_TIMEOUT=int(os.environ.get('ITEM_TIMEOUT','180'))   # FIX: hard cap per peptide; some macrocycles hang AM1-BCC/sqm forever
def _timeout(signum, frame): raise TimeoutError('item timeout')
def worker(args):
    smi,perm=args
    try:
        signal.signal(signal.SIGALRM,_timeout); signal.alarm(ITEM_TIMEOUT)  # SIGALRM fires in this child's main thread
        te=two_env(smi); f2=feat2d(smi)
        signal.alarm(0)
        if te and f2 is not None: return {'perm':float(perm),'f2':f2.tolist(),**te}
        return {'_err':'two_env or feat2d returned None (no exception)'}
    except Exception as e:                                  # DIAGNOSTIC: surface the swallowed error (2026-09-19: kept=0 with sqm/AM1-BCC failing silently)
        signal.alarm(0)
        import traceback
        return {'_err':f'{type(e).__name__}: {e}','_tb':traceback.format_exc()[-600:]}
from multiprocessing import Pool
def sync_status(det):
    open('/opt/p2e/status/status.json','w').write(json.dumps({'stage':'run','detail':det}))
    os.system(f'aws s3 cp /opt/p2e/status/status.json {os.environ["OUT_S3"]}/status/status.json --only-show-errors 2>/dev/null')
items=list(zip(df['SMILES'],df['Permeability']))
rows=[]; nerr=0
ckpt=open('/opt/p2e/status/rows.jsonl','w')            # FIX: checkpoint kept rows to disk so a hard-deadline shutdown can't erase progress
with Pool(processes=max(1, (os.cpu_count() or 8)-1)) as pool:
    it=pool.imap_unordered(worker, items, chunksize=1)
    for i in range(len(items)):
        try: r=next(it)
        except StopIteration: break
        if r and '_err' in r:                          # DIAGNOSTIC: log first 15 worker failures so kept=0 is never a mystery again
            nerr+=1
            if nerr<=15:
                open('/opt/p2e/status/worker_errors.txt','a').write(f"[{i}] {r['_err']} || {r.get('_tb','')}\n")
                os.system(f'aws s3 cp /opt/p2e/status/worker_errors.txt {os.environ["OUT_S3"]}/status/worker_errors.txt --only-show-errors 2>/dev/null')
            r=None
        if r: rows.append(r); ckpt.write(json.dumps(r)+'\n'); ckpt.flush()
        if time.time()-t0>BUDGET:                       # FIX: budget checked EVERY iteration (was gated behind i%25 -> stalls evaded it)
            print('budget hit at',i); pool.terminate(); break
        if i%10==0: sync_status(f'{i}/{len(items)} kept={len(rows)} el={int(time.time()-t0)}s')
ckpt.close(); sync_status(f'featurization done kept={len(rows)} el={int(time.time()-t0)}s')
print('kept', len(rows))
os.system(f'aws s3 cp /opt/p2e/status/rows.jsonl {os.environ["OUT_S3"]}/status/rows.jsonl --only-show-errors 2>/dev/null')
try:
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
except Exception as e:
    res={'error':str(e),'n_kept':len(rows)}
json.dump(res, open('/opt/p2e/status/perm_2env.json','w'), indent=2)
os.system(f'aws s3 cp /opt/p2e/status/perm_2env.json {os.environ["OUT_S3"]}/status/perm_2env.json --only-show-errors 2>/dev/null')
print(json.dumps(res, indent=2))
PY
stage p2e_complete
