#!/usr/bin/env nextflow
/*
 * drug_discovery/schrodinger_glide_docking
 *
 * Schrodinger Glide docking pipeline: ligand preparation, receptor preparation,
 * grid generation, and SP/XP/HTVS docking with GlideScore ranking.
 *
 * Pipeline Steps:
 * 1. LIGPREP          -- LigPrep: ionization states, tautomers, stereoisomers, 3D geometry
 * 2. RECEPTOR_PREP    -- Protein Preparation Wizard: add H, assign bonds, optimize H-bonds, minimize
 * 3. GRID_GENERATION  -- Glide receptor grid around active site (explicit center or ref ligand)
 * 4. GLIDE_DOCKING    -- Glide SP/XP/HTVS docking: pose generation + GlideScore
 * 5. REPORT           -- Export top poses to SDF, docking_summary.json, HTML report
 *
 * License:
 *   Schrodinger Suite requires a valid FlexLM license.
 *   BioMate injects SCHRODINGER_LICENSE_FILE="27008@host" from the user's stored credential.
 *   Users must provide their own institutional or commercial license.
 *
 * References:
 *   Glide (SP): Friesner et al. J. Med. Chem. 2004, 47:1739-1749
 *   Glide (XP): Friesner et al. J. Med. Chem. 2006, 49:6177-6196
 *   LigPrep: Schrodinger LLC, New York 2024
 *   Protein Preparation Wizard: Sastry et al. J. Comput.-Aided Mol. Des. 2013, 27:221-234
 *   Extra Precision (XP): Halgren et al. J. Med. Chem. 2004, 47:1750-1759
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir               = './results/schrodinger_glide_docking'
params.publish_dir_mode     = 'copy'

// Mode
params.mock_mode            = true

// Inputs
params.receptor             = null    // receptor.pdb | receptor.mae | receptor.maegz
params.ligands              = null    // ligands.sdf | ligands.smi | ligands.maegz

// Docking settings
params.docking_precision    = 'SP'    // HTVS | SP | XP
params.grid_center          = null    // "[x,y,z]" string -- auto from ref_ligand if null
params.ref_ligand           = null    // .sdf/.mae reference ligand for grid box center
params.grid_inner_box       = 10      // Angstrom -- inner sampling box
params.grid_outer_box       = 30      // Angstrom -- outer bounding box
params.poses_per_ligand     = 5       // poses written per ligand
params.top_n                = 20      // top poses in final SDF output
params.use_epik             = true    // Epik metal-binding state penalties
params.use_samplering       = true    // ring conformation sampling

// LigPrep settings
params.ligprep_ph           = 7.4     // target pH for ionization
params.ligprep_ph_tolerance = 2.0     // +/- tolerance around target pH
params.max_stereoisomers    = 4       // max stereoisomers per ligand

// Resources
params.n_cpus               = 8

// ============================================================================
// Container
// ============================================================================

// User must build this image with Schrodinger Suite installed.
// Schrodinger does not provide a public Docker image.
// Build: install Suite 2024 -> docker commit -> push to ECR
def SCHRODINGER_CONTAINER = '399683337364.dkr.ecr.us-west-2.amazonaws.com/schrodinger2024:latest'

// ============================================================================
// Processes
// ============================================================================

process LIGPREP {
    /*
     * LigPrep: enumerate ionization states, tautomers, ring conformations,
     * and stereoisomers. Generates 3D geometries optimized with OPLS4.
     */
    tag "ligprep"
    container SCHRODINGER_CONTAINER
    publishDir "${params.outdir}/ligprep", mode: params.publish_dir_mode

    input:
    path ligands_file

    output:
    path "ligands_prepared.maegz", emit: prepared
    path "ligprep.log",            emit: log

    script:
    if (params.mock_mode) {
        """
        echo "[MOCK] LIGPREP -- LigPrep ionization/tautomer/3D preparation" > ligprep.log
        echo "[MOCK] Input: ${ligands_file}" >> ligprep.log
        echo "[MOCK] pH: ${params.ligprep_ph} +/- ${params.ligprep_ph_tolerance}" >> ligprep.log
        echo "[MOCK] Max stereoisomers: ${params.max_stereoisomers}" >> ligprep.log

        python3 -c "
data = b'Schrodinger Maestro File (MOCK)\\n'
with open('ligands_prepared.maegz', 'wb') as f:
    f.write(b'\\x1f\\x8b\\x08\\x00' + b'\\x00' * 8 + data)
print('[MOCK] ligands_prepared.maegz written')
"
        echo "[MOCK] LigPrep complete: 5 ligands prepared, 8 total structures" >> ligprep.log
        """
    } else {
        """
        set -euo pipefail

        input_ext="\$(echo '${ligands_file}' | rev | cut -d. -f1 | rev)"
        if [[ "\$input_ext" == "sdf" || "\$input_ext" == "sd" ]]; then
            input_fmt="-isd"
        elif [[ "\$input_ext" == "smi" || "\$input_ext" == "smiles" ]]; then
            input_fmt="-ismi"
        elif [[ "\$input_ext" == "mae" || "\$input_ext" == "maegz" ]]; then
            input_fmt="-imae"
        else
            echo "Unsupported format: \$input_ext" >&2; exit 1
        fi

        \$SCHRODINGER/ligprep \\
            \$input_fmt ${ligands_file} \\
            -omae ligands_prepared.maegz \\
            -ph ${params.ligprep_ph} \\
            -pht ${params.ligprep_ph_tolerance} \\
            -s ${params.max_stereoisomers} \\
            -bff 16 \\
            -WAIT \\
            2>&1 | tee ligprep.log
        """
    }
}


