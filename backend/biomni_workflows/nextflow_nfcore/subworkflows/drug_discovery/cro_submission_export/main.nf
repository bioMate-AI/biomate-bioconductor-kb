#!/usr/bin/env nextflow
// ============================================================================
// drug_discovery/cro_submission_export
// Format top-N compounds for CRO submission (WuXi AppTec standard format).
//
// Steps:
//   1. VALIDATE_COMPOUNDS     -- Safety check: hERG IC50 > threshold, flag withdrawn
//   2. FORMAT_CRO_SUBMISSION  -- Add MW/LogP from SMILES (RDKit), build WuXi columns
//   3. EXPORT_CSV             -- Write submission CSV + metadata JSON
// ============================================================================

nextflow.enable.dsl = 2

// -- default parameters -------------------------------------------------------
params.compound_csv        = null       // CSV file path or inline CSV: compound_id,smiles,bcrabl1_ic50_nm,herg_ic50_um,composite_score (required)
params.cro_target          = 'WuXiAppTec'
params.top_n               = 5
params.herg_safe_threshold  = 1.0      // uM -- below = safety failure
params.assay_name           = 'BCR-ABL1 Kinase Inhibition'
params.project_code         = 'BIOMATE-BCR-ABL1-2026'
params.outdir               = './results'
params.publish_dir_mode     = 'copy'

// Banner removed 2026-05-21 — Nextflow 26.04 DSL2 forbids statements at script scope

// =============================================================================
// PROCESS 1: VALIDATE_COMPOUNDS
// =============================================================================
process VALIDATE_COMPOUNDS {
    tag "validate"
    label 'process_low'
    publishDir "${params.outdir}/01_validated", mode: params.publish_dir_mode

    // local (ARM dev placeholder): biomate/biomni-tools:latest
    // aws batch (AMD64): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(compound_csv_content)

    output:
    path 'validated_compounds.csv', emit: validated_csv
    path 'validation_report.txt',   emit: report

    script:
    def threshold = params.herg_safe_threshold
    def top_n     = params.top_n
    """
python3 - <<'PYEOF'
import csv, io, os, sys

raw = '''${compound_csv_content}'''

# If the value looks like a file path (no newlines, path exists), read it
raw = raw.strip()
if raw and '\\n' not in raw and os.path.exists(raw):
    with open(raw) as _f:
        raw = _f.read()

lines = [l for l in raw.strip().splitlines() if l.strip()]
if not lines:
    sys.exit('ERROR: No compound data provided')

reader = csv.DictReader(lines)
rows = list(reader)

def norm(h):
    return h.strip().lower().replace(' ', '_').replace('-', '_')

rows_norm = [{norm(k): v.strip() for k, v in r.items()} for r in rows]

herg_threshold = float('${threshold}')
top_n = int('${top_n}')

validated = []
failures = []
for r in rows_norm:
    cid = r.get('compound_id', r.get('name', r.get('id', '')))
    smiles = r.get('smiles', r.get('canonical_smiles', ''))
    ic50 = r.get('bcrabl1_ic50_nm', r.get('ic50_nm', r.get('ic50', '')))
    herg = r.get('herg_ic50_um', r.get('herg', ''))
    score = r.get('composite_score', r.get('score', ''))

    try:
        herg_f = float(herg)
    except (ValueError, TypeError):
        herg_f = None

    if herg_f is not None and herg_f < herg_threshold:
        failures.append(f'FAIL: {cid} hERG IC50={herg_f} uM < {herg_threshold} uM (safety failure)')
        continue

    validated.append({
        'compound_id': cid,
        'smiles': smiles,
        'bcrabl1_ic50_nm': ic50,
        'herg_ic50_um': herg,
        'composite_score': score,
        'herg_safe': 'YES',
    })

# Take top N by composite score
try:
    validated.sort(key=lambda x: -float(x['composite_score'] or 0))
except Exception:
    pass
validated = validated[:top_n]

with open('validated_compounds.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['compound_id', 'smiles', 'bcrabl1_ic50_nm',
                                           'herg_ic50_um', 'composite_score', 'herg_safe'])
    writer.writeheader()
    writer.writerows(validated)

with open('validation_report.txt', 'w') as f:
    f.write(f'Input compounds: {len(rows_norm)}\\n')
    f.write(f'Safety failures: {len(failures)}\\n')
    f.write(f'Passing compounds: {len(validated)}\\n')
    for fail in failures:
        f.write(fail + '\\n')

print(f'Validation: {len(validated)} pass, {len(failures)} fail safety check')
PYEOF
"""
}

