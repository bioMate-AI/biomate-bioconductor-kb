#!/bin/bash
# Physics verify (CPU, self-contained) — the non-circular oracle for BoltzGen's ML-predicted
# iptm/pae. For the top cyclic designs per target: OpenMM force-field relaxation (amber14 + GBN2
# implicit solvent) + all-atom clash score. Self-contained (no PepGLAD relaxer, so no hardcoded-CUDA
# bug); explicit CPU platform. Runs on a cheap CPU instance — GPU is not needed for minimization.
#
# HONEST CAVEAT: PDBFixer caps termini, so this relaxes a LINEAR approximation of each head-to-tail
# macrocycle (the cyclization bond is not enforced). It is a coarse physical-plausibility filter
# (does the interface minimize without exploding? how strained / clashing is it?), not a rigorous
# macrocyclic MD. Rigorous cyclic MD (explicit head-to-tail bond + solvent) is the follow-up rung.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/phys
OUT_S3=${OUT_S3:?}
DESIGNS_S3=${DESIGNS_S3:?}         # s3://.../<run>/boltzgen_targets
TOPN=${TOPN:-3}
mkdir -p "$ROOT/status" "$ROOT/designs"
exec > >(tee -a "$ROOT/status/physics.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 8; aws s3 cp "$ROOT/status/physics.log" "$OUT_S3/status/physics.log" --only-show-errors || true; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 5; shutdown -h now; exit $rc' EXIT
systemd-run --unit=phys-deadline --on-active=2h /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda
source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n phys -c conda-forge python=3.11 openmm pdbfixer gemmi numpy
conda activate phys
python -c "import openmm; print('openmm', openmm.__version__, 'platforms:', [openmm.Platform.getPlatform(i).getName() for i in range(openmm.Platform.getNumPlatforms())])"

stage fetching_designs
aws s3 sync "$DESIGNS_S3" "$ROOT/designs" --only-show-errors --exclude "*" --include "*.cif"
echo "total cif: $(find "$ROOT/designs" -name '*.cif' | wc -l)"; find "$ROOT/designs" -name "*.cif" | head -20 || true

stage relaxing
TOPN=$TOPN ROOT=$ROOT python - <<'PY'
import sys, traceback, glob, json, os
import numpy as np
import openmm as mm
from openmm import app, unit
from pdbfixer import PDBFixer
ROOT=os.environ['ROOT']; TOPN=int(os.environ['TOPN'])
# capture ANY uncaught top-level error to a synced file (the last run's traceback was lost to shutdown)
def _hook(t,v,tb):
    with open(ROOT+'/status/relax_error.txt','w') as f: traceback.print_exception(t,v,tb,file=f)
    traceback.print_exception(t,v,tb)
sys.excepthook=_hook
print('openmm', mm.__version__, 'platforms:', [mm.Platform.getPlatform(i).getName() for i in range(mm.Platform.getNumPlatforms())], flush=True)
CPU=mm.Platform.getPlatformByName('CPU')
# force-field fallback: gbn2 implicit -> obc2 implicit -> classic amber99+obc (whichever loads)
FF_TRIES=[('amber14-all.xml','implicit/gbn2.xml'),('amber14-all.xml','implicit/obc2.xml'),('amber99sbildn.xml','amber99_obc.xml')]
def make_ff():
    last=None
    for spec in FF_TRIES:
        try: return app.ForceField(*spec), spec
        except Exception as e: last=e
    raise last
FF,FF_SPEC=make_ff()
print('forcefield:', FF_SPEC, flush=True)

def clash_count(topology, positions, cutoff=2.0):
    pos=np.array(positions.value_in_unit(unit.angstrom))
    atoms=list(topology.atoms())
    heavy=[i for i,a in enumerate(atoms) if (a.element is not None and a.element.symbol!='H')]
    if len(heavy)<2: return 0
    P=pos[heavy]; resid=np.array([atoms[i].residue.index for i in heavy])
    d=np.sqrt(((P[:,None,:]-P[None,:,:])**2).sum(-1))
    m=(d<cutoff) & (resid[:,None]!=resid[None,:])
    return int(np.triu(m,1).sum())

# pick top-N cif per target (prefer rank0* names), skip obvious input-target copies
per_target={}
for cif in glob.glob(ROOT+'/designs/**/*.cif', recursive=True):
    tgt=cif.split('/designs/')[1].split('/')[0]
    per_target.setdefault(tgt,[]).append(cif)
def keyfn(p):
    b=os.path.basename(p).lower()
    r=999
    for i in range(1,10):
        if f'rank0{i}' in b or f'rank_{i}' in b: r=i; break
    return (0 if 'final' in p.lower() else 1, r, b)

results=[]
for tgt,cifs in sorted(per_target.items()):
    picks=sorted(set(cifs), key=keyfn)[:TOPN]
    for cif in picks:
        rec={'target':tgt,'design':os.path.relpath(cif, ROOT+'/designs')}
        try:
            fixer=PDBFixer(filename=cif)
            fixer.findMissingResidues(); fixer.missingResidues={}
            fixer.findNonstandardResidues(); fixer.replaceNonstandardResidues()
            fixer.removeHeterogens(keepWater=False)
            fixer.findMissingAtoms(); fixer.addMissingAtoms()
            fixer.addMissingHydrogens(7.0)
            system=FF.createSystem(fixer.topology, nonbondedMethod=app.CutoffNonPeriodic,
                                   nonbondedCutoff=1.0*unit.nanometer, constraints=app.HBonds)
            integ=mm.LangevinMiddleIntegrator(300*unit.kelvin,1/unit.picosecond,0.002*unit.picoseconds)
            sim=app.Simulation(fixer.topology, system, integ, CPU)
            sim.context.setPositions(fixer.positions)
            rec['clashes_prerelax']=clash_count(fixer.topology, fixer.positions)
            e0=sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(unit.kilojoule_per_mole)
            sim.minimizeEnergy(maxIterations=1000)
            stt=sim.context.getState(getEnergy=True, getPositions=True)
            e1=stt.getPotentialEnergy().value_in_unit(unit.kilojoule_per_mole)
            rec.update(e_init_kJ=round(e0,1), e_final_kJ=round(e1,1), dE_kJ=round(e0-e1,1),
                       clashes_postrelax=clash_count(fixer.topology, stt.getPositions()),
                       n_atoms=fixer.topology.getNumAtoms(), ok=(e1==e1 and abs(e1)<1e9))
        except Exception as ex:
            rec.update(ok=False, error=type(ex).__name__+': '+str(ex)[:200])
        print(json.dumps(rec)); results.append(rec)

rep={'n':len(results), 'ok':sum(1 for r in results if r.get('ok')),
     'note':'amber14+GBN2 implicit-solvent minimization; LINEAR-approx of the macrocycle (termini '
            'capped by PDBFixer). Coarse physical-plausibility filter, not rigorous cyclic MD. '
            'Lower/negative e_final + low post-relax clashes + modest dE = physically plausible.',
     'results':results}
json.dump(rep, open(ROOT+'/status/physics_verify.json','w'), indent=2)
print(json.dumps({k:v for k,v in rep.items() if k!='results'}, indent=2))
PY
stage physics_complete
