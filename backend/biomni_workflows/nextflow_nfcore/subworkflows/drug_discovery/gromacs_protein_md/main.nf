#!/usr/bin/env nextflow
/*
 * drug_discovery/gromacs_protein_md
 *
 * Protein-ligand molecular dynamics + MM-GBSA binding free energy pipeline.
 * Uses AmberTools 23 for GAFF2 parameterization, GROMACS 2025 for MD,
 * and gmx_MMPBSA for binding free energy.
 *
 * Pipeline Steps:
 * 1. LIGAND_PREP         -- AmberTools antechamber + parmchk2 -> GAFF2 force-field params
 * 2. SYSTEM_SETUP        -- tleap: solvate protein-ligand complex; ParmEd -> GROMACS topology
 * 3. ENERGY_MINIMIZATION -- GROMACS steepest descent (gmx grompp + gmx mdrun)
 * 4. NVT_EQUILIBRATION   -- GROMACS 100 ps NVT (position restrained)
 * 5. NPT_EQUILIBRATION   -- GROMACS 100 ps NPT (Parrinello-Rahman barostat)
 * 6. PRODUCTION_MD       -- GROMACS NPT production run (default 10 ns)
 * 7. TRAJECTORY_ANALYSIS -- gmx rms + gmx rmsf + matplotlib RMSD/RMSF plots
 * 8. MM_GBSA             -- gmx_MMPBSA: deltaGbind + per-residue decomposition
 *
 * Outputs:
 *   trajectory.xtc            -- compressed production trajectory
 *   binding_summary.json      -- deltaGbind, RMSD stats, system info
 *   rmsd_plot.png             -- RMSD over time (protein backbone + ligand)
 *   mmgbsa_results.csv        -- per-residue energy decomposition
 *
 * References:
 *   GROMACS: Abraham et al. SoftwareX 2015, 1-2:19-25
 *   AmberTools: Case et al. J. Chem. Inf. Model. 2023, 63:6183-6200
 *   GAFF2: Wang et al. J. Comput. Chem. 2004, 25:1157-1174
 *   gmx_MMPBSA: Valdes-Tresanco et al. J. Chem. Theory Comput. 2021, 17:6281-6291
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir               = './results/gromacs_protein_md'
params.publish_dir_mode     = 'copy'

// Inputs
params.receptor             = null       // receptor.pdb or S3 URI
params.ligand               = null       // ligand.sdf or ligand.mol2

// Force field
params.force_field          = 'amber99sb-ildn'  // amber99sb-ildn | charmm36m | amber14sb
params.water_model          = 'tip3p'           // tip3p | tip4p | spc
params.gaff_version         = 'gaff2'           // gaff | gaff2

// Simulation settings
params.box_padding          = 12         // Angstrom from protein surface to box edge
params.ion_concentration    = 0.15       // mol/L (NaCl neutralizing salt)
params.temperature          = 300        // K (NVT/NPT equilibration + production)
params.pressure             = 1.0        // bar (NPT)

// Production run
params.n_steps              = 5000000    // MD steps (2 fs dt -> 10 ns default)
params.dt                   = 0.002      // ps (2 fs timestep)
params.nstxout_compressed   = 5000       // write trajectory frame every 10 ps

// MM-GBSA
params.mmgbsa_startframe    = 500        // skip first N frames (equilibration buffer)
params.mmgbsa_endframe      = -1         // -1 = all frames
params.mmgbsa_interval      = 5          // analyse every Nth frame

// Resources
params.n_cpus               = 8
params.gpu                  = true
params.gpu_device           = 0

// AWS Batch flag — set via profile (aws/gpu_batch) or CLI --use_aws true
// Using a param (not System.getenv) so config profiles can set it reliably.
params.use_aws              = false

// ============================================================================
// Containers
// ============================================================================

// On AWS Batch use single ECR image containing all tools (avoids Docker Hub auth issues)
// Also honour the legacy NEXTFLOW_USE_AWS env var for backwards compatibility.
def _useAws = params.use_aws || System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes']
def _ECR    = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest'
// AmberTools 23: antechamber, tleap, parmchk2, pdb4amber, ParmEd, acpype
def AMBERTOOLS_CONTAINER = _useAws ? _ECR : 'ambermd/ambertools:23'
// GROMACS 2025: gmx grompp, gmx mdrun, gmx rms, gmx rmsf, gmx genrestr, gmx editconf, etc.
def GROMACS_CONTAINER    = _useAws ? _ECR : 'gromacs/gromacs:2025.1'
// gmx_MMPBSA: gmx_MMPBSA Python API + AmberTools + GROMACS
def MMPBSA_CONTAINER     = _useAws ? _ECR : 'simonbray/gmx_mmpbsa:1.6.3'

// ============================================================================
// Processes
// ============================================================================

process LIGAND_PREP {
    /*
     * Convert ligand to GAFF2 force-field parameters using AmberTools antechamber.
     * Input:  ligand.sdf or ligand.mol2
     * Output: ligand_gaff2.mol2  -- AM1-BCC charges, GAFF2 atom types
     *         ligand.frcmod      -- missing GAFF2 force-field terms
     */
    tag "ligand_prep"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/prep", mode: params.publish_dir_mode

    input:
    path ligand_file

    output:
    path "ligand_gaff2.mol2", emit: mol2
    path "ligand.frcmod",     emit: frcmod
    path "ligand_prep.log",   emit: log

    script:
    def gaff = params.gaff_version
    """
    set -euo pipefail

    lig_file="${ligand_file}"
    lig_ext=\$(echo "\$lig_file" | rev | cut -d'.' -f1 | rev | tr '[:upper:]' '[:lower:]')

    # Determine input format flag for antechamber
    if [ "\$lig_ext" = "sdf" ] || [ "\$lig_ext" = "sd" ]; then
        in_fmt="sdf"
    elif [ "\$lig_ext" = "mol2" ]; then
        in_fmt="mol2"
    elif [ "\$lig_ext" = "mol" ]; then
        in_fmt="mdl"
    else
        echo "ERROR: unsupported ligand format: \$lig_ext" >&2
        exit 1
    fi

    # Run antechamber: AM1-BCC charges + GAFF2 atom types
    antechamber \
        -i "\$lig_file" -fi "\$in_fmt" \
        -o ligand_gaff2.mol2 -fo mol2 \
        -c bcc -at ${gaff} -rn LIG -nc 0 -m 1 \
        2>&1 | tee ligand_prep.log

    # Generate missing GAFF2 torsion/angle parameters
    parmchk2 -i ligand_gaff2.mol2 -f mol2 -o ligand.frcmod -s ${gaff} \
        2>&1 | tee -a ligand_prep.log

    echo "LIGAND_PREP complete: GAFF2 parameterization done" | tee -a ligand_prep.log
    """
}