process RECEPTOR_PREP {
    /*
     * Protein Preparation Wizard: add H, assign bonds, optimize H-bonds,
     * restrained OPLS4 minimization.
     */
    tag "receptor_prep"
    container SCHRODINGER_CONTAINER
    publishDir "${params.outdir}/receptor", mode: params.publish_dir_mode

    input:
    path receptor_file

    output:
    path "receptor_prepared.maegz", emit: prepared
    path "prepwizard.log",          emit: log

    script:
    if (params.mock_mode) {
        """
        echo "[MOCK] RECEPTOR_PREP -- Protein Preparation Wizard" > prepwizard.log
        echo "[MOCK] Input: ${receptor_file}" >> prepwizard.log
        echo "[MOCK] Steps: add H, assign bonds, optimize H-bonds, OPLS4 minimize" >> prepwizard.log

        python3 -c "
data = b'Schrodinger Maestro File (MOCK RECEPTOR)\\n'
with open('receptor_prepared.maegz', 'wb') as f:
    f.write(b'\\x1f\\x8b\\x08\\x00' + b'\\x00' * 8 + data)
print('[MOCK] receptor_prepared.maegz written')
"
        echo "[MOCK] PrepWizard complete: 287 residues, 2314 atoms, 0 missing" >> prepwizard.log
        """
    } else {
        """
        set -euo pipefail

        \$SCHRODINGER/utilities/prepwizard \\
            -WAIT \\
            -watdist 0 \\
            -rehtreat \\
            -rmsd 0.3 \\
            -f 3 \\
            ${receptor_file} \\
            receptor_prepared.mae \\
            2>&1 | tee prepwizard.log

        \$SCHRODINGER/utilities/structconvert \\
            -imae receptor_prepared.mae \\
            -omaegz receptor_prepared.maegz
        """
    }
}


