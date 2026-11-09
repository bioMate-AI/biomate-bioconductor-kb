#!/usr/bin/env nextflow
/*
 * drug_discovery/amber_pmemd_md
 *
 * AMBER pmemd protein-ligand molecular dynamics + MM-GBSA binding free energy pipeline.
 * Uses AMBER 24 pmemd.cuda for GPU-accelerated MD and MMPBSA.py for binding DeltaGbind.
 *
 * Pipeline Steps:
 * 1. LIGAND_PREP         -- antechamber (GAFF2 charges/atom types) + parmchk2 (missing params)
 *                           Converts sdf/mol2 -> ligand_gaff2.mol2 + ligand.frcmod
 * 2. SYSTEM_SETUP        -- tleap: protein+ligand complex, solvate (TIP3P), neutralize
 *                           Saves AMBER prmtop + inpcrd for downstream runs
 * 3. ENERGY_MINIMIZATION -- sander: 2500 H-only + 2500 all-atom steepest descent
 * 4. EQUILIBRATION       -- MD engine: 100ps NVT (heating 0->300K, restrained)
 *                                     + 100ps NPT (1 atm, restrained)
 * 5. PRODUCTION_MD       -- MD engine: N ns NPT unrestrained production
 *
 * MD engine (params.md_engine = auto | pmemd | openmm). pmemd/pmemd.cuda is licensed AMBER (not in
 * AmberTools), so it runs only from a licensed image the user provides (Settings -> Credentials ->
 * AMBER, passed as params.pmemd_container). Without one, 'auto' runs steps 4-5 in OpenMM 8 on the
 * GPU from the same AMBER prmtop/rst7 (same ff19SB/GAFF2/TIP3P force field, PME, SHAKE-equivalent
 * H-bond constraints, Langevin thermostat, Monte Carlo barostat). Preparation (tleap), minimization
 * (sander), analysis (cpptraj) and MM-GBSA (MMPBSA.py) are free AmberTools either way.
 * 6. TRAJECTORY_ANALYSIS -- cpptraj: RMSD, RMSF, H-bonds, radius of gyration
 * 7. MM_GBSA             -- MMPBSA.py: GB model (igb=2), per-residue decomposition
 *
 * Outputs:
 *   trajectory.nc|.dcd        -- production trajectory (NetCDF from pmemd, DCD from OpenMM)
 *   binding_summary.json      -- DeltaGbind, RMSD stats, system info
 *   rmsd_plot.png             -- RMSD over time (protein backbone + ligand)
 *   rmsf_per_residue.csv      -- per-residue RMSF table
 *   mmgbsa_results.csv        -- per-residue energy decomposition
 *
 * References:
 *   AMBER:   Case et al. J. Chem. Inf. Model. 2023, 63:6183-6200
 *   GAFF2:   Wang et al. J. Comput. Chem. 2004, 25:1157-1174
 *   MM-GBSA: Kollman et al. Acc. Chem. Res. 2000, 33:889-897
 *   cpptraj: Roe & Cheatham J. Chem. Theory Comput. 2013, 9:3084-3095
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir               = './results/amber_pmemd_md'
params.publish_dir_mode     = 'copy'

// Inputs
params.receptor             = null       // receptor.pdb or S3 URI
params.ligand               = null       // ligand.sdf / ligand.mol2

// Force field
params.force_field          = 'ff19SB'   // ff14SB | ff19SB
params.water_model          = 'tip3p'    // tip3p
params.gaff_version         = 'gaff2'   // gaff | gaff2

// System setup
params.box_padding          = 12         // Angstrom from protein surface to box edge

// Simulation settings
params.n_steps              = 5000000    // MD steps (2 fs dt -> 10 ns default)
params.dt                   = 0.002      // ps (2 fs timestep)
params.temperature          = 300        // K
params.pressure             = 1.0        // atm

// MM-GBSA
params.mmgbsa_startframe    = 500        // skip first N frames (equilibration buffer)
params.mmgbsa_interval      = 5          // analyse every Nth frame

// Resources
params.n_cpus               = 8
params.gpu                  = true

// MD engine for EQUILIBRATION + PRODUCTION_MD: 'auto' | 'pmemd' | 'openmm'
params.md_engine            = 'auto'
// Licensed AMBER image with pmemd.cuda, from the user's BYOL AMBER credential. The executor injects
// it into the head env as AMBER_PMEMD_CONTAINER (credentials_api 'amber' → license_image); unset =
// no licence = md_engine=auto runs the dynamics in OpenMM.
params.pmemd_container      = System.getenv('AMBER_PMEMD_CONTAINER') ?: null

// AWS Batch flag — set via profile (aws/gpu_batch) or --use_aws true
params.use_aws              = false

// ============================================================================
// Containers
// ============================================================================

// On AWS Batch use the unified ECR image (AmberTools 23 + GROMACS 2024 via conda-forge)
def _useAws = params.use_aws || System.getenv('NEXTFLOW_USE_AWS') == 'true'
def _ECR    = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest'
def AMBER_CONTAINER      = _useAws ? _ECR : '399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest'
def AMBERTOOLS_CONTAINER = _useAws ? _ECR : 'ambermd/ambertools:23'
// OpenMM 8 + CUDA (built by scripts/build_mlip_md_image.sh; also serves MLIP MD)
def OPENMM_CONTAINER     = _useAws ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mlip-md:cuda12-x86' : 'biomate/mlip-md:latest'

// 'auto' uses pmemd only with a licensed image; BioMate's own images carry AmberTools, not pmemd.
def MD_ENGINE = (params.md_engine ?: 'auto') == 'auto' ? (params.pmemd_container ? 'pmemd' : 'openmm') : params.md_engine
if (!(MD_ENGINE in ['pmemd', 'openmm'])) {
    error "params.md_engine must be auto, pmemd or openmm (got '${params.md_engine}')"
}
if (MD_ENGINE == 'pmemd' && _useAws && !params.pmemd_container) {
    error "md_engine=pmemd needs a licensed AMBER image with pmemd.cuda (Settings -> Credentials -> AMBER); BioMate's images carry AmberTools only. Use md_engine=auto or openmm to run the dynamics in OpenMM."
}
def PMEMD_CONTAINER = params.pmemd_container ?: AMBER_CONTAINER
def MD_CONTAINER    = MD_ENGINE == 'pmemd' ? PMEMD_CONTAINER : OPENMM_CONTAINER

// OpenMM helpers shared by EQUILIBRATION and PRODUCTION_MD (written to omm_helpers.py in the task).
// Conventions follow the pmemd inputs below: PME with an 8 A cutoff, H-bond constraints (ntc=ntf=2),
// Langevin thermostat, Monte Carlo barostat, AMBER positional restraints E = k*dx^2 in kcal/mol/A^2.
// Restarts are written as AMBER rst7 (positions, velocities, box) so every downstream step reads the
// same files whichever engine ran. Positions are never wrapped (pmemd iwrap=0 equivalent): MM-GBSA
// needs receptor and ligand in the same periodic image.
def OPENMM_HELPERS = '''
import math
import numpy as np
import openmm as mm
from openmm import app, unit

KCAL_A2_TO_KJ_NM2 = 4.184 * 100.0
AMBER_VEL = 20.455  # AMBER time unit = 1/20.455 ps

def platform():
    for name, props in (("CUDA", {"Precision": "mixed"}), ("OpenCL", {"Precision": "mixed"}), ("CPU", {})):
        try:
            return mm.Platform.getPlatformByName(name), props
        except Exception:
            continue
    raise SystemExit("no OpenMM platform available")

def build_system(prmtop):
    return prmtop.createSystem(nonbondedMethod=app.PME, nonbondedCutoff=0.8 * unit.nanometer,
                               constraints=app.HBonds, rigidWater=True, ewaldErrorTolerance=0.0005)

def backbone_restraint(system, topology, ref_nm, k_kcal_a2):
    f = mm.CustomExternalForce("k_rest*periodicdistance(x, y, z, x0, y0, z0)^2")
    f.addGlobalParameter("k_rest", k_kcal_a2 * KCAL_A2_TO_KJ_NM2)
    for name in ("x0", "y0", "z0"):
        f.addPerParticleParameter(name)
    idx = [a.index for a in topology.atoms()
           if a.name in ("CA", "C", "N") and a.residue.name not in ("LIG", "WAT", "HOH")]
    for i in idx:
        f.addParticle(i, [float(v) for v in ref_nm[i]])
    system.addForce(f)
    if not idx:
        raise SystemExit("no backbone atoms (CA/C/N) found for the restraint mask")
    return f, idx

def move_restraint(force, idx, positions_nm, context):
    for k, i in enumerate(idx):
        force.setParticleParameters(k, i, [float(v) for v in positions_nm[i]])
    force.updateParametersInContext(context)

def load_state(sim, inpcrd):
    sim.context.setPositions(inpcrd.getPositions())
    if inpcrd.getBoxVectors() is not None:
        sim.context.setPeriodicBoxVectors(*inpcrd.getBoxVectors())
    # AmberInpcrdFile.getVelocities() RAISES when the rst7 has no velocities (a sander-minimized
    # restart has none), so hasattr is true but the call throws — guard it and return None.
    try:
        vel = inpcrd.getVelocities()
    except Exception:
        vel = None
    return vel

def _angle(u, v):
    return math.degrees(math.acos(float(np.dot(u, v) / (np.linalg.norm(u) * np.linalg.norm(v)))))

def write_rst7(path, state, title):
    pos = state.getPositions(asNumpy=True).value_in_unit(unit.angstrom)
    vel = state.getVelocities(asNumpy=True).value_in_unit(unit.angstrom / unit.picosecond) / AMBER_VEL
    a, b, c = state.getPeriodicBoxVectors(asNumpy=True).value_in_unit(unit.angstrom)
    box = (np.linalg.norm(a), np.linalg.norm(b), np.linalg.norm(c), _angle(b, c), _angle(a, c), _angle(a, b))
    with open(path, "w") as fh:
        fh.write(title[:80] + "\\n")
        fh.write("%6d%15.7e\\n" % (len(pos), state.getTime().value_in_unit(unit.picosecond)))
        for block in (pos, vel):
            flat = np.asarray(block).reshape(-1)
            for i in range(0, len(flat), 6):
                fh.write("".join("%12.7f" % v for v in flat[i:i + 6]) + "\\n")
        fh.write("".join("%12.7f" % v for v in box) + "\\n")
'''

// ============================================================================
// Processes
// ============================================================================

// [Phase A] Ligand & System Preparation
process LIGAND_PREP {
    /*
     * Convert ligand to GAFF2 force-field parameters using AmberTools antechamber.
     * Input:  ligand.sdf / ligand.mol2
     * Output: ligand_gaff2.mol2  -- AM1-BCC charges, GAFF2 atom types
     *         ligand.frcmod      -- missing GAFF2 force-field terms
     */
    tag "ligand_prep"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/01_ligand_prep", mode: params.publish_dir_mode

    input:
    path ligand_file

    output:
    path "ligand_gaff2.mol2", emit: mol2
    path "ligand.frcmod",     emit: frcmod
    path "ligand_prep.log",   emit: log

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        input_ext=\$(echo "${ligand_file}" | rev | cut -d. -f1 | rev | tr '[:upper:]' '[:lower:]')
        lig_input="${ligand_file}"

        if [[ "\$input_ext" == "smi" ]]; then
            # Convert SMILES to SDF using RDKit (available in AMBERTOOLS container)
            python3 -c "
