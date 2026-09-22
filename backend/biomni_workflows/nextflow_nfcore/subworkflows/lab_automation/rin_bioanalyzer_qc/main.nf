#!/usr/bin/env nextflow
/*
 * lab_automation/rin_bioanalyzer_qc
 *
 * RNA Integrity (RIN) / Bioanalyzer / TapeStation sample-QC parser.
 * Ingests an Agilent 2100 Bioanalyzer or 4200/4150 TapeStation electropherogram
 * export (per-sample CSV of {sample, RIN|RINe, 28S/18S ratio, concentration,
 * region-molarity/fragment-size fields}) and produces a tidy per-sample QC
 * table + a summary with pass/fail called on a configurable RIN threshold and a
 * fragment-size (DV200 / smear) sanity check.
 *
 * The parser is tolerant of the several column names Agilent tooling emits
 * (RIN, RINe, "RNA Integrity Number", "28S/18S", "DV200", "Region 1 [nt]") and
 * falls back to demo data when no input is supplied, matching the idiom of the
 * sibling drug_discovery/hts_plate_qc_hit_calling module.
 *
 * Reference tool: bioanalyzeR (Bioconductor) for electropherogram import; the
 * RIN algorithm itself is Schroeder et al. BMC Mol Biol 2006.
 *
 * Input:  bioanalyzer_csv (path to Agilent/TapeStation per-sample export),
 *         rin_threshold (default 7.0), dv200_min_pct (default 30.0),
 *         assay_type (RNA | FFPE_RNA — FFPE relaxes RIN, gates on DV200)
 * Output: rin_qc_results.json, rin_per_sample.csv, rin_summary.txt, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir           = './results'
params.bioanalyzer_csv  = 'null'
params.rin_threshold    = '7.0'
params.dv200_min_pct    = '30.0'
params.assay_type       = 'RNA'

process RIN_BIOANALYZER_QC {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("rin_qc_results.json"), emit: results
    tuple val(meta), path("rin_per_sample.csv"),  emit: table
    tuple val(meta), path("rin_summary.txt"),     emit: summary
    path "versions.yml",                          emit: versions

    script:
    """
    export PARAM_CSV='${params.bioanalyzer_csv}'
    export PARAM_RIN_THRESH='${params.rin_threshold}'
    export PARAM_DV200_MIN='${params.dv200_min_pct}'
    export PARAM_ASSAY='${params.assay_type}'

    python3 << 'PYEOF'
import json, os, csv, sys, io

def ac(v, default=None):
    if v in (None, '', 'null', 'None'):
        return default
    try:
        return float(v)
    except (TypeError, ValueError):
        return default

# -- column-name resolution (Agilent 2100 / TapeStation emit several spellings) --
RIN_KEYS    = ['rin', 'rine', 'rin_e', 'rna integrity number', 'rna integrity',
               'rin value', 'rqn']
SAMPLE_KEYS = ['sample', 'sample name', 'sample_name', 'sample id', 'well',
               'well label', 'name']
RATIO_KEYS  = ['28s/18s', '28s/18s ratio', 'rrna ratio [28s / 18s]',
               'rrna ratio', 'ratio']
CONC_KEYS   = ['conc', 'conc.', 'concentration', 'concentration [ng/ul]',
               'conc [ng/ul]', 'ng/ul']
DV200_KEYS  = ['dv200', 'dv200 [%]', '% > 200 nt', 'dv200 (%)']

def find_key(row, candidates):
    for cand in candidates:
        if cand in row:
            return row[cand]
    return None

def parse_csv(raw):
    '''Parse the Agilent/TapeStation CSV export string; demo data if absent.'''
    if raw and raw not in ('null', 'None', ''):
        # PARAM_CSV may be a path (Nextflow-staged) or inline CSV text.
        text = None
        if os.path.isfile(raw):
            with open(raw, 'r') as fh:
                text = fh.read()
        elif '\\n' in raw or ',' in raw:
            text = raw
        if text:
            # Agilent exports often carry a preamble; skip to the header row
            # that contains a sample column.
            lines = [ln for ln in text.splitlines() if ln.strip()]
            hdr_idx = 0
            for i, ln in enumerate(lines):
                low = ln.lower()
                if any(k in low for k in ('sample', 'well')) and ',' in ln:
                    hdr_idx = i
                    break
            reader = csv.DictReader(io.StringIO('\\n'.join(lines[hdr_idx:])))
            rows = []
            for r in reader:
                rows.append({(k or '').strip().lower(): (v or '').strip()
                             for k, v in r.items()})
            if rows:
                return rows
    # Demo data: 6 samples, one degraded, one FFPE-like low-RIN-high-DV200
    return [
        {'sample': 'RNA_01', 'rin': '9.4', '28s/18s': '1.9', 'conc': '210', 'dv200': '92'},
        {'sample': 'RNA_02', 'rin': '8.1', '28s/18s': '1.7', 'conc': '180', 'dv200': '85'},
        {'sample': 'RNA_03', 'rin': '7.2', '28s/18s': '1.4', 'conc': '150', 'dv200': '78'},
        {'sample': 'RNA_04', 'rin': '5.6', '28s/18s': '0.9', 'conc': '95',  'dv200': '61'},
        {'sample': 'RNA_05', 'rin': '3.1', '28s/18s': '0.4', 'conc': '40',  'dv200': '28'},
        {'sample': 'RNA_06', 'rin': '2.4', '28s/18s': '0.2', 'conc': '22',  'dv200': '35'},
    ]

# -- params --------------------------------------------------------------------
raw_csv     = os.environ.get('PARAM_CSV', 'null')
rin_thresh  = ac(os.environ.get('PARAM_RIN_THRESH'), 7.0)
dv200_min   = ac(os.environ.get('PARAM_DV200_MIN'), 30.0)
assay_type  = (os.environ.get('PARAM_ASSAY') or 'RNA').strip().upper()

rows = parse_csv(raw_csv)

per_sample = []
for row in rows:
    # find_key returns the matched *value* (or None) for the first candidate
    # column name present in the row.
    sample = (find_key(row, SAMPLE_KEYS) or f"sample_{len(per_sample)+1}").strip() or f"sample_{len(per_sample)+1}"
    rin    = ac(find_key(row, RIN_KEYS))
    ratio  = ac(find_key(row, RATIO_KEYS))
    conc   = ac(find_key(row, CONC_KEYS))
    dv200  = ac(find_key(row, DV200_KEYS))

    # FFPE / heavily degraded RNA: RIN is uninformative; gate on DV200 instead
    # (Illumina TruSeq RNA Access guidance). Fresh RNA gates on RIN.
    if assay_type in ('FFPE_RNA', 'FFPE'):
        passed = dv200 is not None and dv200 >= dv200_min
        gate   = 'DV200'
        reasons = [] if passed else [f"DV200={dv200 if dv200 is not None else 'NA'} < {dv200_min}%"]
    else:
        rin_ok   = rin is not None and rin >= rin_thresh
        dv200_ok = dv200 is None or dv200 >= dv200_min  # advisory when present
        passed   = bool(rin_ok and dv200_ok)
        gate     = 'RIN'
        reasons  = []
        if not rin_ok:
            reasons.append(f"RIN={rin if rin is not None else 'NA'} < {rin_thresh}")
        if dv200 is not None and dv200 < dv200_min:
            reasons.append(f"DV200={dv200} < {dv200_min}%")

    per_sample.append({
        'sample': sample, 'rin': rin, 'rrna_ratio_28s_18s': ratio,
        'concentration_ng_ul': conc, 'dv200_pct': dv200,
        'gate': gate, 'qc_pass': passed,
        'fail_reason': '; '.join(reasons) if reasons else '',
    })

n_total = len(per_sample)
n_pass  = sum(1 for s in per_sample if s['qc_pass'])
rins    = [s['rin'] for s in per_sample if s['rin'] is not None]
mean_rin = round(sum(rins) / len(rins), 2) if rins else None

summary = {
    'assay_type': assay_type,
    'rin_threshold': rin_thresh,
    'dv200_min_pct': dv200_min,
    'n_samples': n_total,
    'n_pass': n_pass,
    'n_fail': n_total - n_pass,
    'pass_rate_pct': round(100 * n_pass / n_total, 1) if n_total else 0.0,
    'mean_rin': mean_rin,
    'batch_qc_status': 'PASS' if n_pass == n_total and n_total > 0 else 'REVIEW',
}

# -- write outputs -------------------------------------------------------------
with open('rin_per_sample.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['sample', 'RIN', '28S/18S', 'concentration_ng_ul',
                'DV200_pct', 'gate', 'qc_pass', 'fail_reason'])
    for s in per_sample:
        w.writerow([s['sample'], s['rin'], s['rrna_ratio_28s_18s'],
                    s['concentration_ng_ul'], s['dv200_pct'], s['gate'],
                    s['qc_pass'], s['fail_reason']])

with open('rin_qc_results.json', 'w') as f:
    json.dump({'status': 'completed', 'summary': summary,
               'per_sample': per_sample}, f, indent=2)

report = [
    '=== RIN / BIOANALYZER SAMPLE-QC REPORT ===', '',
    f"Assay type:      {assay_type}  (gate on {'DV200' if assay_type.startswith('FFPE') else 'RIN'})",
    f"RIN threshold:   {rin_thresh}   DV200 min: {dv200_min}%",
    f"Samples:         {n_total}",
    f"Pass / Fail:     {n_pass} / {n_total - n_pass}  ({summary['pass_rate_pct']}% pass)",
    f"Mean RIN:        {mean_rin}",
    f"Batch status:    {summary['batch_qc_status']}",
    '', 'Per-sample:',
]
for s in per_sample:
    flag = 'PASS' if s['qc_pass'] else 'FAIL'
    detail = f" [{s['fail_reason']}]" if s['fail_reason'] else ''
    report.append(f"  {s['sample']:12s} RIN={s['rin']}  DV200={s['dv200_pct']}%  {flag}{detail}")

with open('rin_summary.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
rin_bioanalyzer_qc:
  python: "3.10"
  reference: "bioanalyzeR (Bioconductor); Schroeder 2006 RIN algorithm"
EOF
    """
}

workflow RIN_BIOANALYZER_QC_WORKFLOW {
    take: meta_ch
    main: RIN_BIOANALYZER_QC(meta_ch)
    emit:
        results  = RIN_BIOANALYZER_QC.out.results
        table    = RIN_BIOANALYZER_QC.out.table
        summary  = RIN_BIOANALYZER_QC.out.summary
        versions = RIN_BIOANALYZER_QC.out.versions
}

workflow {
    meta = [id: 'rin_qc_run', single_end: false]
    Channel.value(meta) | RIN_BIOANALYZER_QC_WORKFLOW
}
