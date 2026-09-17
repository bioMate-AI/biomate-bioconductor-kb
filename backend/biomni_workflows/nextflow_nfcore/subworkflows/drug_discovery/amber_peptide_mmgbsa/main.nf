#!/usr/bin/env nextflow
/*
 * drug_discovery/amber_peptide_mmgbsa
 *
 * Protein–PEPTIDE MD + MM-GBSA binding free energy — the peptide-appropriate counterpart to
 * amber_pmemd_md (which is small-molecule-ligand-only via GAFF2/antechamber, wrong for a peptide).
 *
 * BUILD IS EXTERNAL (see docs/PEPTIDE_MMGBSA_TOOLING.md): three cheap smoke tests confirmed that
 * automated cyclic-peptide topology building is not achievable with available headless tooling
 * (tleap => N3-C charged-terminal typing; psfgen => only VMD 1.9.3 on conda, patch fails). The field
 * uses CHARMM-GUI. So THIS workflow consumes a PRE-BUILT, solvated, (optionally cyclized) complex
 * topology from CHARMM-GUI's AMBER export (prmtop + inpcrd), where the peptide is a proper protein
 * chain — then automates the well-defined downstream: MD sampling + MM-GBSA with the receptor/ligand
 * split by the PEPTIDE RESIDUE RANGE (both under the protein FF; NO GAFF2).
 *
 * Pipeline (reuses amber_pmemd_md min/equil/production/analysis verbatim):
 *   3. ENERGY_MINIMIZATION  4. EQUILIBRATION  5. PRODUCTION_MD  6. TRAJECTORY_ANALYSIS
 *   7. MM_GBSA  -- MMPBSA.py igb=8, receptor/ligand topologies split by peptide residue range
 *
 * Inputs:
 *   params.complex_prmtop  -- CHARMM-GUI AMBER export: solvated complex topology (.prmtop) [required]
 *   params.complex_inpcrd  -- matching coordinates (.inpcrd / .rst7)                        [required]
 *   params.pep_start       -- first peptide residue number in the complex                   [required]
 *   params.pep_end         -- last  peptide residue number in the complex                   [required]
 *
 * STATUS: v1 downstream — reviewed, but NOT yet smoke-tested end-to-end (needs one real CHARMM-GUI
 * bundle). Do not treat ΔG output as validated until a bundle-based smoke run passes.
 *
 * Refs: gmx_MMPBSA/MMPBSA.py (Valdés-Tresanco 2021; Miller 2012); ff19SB/CHARMM36m; Kollman 2000.
 */

nextflow.enable.dsl = 2

params.outdir            = './results/amber_peptide_mmgbsa'
params.publish_dir_mode  = 'copy'

params.complex_prmtop    = null      // CHARMM-GUI AMBER export (solvated complex topology)
params.complex_inpcrd    = null      // matching coordinates
params.pep_start         = null      // peptide first residue number (in the complex)
params.pep_end           = null      // peptide last residue number

params.force_field       = 'ff19SB'  // recorded for provenance (topology already carries params)
params.water_model       = 'tip3p'
params.n_steps           = 5000000   // 10 ns production @ 2 fs
params.dt                = 0.002
params.temperature       = 300
params.pressure          = 1.0
params.mmgbsa_startframe = 500
params.mmgbsa_interval   = 5
params.n_cpus            = 8
params.gpu               = true
params.use_aws           = false

def _useAws = params.use_aws || System.getenv('NEXTFLOW_USE_AWS') == 'true'
def _ECR    = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest'
def AMBERTOOLS_CONTAINER = _useAws ? _ECR : 'ambermd/ambertools:23'

// reuse the proven AMBER MD stages (topology-agnostic to ligand type)
include { ENERGY_MINIMIZATION; EQUILIBRATION; PRODUCTION_MD; TRAJECTORY_ANALYSIS } from '../amber_pmemd_md/main.nf'