process GRID_GENERATION {
    /*
     * Glide receptor grid generation.
     * Box center from: explicit [x,y,z] OR centroid of ref_ligand OR protein center.
     */
    tag "grid_gen"
    container SCHRODINGER_CONTAINER
    publishDir "${params.outdir}/grid", mode: params.publish_dir_mode

    input:
    path receptor_prepared
    path ref_ligand_file

    output:
    path "receptor_grid.zip", emit: grid
    path "grid_gen.log",      emit: log

    script:
    if (params.mock_mode) {
        """
        echo "[MOCK] GRID_GENERATION -- Glide receptor grid" > grid_gen.log
        echo "[MOCK] Grid center: ${params.grid_center ?: 'auto (protein centroid)'}" >> grid_gen.log
        echo "[MOCK] Inner box: ${params.grid_inner_box} A  Outer box: ${params.grid_outer_box} A" >> grid_gen.log

        python3 -c "
import zipfile, io
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('receptor_grid.grd', '[MOCK] Glide grid placeholder')
    zf.writestr('receptor_grid.box', 'INNERBOX ${params.grid_inner_box}\\nOUTERBOX ${params.grid_outer_box}')
buf.seek(0)
with open('receptor_grid.zip', 'wb') as f:
    f.write(buf.read())
print('[MOCK] receptor_grid.zip written')
"
        echo "[MOCK] Grid generation complete" >> grid_gen.log
        """
    } else {
        """
        set -euo pipefail

        # Determine grid center
        if [[ -s "${ref_ligand_file}" && "${ref_ligand_file}" != "NO_REF_LIGAND" ]]; then
            python3 - << 'PYEOF'
from schrodinger.structure import StructureReader
import numpy as np
with StructureReader('${ref_ligand_file}') as reader:
    st = next(reader)
coords = np.array([[a.x, a.y, a.z] for a in st.atom])
cx, cy, cz = coords.mean(axis=0)
with open('grid_center.dat', 'w') as f:
    f.write(f'{cx:.3f} {cy:.3f} {cz:.3f}')
PYEOF
            GCENTER=\$(cat grid_center.dat)
        elif [[ -n "${params.grid_center}" ]]; then
            GCENTER="${params.grid_center}"
        else
            GCENTER="auto"
        fi

        cat > grid_gen.in << GLIDE_IN
GRIDFILE receptor_grid
INNERBOX ${params.grid_inner_box} ${params.grid_inner_box} ${params.grid_inner_box}
OUTERBOX ${params.grid_outer_box} ${params.grid_outer_box} ${params.grid_outer_box}
RECEPTOR_FILE ${receptor_prepared}
GRID_CENTER \$GCENTER
GLIDE_IN

        \$SCHRODINGER/glide grid_gen.in -WAIT 2>&1 | tee grid_gen.log
        """
    }
}


