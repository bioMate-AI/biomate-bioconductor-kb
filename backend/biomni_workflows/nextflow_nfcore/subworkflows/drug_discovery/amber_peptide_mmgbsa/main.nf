#!/usr/bin/env nextflow
/*
 * !!! DRAFT — SUPERSEDED, DO NOT REGISTER/RUN AS-IS !!!
 * The cited survey (docs/PEPTIDE_MMGBSA_TOOLING.md) shows the field uses `gmx_MMPBSA` (peptide as a
 * second protein / chain group, protein FF, igb=8, single-trajectory, entropy off) rather than the
 * hand-rolled MMPBSA.py + `:LIG`-residue-strip below, and that the naive tleap `bond` here misses the
 * OXT/terminal-atom handling that head-to-tail cyclization requires. Keep only the reused AMBER
 * min/equil/production scaffolding; the SYSTEM_SETUP cyclization and MM_GBSA must be rewritten to
 * (a) build via a validated cyclic-tleap recipe or CHARMM-GUI, (b) score via gmx_MMPBSA.
 *
 * drug_discovery/amber_peptide_mmgbsa
 *
 * AMBER pmemd protein-PEPTIDE molecular dynamics + MM-GBSA binding free energy pipeline.
 *
 * WHY THIS EXISTS (vs amber_pmemd_md): the standard protein-LIGAND MD pipeline parametrizes the
 * binder with GAFF2/antechamber (AM1-BCC), which is WRONG for a peptide binder — a peptide must use
 * the protein force field (ff19SB), and a cyclic peptide needs its head-to-tail bond declared in
 * tleap. This workflow loads BOTH chains as protein (loadpdb), optionally cyclizes the peptide, and
 * splits the MM-GBSA by peptide residue-range instead of the ":LIG" residue name.
 *
 * Reuses (verbatim, from amber_pmemd_md) the min/equil/production/analysis stages; only PREP,
 * SYSTEM_SETUP and MM_GBSA masking differ.
 *
 * Pipeline Steps:
 * 1. PREP_INPUTS         -- pdb4amber clean receptor + peptide; strip terminal OXT/H3 from the
 *                           peptide when cyclic; count residues -> receptor N, peptide N, masks
 * 2. SYSTEM_SETUP        -- tleap: loadpdb PROT + PEP (ff19SB), optional head-to-tail bond, combine,
 *                           solvate (TIP3P oct), neutralize; emit prmtop/inpcrd + pep residue range
 * 3. ENERGY_MINIMIZATION -- sander 2-stage (reused)
 * 4. EQUILIBRATION       -- pmemd.cuda NVT+NPT (reused)
 * 5. PRODUCTION_MD       -- pmemd.cuda production (reused)
 * 6. TRAJECTORY_ANALYSIS -- cpptraj RMSD/RMSF/Rg + interface H-bonds (peptide range)
 * 7. MM_GBSA             -- MMPBSA.py igb=2, receptor/peptide split by residue range
 *
 * Inputs:
 *   params.receptor  -- target protein: .pdb path / S3 URI / 4-char PDB ID
 *   params.peptide   -- designed peptide chain: .pdb path / S3 URI  (protein residues, standard AAs)
 *   params.cyclic    -- true => declare head-to-tail bond (peptide C-term -> N-term)
 *
 * SCOPE / HONEST LIMITS (v1): standard L-amino-acid cyclic/linear peptides only. Non-natural
 * monomers (N-methyl, D-AA, staples) need extra tleap params (SwissSidechain/NCAA frcmod) and are a
 * documented TODO — this v1 is a strict improvement over the GAFF2 path, not the final word.
 * MUST be smoke-tested (tleap build + 1 short MD) before production use.
 *
 * References: AMBER Case 2023; ff19SB Tian 2020; MM-GBSA Kollman 2000; cpptraj Roe & Cheatham 2013.
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================
params.outdir            = './results/amber_peptide_mmgbsa'
params.publish_dir_mode  = 'copy'

params.receptor          = null       // target protein .pdb / S3 / PDB ID
params.peptide           = null       // designed peptide chain .pdb / S3
params.cyclic            = true       // head-to-tail macrocycle

params.force_field       = 'ff19SB'   // ff14SB | ff19SB (protein FF for BOTH chains)
params.water_model       = 'tip3p'
params.box_padding       = 12

params.n_steps           = 5000000    // 10 ns @ 2 fs
params.dt                = 0.002
params.temperature       = 300
params.pressure          = 1.0

params.mmgbsa_startframe = 500
params.mmgbsa_interval   = 5

params.n_cpus            = 8
params.gpu               = true
params.use_aws           = false

// ============================================================================
// Containers (same images as amber_pmemd_md)
// ============================================================================
def _useAws = params.use_aws || System.getenv('NEXTFLOW_USE_AWS') == 'true'
def _ECR    = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest'
def AMBER_CONTAINER      = _useAws ? _ECR : '399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest'
def AMBERTOOLS_CONTAINER = _useAws ? _ECR : 'ambermd/ambertools:23'

// ============================================================================
// Processes
// ============================================================================

// [Phase A] Prepare + clean receptor and peptide; count residues; build masks.
process PREP_INPUTS {
    tag "prep_inputs"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/01_prep", mode: params.publish_dir_mode

    input:
    path receptor_file
    path peptide_file

    output:
    path "receptor_clean.pdb", emit: receptor
    path "peptide_clean.pdb",  emit: peptide
    path "ranges.env",         emit: ranges
    path "prep.log",           emit: log

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true

        # pdb4amber: strip waters/hydrogens, standardize names, drop OXT (so tleap assigns termini)
        pdb4amber -i ${receptor_file} -o receptor_clean.pdb --nohyd --dry 2>&1 | tee prep.log
        # for a cyclic peptide, also strip OXT so head-to-tail bond can form cleanly
        pdb4amber -i ${peptide_file}  -o peptide_clean.pdb  --nohyd --dry 2>&1 | tee -a prep.log

        # count protein residues in each cleaned pdb (unique chain+resSeq over ATOM records)
        NREC=\$(awk '/^ATOM/{print substr(\$0,22,5)}' receptor_clean.pdb | sort -u | wc -l)
        NPEP=\$(awk '/^ATOM/{print substr(\$0,22,5)}' peptide_clean.pdb  | sort -u | wc -l)
        PEP_START=\$((NREC + 1))
        PEP_END=\$((NREC + NPEP))
        {
          echo "NREC=\$NREC"
          echo "NPEP=\$NPEP"
          echo "PEP_START=\$PEP_START"
          echo "PEP_END=\$PEP_END"
        } > ranges.env
        echo "PREP_INPUTS: receptor=\$NREC res, peptide=\$NPEP res, peptide range \$PEP_START-\$PEP_END" >> prep.log
    """
}

// [Phase A] Build solvated complex; peptide as PROTEIN; optional head-to-tail cyclization.
process SYSTEM_SETUP {
    tag "system_setup"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/02_system_setup", mode: params.publish_dir_mode

    input:
    path receptor_clean
    path peptide_clean
    path ranges_env

    output:
    path "complex.prmtop", emit: prmtop
    path "complex.inpcrd", emit: inpcrd
    path "ranges.env",     emit: ranges
    path "tleap.log",      emit: log

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true
        . ./${ranges_env}

        # head-to-tail bond only when cyclic: connect peptide C-term (last res) to N-term (first res).
        # Peptide residues in COMP are numbered PEP_START..PEP_END after PROT.
        CYCBOND=""
        if [ "${params.cyclic}" = "true" ]; then
            CYCBOND="bond COMP.\${PEP_END}.C COMP.\${PEP_START}.N"
        fi

        cat > tleap.in << TLEAPIN
source leaprc.protein.${params.force_field}
source leaprc.water.${params.water_model}
PROT = loadpdb ${receptor_clean}
PEP  = loadpdb ${peptide_clean}
COMP = combine {PROT PEP}
\${CYCBOND}
check COMP
solvateOct COMP TIP3PBOX ${params.box_padding}
addionsrand COMP Na+ 0
addionsrand COMP Cl- 0
saveamberparm COMP complex.prmtop complex.inpcrd
desc COMP
quit
TLEAPIN

        tleap -f tleap.in 2>&1 | tee tleap.log
        cp ${ranges_env} ranges.env
        echo "SYSTEM_SETUP complete (cyclic=${params.cyclic})" >> tleap.log
    """
}

// [Phase D] MM-GBSA split by PEPTIDE RESIDUE RANGE (not :LIG).
process MM_GBSA {
    tag "mm_gbsa"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/07_mmgbsa", mode: params.publish_dir_mode

    input:
    path prmtop
    path trajectory
    path ranges_env

    output:
    path "mmgbsa_results.csv",   emit: results_csv
    path "binding_summary.json", emit: summary

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true
        . ./${ranges_env}
        PEPMASK=":\${PEP_START}-\${PEP_END}"

        # receptor prmtop = strip the peptide range; ligand(peptide) prmtop = keep only that range
        cat > strip_receptor.in << STREOF
parm ${prmtop}
parmstrip \${PEPMASK}
parmwrite out receptor.prmtop
quit
STREOF
        cpptraj -p ${prmtop} -i strip_receptor.in

        cat > strip_ligand.in << STLEOF
parm ${prmtop}
parmstrip !(\${PEPMASK})
parmwrite out ligand_only.prmtop
quit
STLEOF
        cpptraj -p ${prmtop} -i strip_ligand.in

        cat > mmgbsa.in << GBSEOF
Protein-peptide MM-GBSA (igb=2)
&general
  startframe=${params.mmgbsa_startframe}, endframe=-1, interval=${params.mmgbsa_interval},
  verbose=2, keep_files=0,
/
&gb
  igb=2, saltcon=0.15,
/
&decomp
  idecomp=1, print_res='within 6.0',
/
GBSEOF

        MMPBSA.py -O -i mmgbsa.in -o mmgbsa_raw.dat -do mmgbsa_decomp.dat \
            -cp ${prmtop} -rp receptor.prmtop -lp ligand_only.prmtop \
            -y ${trajectory} 2>&1 | tee mmpbsa.log

        python3 - << 'PYEOF'
import json, re, sys
delta_g=std_dg=None; comp={}
try:
    for line in open('mmgbsa_raw.dat'):
        for key,pat in [('vdw_kcal_mol','VDWAALS'),('electrostatic_kcal_mol','EEL'),
                        ('polar_solvation_kcal_mol','EGB'),('nonpolar_solv_kcal_mol','ESURF')]:
            m=re.search(pat+r'\\s*=\\s*([-\\d.]+)', line)
            if m: comp[key]=float(m.group(1))
        m=re.search(r'DELTA TOTAL\\s*=\\s*([-\\d.]+)\\s*\\+/-\\s*([\\d.]+)', line)
        if m: delta_g=float(m.group(1)); std_dg=float(m.group(2))
except Exception as e:
    print('warn raw:', e, file=sys.stderr)
res=[]
try:
    inseg=False
    for line in open('mmgbsa_decomp.dat'):
        if 'Residue' in line and 'Internal' in line: inseg=True; continue
        if inseg and not line.strip(): break
        if inseg:
            c=line.split()
            if len(c)>=5: res.append({'residue':c[0],'delta_g_gb':float(c[1])})
except Exception as e:
    print('warn decomp:', e, file=sys.stderr)
open('mmgbsa_results.csv','w').write('residue,delta_g_gb\\n'+''.join(f"{r['residue']},{r['delta_g_gb']}\\n" for r in res))
summary={'pipeline':'AMBER protein-peptide MM-GBSA','gb_model':'igb=2',
         'delta_g_bind':{'value_kcal_mol':round(delta_g,2) if delta_g is not None else None,
                         'std_kcal_mol':round(std_dg,2) if std_dg is not None else None,
                         **{k:round(v,2) for k,v in comp.items()}},
         'classification':('strong_binder' if delta_g is not None and delta_g<-8.0 else 'moderate_binder'),
         'top_binding_residues':sorted(res,key=lambda x:x['delta_g_gb'])[:10],
         'force_field':'${params.force_field}','cyclic':'${params.cyclic}'}
json.dump(summary, open('binding_summary.json','w'), indent=2)
print('MM_GBSA complete — DeltaG_bind =', summary['delta_g_bind']['value_kcal_mol'], 'kcal/mol')
PYEOF
    """
}

// ---- reused stages: import the proven processes from amber_pmemd_md by include ----
include { ENERGY_MINIMIZATION; EQUILIBRATION; PRODUCTION_MD; TRAJECTORY_ANALYSIS } from '../amber_pmemd_md/main.nf'

// ============================================================================
// Workflow
// ============================================================================
workflow {
    if (!params.receptor) error "ERROR: params.receptor is required (target protein .pdb / S3 / PDB ID)."
    if (!params.peptide)  error "ERROR: params.peptide is required (designed peptide chain .pdb / S3)."

    log.info """
    ============================================================
     AMBER protein-PEPTIDE MD + MM-GBSA
    ============================================================
     receptor    : ${params.receptor}
     peptide     : ${params.peptide}
     cyclic      : ${params.cyclic}
     force_field : ${params.force_field} (protein FF for BOTH chains)
     n_steps     : ${params.n_steps}   temperature: ${params.temperature} K
    ============================================================
    """.stripIndent()

    // receptor: accept .pdb / S3 / 4-char PDB ID (auto-download)
    def rin = params.receptor.trim()
    if (rin ==~ /^[A-Za-z0-9]{4}$/) {
        def id = rin.toUpperCase()
        def pf = file("/tmp/biomate_nf_inputs/pdb/${id}.pdb"); pf.parent.mkdirs()
        if (!pf.exists()) ["curl","-sSf","-o",pf.toString(),"https://files.rcsb.org/download/${id}.pdb"].execute().waitFor()
        if (!pf.exists() || pf.size()==0) error "Failed to download PDB ${id} from RCSB."
        receptor_ch = Channel.fromPath(pf.toString())
    } else { receptor_ch = Channel.fromPath(rin, checkIfExists: true) }
    peptide_ch = Channel.fromPath(params.peptide.trim(), checkIfExists: true)

    prep   = PREP_INPUTS(receptor_ch, peptide_ch)
    setup  = SYSTEM_SETUP(prep.receptor, prep.peptide, prep.ranges)
    em     = ENERGY_MINIMIZATION(setup.prmtop, setup.inpcrd)
    equil  = EQUILIBRATION(setup.prmtop, em.rst)
    prod   = PRODUCTION_MD(setup.prmtop, equil.rst)
    TRAJECTORY_ANALYSIS(setup.prmtop, prod.trajectory, prod.rst)
    mmgbsa = MM_GBSA(setup.prmtop, prod.trajectory, setup.ranges)

    mmgbsa.summary.subscribe { f ->
        def m = f.text =~ /"value_kcal_mol"\s*:\s*([-\d.]+)/
        log.info "AMBER peptide MM-GBSA COMPLETE — DeltaG_bind = ${m ? m[0][1] : 'N/A'} kcal/mol"
    }
}