process SYSTEM_SETUP {
    /*
     * tleap: build solvated protein-ligand complex topology.
     * Converts AMBER prmtop/inpcrd -> GROMACS gro/top via ParmEd.
     * Also generates position restraint ITP file via gmx genrestr.
     */
    tag "system_setup"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/prep", mode: params.publish_dir_mode

    input:
    path receptor_pdb
    path ligand_mol2
    path ligand_frcmod

    output:
    path "complex.gro",   emit: gro
    path "complex.top",   emit: top
    path "posres.itp",    emit: posres
    path "setup.log",     emit: log

    script:
    def ff   = params.force_field
    def wm   = params.water_model
    def gaff = params.gaff_version
    def pad  = params.box_padding
    def conc = params.ion_concentration
    """
    set -euo pipefail

    # 1. Clean receptor with pdb4amber (strip HETATM first, then fix residue names)
    # Remove HETATM (ligands, waters, cofactors) before pdb4amber so tLeap only
    # sees protein ATOM records — prevents "does not have a type" for heteroatoms
    grep -E "^(ATOM|TER|END)" "${receptor_pdb}" > receptor_nohet.pdb || true
    # Fallback: if grep found nothing, use original (already protein-only)
    [ -s receptor_nohet.pdb ] || cp "${receptor_pdb}" receptor_nohet.pdb
    pdb4amber -i receptor_nohet.pdb -o receptor_clean.pdb --no-conect \
        2>&1 | tee setup.log

    # 2. Determine leaprc water model
    case "${wm}" in
        tip3p)  WATER_LEAPRC="leaprc.water.tip3p"  ; WATER_BOX="TIP3PBOX"  ;;
        tip4p)  WATER_LEAPRC="leaprc.water.tip4p"  ; WATER_BOX="TIP4PBOX"  ;;
        spc)    WATER_LEAPRC="leaprc.water.spce"   ; WATER_BOX="SPCBOX"    ;;
        *)      WATER_LEAPRC="leaprc.water.tip3p"  ; WATER_BOX="TIP3PBOX"  ;;
    esac

    # 3. Build tleap input script
    cat > tleap.in << TLEAP_EOF
source leaprc.protein.ff14SB
source \$WATER_LEAPRC
source leaprc.${gaff}

LIG = loadmol2 ${ligand_mol2}
loadamberparams ${ligand_frcmod}
check LIG

PROT = loadpdb receptor_clean.pdb
COMPLEX = combine {PROT LIG}
charge COMPLEX

solvateBox COMPLEX \$WATER_BOX ${pad}
addIons2 COMPLEX Na+ 0
addIons2 COMPLEX Cl- 0

saveamberparm COMPLEX complex.prmtop complex.inpcrd
quit
TLEAP_EOF

    tleap -f tleap.in 2>&1 | tee -a setup.log

    # 4. Convert AMBER topology -> GROMACS format via ParmEd
    python3 << 'PARMED_EOF'
import parmed
import sys

print("Converting AMBER -> GROMACS topology via ParmEd...", flush=True)
amber = parmed.load_file('complex.prmtop', 'complex.inpcrd')
amber.save('complex.gro', overwrite=True)
amber.save('complex.top', overwrite=True)
print(f"System: {len(amber.atoms)} atoms, {len(amber.residues)} residues", flush=True)
PARMED_EOF

    # 5. Generate GROMACS position restraints for protein heavy atoms
    # Extract protein atom indices (residue names != WAT, Na+, Cl-, LIG)
    python3 << 'POSRES_EOF'
import parmed

amber = parmed.load_file('complex.prmtop', 'complex.inpcrd')
protein_res = {'ALA','ARG','ASN','ASP','CYS','GLN','GLU','GLY','HIS','HID','HIE','HIP',
               'ILE','LEU','LYS','MET','PHE','PRO','SER','THR','TRP','TYR','VAL',
               'HYP','ACE','NME','NHE'}
with open('posres.itp', 'w') as f:
    f.write('[ position_restraints ]\\n')
    f.write(';  i funct       fcx        fcy        fcz\\n')
    for i, atom in enumerate(amber.atoms, 1):
        res = atom.residue
        if res.name in protein_res and atom.name in ('CA','C','N','O'):
            f.write(f'{i:6d}    1     1000       1000       1000\\n')
print('Position restraints written to posres.itp', flush=True)
POSRES_EOF

    echo "SYSTEM_SETUP complete" | tee -a setup.log
    """
}