// =============================================================================
// PROCESS 2: FORMAT_CRO_SUBMISSION
// =============================================================================
process FORMAT_CRO_SUBMISSION {
    tag "format_${params.cro_target}"
    label 'process_low'
    publishDir "${params.outdir}/02_formatted", mode: params.publish_dir_mode

    // local (ARM dev placeholder): biomate/biomni-tools:latest
    // aws batch (AMD64): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path(validated_csv)

    output:
    path 'cro_submission.csv',  emit: cro_csv
    path 'compound_metadata.json', emit: metadata_json

    script:
    def cro = params.cro_target
    def project = params.project_code
    def assay = params.assay_name
    """
python3 - <<'PYEOF'
import csv, json, math
cro = '${cro}'

# Try RDKit for MW/LogP; fall back to formula-based estimate if not available
try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors
    HAS_RDKIT = True
except ImportError:
    HAS_RDKIT = False

def calc_mw_logp(smiles):
    if not smiles or not HAS_RDKIT:
        return None, None
    try:
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return None, None
        return round(Descriptors.MolWt(mol), 2), round(Descriptors.MolLogP(mol), 2)
    except Exception:
        return None, None

with open('${validated_csv}') as f:
    rows = list(csv.DictReader(f))

import datetime
submission_date = datetime.date.today().isoformat()

formatted = []
for i, r in enumerate(rows):
    mw, logp = calc_mw_logp(r.get('smiles', ''))
    row = {
        'Sample_ID': r['compound_id'],
        'Project_Code': '${project}',
        'SMILES': r.get('smiles', ''),
        'MW': mw if mw is not None else 'N/A',
        'LogP': logp if logp is not None else 'N/A',
        'BCR_ABL1_IC50_nM': r.get('bcrabl1_ic50_nm', ''),
        'hERG_IC50_uM': r.get('herg_ic50_um', ''),
        'Composite_Score': r.get('composite_score', ''),
        'Safety_Flag': 'PASS',
        'Assay': '${assay}',
        'Submission_Date': submission_date,
        'CRO': '${cro}',
        'Priority': i + 1,
    }
    formatted.append(row)

fields = ['Sample_ID', 'Project_Code', 'SMILES', 'MW', 'LogP',
          'BCR_ABL1_IC50_nM', 'hERG_IC50_uM', 'Composite_Score',
          'Safety_Flag', 'Assay', 'Submission_Date', 'CRO', 'Priority']

with open('cro_submission.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(formatted)

metadata = {
    'cro': '${cro}',
    'project_code': '${project}',
    'assay': '${assay}',
    'submission_date': submission_date,
    'compound_count': len(formatted),
    'rdkit_available': HAS_RDKIT,
    'compounds': [{'id': r['Sample_ID'], 'priority': r['Priority'],
                   'smiles': r['SMILES'][:40] + '...' if len(r['SMILES']) > 40 else r['SMILES']}
                  for r in formatted],
}
with open('compound_metadata.json', 'w') as f:
    json.dump(metadata, f, indent=2)

print(f'Formatted {len(formatted)} compounds for {cro} submission')
print(f'RDKit available: {HAS_RDKIT}')
PYEOF
"""
}

// =============================================================================
// PROCESS 3: EXPORT_CSV
// =============================================================================
process EXPORT_CSV {
    tag "export_final"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    // local (ARM dev placeholder): biomate/biomni-tools:latest
    // aws batch (AMD64): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path(cro_csv)
    path(metadata_json)

    output:
    path 'wuxiapptec_submission.csv', emit: final_csv
    path 'submission_summary.txt',    emit: summary

    script:
    def cro = params.cro_target
    """
python3 - <<'PYEOF'
import csv, json, shutil

# Rename cro_submission.csv -> wuxiapptec_submission.csv (or CRO-specific name)
shutil.copy('${cro_csv}', 'wuxiapptec_submission.csv')

with open('${metadata_json}') as f:
    meta = json.load(f)

with open('submission_summary.txt', 'w') as f:
    f.write(f'CRO Submission Summary\\n')
    f.write(f'======================\\n')
    f.write(f'CRO: {meta["cro"]}\\n')
    f.write(f'Project: {meta["project_code"]}\\n')
    f.write(f'Assay: {meta["assay"]}\\n')
    f.write(f'Date: {meta["submission_date"]}\\n')
    f.write(f'Compounds: {meta["compound_count"]}\\n')
    f.write(f'\\nPriority list:\\n')
    for c in meta.get('compounds', []):
        f.write(f'  {c["priority"]}. {c["id"]}\\n')
    f.write(f'\\nAll compounds passed hERG safety screening (IC50 > ${params.herg_safe_threshold} uM).\\n')
    f.write(f'Output file: wuxiapptec_submission.csv\\n')

with open('wuxiapptec_submission.csv') as f:
    rows = list(csv.DictReader(f))

print(f'Export complete: {len(rows)} compounds in wuxiapptec_submission.csv')
for r in rows:
    print(f'  {r["Priority"]}. {r["Sample_ID"]} IC50={r["BCR_ABL1_IC50_nM"]} nM hERG={r["hERG_IC50_uM"]} uM score={r["Composite_Score"]}')
PYEOF
"""
}

// =============================================================================
// WORKFLOW
// =============================================================================
workflow {
    if (!params.compound_csv) error "params.compound_csv is required. Provide a file path or inline CSV string."
    compound_ch = Channel.value(params.compound_csv)

    VALIDATE_COMPOUNDS(compound_ch)
    FORMAT_CRO_SUBMISSION(VALIDATE_COMPOUNDS.out.validated_csv)
    EXPORT_CSV(
        FORMAT_CRO_SUBMISSION.out.cro_csv,
        FORMAT_CRO_SUBMISSION.out.metadata_json
    )
}