process GLIDE_DOCKING {
    /*
     * Glide docking at chosen precision:
     *   HTVS -- high-throughput virtual screening (fast, less accurate)
     *   SP   -- standard precision (balance of speed and accuracy)
     *   XP   -- extra precision (most accurate, slowest; for lead optimization)
     */
    tag "glide_${params.docking_precision}"
    container SCHRODINGER_CONTAINER
    publishDir "${params.outdir}/docking", mode: params.publish_dir_mode

    input:
    path grid_zip
    path ligands_prepared

    output:
    path "docked_poses.maegz",  emit: poses
    path "docking_report.csv",  emit: report
    path "glide.log",           emit: log

    script:
    if (params.mock_mode) {
        """
        python3 << 'PYEOF'
import csv, random

random.seed(42)

LIGANDS = [
    ('LIG001', 'CC(=O)Nc1ccc(-c2nnc(C)s2)cc1',       -8.41, -52.3),
    ('LIG002', 'O=C(NC1CCCC1)c1ccc(F)cc1',             -7.83, -48.7),
    ('LIG003', 'Cn1cc(-c2ccc(Cl)cc2)cn1',              -7.21, -44.1),
    ('LIG004', 'CC1(C)CCN(C(=O)c2cccs2)CC1',           -8.95, -57.2),
    ('LIG005', 'O=C(O)c1ccc(-n2ccnc2)nc1',             -6.54, -39.8),
    ('LIG006', 'O=C(Nc1ccccc1F)c1ccco1',               -7.67, -46.3),
    ('LIG007', 'CC(Nc1nc2ccccc2s1)c1ccccc1',           -6.88, -42.5),
    ('LIG008', 'N#Cc1ccc(NC(=O)c2cccc(Cl)c2)cc1',     -8.12, -50.9),
    ('LIG009', 'O=C(c1ccc(F)cc1)N1CCN(c2ccccn2)CC1',  -9.34, -61.8),
    ('LIG010', 'Cc1ccc(-c2cc(=O)n(C)cc2)cc1',         -7.45, -45.6),
]

rows = []
for name, smiles, gs_base, emodel_base in LIGANDS:
    for pose_n in range(1, ${params.poses_per_ligand} + 1):
        gs    = round(gs_base + random.gauss(0, 0.3), 3)
        emod  = round(emodel_base + random.gauss(0, 2.0), 2)
        lipo  = round(random.gauss(-2.1, 0.5), 3)
        hbond = round(random.gauss(-1.2, 0.4), 3)
        rows.append({
            'rank':          len(rows) + 1,
            'ligand_name':   name,
            'pose':          pose_n,
            'smiles':        smiles,
            'GlideScore':    gs,
            'Emodel':        emod,
            'LipophilicEvdW': lipo,
            'HBond':         hbond,
        })

rows.sort(key=lambda r: r['GlideScore'])
for i, r in enumerate(rows, 1):
    r['rank'] = i

with open('docking_report.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['rank','ligand_name','pose','smiles',
                                           'GlideScore','Emodel','LipophilicEvdW','HBond'])
    writer.writeheader()
    writer.writerows(rows)

data = b'Schrodinger Maestro File (MOCK DOCKED POSES)\\n'
with open('docked_poses.maegz', 'wb') as f:
    f.write(b'\\x1f\\x8b\\x08\\x00' + b'\\x00' * 8 + data)

with open('glide.log', 'w') as f:
    f.write('[MOCK] Glide ${params.docking_precision} docking\\n')
    f.write(f'[MOCK] {len(LIGANDS)} ligands, ${params.poses_per_ligand} poses each\\n')
    f.write(f'[MOCK] Top GlideScore: {rows[0]["GlideScore"]} ({rows[0]["ligand_name"]})\\n')

print(f'[MOCK] Glide complete: {len(rows)} poses')
PYEOF
        """
    } else {
        """
        set -euo pipefail

        cat > docking.in << GLIDE_IN
GRIDFILE ${grid_zip}
LIGANDFILE ${ligands_prepared}
PRECISION ${params.docking_precision}
POSES_PER_LIG ${params.poses_per_ligand}
EPIK_PENALTIES ${params.use_epik}
SAMPLERING ${params.use_samplering}
POSTDOCK_NPOSE ${params.poses_per_ligand}
GLIDE_IN

        \$SCHRODINGER/glide docking.in -WAIT -NJOBS ${params.n_cpus} 2>&1 | tee glide.log

        ls *.pv.maegz 2>/dev/null && mv \$(ls *.pv.maegz | head -1) docked_poses.maegz

        python3 - << 'PYEOF'
from schrodinger.structure import StructureReader
import csv

rows = []
with StructureReader('docked_poses.maegz') as reader:
    for i, st in enumerate(reader, 1):
        p = st.property
        rows.append({
            'rank':          i,
            'ligand_name':   p.get('s_m_title', f'LIG_{i:04d}'),
            'pose':          p.get('i_i_glide_posenum', i),
            'smiles':        p.get('s_m_smiles', ''),
            'GlideScore':    p.get('r_i_glide_gscore', ''),
            'Emodel':        p.get('r_i_glide_emodel', ''),
            'LipophilicEvdW': p.get('r_i_glide_lipo', ''),
            'HBond':         p.get('r_i_glide_hbond', ''),
        })

rows.sort(key=lambda r: float(r['GlideScore']) if r['GlideScore'] else 0)
for i, r in enumerate(rows, 1):
    r['rank'] = i

with open('docking_report.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['rank','ligand_name','pose','smiles',
                                           'GlideScore','Emodel','LipophilicEvdW','HBond'])
    writer.writeheader()
    writer.writerows(rows)
PYEOF
        """
    }
}