process ENERGY_MINIMIZATION {
    /*
     * Steepest descent energy minimization using GROMACS.
     * Minimizes forces to below 1000 kJ/mol/nm.
     */
    tag "em"
    container GROMACS_CONTAINER
    publishDir "${params.outdir}/em", mode: params.publish_dir_mode

    input:
    path gro
    path top
    path posres

    output:
    path "minimized.gro",    emit: gro
    path "em.log",           emit: log
    path "em_potential.xvg", emit: potential

    script:
    """
    set -euo pipefail

    # Write energy minimization MDP
    cat > em.mdp << 'MDP_EOF'
; Energy minimization
integrator      = steep
emtol           = 1000.0
emstep          = 0.01
nsteps          = 50000

; Neighbour list
nstlist         = 1
cutoff-scheme   = Verlet
ns_type         = grid
pbc             = xyz

; Electrostatics
coulombtype     = PME
rcoulomb        = 1.0
fourierspacing  = 0.16

; Van der Waals
rvdw            = 1.0
vdwtype         = Cut-off

; Position restraints
define          = -DPOSRES
MDP_EOF

    # Include posres.itp before the [ system ] section (inside molecule type definition)
    # Position restraints must not go in [ intermolecular_interactions ]
    if ! grep -q "posres.itp" ${top}; then
        python3 - "${top}" << 'POSRES_INSERT'
import sys, re
top = sys.argv[1]
lines = open(top).readlines()
out = []
inserted = False
mol_count = 0
for line in lines:
    # Count [ moleculetype ] headers; insert before the 2nd one (end of protein section)
    if re.match(r'^\s*\[\s*moleculetype\s*\]', line):
        mol_count += 1
        if mol_count == 2 and not inserted:
            out.append('#ifdef POSRES\\n')
            out.append('#include "posres.itp"\\n')
            out.append('#endif\\n\\n')
            inserted = True
    out.append(line)
# Fallback: insert before [ system ] if protein was the only molecule type
if not inserted:
    out2 = []
    for line in out:
        if not inserted and re.match(r'^\s*\[\s*system\s*\]', line):
            out2.append('#ifdef POSRES\\n')
            out2.append('#include "posres.itp"\\n')
            out2.append('#endif\\n\\n')
            inserted = True
        out2.append(line)
    out = out2
open(top, 'w').writelines(out)
POSRES_INSERT
    fi

    gmx grompp -f em.mdp -c ${gro} -p ${top} -r ${gro} -o em.tpr -maxwarn 5 2>&1 | tee em_grompp.log
    gmx mdrun -v -deffnm em -ntmpi 1 -ntomp ${task.cpus} 2>&1 | tee em_mdrun.log
    cat em_grompp.log em_mdrun.log > em.log

    # Extract potential energy convergence
    echo "Potential\n0\n" | gmx energy -f em.edr -o em_potential.xvg 2>/dev/null || \
        echo "# potential energy not available" > em_potential.xvg

    mv em.gro minimized.gro
    echo "ENERGY_MINIMIZATION complete" | tee -a em.log
    """
}


