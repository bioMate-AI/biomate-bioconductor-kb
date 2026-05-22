#!/usr/bin/env nextflow
// ============================================================================
// drug_discovery/assay_ingestion_and_ranking
// Ingest multi-assay compound data and produce a composite safety-potency ranking.
//
// Steps:
//   1. PARSE_ASSAY_DATA       -- Parse CSV, validate columns, pivot to wide format
//   2. COMPUTE_COMPOSITE_SCORE -- Normalise IC50/hERG, compute weighted composite score
//   3. RANK_AND_REPORT        -- Sort by score, emit ranked CSV + HTML report
// ============================================================================

nextflow.enable.dsl = 2

// -- default parameters -------------------------------------------------------
params.assay_csv          = null        // path to CSV file or inline CSV string (required)
params.potency_assay      = 'IC50_BCR_ABL1'
params.safety_assay       = 'hERG_IC50'
params.potency_weight     = 0.6
params.safety_weight      = 0.4
params.herg_safe_threshold = 1.0       // uM -- below this = unsafe
params.top_n              = 10
params.outdir             = './results'
params.publish_dir_mode   = 'copy'

// -- banner -------------------------------------------------------------------
log.info '''
============================================================
  BioMate -- Assay Ingestion & Composite Ranking
============================================================
  Potency assay  : ''' + params.potency_assay + '''
  Safety assay   : ''' + params.safety_assay + '''
  Weights        : potency=''' + params.potency_weight + ''' safety=''' + params.safety_weight + '''
  hERG threshold : ''' + params.herg_safe_threshold + ''' uM
  Top-N          : ''' + params.top_n + '''
============================================================
'''

// =============================================================================
// PROCESS 1: PARSE_ASSAY_DATA
// =============================================================================
process PARSE_ASSAY_DATA {
    tag "parse_assay"
    label 'process_low'
    publishDir "${params.outdir}/01_parsed", mode: params.publish_dir_mode

    // local (ARM dev placeholder): biomate/biomni-tools:latest
    // aws batch (AMD64): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(assay_csv_content)

    output:
    path 'wide_assay.csv',   emit: wide_csv
    path 'parse_report.txt', emit: parse_report

    script:
    def potency = params.potency_assay
    def safety  = params.safety_assay
    """
python3 - <<'PYEOF'
import csv, io, json, os, sys

raw = '''${assay_csv_content}'''

# If the value looks like a file path (no newlines, path exists), read it
raw = raw.strip()
if raw and '\\n' not in raw and os.path.exists(raw):
    with open(raw) as _f:
        raw = _f.read()

# Strip any leading/trailing whitespace lines
lines = [l for l in raw.strip().splitlines() if l.strip()]

# Find header row
header_idx = 0
for i, l in enumerate(lines):
    if 'compound_id' in l.lower() or 'cpd' in l.lower() and 'assay' in l.lower():
        header_idx = i
        break

reader = csv.DictReader(lines[header_idx:])
rows = list(reader)

if not rows:
    sys.exit('ERROR: No data rows found in assay CSV')

# Normalize column names
def norm_col(c):
    return c.strip().lower().replace(' ', '_')

rows_norm = [{norm_col(k): v.strip() for k, v in r.items()} for r in rows]

# Pivot: one row per compound, columns per assay_type
from collections import defaultdict
data = defaultdict(dict)
for r in rows_norm:
    cid = r.get('compound_id', r.get('cpd_id', ''))
    atype = r.get('assay_type', '')
    val = r.get('value', r.get('ic50', ''))
    unit = r.get('unit', '')
    data[cid][atype] = (val, unit)

assay_types = sorted({atype for cid_data in data.values() for atype in cid_data})

with open('wide_assay.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    header = ['compound_id'] + [f'{a}_value' for a in assay_types] + [f'{a}_unit' for a in assay_types]
    writer.writerow(header)
    for cid, amap in sorted(data.items()):
        row = [cid]
        for a in assay_types:
            v, u = amap.get(a, ('', ''))
            row.append(v)
        for a in assay_types:
            v, u = amap.get(a, ('', ''))
            row.append(u)
        writer.writerow(row)

with open('parse_report.txt', 'w') as f:
    f.write(f'Compounds parsed: {len(data)}\\n')
    f.write(f'Assay types: {assay_types}\\n')
    f.write(f'Total rows: {len(rows)}\\n')

print(f'Parsed {len(data)} compounds, assays: {assay_types}')
PYEOF
"""
}

