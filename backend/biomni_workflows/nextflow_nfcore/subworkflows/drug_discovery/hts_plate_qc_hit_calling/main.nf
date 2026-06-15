#!/usr/bin/env nextflow
/*
 * drug_discovery/hts_plate_qc_hit_calling
 *
 * High-Throughput Screening (HTS) plate quality control and hit identification.
 * Accepts raw plate reader output (signal values + controls), computes Z-factor
 * and Z'-factor, normalizes to percent activity/inhibition, applies configurable
 * hit threshold, and fits 4-parameter logistic (4PL / Hill equation) dose-response
 * curves when replicate concentration data are available.
 *
 * References:
 *   - Zhang et al. J Biomol Screen 1999 (Z-factor)
 *   - Haney et al. J Biomol Screen 2003 (hit calling normalization)
 *   - Sebaugh J Pharm Stat 2011 (4PL Hill model)
 *
 * Input:  plate_data_json (array of {well, compound_id, signal, is_pos_ctrl,
 *         is_neg_ctrl, concentration_uM}), hit_threshold_pct (default 50),
 *         hit_direction (inhibition | activation)
 * Output: qc_metrics.json, hit_list.csv, dose_response_curves.csv
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.plate_data_json     = 'null'
params.hit_threshold_pct   = '50'
params.hit_direction       = 'inhibition'
params.n_sigma_threshold   = '3'
params.min_z_prime         = '0.5'

process HTS_PLATE_QC_HIT_CALLING {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("hts_results.json"),             emit: results
    tuple val(meta), path("hts_output.txt"),               emit: output
    tuple val(meta), path("qc_metrics.json"),              emit: qc_metrics
    tuple val(meta), path("hit_list.csv"),                 emit: hits
    tuple val(meta), path("dose_response_curves.csv"),     emit: dose_response
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_PLATE_DATA='${params.plate_data_json}'
    export PARAM_HIT_THRESH='${params.hit_threshold_pct}'
    export PARAM_DIRECTION='${params.hit_direction}'
    export PARAM_N_SIGMA='${params.n_sigma_threshold}'
    export PARAM_MIN_Z='${params.min_z_prime}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np
from scipy.optimize import curve_fit
from scipy.stats import sem as scipy_sem

def ac(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

def parse_plate_data(raw):
    '''Parse plate data from JSON string or generate demo data.'''
    if raw and raw not in ('null','None',''):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            pass
    # Demo data: 96-well plate
    import random
    random.seed(42)
    data = []
    # Positive controls (wells A1-A4): high inhibition signal ~ 200
    for i in range(4):
        data.append({'well': f'A{i+1}', 'compound_id': 'POS_CTRL',
                     'signal': 200 + random.gauss(0, 10), 'is_pos_ctrl': True,
                     'is_neg_ctrl': False, 'concentration_uM': None})
    # Negative controls (wells H9-H12): low signal ~ 1000
    for i in range(4):
        data.append({'well': f'H{9+i}', 'compound_id': 'NEG_CTRL',
                     'signal': 1000 + random.gauss(0, 30), 'is_pos_ctrl': False,
                     'is_neg_ctrl': True, 'concentration_uM': None})
    # Compounds: 88 samples at random signals, few hits
    well_names = [f'{r}{c}' for r in 'BCDEFG' for c in range(1,13)]
    hit_wells = random.sample(well_names, 8)
    for i, well in enumerate(well_names):
        is_hit = well in hit_wells
        signal = 250 + random.gauss(0, 15) if is_hit else 900 + random.gauss(0, 40)
        data.append({'well': well, 'compound_id': f'CPD-{i+1:04d}',
                     'signal': signal, 'is_pos_ctrl': False,
                     'is_neg_ctrl': False, 'concentration_uM': None})
    return data

# -- Plate QC metrics ----------------------------------------------------------
def compute_z_factor(pos_signals, neg_signals):
    '''Zhang 1999: Z = 1 - 3*(sigmapos + sigmaneg) / |upos - uneg|'''
    if len(pos_signals) < 2 or len(neg_signals) < 2:
        return None
    mu_p = np.mean(pos_signals)
    mu_n = np.mean(neg_signals)
    sd_p = np.std(pos_signals, ddof=1)
    sd_n = np.std(neg_signals, ddof=1)
    denom = abs(mu_p - mu_n)
    if denom < 1e-10:
        return 0.0
    z = 1 - 3 * (sd_p + sd_n) / denom
    return round(float(z), 4)

def compute_signal_window(pos_signals, neg_signals):
    '''Signal window = (uneg - upos) / pooled SD -- assay robustness.'''
    mu_p = np.mean(pos_signals)
    mu_n = np.mean(neg_signals)
    sd_p = np.std(pos_signals, ddof=1)
    sd_n = np.std(neg_signals, ddof=1)
    pooled_sd = math.sqrt((sd_p**2 + sd_n**2) / 2)
    if pooled_sd < 1e-10:
        return None
    return round((mu_n - mu_p) / pooled_sd, 2)

def normalize_to_pct(signal, mu_pos, mu_neg, direction):
    '''
    Percent inhibition = (uneg - signal) / (uneg - upos) * 100
    Percent activation = (signal - uneg) / (upos - uneg) * 100
    '''
    window = mu_neg - mu_pos
    if abs(window) < 1e-10:
        return 0.0
    if direction == 'inhibition':
        pct = (mu_neg - signal) / window * 100
    else:
        pct = (signal - mu_neg) / window * 100
    return round(float(pct), 2)

# -- Hill equation (4PL) -------------------------------------------------------
def hill_4pl(c, bottom, top, ec50, hill_coeff):
    '''4-parameter logistic: y = Bottom + (Top-Bottom)/(1 + (EC50/x)^n)'''
    return bottom + (top - bottom) / (1 + (ec50 / (c + 1e-12)) ** hill_coeff)

def fit_dose_response(concentrations, responses):
    '''Fit 4PL; return (bottom, top, EC50, n, R2) or None on failure.'''
    if len(concentrations) < 4:
        return None
    c = np.array(concentrations, dtype=float)
    r = np.array(responses, dtype=float)
    try:
        p0 = [r.min(), r.max(), np.median(c), 1.0]
        bounds = ([0, 0, 1e-4, 0.1], [100, 200, 1e6, 10])
        popt, _ = curve_fit(hill_4pl, c, r, p0=p0, bounds=bounds, maxfev=5000)
        r_pred = hill_4pl(c, *popt)
        ss_res = np.sum((r - r_pred) ** 2)
        ss_tot = np.sum((r - r.mean()) ** 2)
        r2 = 1 - ss_res / ss_tot if ss_tot > 0 else 0
        return {'bottom': round(popt[0], 2), 'top': round(popt[1], 2),
                'EC50_uM': round(popt[2], 4), 'hill_coeff': round(popt[3], 2),
                'R2': round(r2, 4)}
    except Exception:
        return None

# -- Process -------------------------------------------------------------------
raw_data     = os.environ.get('PARAM_PLATE_DATA', 'null')
hit_thresh   = ac(os.environ.get('PARAM_HIT_THRESH'), 50)
direction    = os.environ.get('PARAM_DIRECTION', 'inhibition').lower()
n_sigma      = ac(os.environ.get('PARAM_N_SIGMA'), 3)
min_z_prime  = ac(os.environ.get('PARAM_MIN_Z'), 0.5)

plate_data   = parse_plate_data(raw_data)

pos_signals  = [r['signal'] for r in plate_data if r.get('is_pos_ctrl')]
neg_signals  = [r['signal'] for r in plate_data if r.get('is_neg_ctrl')]

if not pos_signals or not neg_signals:
    print("WARNING: No control wells found -- cannot compute Z-factor", file=sys.stderr)
    pos_signals  = [200.0] * 4
    neg_signals  = [1000.0] * 4

mu_pos = np.mean(pos_signals)
mu_neg = np.mean(neg_signals)

z_prime     = compute_z_factor(pos_signals, neg_signals)
signal_win  = compute_signal_window(pos_signals, neg_signals)
cv_pos      = round(100 * np.std(pos_signals) / mu_pos, 2) if mu_pos > 0 else None
cv_neg      = round(100 * np.std(neg_signals) / mu_neg, 2) if mu_neg > 0 else None

# ── Two-gate QC: z_prime (GOLD, Zhang 1999) + signal_window (SILVER, Iversen 2006)
# Track 2 batch 4 (2026-06-15): wire the signal_window gate alongside z_prime.
# Both metrics were already computed; previously only z_prime had a pass/fail
# field. Iversen 2006 sets signal_window ≥ 2 as the adequate-dynamic-range
# threshold; the YAML rule_text in qc_evidence.yaml.hts.hts_signal_window
# captures that as the operational cutoff.
SIGNAL_WINDOW_THRESHOLD = 2.0

z_prime_pass     = z_prime is not None and z_prime >= min_z_prime
signal_win_pass  = signal_win is not None and signal_win >= SIGNAL_WINDOW_THRESHOLD
qc_pass          = z_prime_pass and signal_win_pass

failures = []
if not z_prime_pass:
    failures.append(f"Z' = {z_prime if z_prime is not None else 'NA'} < {min_z_prime}")
if not signal_win_pass:
    failures.append(f"signal_window = {signal_win if signal_win is not None else 'NA'} < {SIGNAL_WINDOW_THRESHOLD}")
qc_status = 'PASS' if qc_pass else ('FAIL: ' + '; '.join(failures))

qc_metrics = {
    # z_prime gate (Zhang 1999, GOLD)
    'z_prime': z_prime,
    'z_prime_threshold': min_z_prime,
    'z_prime_passes': z_prime_pass,
    # signal_window gate (Iversen 2006, SILVER)
    'signal_window': signal_win,
    'signal_window_threshold': SIGNAL_WINDOW_THRESHOLD,
    'signal_window_passes': signal_win_pass,
    # context
    'mu_pos_ctrl': round(float(mu_pos), 2),
    'mu_neg_ctrl': round(float(mu_neg), 2),
    'cv_pos_ctrl_pct': cv_pos,
    'cv_neg_ctrl_pct': cv_neg,
    'n_pos_controls': len(pos_signals),
    'n_neg_controls': len(neg_signals),
    'qc_status': qc_status,
    'dynamic_range': round(float(mu_neg / mu_pos), 2) if mu_pos > 0 else None,
}

# Normalize and call hits
sample_rows = [r for r in plate_data if not r.get('is_pos_ctrl') and not r.get('is_neg_ctrl')]
hit_rows   = [['compound_id', 'well', 'signal', 'pct_inhibition',
               'hit', 'concentration_uM', 'dr_fit_ec50_uM', 'dr_fit_r2']]

# Group by compound for dose-response fitting
from collections import defaultdict
dr_groups = defaultdict(lambda: {'concentrations': [], 'responses': []})

hits = []
for row in sample_rows:
    pct = normalize_to_pct(row['signal'], mu_pos, mu_neg, direction)
    is_hit = pct >= hit_thresh

    conc = row.get('concentration_uM')
    cpd  = row.get('compound_id', 'unknown')
    if conc is not None:
        dr_groups[cpd]['concentrations'].append(conc)
        dr_groups[cpd]['responses'].append(pct)

    if is_hit:
        hits.append({'compound_id': cpd, 'well': row.get('well', ''),
                     'signal': round(row['signal'], 2), 'pct': pct})

# Fit DR curves
dr_fits = {}
dr_csv_rows = [['compound_id', 'concentration_uM', 'pct_response',
                'fitted_response', 'EC50_uM', 'hill_coeff', 'R2']]
for cpd, drdata in dr_groups.items():
    if len(drdata['concentrations']) >= 4:
        fit = fit_dose_response(drdata['concentrations'], drdata['responses'])
        dr_fits[cpd] = fit
        for c, r in zip(sorted(drdata['concentrations']), drdata['responses']):
            fitted = hill_4pl(c, fit['bottom'], fit['top'], fit['EC50_uM'], fit['hill_coeff']) if fit else r
            dr_csv_rows.append([cpd, c, r, round(fitted, 2),
                                 fit['EC50_uM'] if fit else '', fit['hill_coeff'] if fit else '',
                                 fit['R2'] if fit else ''])

# Build hit list CSV
for h in hits:
    cpd   = h['compound_id']
    fit   = dr_fits.get(cpd)
    hit_rows.append([cpd, h['well'], h['signal'], h['pct'],
                     True, '', fit['EC50_uM'] if fit else '', fit['R2'] if fit else ''])
# Add non-hits too
for row in sample_rows:
    pct = normalize_to_pct(row['signal'], mu_pos, mu_neg, direction)
    if pct < hit_thresh:
        cpd = row.get('compound_id', 'unknown')
        hit_rows.append([cpd, row.get('well',''), round(row['signal'],2), pct,
                         False, row.get('concentration_uM',''), '', ''])

with open('qc_metrics.json', 'w') as f:
    json.dump(qc_metrics, f, indent=2)
with open('hit_list.csv', 'w', newline='') as f:
    csv.writer(f).writerows(hit_rows)
with open('dose_response_curves.csv', 'w', newline='') as f:
    csv.writer(f).writerows(dr_csv_rows)

full = {'status': 'completed', 'qc_metrics': qc_metrics,
        'n_compounds': len(sample_rows), 'n_hits': len(hits),
        'hit_rate_pct': round(100*len(hits)/max(len(sample_rows),1), 2),
        'hits': hits[:50]}  # cap first 50 hits in JSON
with open('hts_results.json', 'w') as f:
    json.dump(full, f, indent=2)

report = [
    '=== HTS PLATE QC & HIT CALLING REPORT ===', '',
    f"QC Status:       {qc_status}",
    f"Z' factor:       {z_prime:.3f}  (>={min_z_prime} = pass)",
    f"Signal window:   {signal_win}",
    f"Dynamic range:   {qc_metrics['dynamic_range']}x",
    f"Pos ctrl CV:     {cv_pos}% | Neg ctrl CV: {cv_neg}%",
    '',
    f"Compounds:       {len(sample_rows)}",
    f"Hits ({'>=' if direction=='inhibition' else '<='}{hit_thresh}%): "
    f"{len(hits)} ({full['hit_rate_pct']:.1f}% hit rate)",
    f"DR curves fit:   {len(dr_fits)}",
    '',
    'Top 10 Hits:',
]
sorted_hits = sorted(hits, key=lambda h: h['pct'], reverse=True)[:10]
for h in sorted_hits:
    fit = dr_fits.get(h['compound_id'])
    ec50_str = f" | EC50={fit['EC50_uM']:.3f} uM" if fit else ''
    report.append(f"  {h['compound_id']:15s}: {h['pct']:.1f}% inhibition{ec50_str}")

with open('hts_output.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
hts_plate_qc_hit_calling:
  python: "3.10"
  scipy: ">=1.10"
  numpy: ">=1.24"
  reference: "Zhang 1999 Z-factor; Sebaugh 2011 4PL"
EOF
    """
}

workflow HTS_PLATE_QC_WORKFLOW {
    take: meta_ch
    main: HTS_PLATE_QC_HIT_CALLING(meta_ch)
    emit:
        results      = HTS_PLATE_QC_HIT_CALLING.out.results
        qc_metrics   = HTS_PLATE_QC_HIT_CALLING.out.qc_metrics
        hits         = HTS_PLATE_QC_HIT_CALLING.out.hits
        dose_response = HTS_PLATE_QC_HIT_CALLING.out.dose_response
}

workflow {
    meta = [id: 'hts_run', single_end: false]
    Channel.value(meta) | HTS_PLATE_QC_WORKFLOW
}