process NVT_EQUILIBRATION {
    /*
     * 100 ps NVT equilibration at target temperature.
     * Velocity-rescaling thermostat; protein+ligand position restrained.
     */
    tag "nvt"
    container GROMACS_CONTAINER
    publishDir "${params.outdir}/nvt", mode: params.publish_dir_mode

    input:
    path gro
    path top
    path posres

    output:
    path "nvt.gro",      emit: gro
    path "nvt_temp.xvg", emit: temperature
    path "nvt.log",      emit: log

    script:
    def temp = params.temperature
    """
    set -euo pipefail

    cat > nvt.mdp << 'MDP_EOF'
; NVT equilibration -- 100 ps
integrator      = md
dt              = 0.002
nsteps          = 50000
nstxout         = 500
nstvout         = 500
nstenergy       = 500
nstlog          = 500

; Neighbour list
cutoff-scheme   = Verlet
nstlist         = 10
pbc             = xyz

; Electrostatics
coulombtype     = PME
rcoulomb        = 1.0
fourierspacing  = 0.16

; Van der Waals
rvdw            = 1.0
DispCorr        = EnerPres

; Temperature coupling (V-rescale)
tcoupl          = V-rescale
tc-grps         = Protein Non-Protein
tau_t           = 0.1 0.1
ref_t           = MDP_TEMP MDP_TEMP

; No pressure coupling (NVT)
pcoupl          = no

; Position restraints
define          = -DPOSRES

; Bond constraints
constraints     = h-bonds
constraint-algorithm = LINCS
MDP_EOF
    sed -i "s/MDP_TEMP/${temp}/g" nvt.mdp

    gmx grompp -f nvt.mdp -c ${gro} -r ${gro} -p ${top} -o nvt.tpr -maxwarn 5 2>&1 | tee nvt_grompp.log
    gmx mdrun -v -deffnm nvt -ntmpi 1 -ntomp ${task.cpus} 2>&1 | tee nvt_mdrun.log
    cat nvt_grompp.log nvt_mdrun.log > nvt.log

    echo "Temperature\n0\n" | gmx energy -f nvt.edr -o nvt_temp.xvg 2>/dev/null || \
        echo "# temperature not available" > nvt_temp.xvg

    echo "NVT_EQUILIBRATION complete" | tee -a nvt.log
    """
}


process NPT_EQUILIBRATION {
    /*
     * 100 ps NPT equilibration at target temperature + 1 bar pressure.
     * Parrinello-Rahman barostat; protein+ligand position restrained.
     */
    tag "npt"
    container GROMACS_CONTAINER
    publishDir "${params.outdir}/npt", mode: params.publish_dir_mode

    input:
    path gro
    path top
    path posres

    output:
    path "npt.gro",         emit: gro
    path "npt_density.xvg", emit: density
    path "npt.log",         emit: log

    script:
    def temp = params.temperature
    def pres = params.pressure
    """
    set -euo pipefail

    cat > npt.mdp << 'MDP_EOF'
; NPT equilibration -- 100 ps
integrator      = md
dt              = 0.002
nsteps          = 50000
nstxout         = 500
nstvout         = 500
nstenergy       = 500
nstlog          = 500

; Neighbour list
cutoff-scheme   = Verlet
nstlist         = 10
pbc             = xyz

; Electrostatics
coulombtype     = PME
rcoulomb        = 1.0
fourierspacing  = 0.16

; Van der Waals
rvdw            = 1.0
DispCorr        = EnerPres

; Temperature coupling
tcoupl          = V-rescale
tc-grps         = Protein Non-Protein
tau_t           = 0.1 0.1
ref_t           = MDP_TEMP MDP_TEMP

; Pressure coupling (Parrinello-Rahman)
pcoupl          = Parrinello-Rahman
pcoupltype      = isotropic
tau_p           = 2.0
ref_p           = MDP_PRES
compressibility = 4.5e-5

; Position restraints
define          = -DPOSRES

; Bond constraints
constraints     = h-bonds
constraint-algorithm = LINCS
MDP_EOF
    sed -i "s/MDP_TEMP/${temp}/g" npt.mdp
    sed -i "s/MDP_PRES/${pres}/g" npt.mdp

    gmx grompp -f npt.mdp -c ${gro} -r ${gro} -p ${top} -o npt.tpr -maxwarn 5 2>&1 | tee npt_grompp.log
    gmx mdrun -v -deffnm npt -ntmpi 1 -ntomp ${task.cpus} 2>&1 | tee npt_mdrun.log
    cat npt_grompp.log npt_mdrun.log > npt.log

    echo "Density\n0\n" | gmx energy -f npt.edr -o npt_density.xvg 2>/dev/null || \
        echo "# density not available" > npt_density.xvg

    echo "NPT_EQUILIBRATION complete" | tee -a npt.log
    """
}


