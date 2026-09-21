#!/usr/bin/env nextflow
/*
 * lab_automation/nanodrop_purity_qc
 *
 * NanoDrop / microvolume spectrophotometer sample-QC parser.
 * Ingests a Thermo NanoDrop (One / 2000 / 8000) or comparable microvolume
 * spectrophotometer CSV export (per-sample {sample, ng/uL, A260, A280, A230,
 * A260/280, A260/230}) and produces a tidy per-sample QC table + a summary with
 * a purity pass/fail called against nucleic-acid-type-specific ranges:
 *   DNA: A260/280 ~ 1.8   RNA: A260/280 ~ 2.0
 *   both: A260/230 ~ 2.0-2.2 (low values flag guanidine / phenol / EDTA carryover)
 *
 * Ratios are recomputed from raw absorbances when the vendor export omits the
 * ratio columns, and a minimum-concentration gate is applied. Falls back to
 * demo data when no input is supplied, matching the sibling
 * drug_discovery/hts_plate_qc_hit_calling idiom.
 *
 * Reference: Thermo NanoDrop technical bulletin T042 (260/280 & 260/230 purity);
 * Wilfinger et al. BioTechniques 1997 (ratio interpretation).
 *
 * Input:  nanodrop_csv (path to NanoDrop CSV export),
 *         nucleic_acid_type (DNA | RNA),
 *         min_conc_ng_ul (default 10.0),
 *         a260_230_min (default 2.0)
 * Output: nanodrop_qc_results.json, nanodrop_per_sample.csv,
 *         nanodrop_summary.txt, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir             = './results'
params.nanodrop_csv       = 'null'
params.nucleic_acid_type  = 'DNA'
params.min_conc_ng_ul     = '10.0'
params.a260_230_min       = '2.0'

process NANODROP_PURITY_QC {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("nanodrop_qc_results.json"), emit: results
    tuple val(meta), path("nanodrop_per_sample.csv"),  emit: table
    tuple val(meta), path("nanodrop_summary.txt"),     emit: summary
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_CSV='${params.nanodrop_csv}'
    export PARAM_NA_TYPE='${params.nucleic_acid_type}'
    export PARAM_MIN_CONC='${params.min_conc_ng_ul}'
    export PARAM_A260_230_MIN='${params.a260_230_min}'

    python3 << 'PYEOF'
import json, os, csv, sys, io

def ac(v, default=None):
    if v in (None, '', 'null', 'None'):
        return default
    try:
        return float(v)
    except (TypeError, ValueError):
        return default

# NanoDrop firmware emits several header spellings across One / 2000 / 8000.
SAMPLE_KEYS = ['sample', 'sample name', 'sample id', 'sample_name', 'name',
               'well']
CONC_KEYS   = ['conc', 'conc.', 'concentration', 'ng/ul', 'nucleic acid',
               'nucleic acid conc.', 'conc (ng/ul)']
A260_KEYS   = ['a260', '260', 'a260 (abs)', 'abs 260']
A280_KEYS   = ['a280', '280', 'a280 (abs)', 'abs 280']
A230_KEYS   = ['a230', '230', 'a230 (abs)', 'abs 230']
R260280_KEYS = ['260/280', 'a260/280', '260/280 ratio']
R260230_KEYS = ['260/230', 'a260/230', '260/230 ratio']

def find_key(row, candidates):
    for cand in candidates:
        if cand in row:
            return row[cand]
    return None

def parse_csv(raw):
    '''Parse the NanoDrop CSV export string; demo data if absent.'''
    if raw and raw not in ('null', 'None', ''):
        text = None
        if os.path.isfile(raw):
            with open(raw, 'r') as fh:
                text = fh.read()
        elif '\\n' in raw or ',' in raw:
            text = raw
        if text:
            lines = [ln for ln in text.splitlines() if ln.strip()]
            hdr_idx = 0
            for i, ln in enumerate(lines):
                low = ln.lower()
                if any(k in low for k in ('sample', '260/280', 'a260', 'conc')) and ',' in ln:
                    hdr_idx = i
                    break
            reader = csv.DictReader(io.StringIO('\\n'.join(lines[hdr_idx:])))
            rows = []
            for r in reader:
                rows.append({(k or '').strip().lower(): (v or '').strip()
                             for k, v in r.items()})
            if rows:
                return rows
    # Demo data: 5 samples, mixed purity (clean, phenol carryover, dilute)
    return [
        {'sample': 'DNA_01', 'ng/ul': '85.2',  'a260': '1.70', 'a280': '0.93', 'a230': '0.81'},
        {'sample': 'DNA_02', 'ng/ul': '120.5', 'a260': '2.41', 'a280': '1.34', 'a230': '1.15'},
        {'sample': 'DNA_03', 'ng/ul': '45.0',  'a260': '0.90', 'a280': '0.53', 'a230': '0.60'},
        {'sample': 'DNA_04', 'ng/ul': '6.3',   'a260': '0.13', 'a280': '0.07', 'a230': '0.06'},
        {'sample': 'DNA_05', 'ng/ul': '200.1', 'a260': '4.00', 'a280': '2.10', 'a230': '1.95'},
    ]

# -- params --------------------------------------------------------------------
raw_csv      = os.environ.get('PARAM_CSV', 'null')
na_type      = (os.environ.get('PARAM_NA_TYPE') or 'DNA').strip().upper()
min_conc     = ac(os.environ.get('PARAM_MIN_CONC'), 10.0)
a260_230_min = ac(os.environ.get('PARAM_A260_230_MIN'), 2.0)

# Type-specific 260/280 acceptance window (Thermo T042 / Wilfinger 1997).
if na_type == 'RNA':
    r280_lo, r280_hi = 1.9, 2.2
else:  # DNA (default)
    r280_lo, r280_hi = 1.7, 2.0

rows = parse_csv(raw_csv)

def ratio(num, den):
    if num is None or den is None or abs(den) < 1e-9:
        return None
    return round(num / den, 3)

per_sample = []
for row in rows:
    sample = (find_key(row, SAMPLE_KEYS) or f"sample_{len(per_sample)+1}").strip() or f"sample_{len(per_sample)+1}"
    conc   = ac(find_key(row, CONC_KEYS))
    a260   = ac(find_key(row, A260_KEYS))
    a280   = ac(find_key(row, A280_KEYS))
    a230   = ac(find_key(row, A230_KEYS))

    # Prefer vendor-reported ratios; recompute from raw absorbances otherwise.
    r260280 = ac(find_key(row, R260280_KEYS))
    if r260280 is None:
        r260280 = ratio(a260, a280)
    r260230 = ac(find_key(row, R260230_KEYS))
    if r260230 is None:
        r260230 = ratio(a260, a230)

    reasons = []
    conc_ok = conc is not None and conc >= min_conc
    if not conc_ok:
        reasons.append(f"conc={conc if conc is not None else 'NA'} < {min_conc} ng/uL")
    r280_ok = r260280 is not None and r280_lo <= r260280 <= r280_hi
    if not r280_ok:
        reasons.append(f"A260/280={r260280 if r260280 is not None else 'NA'} outside {r280_lo}-{r280_hi}")
    r230_ok = r260230 is not None and r260230 >= a260_230_min
    if not r230_ok:
        reasons.append(f"A260/230={r260230 if r260230 is not None else 'NA'} < {a260_230_min}")

    passed = bool(conc_ok and r280_ok and r230_ok)
    per_sample.append({
        'sample': sample, 'concentration_ng_ul': conc,
        'a260': a260, 'a280': a280, 'a230': a230,
        'a260_280': r260280, 'a260_230': r260230,
        'qc_pass': passed, 'fail_reason': '; '.join(reasons) if reasons else '',
    })

n_total = len(per_sample)
n_pass  = sum(1 for s in per_sample if s['qc_pass'])

summary = {
    'nucleic_acid_type': na_type,
    'a260_280_window': [r280_lo, r280_hi],
    'a260_230_min': a260_230_min,
    'min_conc_ng_ul': min_conc,
    'n_samples': n_total,
    'n_pass': n_pass,
    'n_fail': n_total - n_pass,
    'pass_rate_pct': round(100 * n_pass / n_total, 1) if n_total else 0.0,
    'batch_qc_status': 'PASS' if n_pass == n_total and n_total > 0 else 'REVIEW',
}

# -- write outputs -------------------------------------------------------------
with open('nanodrop_per_sample.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['sample', 'concentration_ng_ul', 'A260', 'A280', 'A230',
                'A260/280', 'A260/230', 'qc_pass', 'fail_reason'])
    for s in per_sample:
        w.writerow([s['sample'], s['concentration_ng_ul'], s['a260'],
                    s['a280'], s['a230'], s['a260_280'], s['a260_230'],
                    s['qc_pass'], s['fail_reason']])

with open('nanodrop_qc_results.json', 'w') as f:
    json.dump({'status': 'completed', 'summary': summary,
               'per_sample': per_sample}, f, indent=2)

report = [
    '=== NANODROP / MICROVOLUME SPECTROPHOTOMETER PURITY-QC REPORT ===', '',
    f"Nucleic acid:    {na_type}",
    f"A260/280 window: {r280_lo}-{r280_hi}   A260/230 min: {a260_230_min}",
    f"Min conc:        {min_conc} ng/uL",
    f"Samples:         {n_total}",
    f"Pass / Fail:     {n_pass} / {n_total - n_pass}  ({summary['pass_rate_pct']}% pass)",
    f"Batch status:    {summary['batch_qc_status']}",
    '', 'Per-sample:',
]
for s in per_sample:
    flag = 'PASS' if s['qc_pass'] else 'FAIL'
    detail = f" [{s['fail_reason']}]" if s['fail_reason'] else ''
    report.append(
        f"  {s['sample']:12s} {s['concentration_ng_ul']} ng/uL  "
        f"260/280={s['a260_280']}  260/230={s['a260_230']}  {flag}{detail}")

with open('nanodrop_summary.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
nanodrop_purity_qc:
  python: "3.10"
  reference: "Thermo NanoDrop T042; Wilfinger 1997 (260/280 & 260/230)"
EOF
    """
}

workflow NANODROP_PURITY_QC_WORKFLOW {
    take: meta_ch
    main: NANODROP_PURITY_QC(meta_ch)
    emit:
        results  = NANODROP_PURITY_QC.out.results
        table    = NANODROP_PURITY_QC.out.table
        summary  = NANODROP_PURITY_QC.out.summary
        versions = NANODROP_PURITY_QC.out.versions
}

workflow {
    meta = [id: 'nanodrop_qc_run', single_end: false]
    Channel.value(meta) | NANODROP_PURITY_QC_WORKFLOW
}