// =============================================================================
// PROCESS 2: COMPUTE_COMPOSITE_SCORE
// =============================================================================
process COMPUTE_COMPOSITE_SCORE {
    tag "score_compounds"
    label 'process_low'
    publishDir "${params.outdir}/02_scored", mode: params.publish_dir_mode

    // local (ARM dev placeholder): biomate/biomni-tools:latest
    // aws batch (AMD64): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path(wide_csv)

    output:
    path 'scored_compounds.csv', emit: scored_csv

    script:
    def potency_col = "${params.potency_assay}_value"
    def safety_col  = "${params.safety_assay}_value"
    def pw          = params.potency_weight
    def sw          = params.safety_weight
    def threshold   = params.herg_safe_threshold
    """
python3 - <<'PYEOF'
import csv, math

potency_col = '${potency_col}'
safety_col  = '${safety_col}'
pw = float('${pw}')
sw = float('${sw}')
herg_threshold = float('${threshold}')

with open('${wide_csv}') as f:
    rows = list(csv.DictReader(f))

def safe_float(v, default=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default

def potency_score(ic50_nm):
    # Log-scaled score: max at 0.01 nM, 0.5 at 1 nM, decays for weaker compounds
    if ic50_nm is None or ic50_nm <= 0:
        return 0.0
    # pIC50-based normalisation, clamp 0-1
    pic50 = -math.log10(ic50_nm * 1e-9)  # convert nM to M
    # Normalise: 12 = perfect (0.01 nM), 6 = weak (1 uM)
    score = max(0.0, min(1.0, (pic50 - 6.0) / 6.0))
    return score

def safety_score(herg_um):
    # Higher hERG IC50 = safer; threshold at 1 uM
    if herg_um is None:
        return 0.5  # unknown -- neutral
    if herg_um <= 0:
        return 0.0
    # Log-scaled: 30 uM = 1.0, 1 uM = 0.5, 0.05 uM = 0 (withdrawn)
    score = max(0.0, min(1.0, math.log10(herg_um + 0.001) / math.log10(30)))
    return score

scored = []
for r in rows:
    cid = r.get('compound_id', '')
    pot_nm = safe_float(r.get(potency_col, ''))
    herg_um_raw = safe_float(r.get(safety_col, ''))

    # Safety assay may be in uM or nM -- detect by magnitude
    # hERG IC50 for most drugs is in uM range (0.05-30 uM)
    # If value > 100, assume nM and convert
    if herg_um_raw is not None and herg_um_raw > 100:
        herg_um = herg_um_raw / 1000.0
    else:
        herg_um = herg_um_raw

    ps = potency_score(pot_nm)
    ss = safety_score(herg_um)
    composite = pw * ps + sw * ss

    safety_flag = 'SAFE' if (herg_um is not None and herg_um >= herg_threshold) else 'UNSAFE'

    scored.append({
        'compound_id': cid,
        'potency_ic50_nm': pot_nm if pot_nm is not None else 'N/A',
        'herg_ic50_um': herg_um if herg_um is not None else 'N/A',
        'potency_score': round(ps, 4),
        'safety_score': round(ss, 4),
        'composite_score': round(composite, 4),
        'safety_flag': safety_flag,
    })

scored.sort(key=lambda x: -x['composite_score'])

with open('scored_compounds.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['compound_id', 'potency_ic50_nm', 'herg_ic50_um',
                                           'potency_score', 'safety_score', 'composite_score', 'safety_flag'])
    writer.writeheader()
    writer.writerows(scored)

print(f'Scored {len(scored)} compounds')
for s in scored[:5]:
    print(f"  {s['compound_id']}: composite={s['composite_score']:.4f} ({s['safety_flag']})")
PYEOF
"""
}