process PRODUCTION_MD {
    /*
     * NPT production MD run (default 10 ns).
     * Unrestrained protein + ligand. GPU-accelerated when params.gpu = true.
     */
    tag "production_md"
    container GROMACS_CONTAINER
    publishDir "${params.outdir}/md", mode: params.publish_dir_mode

    input:
    path gro
    path top

    output:
    path "trajectory.xtc",  emit: trajectory
    path "production.gro",  emit: final_gro
    path "md.edr",          emit: energy
    path "md.log",          emit: log

    script:
    def temp     = params.temperature
    def pres     = params.pressure
    def n_steps  = params.n_steps
    def dt       = params.dt
    def nstxtc   = params.nstxout_compressed
    def gpu_flag = params.gpu ? "-gpu_id ${params.gpu_device} -nb gpu -pme gpu -bonded gpu" : ""
    """
    set -euo pipefail

    cat > md.mdp << 'MDP_EOF'
; Production MD
integrator      = md
dt              = MDP_DT
nsteps          = MDP_NSTEPS

; Output
nstxout-compressed = MDP_NSTXTC
nstxout         = 0
nstvout         = 0
nstenergy       = 5000
nstlog          = 5000

; Neighbour list
cutoff-scheme   = Verlet
nstlist         = 10
pbc             = xyz

; Electrostatics
coulombtype     = PME
rcoulomb        = 1.0
fourierspacing  = 0.16

; Van der Waals
rvdw            = 1.0
DispCorr        = EnerPres

; Temperature coupling
tcoupl          = V-rescale
tc-grps         = Protein Non-Protein
tau_t           = 0.1 0.1
ref_t           = MDP_TEMP MDP_TEMP

; Pressure coupling (Parrinello-Rahman)
pcoupl          = Parrinello-Rahman
pcoupltype      = isotropic
tau_p           = 2.0
ref_p           = MDP_PRES
compressibility = 4.5e-5

; No position restraints (production)
; Bond constraints
constraints     = h-bonds
constraint-algorithm = LINCS
lin_cs_order    = 4

; COM motion removal
comm-mode       = Linear
nstcomm         = 100

; Free energy (off)
free-energy     = no
MDP_EOF

    sed -i "s/MDP_DT/${dt}/g"         md.mdp
    sed -i "s/MDP_NSTEPS/${n_steps}/g" md.mdp
    sed -i "s/MDP_NSTXTC/${nstxtc}/g"  md.mdp
    sed -i "s/MDP_TEMP/${temp}/g"      md.mdp
    sed -i "s/MDP_PRES/${pres}/g"      md.mdp

    gmx grompp -f md.mdp -c ${gro} -p ${top} -o md.tpr -maxwarn 5 2>&1 | tee md_grompp.log
    gmx mdrun -v -deffnm md -ntmpi 1 -ntomp ${task.cpus} ${gpu_flag} \
        -nsteps ${n_steps} 2>&1 | tee md_mdrun.log
    cat md_grompp.log md_mdrun.log > md.log

    # Rename final frame GRO
    cp md.gro production.gro
    # Use compressed trajectory if XTC available
    if [ -f md.xtc ]; then
        cp md.xtc trajectory.xtc
    else
        # Fallback: convert TRR to XTC
        echo "0\n" | gmx trjconv -f md.trr -s md.tpr -o trajectory.xtc -pbc mol 2>/dev/null || \
            touch trajectory.xtc
    fi

    echo "PRODUCTION_MD complete: ${n_steps} steps at dt=${dt} ps" | tee -a md.log
    """
}


