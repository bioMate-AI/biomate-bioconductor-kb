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
 * 4. EQUILIBRATION       -- pmemd.cuda: 100ps NVT (heating 0->300K, restrained)
 *                                     + 100ps NPT (1 atm, restrained)
 * 5. PRODUCTION_MD       -- pmemd.cuda: N ns NPT unrestrained production
 * 6. TRAJECTORY_ANALYSIS -- cpptraj: RMSD, RMSF, H-bonds, radius of gyration
 * 7. MM_GBSA             -- MMPBSA.py: GB model (igb=2), per-residue decomposition
 *
 * Outputs:
 *   trajectory.nc             -- NetCDF production trajectory
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

// AWS Batch flag — set via profile (aws/gpu_batch) or --use_aws true
params.use_aws              = false

// ============================================================================
// Containers
// ============================================================================

// On AWS Batch use the unified ECR image (AmberTools 23 + GROMACS 2024 via conda-forge)
params._useAws = params.use_aws || System.getenv('NEXTFLOW_USE_AWS') == 'true'
params._ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest'
params.AMBER_CONTAINER = params._useAws ? params._ECR : '399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest'
params.AMBERTOOLS_CONTAINER = params._useAws ? params._ECR : 'ambermd/ambertools:23'

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
    container params.AMBERTOOLS_CONTAINER
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
    container params.AMBERTOOLS_CONTAINER
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
    container params.AMBER_CONTAINER
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
  ntpr=100, ntwx=0,
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
  ntpr=100, ntwx=0,
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
    container params.AMBER_CONTAINER
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
    container params.AMBER_CONTAINER
    publishDir "${params.outdir}/05_production", mode: params.publish_dir_mode

    cpus params.n_cpus

    input:
    path prmtop
    path equil_rst

    output:
    path "trajectory.nc",  emit: trajectory
    path "md.out",         emit: log
    path "md.rst",         emit: rst

    script:
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
    container params.AMBERTOOLS_CONTAINER
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
trajin trajectory.nc
reference minimized.rst parm complex.prmtop
rmsd backbone_rmsd @CA,C,N,O ref reference out rmsd.dat
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
    container params.AMBERTOOLS_CONTAINER
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

        cat > strip_receptor.in << STREOF
parm complex.prmtop
parmstrip :LIG
parmwrite out receptor.prmtop
quit
STREOF
        cpptraj -p ${prmtop} -i strip_receptor.in

        cat > strip_ligand.in << STLEOF
parm complex.prmtop
parmstrip !:LIG
parmwrite out ligand_only.prmtop
quit
STLEOF
        cpptraj -p ${prmtop} -i strip_ligand.in

        cat > mmgbsa.in << GBSEOF
Input file for MM/GBSA calculation
&general
  startframe=${params.mmgbsa_startframe},
  endframe=-1,
  interval=${params.mmgbsa_interval},
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
            -cp ${prmtop} \
            -rp receptor.prmtop \
            -lp ligand_only.prmtop \
            -y ${trajectory} \
            2>&1 | tee mmpbsa.log

        python3 - << PYEOF
import json, re, sys
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
summary = {
    'pipeline': 'AMBER MM-GBSA',
    'gb_model': 'igb=2 (Onufriev-Bashford-Case)',
    'startframe': ${params.mmgbsa_startframe}, 'interval': ${params.mmgbsa_interval},
    'delta_g_bind': {
        'value_kcal_mol': round(delta_g, 2) if delta_g is not None else None,
        'std_kcal_mol':   round(std_dg,  2) if std_dg  is not None else None,
        **{k: round(v, 2) for k, v in components.items()}
    },
    'classification': ('strong_binder' if delta_g is not None and delta_g < -8.0
                        else 'moderate_binder'),
    'top_binding_residues': top_res[:10],
    'force_field': '${params.force_field}', 'water_model': '${params.water_model}'
}
with open('binding_summary.json', 'w') as fh:
    json.dump(summary, fh, indent=2)
dg_str = f'{delta_g:.2f}' if delta_g is not None else 'N/A'
print(f'MM_GBSA complete -- DeltaG_bind = {dg_str} kcal/mol (GB igb=2)')
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
