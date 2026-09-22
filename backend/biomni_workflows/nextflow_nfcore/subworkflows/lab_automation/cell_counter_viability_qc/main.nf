#!/usr/bin/env nextflow
/*
 * lab_automation/cell_counter_viability_qc
 *
 * Automated cell-counter sample-QC parser.
 * Ingests a CSV export from an automated cell counter (e.g. Countess 3 / 3 FL,
 * LUNA, Cellometer, NucleoCounter, Vi-CELL) with per-sample
 * {sample, total|live|dead cells/mL, viability %, mean diameter um} and
 * produces a tidy per-sample QC table + a summary with a viability pass/fail
 * gate and a live-cell-concentration floor. Viability and live concentration
 * are recomputed from live/dead counts when the vendor export omits the
 * derived columns.
 *
 * Falls back to demo data when no input is supplied, matching the sibling
 * drug_discovery/hts_plate_qc_hit_calling idiom.
 *
 * Input:  cellcount_csv (path to cell-counter CSV export),
 *         viability_min_pct (default 80.0),
 *         min_live_conc (cells/mL, default 100000.0),
 *         diameter_min_um / diameter_max_um (advisory size window; defaults 5-30)
 * Output: cellcount_qc_results.json, cellcount_per_sample.csv,
 *         cellcount_summary.txt, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir             = './results'
params.cellcount_csv      = 'null'
params.viability_min_pct  = '80.0'
params.min_live_conc      = '100000.0'
params.diameter_min_um    = '5.0'
params.diameter_max_um    = '30.0'

process CELL_COUNTER_VIABILITY_QC {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("cellcount_qc_results.json"), emit: results
    tuple val(meta), path("cellcount_per_sample.csv"),  emit: table
    tuple val(meta), path("cellcount_summary.txt"),     emit: summary
    path "versions.yml",                                emit: versions

    script:
    """
    export PARAM_CSV='${params.cellcount_csv}'
    export PARAM_VIAB_MIN='${params.viability_min_pct}'
    export PARAM_MIN_LIVE='${params.min_live_conc}'
    export PARAM_DIAM_MIN='${params.diameter_min_um}'
    export PARAM_DIAM_MAX='${params.diameter_max_um}'

    python3 << 'PYEOF'
import json, os, csv, sys, io

def ac(v, default=None):
    if v in (None, '', 'null', 'None'):
        return default
    try:
        return float(str(v).replace(',', ''))
    except (TypeError, ValueError):
        return default

# Cell-counter firmwares emit several header spellings.
SAMPLE_KEYS = ['sample', 'sample name', 'sample id', 'name', 'well', 'id']
TOTAL_KEYS  = ['total cells/ml', 'total (cells/ml)', 'total conc', 'total',
               'total cells', 'concentration', 'cells/ml']
LIVE_KEYS   = ['live cells/ml', 'live (cells/ml)', 'live conc', 'live',
               'viable cells/ml', 'viable', 'live cells']
DEAD_KEYS   = ['dead cells/ml', 'dead (cells/ml)', 'dead', 'dead cells',
               'nonviable', 'non-viable']
VIAB_KEYS   = ['viability', 'viability %', 'viability (%)', '% viability',
               'viable %', 'pct_viable']
DIAM_KEYS   = ['diameter', 'mean diameter', 'mean diameter (um)',
               'mean diameter um', 'avg diameter', 'size', 'diameter (um)']

def find_key(row, candidates):
    for cand in candidates:
        if cand in row:
            return row[cand]
    return None

def parse_csv(raw):
    '''Parse the cell-counter CSV export string; demo data if absent.'''
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
                if any(k in low for k in ('sample', 'viability', 'cells/ml', 'live')) and ',' in ln:
                    hdr_idx = i
                    break
            reader = csv.DictReader(io.StringIO('\\n'.join(lines[hdr_idx:])))
            rows = []
            for r in reader:
                rows.append({(k or '').strip().lower(): (v or '').strip()
                             for k, v in r.items()})
            if rows:
                return rows
    # Demo data: 5 samples, mixed viability and one over-clumped/oversized.
    return [
        {'sample': 'CELL_01', 'total cells/ml': '2.10e6', 'live cells/ml': '2.00e6', 'dead cells/ml': '1.0e5', 'viability': '95.2', 'mean diameter': '14.1'},
        {'sample': 'CELL_02', 'total cells/ml': '1.50e6', 'live cells/ml': '1.35e6', 'dead cells/ml': '1.5e5', 'viability': '90.0', 'mean diameter': '13.4'},
        {'sample': 'CELL_03', 'total cells/ml': '9.0e5',  'live cells/ml': '6.8e5',  'dead cells/ml': '2.2e5', 'viability': '75.6', 'mean diameter': '12.9'},
        {'sample': 'CELL_04', 'total cells/ml': '4.0e4',  'live cells/ml': '3.6e4',  'dead cells/ml': '4.0e3', 'viability': '90.0', 'mean diameter': '15.0'},
        {'sample': 'CELL_05', 'total cells/ml': '1.8e6',  'live cells/ml': '1.6e6',  'dead cells/ml': '2.0e5', 'viability': '88.9', 'mean diameter': '34.5'},
    ]

# -- params --------------------------------------------------------------------
raw_csv    = os.environ.get('PARAM_CSV', 'null')
viab_min   = ac(os.environ.get('PARAM_VIAB_MIN'), 80.0)
min_live   = ac(os.environ.get('PARAM_MIN_LIVE'), 100000.0)
diam_min   = ac(os.environ.get('PARAM_DIAM_MIN'), 5.0)
diam_max   = ac(os.environ.get('PARAM_DIAM_MAX'), 30.0)

rows = parse_csv(raw_csv)

per_sample = []
for row in rows:
    sample = (find_key(row, SAMPLE_KEYS) or f"sample_{len(per_sample)+1}").strip() or f"sample_{len(per_sample)+1}"
    total  = ac(find_key(row, TOTAL_KEYS))
    live   = ac(find_key(row, LIVE_KEYS))
    dead   = ac(find_key(row, DEAD_KEYS))
    viab   = ac(find_key(row, VIAB_KEYS))
    diam   = ac(find_key(row, DIAM_KEYS))

    # Recompute derived fields when the vendor export omits them.
    if viab is None and live is not None and total is not None and total > 0:
        viab = round(100.0 * live / total, 1)
    if viab is None and live is not None and dead is not None and (live + dead) > 0:
        viab = round(100.0 * live / (live + dead), 1)
    if live is None and total is not None and viab is not None:
        live = round(total * viab / 100.0, 1)

    reasons = []
    viab_ok = viab is not None and viab >= viab_min
    if not viab_ok:
        reasons.append(f"viability={viab if viab is not None else 'NA'}% < {viab_min}%")
    live_ok = live is not None and live >= min_live
    if not live_ok:
        reasons.append(f"live_conc={live if live is not None else 'NA'} < {min_live} cells/mL")
    # Size is advisory: out-of-window flags clumping / debris but only warns.
    diam_ok = diam is None or (diam_min <= diam <= diam_max)
    diam_warn = ''
    if diam is not None and not diam_ok:
        diam_warn = f"diameter={diam}um outside {diam_min}-{diam_max}um"

    passed = bool(viab_ok and live_ok)
    per_sample.append({
        'sample': sample, 'total_cells_ml': total, 'live_cells_ml': live,
        'dead_cells_ml': dead, 'viability_pct': viab, 'mean_diameter_um': diam,
        'qc_pass': passed,
        'fail_reason': '; '.join(reasons) if reasons else '',
        'size_warning': diam_warn,
    })

n_total = len(per_sample)
n_pass  = sum(1 for s in per_sample if s['qc_pass'])
viabs   = [s['viability_pct'] for s in per_sample if s['viability_pct'] is not None]
mean_viab = round(sum(viabs) / len(viabs), 1) if viabs else None

summary = {
    'viability_min_pct': viab_min,
    'min_live_conc_cells_ml': min_live,
    'diameter_window_um': [diam_min, diam_max],
    'n_samples': n_total,
    'n_pass': n_pass,
    'n_fail': n_total - n_pass,
    'pass_rate_pct': round(100 * n_pass / n_total, 1) if n_total else 0.0,
    'mean_viability_pct': mean_viab,
    'batch_qc_status': 'PASS' if n_pass == n_total and n_total > 0 else 'REVIEW',
}

# -- write outputs -------------------------------------------------------------
with open('cellcount_per_sample.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['sample', 'total_cells_ml', 'live_cells_ml', 'dead_cells_ml',
                'viability_pct', 'mean_diameter_um', 'qc_pass', 'fail_reason',
                'size_warning'])
    for s in per_sample:
        w.writerow([s['sample'], s['total_cells_ml'], s['live_cells_ml'],
                    s['dead_cells_ml'], s['viability_pct'],
                    s['mean_diameter_um'], s['qc_pass'], s['fail_reason'],
                    s['size_warning']])

with open('cellcount_qc_results.json', 'w') as f:
    json.dump({'status': 'completed', 'summary': summary,
               'per_sample': per_sample}, f, indent=2)

report = [
    '=== AUTOMATED CELL-COUNTER VIABILITY-QC REPORT ===', '',
    f"Viability min:   {viab_min}%   Live-conc min: {min_live} cells/mL",
    f"Diameter window: {diam_min}-{diam_max} um (advisory)",
    f"Samples:         {n_total}",
    f"Pass / Fail:     {n_pass} / {n_total - n_pass}  ({summary['pass_rate_pct']}% pass)",
    f"Mean viability:  {mean_viab}%",
    f"Batch status:    {summary['batch_qc_status']}",
    '', 'Per-sample:',
]
for s in per_sample:
    flag = 'PASS' if s['qc_pass'] else 'FAIL'
    detail = f" [{s['fail_reason']}]" if s['fail_reason'] else ''
    warn = f" (!{s['size_warning']})" if s['size_warning'] else ''
    report.append(
        f"  {s['sample']:12s} viab={s['viability_pct']}%  "
        f"live={s['live_cells_ml']}  {flag}{detail}{warn}")

with open('cellcount_summary.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
cell_counter_viability_qc:
  python: "3.10"
  reference: "Trypan-blue dye-exclusion viability; automated cell-counter CSV export"
EOF
    """
}

workflow CELL_COUNTER_VIABILITY_QC_WORKFLOW {
    take: meta_ch
    main: CELL_COUNTER_VIABILITY_QC(meta_ch)
    emit:
        results  = CELL_COUNTER_VIABILITY_QC.out.results
        table    = CELL_COUNTER_VIABILITY_QC.out.table
        summary  = CELL_COUNTER_VIABILITY_QC.out.summary
        versions = CELL_COUNTER_VIABILITY_QC.out.versions
}

workflow {
    meta = [id: 'cellcount_qc_run', single_end: false]
    Channel.value(meta) | CELL_COUNTER_VIABILITY_QC_WORKFLOW
}