// MM-GBSA split by PEPTIDE RESIDUE RANGE (peptide is a protein chain, not ":LIG")
process MM_GBSA {
    tag "mm_gbsa_peptide"
    container AMBERTOOLS_CONTAINER
    publishDir "${params.outdir}/07_mmgbsa", mode: params.publish_dir_mode

    input:
    path prmtop
    path trajectory

    output:
    path "mmgbsa_results.csv",   emit: results_csv
    path "binding_summary.json", emit: summary

    script:
    """
        set -euo pipefail
        source /opt/amber24/amber.sh || true
        PEPMASK=":${params.pep_start}-${params.pep_end}"

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
Protein-peptide MM-GBSA (igb=8, GB-Neck2)
&general
  startframe=${params.mmgbsa_startframe}, endframe=-1, interval=${params.mmgbsa_interval},
  verbose=2, keep_files=0,
/
&gb
  igb=8, saltcon=0.15,
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
        for key,pat in [('vdw','VDWAALS'),('eel','EEL'),('egb','EGB'),('esurf','ESURF')]:
            m=re.search(pat+r'\\s*=\\s*([-\\d.]+)', line)
            if m: comp[key]=float(m.group(1))
        m=re.search(r'DELTA TOTAL\\s*=\\s*([-\\d.]+)\\s*\\+/-\\s*([\\d.]+)', line)
        if m: delta_g=float(m.group(1)); std_dg=float(m.group(2))
except Exception as e:
    print('warn raw:', e, file=sys.stderr)
res=[]
try:
    seg=False
    for line in open('mmgbsa_decomp.dat'):
        if 'Residue' in line and 'Internal' in line: seg=True; continue
        if seg and not line.strip(): break
        if seg:
            c=line.split()
            if len(c)>=2:
                try: res.append({'residue':c[0],'delta_g_gb':float(c[1])})
                except: pass
except Exception as e:
    print('warn decomp:', e, file=sys.stderr)
open('mmgbsa_results.csv','w').write('residue,delta_g_gb\\n'+''.join(f"{r['residue']},{r['delta_g_gb']}\\n" for r in res))
summary={'pipeline':'AMBER protein-peptide MM-GBSA','gb_model':'igb=8 (GB-Neck2)',
         'peptide_residue_range':[${params.pep_start}, ${params.pep_end}],
         'delta_g_bind':{'value_kcal_mol':round(delta_g,2) if delta_g is not None else None,
                         'std_kcal_mol':round(std_dg,2) if std_dg is not None else None, **comp},
         'note':'MM-GBSA is a RELATIVE ranking oracle for peptides (Sun PCCP 2019, rp~0.73-0.75), '
                'not an absolute affinity; entropy omitted. Confirm finalists with FEP (FEP+/ATM).',
         'top_binding_residues':sorted(res,key=lambda x:x['delta_g_gb'])[:10]}
json.dump(summary, open('binding_summary.json','w'), indent=2)
print('MM_GBSA(peptide) complete — DeltaG_bind =', summary['delta_g_bind']['value_kcal_mol'], 'kcal/mol (RANKING only)')
PYEOF
    """
}

workflow {
    for (p in ['complex_prmtop','complex_inpcrd','pep_start','pep_end']) {
        if (params[p] == null) error "ERROR: params.${p} is required. This workflow consumes a CHARMM-GUI-built complex (see docs/PEPTIDE_MMGBSA_TOOLING.md)."
    }
    log.info """
    ============================================================
     AMBER protein-PEPTIDE MD + MM-GBSA  (build = external CHARMM-GUI)
    ============================================================
     complex_prmtop : ${params.complex_prmtop}
     peptide range  : ${params.pep_start}-${params.pep_end}
     n_steps        : ${params.n_steps}   temperature: ${params.temperature} K
     MM-GBSA        : igb=8 (GB-Neck2), single-traj, entropy off  [RANKING oracle]
    ============================================================
    """.stripIndent()

    prmtop_ch = Channel.fromPath(params.complex_prmtop.trim(), checkIfExists: true)
    inpcrd_ch = Channel.fromPath(params.complex_inpcrd.trim(), checkIfExists: true)

    em    = ENERGY_MINIMIZATION(prmtop_ch, inpcrd_ch)
    equil = EQUILIBRATION(prmtop_ch, em.rst)
    prod  = PRODUCTION_MD(prmtop_ch, equil.rst)
    TRAJECTORY_ANALYSIS(prmtop_ch, prod.trajectory, prod.rst)
    mmg   = MM_GBSA(prmtop_ch, prod.trajectory)

    mmg.summary.subscribe { f ->
        def m = f.text =~ /"value_kcal_mol"\s*:\s*([-\d.]+)/
        log.info "AMBER peptide MM-GBSA COMPLETE — DeltaG_bind = ${m ? m[0][1] : 'N/A'} kcal/mol (RANKING only; confirm finalists with FEP)"
    }
}
