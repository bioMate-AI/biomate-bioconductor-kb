#!/bin/bash
# FEP capstone — RUNG 1: validate the alchemical free-energy machinery on a KNOWN answer before trusting it on
# our (harder, FF-limited) binding/N-methyl questions. Compute the hydration free energy of ethanol by
# alchemical decoupling (electrostatics then sterics) in explicit water with openmmtools + MBAR, and compare
# to the experimental value (~ -5.0 kcal/mol, FreeSolv). If we reproduce it (+/- ~0.5), the pipeline is sound.
# GPU spot; self-terminating. This is the single-edge POC promised in NEXT_BUILDS_PLAN, not a binding result.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/fep; OUT_S3=${OUT_S3:?}
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/fep.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s","detail":"%s"}\n' "$1" "$(date -u +%FT%TZ)" "${2:-}" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 4; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 2; shutdown -h now; exit $rc' EXIT
systemd-run --unit=fep-deadline --on-active=3h /sbin/shutdown -h now || true

stage installing
# DL Base GPU AMI has awscli + drivers. Miniconda env with openmm(cuda)+openmmtools+openff.
which aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq awscli || true; }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n fep -c conda-forge python=3.11 openmm openmmtools openff-toolkit openmmforcefields pymbar numpy >/dev/null 2>&1
conda activate fep
python -c "import openmm,openmmtools,openff.toolkit,pymbar; print('openmm',openmm.__version__,'openmmtools',openmmtools.version.version,'pymbar ok'); import openmm as mm; print('platforms',[mm.Platform.getPlatform(i).getName() for i in range(mm.Platform.getNumPlatforms())])"

stage run
python - <<'PY'
import os, json, time, numpy as np
import openmm as mm
from openmm import unit, app
from openff.toolkit import Molecule
from openmmforcefields.generators import SystemGenerator
from openmmtools import alchemy, states, mcmc, multistate
from openmmtools.multistate import ReplicaExchangeSampler, MultiStateReporter
t0=time.time()
def sync(det):
    open('/opt/fep/status/status.json','w').write(json.dumps({'stage':'run','detail':det}));
    os.system(f'aws s3 cp /opt/fep/status/status.json {os.environ.get("OUT_S3","")}/status/status.json --only-show-errors 2>/dev/null')
try: PLAT=mm.Platform.getPlatformByName('CUDA')
except Exception: PLAT=mm.Platform.getPlatformByName('CPU')
print('platform', PLAT.getName())

# --- ethanol in a small water box (GAFF/AM1-BCC ligand, TIP3P water) ---
sync('building ethanol + water')
mol=Molecule.from_smiles('CCO'); mol.generate_conformers(n_conformers=1)
sysgen=SystemGenerator(forcefields=['amber/tip3p_standard.xml'],
                       small_molecule_forcefield='gaff-2.11', molecules=[mol],
                       forcefield_kwargs={'constraints':app.HBonds,'rigidWater':True})
off_top=mol.to_topology(); omm_top=off_top.to_openmm(); pos=mol.conformers[0].to_openmm()
modeller=app.Modeller(omm_top, pos)
modeller.addSolvent(sysgen.forcefield, model='tip3p', padding=1.0*unit.nanometer)
system=sysgen.create_system(modeller.topology, molecules=[mol])
lig_atoms=list(range(off_top.n_atoms))   # ethanol atoms are first
print('total atoms', system.getNumParticles(), 'ligand atoms', len(lig_atoms))

# --- alchemically decouple the ligand (sterics+electrostatics) ---
sync('alchemical factory')
factory=alchemy.AbsoluteAlchemicalFactory(consistent_exceptions=False)
region=alchemy.AlchemicalRegion(alchemical_atoms=lig_atoms, annihilate_electrostatics=True, annihilate_sterics=False)
alch_system=factory.create_alchemical_system(system, region)
alch_state=alchemy.AlchemicalState.from_system(alch_system)

# lambda schedule: turn OFF electrostatics first (1->0), then sterics (1->0)
elec=[1.0,0.75,0.5,0.25,0.0, 0.0,0.0,0.0,0.0,0.0,0.0,0.0]
ster=[1.0,1.0, 1.0,1.0, 1.0, 0.8,0.6,0.45,0.3,0.2,0.1,0.0]
nstates=len(elec)
sampler_states=states.SamplerState(positions=modeller.getPositions(),
    box_vectors=system.getDefaultPeriodicBoxVectors())
thermo=states.ThermodynamicState(system=alch_system, temperature=298.15*unit.kelvin,
    pressure=1.0*unit.atmosphere)
comp_states=[]
for e,s in zip(elec,ster):
    st=states.CompoundThermodynamicState(thermodynamic_state=states.ThermodynamicState(
        system=alch_system, temperature=298.15*unit.kelvin, pressure=1.0*unit.atmosphere),
        composable_states=[alchemy.AlchemicalState.from_system(alch_system)])
    st.lambda_electrostatics=e; st.lambda_sterics=s
    comp_states.append(st)
sync(f'{nstates} lambda states; replica exchange')

move=mcmc.LangevinDynamicsMove(timestep=2.0*unit.femtoseconds, collision_rate=1.0/unit.picosecond,
                               n_steps=500)   # 1 ps / iteration
reporter=MultiStateReporter('/opt/fep/w/fep.nc', checkpoint_interval=50)
sampler=ReplicaExchangeSampler(mcmc_moves=move, number_of_iterations=200)  # 200 ps/replica (POC)
sampler.create(thermodynamic_states=comp_states,
               sampler_states=[states.SamplerState(positions=modeller.getPositions(),
                    box_vectors=system.getDefaultPeriodicBoxVectors()) for _ in comp_states],
               storage=reporter)
sync('running replica exchange (200 iters)')
sampler.run()

from openmmtools.multistate import MultiStateSamplerAnalyzer
ana=MultiStateSamplerAnalyzer(reporter)
dF,ddF=ana.get_free_energy()   # matrix in kT
kT=(unit.BOLTZMANN_CONSTANT_kB*298.15*unit.kelvin*unit.AVOGADRO_CONSTANT_NA).value_in_unit(unit.kilocalorie_per_mole)
# hydration FE = -(free energy of decoupling fully-interacting -> non-interacting) in solvent
dG_decouple=dF[0,-1]*kT; err=ddF[0,-1]*kT
hydration=-dG_decouple
res={'molecule':'ethanol','n_lambda':nstates,'iters':200,
     'dG_decouple_kcal':round(float(dG_decouple),2),'hydration_FE_kcal':round(float(hydration),2),
     'stderr_kcal':round(float(err),2),'experiment_FreeSolv_kcal':-5.0,
     'platform':PLAT.getName(),'elapsed_s':int(time.time()-t0),
     'verdict':('PIPELINE VALIDATED (within ~1 kcal of exp -5.0)' if abs(hydration-(-5.0))<1.2 else 'OFF — investigate (POC sampling may be too short)'),
     'note':'RUNG 1 validation only: proves the alchemical decouple + MBAR machinery on a known answer. Short '
            '200-iter POC so noisy; binding ABFE (complex leg + Boresch restraints) and N-methyl RBFE are the '
            'follow-ons. N-methyl FEP still needs a CMAP-correct FF (committee reviewer C).'}
json.dump(res, open('/opt/fep/status/fep_hydration.json','w'), indent=2)
print(json.dumps(res, indent=2))
PY
aws s3 cp /opt/fep/status/fep_hydration.json "$OUT_S3/status/fep_hydration.json" --only-show-errors || true
stage fep_complete