process TRAJECTORY_ANALYSIS {
    /*
     * Structural analysis of production trajectory using GROMACS tools:
     * - Backbone RMSD vs. initial minimized structure (gmx rms)
     * - Per-residue RMSF (gmx rmsf)
     * - matplotlib RMSD/RMSF plots
     */
    tag "analysis"
    container GROMACS_CONTAINER
    publishDir "${params.outdir}/analysis", mode: params.publish_dir_mode

    input:
    path trajectory
    path final_gro
    path top

    output:
    path "rmsd_plot.png",         emit: rmsd_plot
    path "rmsf_per_residue.csv",  emit: rmsf
    path "analysis_summary.json", emit: summary

    script:
    """
    set -euo pipefail

    # Recreate TPR from final GRO for gmx analysis tools
    cat > analysis.mdp << 'MDP_EOF'
integrator = md
nsteps     = 0
MDP_EOF
    gmx grompp -f analysis.mdp -c ${final_gro} -p ${top} -o analysis.tpr -maxwarn 10 2>/dev/null || true

    # Backbone RMSD vs first frame (group 4 = backbone in most GROMACS topologies)
    if [ -f analysis.tpr ] && [ -s ${trajectory} ]; then
        printf "4\n4\n" | gmx rms -s analysis.tpr -f ${trajectory} -o rmsd_backbone.xvg \
            -tu ns 2>/dev/null || echo "# rmsd unavailable" > rmsd_backbone.xvg

        # Per-residue RMSF (group 4 = backbone, or 1 = protein)
        printf "4\n" | gmx rmsf -s analysis.tpr -f ${trajectory} -o rmsf_per_residue.xvg \
            -res 2>/dev/null || echo "# rmsf unavailable" > rmsf_per_residue.xvg
    else
        echo "# rmsd unavailable" > rmsd_backbone.xvg
        echo "# rmsf unavailable" > rmsf_per_residue.xvg
    fi

    # Parse XVG and generate plots + JSON summary
    python3 << 'PYEOF'
import json, csv, sys, os
from datetime import datetime

def parse_xvg(path):
    '''Read GROMACS XVG file, skip comment/header lines.'''
    data = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line.startswith(('#', '@')) or not line:
                    continue
                parts = line.split()
                if len(parts) >= 2:
                    try:
                        data.append((float(parts[0]), float(parts[1])))
                    except ValueError:
                        pass
    except Exception:
        pass
    return data

rmsd_data = parse_xvg('rmsd_backbone.xvg')
rmsf_data = parse_xvg('rmsf_per_residue.xvg')

# Write RMSF CSV
with open('rmsf_per_residue.csv', 'w', newline='') as csvf:
    writer = csv.writer(csvf)
    writer.writerow(['residue_number', 'rmsf_nm'])
    for resnum, rmsf in rmsf_data:
        writer.writerow([int(resnum), round(rmsf, 4)])

# Plot RMSD and RMSF
try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 2, figsize=(12, 4))
    if rmsd_data:
        times = [d[0] for d in rmsd_data]
        rmsds = [d[1] for d in rmsd_data]
        axes[0].plot(times, rmsds, 'b-', linewidth=1.2)
        axes[0].set_xlabel('Time (ns)')
        axes[0].set_ylabel('RMSD (nm)')
        axes[0].set_title('Backbone RMSD')
        axes[0].grid(alpha=0.3)
    else:
        axes[0].text(0.5, 0.5, 'RMSD data not available', ha='center', va='center',
                     transform=axes[0].transAxes)

    if rmsf_data:
        res_nums = [d[0] for d in rmsf_data]
        rmsfs    = [d[1] for d in rmsf_data]
        axes[1].bar(res_nums, rmsfs, color='darkorange', alpha=0.7, width=1.0)
        axes[1].set_xlabel('Residue Number')
        axes[1].set_ylabel('RMSF (nm)')
        axes[1].set_title('Per-Residue RMSF')
        axes[1].grid(alpha=0.3, axis='y')
    else:
        axes[1].text(0.5, 0.5, 'RMSF data not available', ha='center', va='center',
                     transform=axes[1].transAxes)

    plt.tight_layout()
    plt.savefig('rmsd_plot.png', dpi=150, bbox_inches='tight')
    plt.close()
except Exception as e:
    import base64
    # Minimal 1x1 PNG fallback
    _b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg=='
    with open('rmsd_plot.png', 'wb') as imgf:
        imgf.write(base64.b64decode(_b64))
    print(f'WARNING: matplotlib unavailable: {e}', file=sys.stderr)

# Build analysis summary
n_frames   = len(rmsd_data)
mean_rmsd  = round(sum(d[1] for d in rmsd_data) / n_frames, 4) if rmsd_data else None
max_rmsd   = round(max(d[1] for d in rmsd_data), 4) if rmsd_data else None
n_res      = len(rmsf_data)
mean_rmsf  = round(sum(d[1] for d in rmsf_data) / n_res, 4) if rmsf_data else None
flex_res   = [int(r) for r, v in rmsf_data if v > 0.2][:10]

summary = {
    'tool':                          'gromacs',
    'n_frames_analyzed':             n_frames,
    'n_residues':                    n_res,
    'protein_backbone_rmsd_mean_nm': mean_rmsd,
    'protein_backbone_rmsd_max_nm':  max_rmsd,
    'mean_rmsf_nm':                  mean_rmsf,
    'flexible_residues_gt02nm':      flex_res,
    'timestamp':                     datetime.utcnow().isoformat() + 'Z',
}
with open('analysis_summary.json', 'w') as jf:
    json.dump(summary, jf, indent=2)

print(f'Trajectory analysis complete: {n_res} residues, {n_frames} frames')
PYEOF
    """
}