from rdkit import Chem
from rdkit.Chem import AllChem
import sys
with open('${ligand_file}') as f:
    smi = f.read().strip()
mol = Chem.MolFromSmiles(smi)
if mol is None:
    print('Invalid SMILES: ' + smi, file=sys.stderr)
    sys.exit(1)
mol = Chem.AddHs(mol)
AllChem.EmbedMolecule(mol, AllChem.ETKDGv3())
AllChem.MMFFOptimizeMolecule(mol)
w = Chem.SDWriter('ligand_from_smiles.sdf')
w.write(mol)
w.close()
print('SMILES to SDF conversion done')
"
            lig_input="ligand_from_smiles.sdf"
            input_fmt="sdf"
        elif [[ "\$input_ext" == "sdf" || "\$input_ext" == "sd" ]]; then
            input_fmt="sdf"
        elif [[ "\$input_ext" == "mol2" ]]; then
            input_fmt="mol2"
        else
            echo "Unsupported ligand format: \$input_ext" >&2
            exit 1
        fi

        # A ligand taken from a crystal structure usually has no hydrogens; antechamber then fails
        # ("Weird atomic valence"). Add them with RDKit, keeping the heavy-atom pose coordinates.
        # Inputs that already carry explicit H are passed through unchanged.
        if [ "\$input_fmt" = "sdf" ] || [ "\$input_fmt" = "mdl" ]; then
            python3 - "\$lig_input" <<'ADDHEOF'