process REPORT {
    /*
     * Export top-N poses to SDF, generate docking_summary.json and HTML report.
     */
    tag "report"
    container SCHRODINGER_CONTAINER
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    path docked_poses
    path docking_csv

    output:
    path "top_poses.sdf",        emit: sdf
    path "docking_summary.json", emit: summary
    path "docking_report.html",  emit: report

    script:
    if (params.mock_mode) {
        """
        python3 << 'PYEOF'
import json, csv

rows = []
with open('${docking_csv}') as f:
    for row in csv.DictReader(f):
        rows.append(row)

rows.sort(key=lambda r: float(r.get('GlideScore', 0)))
top = rows[: ${params.top_n}]

# SDF
with open('top_poses.sdf', 'w') as f:
    for i, row in enumerate(top, 1):
        f.write(f"{row.get('ligand_name','LIG')}\\n")
        f.write('  BioMate/Glide  3D\\n\\n')
        f.write('  0  0  0  0  0  0  0  0  0  0999 V2000\\n')
        f.write('M  END\\n')
        f.write(f'> <GlideScore>\\n{row.get("GlideScore","")}\\n\\n')
        f.write(f'> <Emodel>\\n{row.get("Emodel","")}\\n\\n')
        f.write(f'> <SMILES>\\n{row.get("smiles","")}\\n\\n')
        f.write(f'> <Rank>\\n{i}\\n\\n')
        f.write(f'> <Precision>\\n${params.docking_precision}\\n\\n')
        f.write('\$\$\$\$\\n')

top_score  = float(top[0]['GlideScore']) if top else 0
mean_score = sum(float(r['GlideScore']) for r in rows) / len(rows) if rows else 0

summary = {
    'mock_mode': True,
    'docking_precision': '${params.docking_precision}',
    'n_ligands_input': len(set(r['ligand_name'] for r in rows)),
    'n_poses_total': len(rows),
    'n_poses_reported': len(top),
    'top_glidescore': round(top_score, 3),
    'mean_glidescore': round(mean_score, 3),
    'top_ligand': top[0].get('ligand_name','') if top else '',
    'top_smiles':  top[0].get('smiles','') if top else '',
    'interpretation': (
        'Strong binder (GlideScore < -8)' if top_score < -8
        else 'Moderate binder (-8 to -6)' if top_score < -6
        else 'Weak binder (> -6)'
    )
}

with open('docking_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

# HTML
html_rows = ''
for r in top[:20]:
    gs = float(r.get('GlideScore', 0))
    color = '#c8e6c9' if gs < -8 else '#fff9c4' if gs < -6 else '#ffccbc'
    html_rows += (f'<tr style="background:{color}">'
                  f'<td>{r.get("rank","")}</td>'
                  f'<td>{r.get("ligand_name","")}</td>'
                  f'<td><code style="font-size:11px">{r.get("smiles","")}</code></td>'
                  f'<td><b>{gs:.3f}</b></td>'
                  f'<td>{r.get("Emodel","")}</td></tr>')

html = f'''<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Glide Docking Report</title>
<style>
  body{{font-family:Arial,sans-serif;margin:40px;background:#fafafa}}
  h1{{color:#1565c0}}
  table{{border-collapse:collapse;width:100%;margin-top:20px}}
  th{{background:#1565c0;color:white;padding:8px 12px;text-align:left}}
  td{{padding:6px 12px;border-bottom:1px solid #ddd}}
  .meta{{background:#e3f2fd;padding:16px;border-radius:6px;margin-bottom:24px}}
  .metric{{display:inline-block;margin:8px 16px}}
  .metric .value{{font-size:24px;font-weight:bold;color:#1565c0}}
  .metric .label{{font-size:12px;color:#666}}
</style>
</head>
<body>
<h1>Schrodinger Glide {summary["docking_precision"]} Docking Report</h1>
<div class="meta">
  <div class="metric"><div class="value">{summary["n_ligands_input"]}</div><div class="label">Ligands Docked</div></div>
  <div class="metric"><div class="value">{summary["top_glidescore"]}</div><div class="label">Top GlideScore</div></div>
  <div class="metric"><div class="value">{summary["mean_glidescore"]:.2f}</div><div class="label">Mean GlideScore</div></div>
  <div class="metric"><div class="value">{summary["docking_precision"]}</div><div class="label">Precision</div></div>
  <p><b>Top compound:</b> <code>{summary["top_smiles"]}</code></p>
  <p><b>Interpretation:</b> {summary["interpretation"]}</p>
  <p style="color:#888;font-size:12px">[MOCK] Synthetic results. Real results require Schrodinger Suite license.</p>
</div>
<h2>Top Docked Poses</h2>
<table>
  <tr><th>Rank</th><th>Ligand</th><th>SMILES</th><th>GlideScore</th><th>Emodel</th></tr>
  {html_rows}
</table>
</body></html>'''

with open('docking_report.html', 'w') as f:
    f.write(html)

print(json.dumps(summary, indent=2))
PYEOF
        """
    } else {
        """
        set -euo pipefail

        python3 - << 'PYEOF'
import json, csv
from schrodinger.structure import StructureWriter, StructureReader

rows = []
with open('${docking_csv}') as f:
    rows = list(csv.DictReader(f))
rows.sort(key=lambda r: float(r.get('GlideScore', 0)))
top = rows[: ${params.top_n}]
top_indices = {int(r['rank']) for r in top}

with StructureReader('${docked_poses}') as reader:
    all_poses = list(reader)

with StructureWriter('top_poses.sdf') as writer:
    for i, st in enumerate(all_poses, 1):
        if i in top_indices:
            writer.append(st)

top_score  = float(top[0]['GlideScore']) if top else 0
mean_score = sum(float(r['GlideScore']) for r in rows) / len(rows) if rows else 0

summary = {
    'mock_mode': False,
    'docking_precision': '${params.docking_precision}',
    'n_ligands_input': len(set(r['ligand_name'] for r in rows)),
    'n_poses_total': len(rows),
    'n_poses_reported': len(top),
    'top_glidescore': round(top_score, 3),
    'mean_glidescore': round(mean_score, 3),
    'top_ligand': top[0].get('ligand_name', '') if top else '',
    'top_smiles':  top[0].get('smiles', '') if top else '',
    'interpretation': (
        'Strong binder (GlideScore < -8)' if top_score < -8
        else 'Moderate binder (-8 to -6)' if top_score < -6
        else 'Weak binder (> -6)'
    )
}

with open('docking_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

with open('docking_report.html', 'w') as f:
    f.write(f'<html><body><h1>Glide {summary["docking_precision"]} Report</h1>'
            f'<p>{summary["n_ligands_input"]} ligands | Top: {summary["top_glidescore"]} | {summary["interpretation"]}</p>'
            f'</body></html>')

print(json.dumps(summary, indent=2))
PYEOF
        """
    }
}