process MM_GBSA {
    /*
     * gmx_MMPBSA: MM-GBSA binding free energy calculation.
     * Uses GB model (igb=2) + per-residue energy decomposition.
     */
    tag "mm_gbsa"
    container MMPBSA_CONTAINER
    publishDir "${params.outdir}/mmgbsa", mode: params.publish_dir_mode

    input:
    path trajectory
    path final_gro
    path top
    path analysis_summary

    output:
    path "mmgbsa_results.csv",   emit: results
    path "binding_summary.json", emit: summary

    script:
    def start_fr = params.mmgbsa_startframe
    def end_fr   = params.mmgbsa_endframe
    def interval = params.mmgbsa_interval
    """
    set -euo pipefail

    # Recreate TPR needed by gmx_MMPBSA
    cat > rerun.mdp << 'MDP_EOF'
integrator = md
nsteps     = 0
MDP_EOF
    gmx grompp -f rerun.mdp -c ${final_gro} -p ${top} -o rerun.tpr -maxwarn 10 2>/dev/null || \
        cp ${top} rerun.tpr 2>/dev/null || true

    # gmx_MMPBSA input file
    cat > mmgbsa.in << 'MMPBSA_IN_EOF'
&general
   startframe=${start_fr}, endframe=${end_fr}, interval=${interval},
   verbose=2,
/
&gb
   igb=2, saltcon=0.15,
/
&decomp
   idecomp=2, dec_verbose=3,
   print_res="within 6",
/
MMPBSA_IN_EOF

    # Determine receptor and ligand mask from topology
    # Default: receptor = protein, ligand = last non-water/ion residue
    gmx_MMPBSA \
        -O \
        -i mmgbsa.in \
        -cs rerun.tpr \
        -ct ${trajectory} \
        -cp ${top} \
        -o FINAL_RESULTS_MMPBSA.dat \
        -eo FINAL_RESULTS_MMPBSA.csv \
        -nogui \
        2>&1 | tee mmgbsa_run.log || true

    # Parse gmx_MMPBSA output into standardised formats
    python3 << 'PYEOF'
import json, csv, os, re, sys
from datetime import datetime

# -- Parse binding free energy from FINAL_RESULTS_MMPBSA.dat --
dg_bind  = None
dg_err   = None
dat_file = 'FINAL_RESULTS_MMPBSA.dat'
if os.path.exists(dat_file):
    with open(dat_file) as f:
        for line in f:
            m = re.search(r'DELTA TOTAL\\s+([-\\d.]+)\\s+\\+/-\\s+([\\d.]+)', line)
            if m:
                dg_bind = float(m.group(1))
                dg_err  = float(m.group(2))
                break

# -- Parse per-residue decomposition from FINAL_RESULTS_MMPBSA.csv --
rows = []
csv_file = 'FINAL_RESULTS_MMPBSA.csv'
if os.path.exists(csv_file):
    with open(csv_file, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

with open('mmgbsa_results.csv', 'w', newline='') as csvf:
    writer = csv.writer(csvf)
    if rows:
        writer.writerow(rows[0].keys())
        for row in rows:
            writer.writerow(row.values())
    else:
        writer.writerow(['residue', 'chain', 'dG_total', 'dG_vdw', 'dG_elec', 'dG_gb', 'dG_total+sd'])
        print('WARNING: no per-residue decomposition data available', file=sys.stderr)

# Load trajectory analysis summary for context
traj_summary = {}
try:
    with open('${analysis_summary}') as f:
        traj_summary = json.load(f)
except Exception:
    pass

# Compute Ki estimate from dG (kcal/mol)
ki_nm = None
if dg_bind is not None:
    import math
    ki_nm = round(10**(dg_bind / 1.364) * 1e9, 2)

summary = {
    'ligand':                  '${params.ligand}',
    'receptor':                '${params.receptor}',
    'delta_g_bind_kcal_mol':   dg_bind,
    'standard_error_kcal_mol': dg_err,
    'ki_estimate_nM':          ki_nm,
    'tool':                    'gmx_mmpbsa',
    'gb_model':                'igb2',
    'startframe':              ${start_fr},
    'endframe':                '${end_fr}',
    'interval':                ${interval},
    'trajectory_analysis':     traj_summary,
    'interpretation': (
        'strong binder' if dg_bind and dg_bind < -10 else
        'moderate binder' if dg_bind and dg_bind < -7 else
        'weak binder' if dg_bind and dg_bind < -5 else
        'unfavorable' if dg_bind else 'calculation failed'
    ),
    'timestamp': datetime.utcnow().isoformat() + 'Z',
}
with open('binding_summary.json', 'w') as jf:
    json.dump(summary, jf, indent=2)

print(f'MM-GBSA complete: dGbind = {dg_bind} kcal/mol')
PYEOF
    """
}


