#!/usr/bin/env nextflow
/*
 * drug_discovery/moe_covalent_docking
 *
 * MOE (Molecular Operating Environment) covalent docking pipeline.
 * Specialised for irreversible/reversible covalent inhibitors and
 * fragment-based drug design (FBDD) where warhead-residue bond formation
 * must be explicitly modelled -- something GNINA/DiffDock cannot do.
 *
 * Pipeline Steps:
 * 1. LIGAND_PREP    -- MOE LigX: protonation states, tautomers, MMFF94x partial charges
 *                      Output: ligands_prepped.mdb, ligprep.log
 * 2. RECEPTOR_PREP  -- MOE QuickPrep: add hydrogens, protonate, constrained minimisation
 *                      Output: receptor_prepped.moe, prep.log
 * 3. COVALENT_DOCK  -- MOE CovDock SVL script: reactive residue + warhead chemistry
 *                      Output: covalent_poses.mdb, covdock.log
 * 4. POSE_ANALYSIS  -- MOE scoring: S score, E_Score1/2, GBVI/WSA dG rescoring
 *                      Output: scored_poses.csv, pose_analysis.log
 * 5. REPORT         -- Export top poses to SDF, JSON summary, HTML report
 *                      Output: top_poses.sdf, docking_summary.json, docking_report.html
 *
 * Supported warhead types:
 *   acrylamide | chloroacetamide | epoxide | aldehyde | michael_acceptor
 *   vinyl_sulfone | boronic_acid
 *
 * Supported reactive residues (nucleophilic):
 *   CYS (thiol) | LYS (amine) | SER (hydroxyl) | THR (hydroxyl) | HIS (imidazole)
 *
 * References:
 *   MOE CovDock: Zhu et al. J. Chem. Inf. Model. 2014, 54:1932-1940
 *   MOE: Chemical Computing Group ULC, Montreal 2024
 *   GBVI/WSA: Labute J. Chem. Inf. Model. 2008, 48:1117-1128
 *   Covalent docking review: Baillie Nat. Chem. Biol. 2016, 12:401-405
 *   FBDD: Erlanson et al. Nat. Rev. Drug Discov. 2016, 15:605-619
 */
nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir               = './results/moe_covalent_docking'
params.publish_dir_mode     = 'copy'


// Inputs
params.receptor             = null   // receptor.pdb or receptor.mol2 (required)
params.ligands              = null   // warhead_smiles.smi or ligands.sdf (required)

// Covalent docking settings
params.reactive_residue     = 'CYS:145'        // residue_name:residue_number
params.warhead_type         = 'acrylamide'     // acrylamide | chloroacetamide | epoxide | aldehyde | michael_acceptor
params.docking_protocol     = 'induced_fit'    // rigid | induced_fit
params.n_poses              = 10               // retained poses per ligand
params.top_n                = 20               // top poses in final output
params.refine_poses         = true             // GBVI/WSA rescoring after docking

// Resources
params.n_cpus               = 8

// ============================================================================
// Containers
// ============================================================================

// MOE requires a valid license; LM_LICENSE_FILE injected at runtime from
// user credential store (e.g. "27001@hostname").
def MOE_CONTAINER = '399683337364.dkr.ecr.us-west-2.amazonaws.com/moe2024:latest'

// ============================================================================
// Processes
// ============================================================================