// ============================================================================
// Workflow
// ============================================================================

workflow {

    if (!params.mock_mode) {
        if (!params.receptor) {
            error "ERROR: --receptor is required (receptor.pdb or .mae)"
        }
        if (!params.ligands) {
            error "ERROR: --ligands is required (ligands.sdf or .smi)"
        }
        if (!System.getenv("SCHRODINGER_LICENSE_FILE") && !System.getenv("SCHRODINGER")) {
            error "ERROR: SCHRODINGER_LICENSE_FILE not set. Enter your FlexLM server address via the BioMate credential gate."
        }
    }

    if (params.mock_mode) {
        receptor_ch  = Channel.of(file("${params.receptor  ?: 'mock_receptor.pdb'}"))
        ligands_ch   = Channel.of(file("${params.ligands   ?: 'mock_ligands.sdf'}"))
        ref_lig_ch   = Channel.of(file("NO_REF_LIGAND"))
    } else {
        receptor_ch  = Channel.fromPath(params.receptor)
        ligands_ch   = Channel.fromPath(params.ligands)
        ref_lig_ch   = params.ref_ligand
            ? Channel.fromPath(params.ref_ligand)
            : Channel.of(file('NO_REF_LIGAND'))
    }

    LIGPREP(ligands_ch)
    RECEPTOR_PREP(receptor_ch)
    GRID_GENERATION(RECEPTOR_PREP.out.prepared, ref_lig_ch)
    GLIDE_DOCKING(GRID_GENERATION.out.grid, LIGPREP.out.prepared)
    REPORT(GLIDE_DOCKING.out.poses, GLIDE_DOCKING.out.report)

    REPORT.out.summary
        .view { f ->
            def d = new groovy.json.JsonSlurper().parseText(f.text)
            log.info ""
            log.info "================================================================"
            log.info "  Schrodinger Glide ${params.docking_precision} Docking -- Results"
            log.info "================================================================"
            log.info "  Ligands docked : ${d.n_ligands_input}"
            log.info "  Total poses    : ${d.n_poses_total}"
            log.info "  Top GlideScore : ${d.top_glidescore}  (${d.top_ligand})"
            log.info "  Mean GlideScore: ${d.mean_glidescore}"
            log.info "  Assessment     : ${d.interpretation}"
            log.info "================================================================"
            log.info ""
        }
}