import sys
from rdkit import Chem
src = sys.argv[1]
mol = Chem.MolFromMolFile(src, removeHs=False)
if mol is None:
        sys.exit("ERROR: could not read ligand " + src)
if not any(a.GetAtomicNum() == 1 for a in mol.GetAtoms()):
        mol = Chem.AddHs(mol, addCoords=True)
        Chem.MolToMolFile(mol, "ligand_with_h.sdf")
        print("added %d hydrogens to %s" % (sum(a.GetAtomicNum() == 1 for a in mol.GetAtoms()), src))
ADDHEOF
            [ -f ligand_with_h.sdf ] && { lig_input="ligand_with_h.sdf"; input_fmt="sdf"; }
        fi

        antechamber \\
            -i \$lig_input -fi \$input_fmt \\
            -o ligand_gaff2.mol2 -fo mol2 \\
            -c bcc -s 2 \\
            -at ${params.gaff_version} \\
            -rn LIG \\
            2>&1 | tee antechamber.log

        parmchk2 \\
            -i ligand_gaff2.mol2 -f mol2 \\
            -o ligand.frcmod \\
            -s ${params.gaff_version} \\
            2>&1 | tee parmchk2.log

        cat antechamber.log parmchk2.log > ligand_prep.log
        echo "LIGAND_PREP complete" >> ligand_prep.log
        """
}

// ----------------------------------------------------------------------------

// [Phase A] Ligand & System Preparation
process SYSTEM_SETUP {
    /*
     * Build protein-ligand complex with tleap.
     * Solvates with TIP3P octahedral box, neutralizes with Na+/Cl-.
     * Saves AMBER topology (prmtop) and coordinates (inpcrd).
     */
    tag "system_setup"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/02_system_setup", mode: params.publish_dir_mode

    input:
    path receptor_file
    path mol2_file
    path frcmod_file

    output:
    path "complex.prmtop",  emit: prmtop
    path "complex.inpcrd",  emit: inpcrd
    path "tleap.log",       emit: log

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        cat > tleap.in << TLEAPIN
source leaprc.protein.${params.force_field}
source leaprc.${params.gaff_version}
source leaprc.water.${params.water_model}
loadamberparams ${frcmod_file}
LIG = loadmol2 ${mol2_file}
PROT = loadpdb ${receptor_file}
COMP = combine {PROT LIG}
check COMP
solvateOct COMP TIP3PBOX ${params.box_padding}
addionsrand COMP Na+ 0
addionsrand COMP Cl- 0
saveamberparm COMP complex.prmtop complex.inpcrd
desc COMP
quit
TLEAPIN

        tleap -f tleap.in 2>&1 | tee tleap.log
        echo "SYSTEM_SETUP complete" >> tleap.log
        """
}

// ----------------------------------------------------------------------------