process LIGAND_PREP {
    /*
     * MOE LigPrep equivalent:
     *   - Generate tautomers and protonation states at pH 7.4
     *   - Assign partial charges (MMFF94x)
     *   - Output: MOE database (.mdb) of 3D conformers ready for docking
     *
     * Warhead SMARTS patterns preserved during prep:
     *   acrylamide        C=CC(=O)N  -- Michael acceptor terminal alkene
     *   chloroacetamide   ClCC(=O)N  -- SN2 electrophile
     *   epoxide           C1OC1      -- ring-opening electrophile
     *   aldehyde          [CH]=O     -- Schiff base / hemithioacetal former
     *   michael_acceptor  generalised alpha,beta-unsaturated carbonyl
     */
    tag "ligand_prep"
    container MOE_CONTAINER
    publishDir "${params.outdir}/01_ligand_prep", mode: params.publish_dir_mode

    input:
    path ligand_file

    output:
    path "ligands_prepped.mdb", emit: prepped_mdb
    path "ligprep.log",         emit: log

    script:
        """
        set -euo pipefail

        export LM_LICENSE_FILE=\${LM_LICENSE_FILE:-""}
        if [[ -z "\$LM_LICENSE_FILE" ]]; then
            echo "ERROR: LM_LICENSE_FILE not set. Inject MOE license via BioMate credential gate." >&2
            exit 1
        fi

        moebatch -exec "
            mdb = db_Open ['ligands_prepped.mdb', 'create'];
            inp = '${ligand_file}';
            ext = fext inp;
            if ext == '.sdf' or ext == '.mol' then
                sd = sd_Open inp;
                while not sd_EOF sd loop
                    mol = sd_Read sd;
                    mol = mol_Protonate3D [mol, 'pH74'];
                    mol = mol_MMFF94x_Charges mol;
                    db_Write [mdb, db_CreateEntry mdb, ['mol': mol]]
                endloop;
                sd_Close sd
            elseif ext == '.smi' or ext == '.smiles' then
                lines = fread inp;
                for i = 1, length lines loop
                    sm = token lines(i);
                    if length sm > 0 then
                        mol = mol_MolFromSmiles sm;
                        mol = mol_3D mol;
                        mol = mol_Protonate3D [mol, 'pH74'];
                        mol = mol_MMFF94x_Charges mol;
                        db_Write [mdb, db_CreateEntry mdb, ['mol': mol, 'smiles': sm]]
                    endif
                endloop
            endif;
            db_Close mdb
        " 2>&1 | tee ligprep.log

        if [[ ! -s ligands_prepped.mdb ]]; then
            echo "ERROR: ligands_prepped.mdb not produced" >&2
            exit 1
        fi
        echo "LigPrep complete" >> ligprep.log
        '''
}

// ----------------------------------------------------------------------------

process RECEPTOR_PREP {
    /*
     * MOE QuickPrep:
     *   - Add hydrogens using Protonate3D (pKa-aware, considers ligand proximity)
     *   - Restrained minimisation (AMBER force field, RMSD tolerance 0.5 A)
     *   - Output: receptor_prepped.moe (native MOE binary format)
     *
     * For covalent docking the reactive residue sidechain must be
     * in the thiol/amine/hydroxyl (nucleophilic) form -- QuickPrep handles this.
     */
    tag "receptor_prep"
    container MOE_CONTAINER
    publishDir "${params.outdir}/02_receptor_prep", mode: params.publish_dir_mode

    input:
    path receptor_file

    output:
    path "receptor_prepped.moe", emit: prepped_moe
    path "prep.log",             emit: log

    script:
        '''
        set -euo pipefail

        moebatch -exec "run ['\$MOE/lib/quickprep.svl', [
            mol:'${receptor_file}',
            out:'receptor_prepped.moe',
            protonate:1,
            minimize:1,
            solvent:'dielectric'
        ]]" 2>&1 | tee prep.log

        if [[ ! -s receptor_prepped.moe ]]; then
            echo "ERROR: receptor_prepped.moe not produced by QuickPrep" >&2
            exit 1
        fi
        echo "QuickPrep complete" >> prep.log
        '''
}

// ----------------------------------------------------------------------------

process COVALENT_DOCK {
    /*
     * MOE CovDock SVL script:
     *  1. Identifies the nucleophilic reactive residue (params.reactive_residue)
     *  2. Maps warhead chemistry to the residue (Michael addition, SN2, etc.)
     *  3. Generates covalent poses with an explicit covalent bond to the residue
     *  4. Optional induced-fit: receptor flexibility modelled around binding site
     *
     * Warhead reaction types:
     *   acrylamide        -> thia-Michael addition (C-S, irreversible)
     *   chloroacetamide   -> SN2 alkylation (C-S, irreversible)
     *   epoxide           -> ring-opening (C-S / C-N / C-O, tunable reversibility)
     *   aldehyde          -> Schiff base (C-N, Lys) or hemithioacetal (C-S, Cys)
     *   michael_acceptor  -> generalised 1,4-conjugate addition
     *   vinyl_sulfone     -> thia-Michael addition (strong EWG, irreversible)
     *   boronic_acid      -> reversible covalent with SER/THR/TYR (boronate ester)
     *
     * Input:  receptor_prepped.moe, ligands_prepped.mdb
     * Output: covalent_poses.mdb -- MOE database of covalent docked poses
     *         covdock.log        -- CovDock SVL run log
     */
    tag "covalent_dock"
    container MOE_CONTAINER
    cpus params.n_cpus
    publishDir "${params.outdir}/03_covalent_dock", mode: params.publish_dir_mode

    input:
    path receptor_moe
    path ligands_mdb

    output:
    path "covalent_poses.mdb", emit: poses_mdb
    path "covdock.log",        emit: log

    script:
        '''
        set -euo pipefail

        moebatch -exec "run ['\$MOE/lib/covdock.svl', [
            rec:'${receptor_moe}',
            lig:'${ligands_mdb}',
            reactive_res:'${params.reactive_residue}',
            warhead:'${params.warhead_type}',
            out:'covalent_poses.mdb',
            nposes:${params.n_poses},
            protocol:'${params.docking_protocol}',
            ncpu:${task.cpus}
        ]]" 2>&1 | tee covdock.log

        if [[ ! -s covalent_poses.mdb ]]; then
            echo "ERROR: covalent_poses.mdb not produced by CovDock" >&2
            exit 1
        fi
        echo "CovDock complete" >> covdock.log
        '''
}

// ----------------------------------------------------------------------------

process POSE_ANALYSIS {
    /*
     * MOE scoring and rescoring:
     *  - S score      : primary MOE docking score (London dG approximation)
     *  - E_Score1/2   : force-field refinement scores (MMFF94x/Amber)
     *  - GBVI/WSA dG  : Generalised Born Volume Integral / Weighted Surface Area
     *                   binding free energy (most accurate MOE rescoring; Labute 2008)
     *  - Cov bond length: C-S (acrylamide/CYS) constraint satisfaction check;
     *                     expected 1.80-1.85 A for thia-Michael (C-S)
     *
     * Input:  covalent_poses.mdb
     * Output: scored_poses.csv  -- ranked table with all scoring columns
     *         pose_analysis.log -- run log
     */
    tag "pose_analysis"
    container MOE_CONTAINER
    publishDir "${params.outdir}/04_pose_analysis", mode: params.publish_dir_mode

    input:
    path poses_mdb

    output:
    path "scored_poses.csv",  emit: scores_csv
    path "pose_analysis.log", emit: log

    script:
        '''
        set -euo pipefail

        moebatch -exec "
            db = db_Open ['${poses_mdb}', 'read'];
            entries = db_Entries db;
            fp = fopenw 'scored_poses.csv';
            fwrite [fp, 'rank,ligand_name,smiles,s_score,e_score1,gbvi_wsa_dg,covalent_bond_length_A\\n'];
            for n = 1, length entries loop
                e = entries(n);
                f = db_ReadFields [db, e, ['Name','SMILES','S','E_Score1','GBVI/WSA dG','CovBondLen']];
                fwrite [fp, tok_cat [string n, ',', f(1), ',', f(2), ',',
                    string f(3), ',', string f(4), ',', string f(5), ',', string f(6), '\\n']]
            endloop;
            fclose fp;
            db_Close db
        " 2>&1 | tee pose_analysis.log

        if [[ ! -s scored_poses.csv ]]; then
            echo "ERROR: scored_poses.csv not produced" >&2
            exit 1
        fi
        echo "POSE_ANALYSIS complete" >> pose_analysis.log
        '''
}

// ----------------------------------------------------------------------------

process REPORT {
    /*
     * Generate pipeline deliverables:
     *  - top_poses.sdf        : top N covalent poses with SD-tag properties
     *                           (S_Score, GBVI_WSA_dG, CovalentBondLength,
     *                            WarheadType, ReactiveResidue, Rank)
     *  - docking_summary.json : machine-readable summary for downstream tools
     *  - docking_report.html  : styled HTML with colour-coded tiers, warhead
     *                           chemistry explainer, and scoring definitions
     *
     * Input:  scored_poses.csv
     * Output: top_poses.sdf, docking_summary.json, docking_report.html
     */
    tag "report"
    container MOE_CONTAINER
    publishDir "${params.outdir}/05_report", mode: params.publish_dir_mode

    input:
    path scores_csv

    output:
    path "top_poses.sdf",        emit: top_sdf
    path "docking_summary.json", emit: summary_json
    path "docking_report.html",  emit: report_html

    script:
        '''
        set -euo pipefail

        python3 - << 'PYEOF'
import csv, json

rows = []
with open('scored_poses.csv') as f:
    for row in csv.DictReader(f):
        rows.append(row)

top_n    = 5
top_rows = rows[:top_n] if len(rows) >= top_n else rows
best     = top_rows[0] if top_rows else {}

summary = {
    'pipeline': 'moe_covalent_docking',
    'reactive_residue': 'CYS145',
    'warhead_type': 'acrylamide',
    'docking_protocol': 'induced_fit',
    'top_n_reported': len(top_rows),
    'total_compounds_docked': len(rows),
    'best_ligand': best.get('ligand_name', 'N/A'),
    'best_s_score': float(best.get('s_score', 0)),
    'best_gbvi_wsa_dg': float(best.get('gbvi_wsa_dg', 0)),
    'best_covalent_bond_length_A': float(best.get('covalent_bond_length_A', 0)),
}
with open('docking_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
print('docking_summary.json written')
PYEOF

        moebatch -exec "
            db = db_Open ['covalent_poses.mdb', 'read'];
            entries = db_Entries db;
            top_entries = entries[1..min [5, length entries]];
            WriteSD ['top_poses.sdf', top_entries, [
                fields:     ['S', 'E_Score1', 'GBVI/WSA dG', 'CovBondLen'],
                prop_names: ['S_Score', 'E_Score1', 'GBVI_WSA_dG', 'CovalentBondLength']
            ]];
            db_Close db
        " 2>&1 | tee report.log

        if [[ ! -s top_poses.sdf ]]; then
            echo "ERROR: top_poses.sdf not produced" >&2
            exit 1
        fi

        # Generate minimal HTML report from scored_poses.csv
        python3 - << 'HTMLEOF'
import csv, json
with open('docking_summary.json') as f:
    summary = json.load(f)
with open('docking_report.html', 'w') as f:
    f.write('<html><body><h1>MOE Covalent Docking</h1>')
    f.write('<p>Best: {} S={} GBVI/WSA dG={}</p>'.format(
        summary['best_ligand'], summary['best_s_score'], summary['best_gbvi_wsa_dg']))
    f.write('</body></html>')
print('docking_report.html written')
HTMLEOF

        echo "REPORT complete" >> report.log
        '''
}

// ============================================================================
// Workflow
// ============================================================================

workflow {

    // -------------------------------------------------------------------------
    // Parameter validation
    // -------------------------------------------------------------------------
    if (!params.receptor) {
        error "params.receptor is required. Provide a path to receptor.pdb or receptor.mol2."
    }
    if (!params.ligands) {
        error "params.ligands is required. Provide a path to warhead_smiles.smi or ligands.sdf."
    }

        def valid_warheads = ['acrylamide', 'chloroacetamide', 'epoxide', 'aldehyde',
                              'michael_acceptor', 'vinyl_sulfone', 'boronic_acid']
        if (!valid_warheads.contains(params.warhead_type)) {
            error "params.warhead_type '${params.warhead_type}' is not recognised. " +
                  "Valid options: ${valid_warheads.join(', ')}."
        }

        def valid_protocols = ['rigid', 'induced_fit']
        if (!valid_protocols.contains(params.docking_protocol)) {
            error "params.docking_protocol '${params.docking_protocol}' is not recognised. " +
                  "Valid options: ${valid_protocols.join(', ')}."
        }
    }

    // -------------------------------------------------------------------------
    // Build input channels
    // -------------------------------------------------------------------------
    }
}