// =============================================================================
// PROCESS 3: RANK_AND_REPORT
// =============================================================================
process RANK_AND_REPORT {
    tag "rank_report"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    // local (ARM dev placeholder): biomate/biomni-tools:latest
    // aws batch (AMD64): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path(scored_csv)

    output:
    path 'ranked_compounds.csv',  emit: ranked_csv
    path 'ranking_report.html',   emit: report_html
    path 'ranking_summary.json',  emit: summary_json

    script:
    def top_n = params.top_n
    """
python3 - <<'PYEOF'
import csv, json

with open('${scored_csv}') as f:
    rows = list(csv.DictReader(f))

# Add rank column
for i, r in enumerate(rows):
    r['rank'] = i + 1

top_n = min(int('${top_n}'), len(rows))
top_rows = rows[:top_n]

# Ranked CSV
with open('ranked_compounds.csv', 'w', newline='') as f:
    fields = ['rank', 'compound_id', 'potency_ic50_nm', 'herg_ic50_um',
              'potency_score', 'safety_score', 'composite_score', 'safety_flag']
    writer = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
    writer.writeheader()
    writer.writerows(rows)

# HTML report
html_rows = ''
for r in rows:
    bg = '#d4edda' if r['safety_flag'] == 'SAFE' else '#f8d7da'
    html_rows += (
        f'<tr style="background:{bg}">'
        f'<td>{r["rank"]}</td><td>{r["compound_id"]}</td>'
        f'<td>{r["potency_ic50_nm"]}</td><td>{r["herg_ic50_um"]}</td>'
        f'<td>{r["potency_score"]}</td><td>{r["safety_score"]}</td>'
        f'<td><b>{r["composite_score"]}</b></td><td>{r["safety_flag"]}</td>'
        f'</tr>\\n'
    )

html = f'''<!DOCTYPE html>
<html><head><title>Compound Ranking Report</title>
<style>body{{font-family:Arial,sans-serif;margin:20px}}
table{{border-collapse:collapse;width:100%}}
th,td{{border:1px solid #ddd;padding:8px;text-align:right}}
th{{background:#4472c4;color:white;text-align:center}}
td:nth-child(2){{text-align:left}}</style></head>
<body>
<h2>BCR-ABL1 Campaign -- Composite Safety-Potency Ranking</h2>
<p>Total compounds: {len(rows)} | Top {top_n} shown in detail</p>
<table>
<tr><th>Rank</th><th>Compound</th><th>BCR-ABL1 IC50 (nM)</th><th>hERG IC50 (uM)</th>
<th>Potency Score</th><th>Safety Score</th><th>Composite Score</th><th>Flag</th></tr>
{html_rows}
</table>
<p><small>Scoring: composite = {float("${params.potency_weight}")*100:.0f}% potency + {float("${params.safety_weight}")*100:.0f}% safety | hERG threshold: ${params.herg_safe_threshold} uM</small></p>
</body></html>'''

with open('ranking_report.html', 'w') as f:
    f.write(html)

summary = {
    'total_compounds': len(rows),
    'safe_compounds': sum(1 for r in rows if r['safety_flag'] == 'SAFE'),
    'unsafe_compounds': sum(1 for r in rows if r['safety_flag'] == 'UNSAFE'),
    'top_compound': rows[0]['compound_id'] if rows else None,
    'top_score': float(rows[0]['composite_score']) if rows else 0.0,
    'top_10': [{'rank': r['rank'], 'compound_id': r['compound_id'],
                'composite_score': r['composite_score'], 'safety_flag': r['safety_flag']}
               for r in rows[:10]],
}
with open('ranking_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

print(f'Ranking complete. Top compound: {rows[0]["compound_id"]} score={rows[0]["composite_score"]}')
print(f'Safe: {summary["safe_compounds"]} / Unsafe: {summary["unsafe_compounds"]}')
PYEOF
"""
}

// =============================================================================
// WORKFLOW
// =============================================================================
workflow {
    if (!params.assay_csv) error "params.assay_csv is required. Provide a file path or inline CSV string."
    assay_ch = Channel.value(params.assay_csv)

    PARSE_ASSAY_DATA(assay_ch)
    COMPUTE_COMPOSITE_SCORE(PARSE_ASSAY_DATA.out.wide_csv)
    RANK_AND_REPORT(COMPUTE_COMPOSITE_SCORE.out.scored_csv)
}