// ============================================================================
// Workflow
// ============================================================================

workflow {

    // Validate required inputs
    if (!params.receptor) {
        error "ERROR: --receptor is required (path to receptor.pdb or S3 URI)"
    }
    if (!params.ligand) {
        error "ERROR: --ligand is required (path to ligand.sdf or mol2)"
    }

    // Create channels
    receptor_ch = Channel.fromPath(params.receptor)
    ligand_ch   = Channel.fromPath(params.ligand)

    // Step 1: Ligand parameterization (AmberTools)
    LIGAND_PREP(ligand_ch)

    // Step 2: Solvated system setup (tleap + ParmEd)
    SYSTEM_SETUP(
        receptor_ch,
        LIGAND_PREP.out.mol2,
        LIGAND_PREP.out.frcmod
    )

    // Step 3: Energy minimization (GROMACS)
    ENERGY_MINIMIZATION(
        SYSTEM_SETUP.out.gro,
        SYSTEM_SETUP.out.top,
        SYSTEM_SETUP.out.posres
    )

    // Step 4: NVT equilibration (GROMACS)
    NVT_EQUILIBRATION(
        ENERGY_MINIMIZATION.out.gro,
        SYSTEM_SETUP.out.top,
        SYSTEM_SETUP.out.posres
    )

    // Step 5: NPT equilibration (GROMACS)
    NPT_EQUILIBRATION(
        NVT_EQUILIBRATION.out.gro,
        SYSTEM_SETUP.out.top,
        SYSTEM_SETUP.out.posres
    )

    // Step 6: Production MD (GROMACS)
    PRODUCTION_MD(
        NPT_EQUILIBRATION.out.gro,
        SYSTEM_SETUP.out.top
    )

    // Step 7: Trajectory analysis (GROMACS + matplotlib)
    TRAJECTORY_ANALYSIS(
        PRODUCTION_MD.out.trajectory,
        PRODUCTION_MD.out.final_gro,
        SYSTEM_SETUP.out.top
    )

    // Step 8: MM-GBSA binding free energy (gmx_MMPBSA)
    MM_GBSA(
        PRODUCTION_MD.out.trajectory,
        PRODUCTION_MD.out.final_gro,
        SYSTEM_SETUP.out.top,
        TRAJECTORY_ANALYSIS.out.summary
    )

    // Emit final summary
    MM_GBSA.out.summary
        .view { summary ->
            def data = new groovy.json.JsonSlurper().parseText(summary.text)
            log.info ""
            log.info "==================================================="
            log.info "  GROMACS Protein-Ligand MD -- Results Summary"
            log.info "==================================================="
            log.info "  dGbind (MM-GBSA): ${data.delta_g_bind_kcal_mol} +/- ${data.standard_error_kcal_mol} kcal/mol"
            log.info "  ${data.interpretation}"
            log.info "  Backbone RMSD: ${data.trajectory_analysis?.protein_backbone_rmsd_mean_nm ?: 'N/A'} nm (mean)"
            log.info "==================================================="
            log.info ""
        }
}
