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

// Mode
params.mock_mode            = true   // true = synthetic output, no MOE license needed

// Inputs
params.receptor             = null   // receptor.pdb or receptor.mol2 (required unless mock)
params.ligands              = null   // warhead_smiles.smi or ligands.sdf (required unless mock)

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
    if (params.mock_mode) {
        """
        echo "[MOCK] LIGAND_PREP -- MOE LigPrep"                               > ligprep.log
        echo "[MOCK] Input       : ${ligand_file}"                             >> ligprep.log
        echo "[MOCK] Warhead type: ${params.warhead_type}"                     >> ligprep.log
        echo "[MOCK] Tautomers/protonation states at pH 7.4"                   >> ligprep.log
        echo "[MOCK] Partial charges: MMFF94x"                                 >> ligprep.log
        echo "[MOCK] Generating 3D conformers for 5 compounds..."              >> ligprep.log
        echo "[MOCK] ligands_prepped.mdb: 5 compounds prepared"               >> ligprep.log
        echo "[MOCK] LIGAND_PREP complete"                                     >> ligprep.log
        printf 'MOE_DB_MOCK_v2024\\x00LIGPREP:5\\x00WARHEAD:${params.warhead_type}\\x00' > ligands_prepped.mdb
        """
    } else {
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
        """
    }
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
    if (params.mock_mode) {
        """
        echo "[MOCK] RECEPTOR_PREP -- MOE QuickPrep"                              > prep.log
        echo "[MOCK] Input          : ${receptor_file}"                           >> prep.log
        echo "[MOCK] Protonate3D at pH 7.4"                                       >> prep.log
        echo "[MOCK] Minimisation: AMBER FF, RMSD tol 0.5 A"                     >> prep.log
        echo "[MOCK] Reactive residue: ${params.reactive_residue}"                >> prep.log
        echo "[MOCK] receptor_prepped.moe: ready for CovDock"                    >> prep.log
        echo "[MOCK] RECEPTOR_PREP complete"                                      >> prep.log
        printf 'MOE_BINARY_MOCK_v2024\\x00RECPREP\\x00REACT:${params.reactive_residue}\\x00' > receptor_prepped.moe
        """
    } else {
        """
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
        """
    }
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
    if (params.mock_mode) {
        """
        echo "[MOCK] COVALENT_DOCK -- MOE CovDock SVL script"                        > covdock.log
        echo "[MOCK] Receptor     : ${receptor_moe}"                                >> covdock.log
        echo "[MOCK] Ligands      : ${ligands_mdb}"                                 >> covdock.log
        echo "[MOCK] Protocol     : ${params.docking_protocol}"                     >> covdock.log
        echo "[MOCK] Reactive res : ${params.reactive_residue}"                     >> covdock.log
        echo "[MOCK] Warhead type : ${params.warhead_type}"                         >> covdock.log
        echo "[MOCK] n_poses      : ${params.n_poses}"                              >> covdock.log
        echo "[MOCK] Covalent bond: C-S (thia-Michael addition, acrylamide/CYS)"   >> covdock.log
        echo "[MOCK] Screening 5 ligands..."                                         >> covdock.log
        echo "[MOCK] Ligand 1 (acrylamide_001): 10 poses, best S=-8.42"            >> covdock.log
        echo "[MOCK] Ligand 2 (acrylamide_002):  9 poses, best S=-7.89"            >> covdock.log
        echo "[MOCK] Ligand 3 (acrylamide_003): 10 poses, best S=-7.34"            >> covdock.log
        echo "[MOCK] Ligand 4 (acrylamide_004):  8 poses, best S=-6.71"            >> covdock.log
        echo "[MOCK] Ligand 5 (acrylamide_005):  9 poses, best S=-5.88"            >> covdock.log
        echo "[MOCK] CovDock complete: 5 ligands, reactive ${params.reactive_residue}" >> covdock.log
        printf 'MOE_DB_MOCK_v2024\\x00POSES:46\\x00REACTIVE:${params.reactive_residue}\\x00WARHEAD:${params.warhead_type}\\x00' > covalent_poses.mdb
        """
    } else {
        """
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
        """
    }
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
    if (params.mock_mode) {
        """
        echo "[MOCK] POSE_ANALYSIS -- MOE S score, E_Score1/2, GBVI/WSA dG" > pose_analysis.log
        echo "[MOCK] Input        : ${poses_mdb}"                            >> pose_analysis.log
        echo "[MOCK] Refine poses : ${params.refine_poses}"                  >> pose_analysis.log

        python3 - << 'PYEOF'
import csv

rows = [
    {'rank': 1, 'ligand_name': 'acrylamide_001',
     'smiles': 'C=CC(=O)Nc1ccc(F)cc1CN2CCCC2=O',
     's_score': -8.42, 'e_score1': -9.15, 'gbvi_wsa_dg': -10.23,
     'covalent_bond_length_A': 1.81},
    {'rank': 2, 'ligand_name': 'acrylamide_002',
     'smiles': 'C=CC(=O)Nc1ccc(-c2ccncc2)cc1',
     's_score': -7.89, 'e_score1': -8.54, 'gbvi_wsa_dg': -9.67,
     'covalent_bond_length_A': 1.83},
    {'rank': 3, 'ligand_name': 'acrylamide_003',
     'smiles': 'C=CC(=O)Nc1cnc2ccccc2c1',
     's_score': -7.34, 'e_score1': -7.91, 'gbvi_wsa_dg': -8.82,
     'covalent_bond_length_A': 1.82},
    {'rank': 4, 'ligand_name': 'acrylamide_004',
     'smiles': 'C=CC(=O)Nc1ccc(OCC2CCCO2)cc1',
     's_score': -6.71, 'e_score1': -7.23, 'gbvi_wsa_dg': -7.95,
     'covalent_bond_length_A': 1.84},
    {'rank': 5, 'ligand_name': 'acrylamide_005',
     'smiles': 'C=CC(=O)Nc1ccc(Cl)c(Cl)c1',
     's_score': -5.88, 'e_score1': -6.40, 'gbvi_wsa_dg': -7.01,
     'covalent_bond_length_A': 1.85},
]

fieldnames = ['rank', 'ligand_name', 'smiles',
              's_score', 'e_score1', 'gbvi_wsa_dg', 'covalent_bond_length_A']
with open('scored_poses.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
print('scored_poses.csv written: 5 rows')
PYEOF

        echo "[MOCK] Best S score: -8.42 (acrylamide_001)"                    >> pose_analysis.log
        echo "[MOCK] GBVI/WSA dG range: -10.23 to -7.01 kcal/mol"            >> pose_analysis.log
        echo "[MOCK] All covalent bond lengths within 1.80-1.85 A (C-S)"     >> pose_analysis.log
        echo "[MOCK] POSE_ANALYSIS complete"                                   >> pose_analysis.log
        """
    } else {
        """
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
        """
    }
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
    if (params.mock_mode) {
        """
        python3 - << 'PYEOF'
import csv, json

def minimal_mol_block(name):
    coords = [
        ( 0.0000,  0.0000, 0.0000, 'C'),
        ( 1.2124,  0.7004, 0.0000, 'C'),
        ( 2.4249,  0.0000, 0.0000, 'C'),
        ( 1.2124, -1.4008, 0.0000, 'C'),
        ( 0.0000, -0.7004, 0.0000, 'N'),
    ]
    bonds = [(1,2,2),(2,3,1),(3,4,2),(4,5,1),(5,1,1)]
    lines = [name, '  MOECovDock2024', '  Covalent docking pose (mock)']
    lines.append('{:3d}{:3d}  0  0  0  0  0  0  0  0999 V2000'.format(len(coords), len(bonds)))
    for x, y, z, sym in coords:
        lines.append('{:10.4f}{:10.4f}{:10.4f} {:<3s} 0  0  0  0  0  0  0  0  0  0  0  0'.format(x, y, z, sym))
    for a, b, t in bonds:
        lines.append('{:3d}{:3d}{:3d}  0  0  0  0'.format(a, b, t))
    lines.append('M  END')
    return '\n'.join(lines)

rows = []
with open('scored_poses.csv') as f:
    for row in csv.DictReader(f):
        rows.append(row)

top_n    = 5
top_rows = rows[:top_n] if len(rows) >= top_n else rows

sdf_parts = []
for i, row in enumerate(top_rows, start=1):
    sdf_parts.append(minimal_mol_block(row['ligand_name']))
    sdf_parts += [
        '> <S_Score>',            row['s_score'],                '',
        '> <GBVI_WSA_dG>',        row['gbvi_wsa_dg'],            '',
        '> <CovalentBondLength>',  row['covalent_bond_length_A'], '',
        '> <WarheadType>',         'acrylamide',                  '',
        '> <ReactiveResidue>',     'CYS145',                      '',
        '> <Rank>',                str(i),                        '',
        '$$$$',
    ]
with open('top_poses.sdf', 'w') as f:
    f.write('\n'.join(sdf_parts) + '\n')
print('top_poses.sdf written: {} entries'.format(len(top_rows)))

best = top_rows[0] if top_rows else {}
summary = {
    'pipeline': 'moe_covalent_docking',
    'moe_version': '2024.0901',
    'reactive_residue': 'CYS145',
    'warhead_type': 'acrylamide',
    'docking_protocol': 'induced_fit',
    'n_poses_per_ligand': 10,
    'top_n_reported': len(top_rows),
    'total_compounds_docked': len(rows),
    'best_ligand': best.get('ligand_name', 'N/A'),
    'best_s_score': float(best.get('s_score', 0)),
    'best_gbvi_wsa_dg': float(best.get('gbvi_wsa_dg', 0)),
    'best_covalent_bond_length_A': float(best.get('covalent_bond_length_A', 0)),
    'refine_poses': True,
    'mock_mode': True,
    'references': [
        'Zhu et al. J. Chem. Inf. Model. 2014, 54:1932-1940 (MOE CovDock)',
        'Labute J. Chem. Inf. Model. 2008, 48:1117-1128 (GBVI/WSA dG)',
        'Baillie Nat. Chem. Biol. 2016, 12:401-405 (Covalent inhibitor review)',
        'Chemical Computing Group ULC, MOE 2024.09, Montreal, Canada',
    ],
}
with open('docking_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)
print('docking_summary.json written')

score_rows_html = ''
for row in top_rows:
    s = float(row['s_score'])
    color = '#c8e6c9' if s <= -8.0 else ('#fff9c4' if s <= -7.0 else '#ffccbc')
    score_rows_html += (
        '<tr style="background:{c};">'
        '<td>{rank}</td><td><code>{name}</code></td>'
        '<td style="font-size:0.8em;max-width:220px;overflow:hidden;'
        'text-overflow:ellipsis;white-space:nowrap;">{smiles}</td>'
        '<td><strong>{s}</strong></td><td>{e1}</td><td>{gbvi}</td><td>{bl}</td>'
        '</tr>\n'
    ).format(
        c=color, rank=row['rank'], name=row['ligand_name'],
        smiles=row['smiles'], s=row['s_score'],
        e1=row['e_score1'], gbvi=row['gbvi_wsa_dg'],
        bl=row['covalent_bond_length_A'],
    )

meta_cards = (
    '<div class="meta-card"><div class="mc-label">Compounds Docked</div>'
    '<div class="mc-value">' + str(len(rows)) + '</div></div>\n'
    '<div class="meta-card"><div class="mc-label">Best S Score (kcal/mol)</div>'
    '<div class="mc-value">' + str(best.get('s_score', 'N/A')) + '</div></div>\n'
    '<div class="meta-card"><div class="mc-label">Best GBVI/WSA dG (kcal/mol)</div>'
    '<div class="mc-value">' + str(best.get('gbvi_wsa_dg', 'N/A')) + '</div></div>\n'
    '<div class="meta-card"><div class="mc-label">Poses per Ligand</div>'
    '<div class="mc-value">10</div></div>\n'
    '<div class="meta-card"><div class="mc-label">Top Poses Reported</div>'
    '<div class="mc-value">' + str(len(top_rows)) + '</div></div>\n'
    '<div class="meta-card"><div class="mc-label">Best Ligand</div>'
    '<div class="mc-value">' + str(best.get('ligand_name', 'N/A')) + '</div></div>\n'
)

html = (
    '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
    '  <meta charset="UTF-8">\n'
    '  <title>MOE Covalent Docking Report</title>\n'
    '  <style>\n'
    '    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;'
    '           margin: 2rem; background: #f5f5f5; color: #212121; }\n'
    '    h1   { color: #1565c0; margin-bottom: 0.25rem; }\n'
    '    h2   { color: #37474f; border-bottom: 2px solid #90a4ae;'
    '           padding-bottom: 4px; margin-top: 2rem; }\n'
    '    .sub { color: #607d8b; margin-top: 0; font-size: 0.9rem; }\n'
    '    .hbox { background: #e3f2fd; border-left: 4px solid #1976d2;'
    '            padding: 1rem 1.25rem; border-radius: 4px; margin: 1.25rem 0; }\n'
    '    .meta-grid { display: grid; grid-template-columns: repeat(3, 1fr);'
    '                 gap: 1rem; margin: 1.5rem 0; }\n'
    '    .meta-card { background: white; border-radius: 8px; padding: 1rem;'
    '                 box-shadow: 0 1px 4px rgba(0,0,0,0.15); }\n'
    '    .mc-label { font-size: 0.72rem; color: #607d8b; text-transform: uppercase;'
    '                letter-spacing: 0.05em; }\n'
    '    .mc-value { font-size: 1.3rem; font-weight: 700; color: #1565c0; margin-top: 4px; }\n'
    '    table { border-collapse: collapse; width: 100%; background: white;'
    '            border-radius: 8px; overflow: hidden;'
    '            box-shadow: 0 1px 4px rgba(0,0,0,0.15); }\n'
    '    th { background: #1565c0; color: white; padding: 10px 14px;'
    '         text-align: left; font-size: 0.85rem; white-space: nowrap; }\n'
    '    td { padding: 8px 14px; font-size: 0.9rem; border-bottom: 1px solid #eceff1; }\n'
    '    .legend { display: flex; gap: 1.25rem; margin: 0.5rem 0 1.25rem; font-size: 0.8rem; }\n'
    '    .li { display: flex; align-items: center; gap: 6px; }\n'
    '    .sw { width: 16px; height: 16px; border-radius: 3px; }\n'
    '    .refs { font-size: 0.78rem; color: #607d8b; }\n'
    '    .refs li { margin: 3px 0; }\n'
    '  </style>\n</head>\n<body>\n'
    '  <h1>MOE Covalent Docking Report</h1>\n'
    '  <p class="sub">Generated by BioMate &bull; MOE 2024.09 &bull; CovDock SVL pipeline</p>\n'
    '  <div class="hbox">\n'
    '    <strong>Reactive Residue:</strong> <code>CYS145</code>\n'
    '    &emsp; <strong>Warhead Type:</strong> <code>acrylamide</code>\n'
    '    &emsp; <strong>Protocol:</strong> <code>induced_fit</code>\n'
    '    &emsp; <strong>Rescoring:</strong> GBVI/WSA dG (Labute 2008)\n'
    '  </div>\n'
    '  <div class="meta-grid">\n' + meta_cards + '  </div>\n'
    '  <h2>Ranked Covalent Poses</h2>\n'
    '  <div class="legend">\n'
    '    <div class="li"><div class="sw" style="background:#c8e6c9;"></div>'
    ' S score &le; -8.0 (excellent)</div>\n'
    '    <div class="li"><div class="sw" style="background:#fff9c4;"></div>'
    ' -8.0 to -7.0 (good)</div>\n'
    '    <div class="li"><div class="sw" style="background:#ffccbc;"></div>'
    ' &gt; -7.0 (moderate)</div>\n'
    '  </div>\n'
    '  <table>\n'
    '    <thead><tr>\n'
    '      <th>Rank</th><th>Ligand</th><th>SMILES</th>\n'
    '      <th>S Score</th><th>E_Score1</th><th>GBVI/WSA dG</th><th>Cov Bond (A)</th>\n'
    '    </tr></thead>\n'
    '    <tbody>\n' + score_rows_html + '    </tbody>\n  </table>\n'
    '  <h2>Scoring Definitions</h2>\n'
    '  <ul>\n'
    '    <li><strong>S Score</strong>: London dG docking score (kcal/mol); primary ranking; lower is better.</li>\n'
    '    <li><strong>E_Score1</strong>: Force-field refinement score (MMFF94x/Amber) after constrained minimisation.</li>\n'
    '    <li><strong>GBVI/WSA dG</strong>: Generalised Born Volume Integral / Weighted Surface Area\n'
    '        binding free energy (Labute 2008); most accurate MOE rescoring.</li>\n'
    '    <li><strong>Cov Bond Length</strong>: Length of newly formed covalent bond (A).\n'
    '        Expected 1.80-1.85 A for C-S (thia-Michael, acrylamide/CYS).</li>\n'
    '  </ul>\n'
    '  <h2>Covalent Warhead Chemistry</h2>\n'
    '  <ul>\n'
    '    <li><strong>acrylamide</strong>: thia-Michael addition to CYS thiol; C-S bond; irreversible</li>\n'
    '    <li><strong>chloroacetamide</strong>: SN2 alkylation of CYS thiol; C-S bond; irreversible</li>\n'
    '    <li><strong>epoxide</strong>: ring-opening by thiol/amine/hydroxyl; tunable reversibility</li>\n'
    '    <li><strong>aldehyde</strong>: reversible Schiff base (LYS) or hemithioacetal (CYS)</li>\n'
    '    <li><strong>michael_acceptor</strong>: generalised 1,4-conjugate addition</li>\n'
    '    <li><strong>vinyl_sulfone</strong>: thia-Michael addition (strong EWG); irreversible</li>\n'
    '    <li><strong>boronic_acid</strong>: reversible covalent with SER/THR/TYR boronate ester</li>\n'
    '  </ul>\n'
    '  <h2>References</h2>\n'
    '  <ul class="refs">\n'
    '    <li>Zhu et al. <em>J. Chem. Inf. Model.</em> 2014, 54:1932-1940 -- MOE CovDock algorithm</li>\n'
    '    <li>Labute, P. <em>J. Chem. Inf. Model.</em> 2008, 48:1117-1128 -- GBVI/WSA dG rescoring</li>\n'
    '    <li>Baillie, T.A. <em>Nat. Chem. Biol.</em> 2016, 12:401-405 -- Targeted covalent inhibitors</li>\n'
    '    <li>Chemical Computing Group ULC. <em>MOE 2024.09</em>. Montreal, QC, Canada, 2024.</li>\n'
    '  </ul>\n</body>\n</html>\n'
)
with open('docking_report.html', 'w') as f:
    f.write(html)
print('docking_report.html written')
PYEOF

        echo "[MOCK] REPORT complete: top_poses.sdf, docking_summary.json, docking_report.html"
        """
    } else {
        """
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
    'mock_mode': False,
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
        """
    }
}

// ============================================================================
// Workflow
// ============================================================================

workflow {

    // -------------------------------------------------------------------------
    // Parameter validation
    // -------------------------------------------------------------------------
    if (!params.mock_mode) {
        if (!params.receptor) {
            error "params.receptor is required when mock_mode = false. " +
                  "Provide a path to receptor.pdb or receptor.mol2."
        }
        if (!params.ligands) {
            error "params.ligands is required when mock_mode = false. " +
                  "Provide a path to warhead_smiles.smi or ligands.sdf."
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
    if (params.mock_mode) {
        ligand_ch   = Channel.of(file('/dev/null'))
        receptor_ch = Channel.of(file('/dev/null'))
    } else {
        ligand_ch   = Channel.fromPath(params.ligands,   checkIfExists: true)
        receptor_ch = Channel.fromPath(params.receptor,  checkIfExists: true)
    }

    // -------------------------------------------------------------------------
    // Pipeline execution
    // -------------------------------------------------------------------------

    // Step 1: Prepare ligands -- protonation states, tautomers, MMFF94x charges
    ligprep_out  = LIGAND_PREP(ligand_ch)

    // Step 2: Prepare receptor -- add H, Protonate3D, constrained minimisation
    recprep_out  = RECEPTOR_PREP(receptor_ch)

    // Step 3: Covalent docking -- CovDock SVL, explicit covalent bond to reactive residue
    covdock_out  = COVALENT_DOCK(recprep_out.prepped_moe, ligprep_out.prepped_mdb)

    // Step 4: Score all poses -- S score, E_Score1/2, GBVI/WSA dG
    analysis_out = POSE_ANALYSIS(covdock_out.poses_mdb)

    // Step 5: Export top poses to SDF + generate HTML report + JSON summary
    report_out   = REPORT(analysis_out.scores_csv)

    // -------------------------------------------------------------------------
    // Pipeline summary banner
    // -------------------------------------------------------------------------
    report_out.summary_json.view { json_file ->
        def summary = new groovy.json.JsonSlurper().parse(json_file)
        """
============================================================
 MOE Covalent Docking -- Pipeline Complete
============================================================
 Reactive residue    : ${summary.reactive_residue}
 Warhead type        : ${summary.warhead_type}
 Docking protocol    : ${summary.docking_protocol}
 Compounds docked    : ${summary.total_compounds_docked}
 Top poses reported  : ${summary.top_n_reported}
 Best ligand         : ${summary.best_ligand}
 Best S score        : ${summary.best_s_score} kcal/mol
 Best GBVI/WSA dG    : ${summary.best_gbvi_wsa_dg} kcal/mol
 Cov bond length     : ${summary.best_covalent_bond_length_A} A
============================================================
 Results directory   : ${params.outdir}
 Key outputs:
   01_ligand_prep/ligands_prepped.mdb
   02_receptor_prep/receptor_prepped.moe
   03_covalent_dock/covalent_poses.mdb
   04_pose_analysis/scored_poses.csv
   05_report/top_poses.sdf
   05_report/docking_summary.json
   05_report/docking_report.html
============================================================
 References:
   Zhu et al. J. Chem. Inf. Model. 2014, 54:1932-1940
   Labute J. Chem. Inf. Model. 2008, 48:1117-1128
   Chemical Computing Group ULC, MOE 2024.09
============================================================
        """
    }
}