// [Phase B] Energy Minimization
process ENERGY_MINIMIZATION {
    /*
     * Two-stage steepest descent minimization using sander (CPU):
     *   Stage 1: 2500 steps -- heavy-atom restraints (restraint_wt=500 kcal/mol/A^2)
     *   Stage 2: 2500 steps -- all-atom, no restraints
     */
    tag "energy_minimization"
    container AMBER_CONTAINER
    publishDir "${params.outdir}/03_minimization", mode: params.publish_dir_mode

    cpus params.n_cpus

    input:
    path prmtop
    path inpcrd

    output:
    path "minimized.rst",  emit: rst
    path "em.out",         emit: log

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        cat > min1.in << MIN1EOF
H-only minimization -- stage 1
 &cntrl
  imin=1, ntmin=1,
  maxcyc=2500, ncyc=1000,
  ntb=1, ntp=0,
  ntf=1, ntc=1,
  ntr=1, restraintmask='!@H=',
  restraint_wt=500.0,
  ntpr=100, ntwx=0, ntxo=1,
 /
MIN1EOF

        sander -O \
            -i min1.in \
            -o min1.out \
            -p ${prmtop} \
            -c ${inpcrd} \
            -r min1.rst \
            -ref ${inpcrd}

        cat > min2.in << MIN2EOF
All-atom minimization -- stage 2
 &cntrl
  imin=1, ntmin=1,
  maxcyc=2500, ncyc=1000,
  ntb=1, ntp=0,
  ntf=2, ntc=2,
  ntr=0,
  ntpr=100, ntwx=0, ntxo=1,
 /
MIN2EOF

        sander -O \
            -i min2.in \
            -o min2.out \
            -p ${prmtop} \
            -c min1.rst \
            -r minimized.rst

        cat min1.out min2.out > em.out
        echo "ENERGY_MINIMIZATION complete" >> em.out
        """
}

// ----------------------------------------------------------------------------

// [Phase B] NVT/NPT Equilibration
process EQUILIBRATION {
    /*
     * Two-stage GPU equilibration with pmemd.cuda:
     *   Stage 1: 100 ps NVT -- linear heating 0->300K, backbone restrained
     *   Stage 2: 100 ps NPT -- 1 atm Berendsen barostat, backbone restrained
     */
    tag "equilibration"
    label 'process_gpu'
    container MD_CONTAINER
    publishDir "${params.outdir}/04_equilibration", mode: params.publish_dir_mode

    cpus params.n_cpus

    input:
    path prmtop
    path minimized_rst

    output:
    path "equil.rst",       emit: rst
    path "equil_nvt.out",   emit: nvt_log
    path "equil_npt.out",   emit: npt_log

    script:
    if (MD_ENGINE == 'openmm')
    """
        set -euo pipefail
        cat > omm_helpers.py << 'OMMEOF'
${OPENMM_HELPERS}
OMMEOF
        python3 - << 'PYEOF'
import sys
sys.path.insert(0, ".")
from omm_helpers import *

T, P, DT, NSTEP = ${params.temperature}, ${params.pressure}, ${params.dt}, 50000
prmtop = app.AmberPrmtopFile("${prmtop}")
inpcrd = app.AmberInpcrdFile("${minimized_rst}")
system = build_system(prmtop)
baro = mm.MonteCarloBarostat(P * unit.atmosphere, T * unit.kelvin, 0)   # off during NVT
system.addForce(baro)
ref = inpcrd.getPositions(asNumpy=True).value_in_unit(unit.nanometer)
restr, idx = backbone_restraint(system, prmtop.topology, ref, 10.0)     # restraintmask @CA,C,N, 10 kcal/mol/A^2
integ = mm.LangevinMiddleIntegrator(1.0 * unit.kelvin, 2.0 / unit.picosecond, DT * unit.picosecond)  # gamma_ln=2
plat, props = platform()
sim = app.Simulation(prmtop.topology, system, integ, plat, props)
load_state(sim, inpcrd)                                                  # tempi=0: no initial velocities

# NVT: linear heating 0 -> T over NSTEP steps (nstlim=50000)
rep = app.StateDataReporter("equil_nvt.out", 1000, step=True, time=True, potentialEnergy=True,
                            temperature=True, speed=True)
sim.reporters.append(rep)
chunks = 50
for i in range(chunks):
    integ.setTemperature(T * (i + 1) / chunks * unit.kelvin)
    sim.step(NSTEP // chunks)
sim.reporters.remove(rep)

# NPT: barostat on, restraints re-referenced to the end of NVT (-ref nvt.rst)
st = sim.context.getState(getPositions=True)
baro.setFrequency(25)
sim.context.reinitialize(preserveState=True)
move_restraint(restr, idx, st.getPositions(asNumpy=True).value_in_unit(unit.nanometer), sim.context)
sim.reporters.append(app.StateDataReporter("equil_npt.out", 1000, step=True, time=True, potentialEnergy=True,
                                           temperature=True, density=True, speed=True))
sim.step(NSTEP)
state = sim.context.getState(getPositions=True, getVelocities=True, enforcePeriodicBox=False)
write_rst7("equil.rst", state, "BioMate OpenMM equilibration")
with open("equil_npt.out", "a") as fh:
    fh.write("EQUILIBRATION complete (OpenMM %s, platform %s, %d restrained backbone atoms)\\n"
             % (mm.__version__, plat.getName(), len(idx)))
print("EQUILIBRATION complete on", plat.getName())
PYEOF
        """
    else
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        cat > nvt.in << NVTEOF
NVT equilibration -- linear heating 0->${params.temperature}K (100 ps)
 &cntrl
  imin=0, irest=0, ntx=1,
  nstlim=50000, dt=${params.dt},
  ntb=1, ntp=0,
  ntf=2, ntc=2,
  tempi=0.0, temp0=${params.temperature},
  ntt=3, gamma_ln=2.0,
  ntr=1, restraintmask='@CA,C,N',
  restraint_wt=10.0,
  ntpr=1000, ntwx=0, ntwr=50000,
  ioutfm=1,
 /
NVTEOF

        pmemd.cuda -O \
            -i nvt.in \
            -o equil_nvt.out \
            -p ${prmtop} \
            -c ${minimized_rst} \
            -r nvt.rst \
            -ref ${minimized_rst}

        cat > npt.in << NPTEOF
NPT equilibration -- ${params.pressure} atm Berendsen barostat (100 ps)
 &cntrl
  imin=0, irest=1, ntx=5,
  nstlim=50000, dt=${params.dt},
  ntb=2, ntp=1, barostat=2,
  pres0=${params.pressure}, taup=2.0,
  ntf=2, ntc=2,
  temp0=${params.temperature},
  ntt=3, gamma_ln=2.0,
  ntr=1, restraintmask='@CA,C,N',
  restraint_wt=10.0,
  ntpr=1000, ntwx=0, ntwr=50000,
  ioutfm=1,
 /
NPTEOF

        pmemd.cuda -O \
            -i npt.in \
            -o equil_npt.out \
            -p ${prmtop} \
            -c nvt.rst \
            -r equil.rst \
            -ref nvt.rst

        echo "EQUILIBRATION complete" >> equil_npt.out
        """
}

// ----------------------------------------------------------------------------

// [Phase C] Production MD
process PRODUCTION_MD {
    /*
     * GPU production MD with pmemd.cuda.
     * NPT ensemble, unrestrained, default 10 ns (5,000,000 steps at 2 fs).
     * Trajectory saved in NetCDF format every 10 ps (ntwx=5000 at dt=0.002 ps).
     */
    tag "production_md"
    label 'process_gpu'
    container MD_CONTAINER
    publishDir "${params.outdir}/05_production", mode: params.publish_dir_mode

    cpus params.n_cpus

    input:
    path prmtop
    path equil_rst

    output:
    path "trajectory.{nc,dcd}", emit: trajectory   // pmemd: NetCDF; OpenMM: DCD (cpptraj/MMPBSA.py read both)
    path "md.out",         emit: log
    path "md.rst",         emit: rst

    script:
    if (MD_ENGINE == 'openmm')
    """
        set -euo pipefail
        cat > omm_helpers.py << 'OMMEOF'
${OPENMM_HELPERS}
OMMEOF
        python3 - << 'PYEOF'
import sys
sys.path.insert(0, ".")
from omm_helpers import *

T, P, DT, NSTEPS = ${params.temperature}, ${params.pressure}, ${params.dt}, int(${params.n_steps})
EVERY = min(5000, NSTEPS)                                                # ntwx=ntpr=5000
prmtop = app.AmberPrmtopFile("${prmtop}")
inpcrd = app.AmberInpcrdFile("${equil_rst}")
system = build_system(prmtop)
system.addForce(mm.MonteCarloBarostat(P * unit.atmosphere, T * unit.kelvin, 25))
integ = mm.LangevinMiddleIntegrator(T * unit.kelvin, 1.0 / unit.picosecond, DT * unit.picosecond)  # gamma_ln=1
plat, props = platform()
sim = app.Simulation(prmtop.topology, system, integ, plat, props)
vel = load_state(sim, inpcrd)                                            # irest=1, ntx=5
if vel is not None:
    sim.context.setVelocities(vel)
else:
    sim.context.setVelocitiesToTemperature(T * unit.kelvin)
sim.reporters.append(app.DCDReporter("trajectory.dcd", EVERY, enforcePeriodicBox=False))
sim.reporters.append(app.StateDataReporter("md.out", EVERY, step=True, time=True, potentialEnergy=True,
                                           temperature=True, density=True, speed=True))
sim.step(NSTEPS)
state = sim.context.getState(getPositions=True, getVelocities=True, enforcePeriodicBox=False)
write_rst7("md.rst", state, "BioMate OpenMM production")
with open("md.out", "a") as fh:
    fh.write("PRODUCTION_MD complete (OpenMM %s, platform %s, %d steps)\\n" % (mm.__version__, plat.getName(), NSTEPS))
print("PRODUCTION_MD complete on", plat.getName())
PYEOF
        """
    else
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        cat > md.in << MDEOF
Production MD -- NPT ${params.n_steps} steps @ ${params.temperature}K ${params.pressure}atm
 &cntrl
  imin=0, irest=1, ntx=5,
  nstlim=${params.n_steps}, dt=${params.dt},
  ntb=2, ntp=1, barostat=2,
  pres0=${params.pressure}, taup=2.0,
  ntf=2, ntc=2,
  temp0=${params.temperature},
  ntt=3, gamma_ln=1.0,
  ntr=0,
  ntpr=5000, ntwx=5000, ntwr=50000,
  ioutfm=1,
 /
MDEOF

        pmemd.cuda -O \
            -i md.in \
            -o md.out \
            -p ${prmtop} \
            -c ${equil_rst} \
            -r md.rst \
            -x trajectory.nc

        echo "PRODUCTION_MD complete" >> md.out
        """
}

// ----------------------------------------------------------------------------

// [Phase D] Trajectory Analysis & MM-GBSA
process TRAJECTORY_ANALYSIS {
    /*
     * Post-processing with cpptraj:
     *   - Protein backbone RMSD vs minimized reference
     *   - Per-residue RMSF (B-factor equivalent)
     *   - Radius of gyration
     *   - Hydrogen bond analysis (protein-ligand)
     * Python generates matplotlib RMSD+RMSF plots, rmsf CSV, analysis_summary.json
     */
    tag "trajectory_analysis"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/06_analysis", mode: params.publish_dir_mode

    input:
    path prmtop
    path trajectory
    path md_rst

    output:
    path "rmsd_plot.png",          emit: rmsd_plot
    path "rmsf_per_residue.csv",   emit: rmsf_csv
    path "analysis_summary.json",  emit: summary

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        cat > analysis.in << CPPEOF
trajin ${trajectory}
rmsd backbone_rmsd @CA,C,N,O first out rmsd.dat
atomicfluct rmsf_residue :1-9999 byres out rmsf.dat
radgyr protein_radgyr @CA out radgyr.dat
hbond lig_hbonds :LIG out hbond.dat avgout hbond_avg.dat
run
quit
CPPEOF

        cpptraj -p ${prmtop} -i analysis.in 2>&1 | tee cpptraj.log

        python3 - << PYEOF
import json, sys
rmsd_time, rmsd_vals = [], []
try:
    with open('rmsd.dat') as fh:
        for line in fh:
            if line.startswith('#'): continue
            cols = line.split()
            if len(cols) >= 2:
                rmsd_time.append(float(cols[0]))
                rmsd_vals.append(float(cols[1]))
except Exception as e:
    print(f'Warning: rmsd.dat: {e}', file=sys.stderr)
rmsf_res, rmsf_vals = [], []
try:
    with open('rmsf.dat') as fh:
        for line in fh:
            if line.startswith('#'): continue
            cols = line.split()
            if len(cols) >= 2:
                rmsf_res.append(int(float(cols[0])))
                rmsf_vals.append(float(cols[1]))
except Exception as e:
    print(f'Warning: rmsf.dat: {e}', file=sys.stderr)
with open('rmsf_per_residue.csv', 'w') as fh:
    fh.write('residue_number,rmsf_angstrom\\n')
    for res, val in zip(rmsf_res, rmsf_vals):
        fh.write(f'{res},{val:.3f}\\n')
try:
    import matplotlib; matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 1, figsize=(10, 8))
    if rmsd_vals:
        axes[0].plot(rmsd_time, rmsd_vals, color='steelblue', linewidth=0.8)
        axes[0].set_xlabel('Frame'); axes[0].set_ylabel('RMSD (Angstrom)')
        axes[0].set_title('Protein Backbone RMSD -- AMBER pmemd Production MD')
        axes[0].grid(alpha=0.3)
    if rmsf_vals:
        axes[1].bar(rmsf_res, rmsf_vals, color='darkorange', alpha=0.7, width=1.0)
        axes[1].set_xlabel('Residue Number'); axes[1].set_ylabel('RMSF (Angstrom)')
        axes[1].set_title('Per-Residue RMSF'); axes[1].grid(alpha=0.3, axis='y')
    plt.tight_layout()
    plt.savefig('rmsd_plot.png', dpi=150, bbox_inches='tight')
    plt.close()
except ImportError:
    open('rmsd_plot.png', 'wb').write(b'PNG_PLACEHOLDER')
n_frames  = len(rmsd_vals)
tail      = max(1, n_frames // 5)
rmsd_mean = sum(rmsd_vals[-tail:]) / tail if rmsd_vals else 0.0
rmsf_mean = sum(rmsf_vals) / len(rmsf_vals) if rmsf_vals else 0.0
flex_res  = [r for r, v in zip(rmsf_res, rmsf_vals) if v > 2.0]
summary = {
    'pipeline': 'AMBER pmemd protein-ligand MD',
    'n_frames': n_frames,
    'rmsd': {'mean_last20pct_angstrom': round(rmsd_mean, 3), 'converged': rmsd_mean < 3.0},
    'rmsf': {'mean_angstrom': round(rmsf_mean, 3), 'flexible_residues_gt2A': flex_res[:10]},
    'force_field': '${params.force_field}', 'water_model': '${params.water_model}',
    'temperature_K': ${params.temperature}, 'pressure_atm': ${params.pressure}
}
with open('analysis_summary.json', 'w') as fh:
    json.dump(summary, fh, indent=2)
print('TRAJECTORY_ANALYSIS complete')
PYEOF
        """
}

// ----------------------------------------------------------------------------

// [Phase D] Trajectory Analysis & MM-GBSA
process MM_GBSA {
    /*
     * MM-GBSA binding free energy with MMPBSA.py:
     *   - GB model igb=2 (Onufriev-Bashford-Case GB)
     *   - Per-residue energy decomposition (idecomp=1)
     *   - Frames: startframe=${params.mmgbsa_startframe}, interval=${params.mmgbsa_interval}
     * Outputs: mmgbsa_results.csv, binding_summary.json
     */
    tag "mm_gbsa"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/07_mmgbsa", mode: params.publish_dir_mode

    input:
    path prmtop
    path trajectory
    path equil_rst

    output:
    path "mmgbsa_results.csv",    emit: results_csv
    path "binding_summary.json",  emit: summary

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        # Dry topologies for MM-GBSA. The complex prmtop is solvated, so it is the -sp topology;
        # complex/receptor/ligand are stripped of water and ions with ante-MMPBSA.py, with mbondi2
        # radii as igb=2 requires. (Stripping only :LIG left the receptor with every water.)
        ante-MMPBSA.py -p ${prmtop} -c com_dry.prmtop -r rec_dry.prmtop -l lig_dry.prmtop \
            -s ':WAT:Na+:Cl-:K+' -n ':LIG' --radii=mbondi2

        # Frame window from the ACTUAL trajectory length: a fixed startframe (500) fails on any run
        # shorter than 500 frames. When the requested start is past the end, skip the first ~20%,
        # analyse to the last frame, and shrink the interval to keep >=~10 frames where possible.
        NFRAMES=\$(cpptraj -p ${prmtop} -y ${trajectory} -tl | awk '\$1 == "Frames:" {print \$2}')
        read -r MMGBSA_START MMGBSA_END MMGBSA_INTERVAL < <(python3 -c "
n = int('\${NFRAMES:-0}' or 0)
s, i = ${params.mmgbsa_startframe}, ${params.mmgbsa_interval}
if n < 1:
    raise SystemExit('ERROR: no readable frames in ${trajectory}')
if s > n:
    s = max(1, int(n * 0.2) + 1)
e = n
i = max(1, min(i, (e - s) // 10 or 1))
print(s, e, i)")
        export NFRAMES MMGBSA_START MMGBSA_END MMGBSA_INTERVAL
        echo "MM-GBSA frames: trajectory has \$NFRAMES; analysing \$MMGBSA_START..\$MMGBSA_END every \$MMGBSA_INTERVAL (requested start ${params.mmgbsa_startframe} every ${params.mmgbsa_interval})"

        cat > mmgbsa.in << GBSEOF
Input file for MM/GBSA calculation
&general
  startframe=\$MMGBSA_START,
  endframe=\$MMGBSA_END,
  interval=\$MMGBSA_INTERVAL,
  verbose=2,
  keep_files=0,
/
&gb
  igb=2, saltcon=0.15,
/
&decomp
  idecomp=1,
  print_res='within 6.0',
/
GBSEOF

        MMPBSA.py \
            -O \
            -i mmgbsa.in \
            -o mmgbsa_raw.dat \
            -do mmgbsa_decomp.dat \
            -sp ${prmtop} \
            -cp com_dry.prmtop \
            -rp rec_dry.prmtop \
            -lp lig_dry.prmtop \
            -y ${trajectory} \
            2>&1 | tee mmpbsa.log

        python3 - << PYEOF
import json, os, re, sys
delta_g = None; std_dg = None; components = {}
try:
    with open('mmgbsa_raw.dat') as fh:
        for line in fh:
            m = re.search(r'VDWAALS\\s*=\\s*([-\\d.]+)', line)
            if m: components['vdw_kcal_mol'] = float(m.group(1))
            m = re.search(r'EEL\\s*=\\s*([-\\d.]+)', line)
            if m: components['electrostatic_kcal_mol'] = float(m.group(1))
            m = re.search(r'EGB\\s*=\\s*([-\\d.]+)', line)
            if m: components['polar_solvation_kcal_mol'] = float(m.group(1))
            m = re.search(r'ESURF\\s*=\\s*([-\\d.]+)', line)
            if m: components['nonpolar_solv_kcal_mol'] = float(m.group(1))
            m = re.search(r'DELTA TOTAL\\s*=\\s*([-\\d.]+)\\s*\\+/-\\s*([\\d.]+)', line)
            if m: delta_g = float(m.group(1)); std_dg = float(m.group(2))
except Exception as e:
    print(f'Warning: mmgbsa_raw.dat: {e}', file=sys.stderr)
res_data = []
try:
    with open('mmgbsa_decomp.dat') as fh:
        lines = fh.readlines()
    in_section = False
    for line in lines:
        if 'Residue' in line and 'Internal' in line:
            in_section = True; continue
        if in_section and line.strip() == '': break
        if in_section:
            cols = line.split()
            if len(cols) >= 5:
                res_data.append({
                    'residue': cols[0], 'delta_g_gb': float(cols[1]),
                    'delta_internal': float(cols[2]), 'delta_electrostatic': float(cols[3]),
                    'delta_vdw': float(cols[4]),
                    'delta_polar_solv': float(cols[5]) if len(cols) > 5 else 0.0
                })
except Exception as e:
    print(f'Warning: mmgbsa_decomp.dat: {e}', file=sys.stderr)
with open('mmgbsa_results.csv', 'w') as fh:
    fh.write('residue,delta_g_gb,delta_internal,delta_electrostatic,delta_vdw,delta_polar_solv\\n')
    for row in res_data:
        fh.write(f'{row["residue"]},{row["delta_g_gb"]},{row["delta_internal"]},'
                 f'{row["delta_electrostatic"]},{row["delta_vdw"]},{row["delta_polar_solv"]}\\n')
top_res = sorted(res_data, key=lambda x: x['delta_g_gb'])[:10]
n_analysed = (int(os.environ['MMGBSA_END']) - int(os.environ['MMGBSA_START'])) // int(os.environ['MMGBSA_INTERVAL']) + 1
summary = {
    'pipeline': 'AMBER MM-GBSA',
    'gb_model': 'igb=2 (Onufriev-Bashford-Case)',
    'trajectory_frames': int(os.environ['NFRAMES']),
    'startframe': int(os.environ['MMGBSA_START']), 'endframe': int(os.environ['MMGBSA_END']),
    'interval': int(os.environ['MMGBSA_INTERVAL']),
    'frames_analysed': n_analysed,
    'requested_window': {'startframe': ${params.mmgbsa_startframe}, 'interval': ${params.mmgbsa_interval}},
    'md_engine': '${MD_ENGINE}',
    'delta_g_bind': {
        'value_kcal_mol': round(delta_g, 2) if delta_g is not None else None,
        'std_kcal_mol':   round(std_dg,  2) if std_dg  is not None else None,
        **{k: round(v, 2) for k, v in components.items()}
    },
    # Fewer than ~10 frames gives no usable estimate of the mean, so the value is reported but not
    # classified. (Previously anything not < -8 was 'moderate_binder', including positive values.)
    'classification': ('calculation_failed' if delta_g is None else
                       'insufficient_sampling' if n_analysed < 10 else
                       'strong_binder' if delta_g < -8.0 else
                       'moderate_binder' if delta_g < -5.0 else
                       'weak_binder' if delta_g < 0.0 else 'unfavorable'),
    'top_binding_residues': top_res[:10],
    'force_field': '${params.force_field}', 'water_model': '${params.water_model}'
}
with open('binding_summary.json', 'w') as fh:
    json.dump(summary, fh, indent=2)
if delta_g is None:
    try:
        tail = open('mmpbsa.log').read().splitlines()[-25:]
    except OSError:
        tail = ['(no mmpbsa.log)']
    sys.exit('ERROR: MMPBSA.py produced no DELTA TOTAL; last log lines:\\n' + '\\n'.join(tail))
print(f'MM_GBSA complete -- DeltaG_bind = {delta_g:.2f} kcal/mol (GB igb=2, {n_analysed} frames)')
PYEOF
        """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {

    // -----------------------------------------------------------------------
    // Parameter validation
    // -----------------------------------------------------------------------
    if (!params.receptor) {
        error "ERROR: params.receptor is required.\n" +
              "       Provide a PDB file path or S3 URI (e.g. s3://bucket/protein.pdb)"
    }
    if (!params.ligand) {
        error "ERROR: params.ligand is required.\n" +
              "       Provide a ligand SDF or mol2 file path"
    }

    log.info """
    ============================================================
     AMBER pmemd Protein-Ligand MD Pipeline
    ============================================================
     receptor     : ${params.receptor}
     ligand       : ${params.ligand}
     force_field  : ${params.force_field}
     water_model  : ${params.water_model}
     gaff_version : ${params.gaff_version}
     box_padding  : ${params.box_padding} A
     n_steps      : ${params.n_steps}
     temperature  : ${params.temperature} K
     pressure     : ${params.pressure} atm
     mmgbsa_start : frame ${params.mmgbsa_startframe}
     mmgbsa_interv: ${params.mmgbsa_interval}
     outdir       : ${params.outdir}
    ============================================================
    """.stripIndent()

    // -----------------------------------------------------------------------
    // Input channels
    // -----------------------------------------------------------------------
    // Resolve receptor: accept .pdb path, S3 URI, or 4-char PDB ID (auto-download from RCSB)
    def receptor_input = params.receptor.trim()
    def _is_pdb_id = (receptor_input ==~ /^[A-Za-z0-9]{4}$/)
    if (_is_pdb_id) {
        def pdb_id = receptor_input.toUpperCase()
        def pdb_file = file("/tmp/biomate_nf_inputs/pdb/${pdb_id}.pdb")
        pdb_file.parent.mkdirs()
        if (!pdb_file.exists()) {
            log.info("[AMBER] Downloading PDB ${pdb_id} from RCSB...")
            ["curl", "-sSf", "-o", pdb_file.toString(),
             "https://files.rcsb.org/download/${pdb_id}.pdb"].execute().waitFor()
        }
        if (!pdb_file.exists() || pdb_file.size() == 0) {
            error "Failed to download PDB ID ${pdb_id} from RCSB. Check the ID and network access."
        }
        receptor_ch = Channel.fromPath(pdb_file.toString())
    } else {
        receptor_ch = Channel.fromPath(receptor_input, checkIfExists: true)
    }

    def ligand_input = params.ligand.trim()
    def _is_smiles = !(ligand_input.contains('/') || ligand_input.contains('\\') ||
                       ligand_input.endsWith('.sdf') || ligand_input.endsWith('.mol2') ||
                       ligand_input.endsWith('.pdb') || ligand_input.startsWith('s3://')) &&
                      (ligand_input.contains('(') || ligand_input.contains('=') ||
                       ligand_input.contains('[') || ligand_input.contains('#') ||
                       ligand_input.contains('@') || ligand_input ==~ /[CNOSPFClBrI].+/)
    if (_is_smiles) {
        // Write SMILES to a .smi file on the head node; rdkit conversion to SDF
        // happens inside LIGAND_PREP process where AMBERTOOLS container has rdkit.
        log.info("[AMBER] Detected SMILES input for ligand — staging as .smi for in-container RDKit conversion...")
        def smi_file = file("/tmp/biomate_nf_inputs/smi/ligand_${System.currentTimeMillis()}.smi")
        smi_file.parent.mkdirs()
        smi_file.text = ligand_input
        ligand_ch = Channel.fromPath(smi_file.toString())
    } else {
        ligand_ch = Channel.fromPath(ligand_input, checkIfExists: true)
    }

    // -----------------------------------------------------------------------
    // Step 1: GAFF2 ligand parameterization
    // -----------------------------------------------------------------------
    ligand_prep_out = LIGAND_PREP(ligand_ch)

    // -----------------------------------------------------------------------
    // Step 2: Build solvated complex with tleap
    // -----------------------------------------------------------------------
    system_setup_out = SYSTEM_SETUP(
        receptor_ch,
        ligand_prep_out.mol2,
        ligand_prep_out.frcmod
    )

    // -----------------------------------------------------------------------
    // Step 3: Energy minimization (sander CPU)
    // -----------------------------------------------------------------------
    em_out = ENERGY_MINIMIZATION(
        system_setup_out.prmtop,
        system_setup_out.inpcrd
    )

    // -----------------------------------------------------------------------
    // Step 4: NVT + NPT equilibration (pmemd.cuda)
    // -----------------------------------------------------------------------
    equil_out = EQUILIBRATION(
        system_setup_out.prmtop,
        em_out.rst
    )

    // -----------------------------------------------------------------------
    // Step 5: Production MD (pmemd.cuda)
    // -----------------------------------------------------------------------
    prod_out = PRODUCTION_MD(
        system_setup_out.prmtop,
        equil_out.rst
    )

    // -----------------------------------------------------------------------
    // Step 6: Trajectory analysis (cpptraj + matplotlib)
    // -----------------------------------------------------------------------
    analysis_out = TRAJECTORY_ANALYSIS(
        system_setup_out.prmtop,
        prod_out.trajectory,
        prod_out.rst
    )

    // -----------------------------------------------------------------------
    // Step 7: MM-GBSA binding free energy (MMPBSA.py)
    // -----------------------------------------------------------------------
    mmgbsa_out = MM_GBSA(
        system_setup_out.prmtop,
        prod_out.trajectory,
        equil_out.rst
    )

    // -----------------------------------------------------------------------
    // Pipeline completion summary -- print DeltaG from binding_summary.json
    // -----------------------------------------------------------------------
    mmgbsa_out.summary
        .subscribe { summary_file ->
            def json_text = summary_file.text
            def dg_match  = json_text =~ /"value_kcal_mol"\s*:\s*([-\d.]+)/
            def std_match = json_text =~ /"std_kcal_mol"\s*:\s*([-\d.]+)/
            def cls_match = json_text =~ /"classification"\s*:\s*"([^"]+)"/

            def dg_val  = dg_match  ? dg_match[0][1]  : 'N/A'
            def std_val = std_match ? std_match[0][1] : 'N/A'
            def cls_val = cls_match ? cls_match[0][1] : 'N/A'

            log.info """
+------------------------------------------------------------+
|  AMBER pmemd MD Pipeline -- COMPLETE                       |
+------------------------------------------------------------+
|  DeltaG_bind (MM-GBSA igb=2)   :  ${dg_val} +/- ${std_val} kcal/mol
|  Classification                 :  ${cls_val}
|  RMSD plot                      :  ${params.outdir}/06_analysis/rmsd_plot.png
|  Per-residue RMSF               :  ${params.outdir}/06_analysis/rmsf_per_residue.csv
|  MM-GBSA per-residue results    :  ${params.outdir}/07_mmgbsa/mmgbsa_results.csv
|  Binding summary JSON           :  ${params.outdir}/07_mmgbsa/binding_summary.json
|  Trajectory (NetCDF)            :  ${params.outdir}/05_production/trajectory.nc
+------------------------------------------------------------+
|  References:
|    AMBER:   Case et al. J. Chem. Inf. Model. 2023, 63:6183
|    GAFF2:   Wang et al. J. Comput. Chem. 2004, 25:1157
|    MM-GBSA: Kollman et al. Acc. Chem. Res. 2000, 33:889
|    cpptraj: Roe & Cheatham JCTC 2013, 9:3084
+------------------------------------------------------------+
            """.stripIndent()
        }
}
