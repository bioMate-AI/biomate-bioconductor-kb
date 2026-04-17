#!/usr/bin/env nextflow
/*
 * pharmacology/exposure_response_modelling
 *
 * Fits Emax/Emin exposure-response (E-R) models to clinical or preclinical
 * PK-PD data. Supports Emax (sigmoid Hill), linear, and power-law E-R models.
 * Outputs EC50, Emax, Hill coefficient, E-R safety margin (TEC/EC50), and
 * dose recommendations to achieve target exposure percentages.
 *
 * Applications: Phase I dose optimisation, benefit-risk E-R analysis,
 * clinical Phase II Go/No-Go decisions, PopPK/PD dosing.
 *
 * References:
 *   - Mager & Jusko Pharm Res 2001 (E-R modelling primer)
 *   - FDA E-R analysis guidance 2019
 *   - Thomas et al. CPT:PSP 2014 (translational E-R)
 *
 * Input:  er_data_json [{exposure_metric, effect, compound_id, dose_mg}],
 *         er_model (emax | linear | power), target_effect_pct,
 *         safety_exposure_uM (TEC for safety margin)
 * Output: er_parameters.json, er_curve.csv, dose_recommendation.json
 */

nextflow.enable.dsl = 2

params.outdir               = './results'
params.er_data_json         = 'null'
params.er_model             = 'emax'
params.target_effect_pct    = '80'
params.safety_exposure_uM   = 'null'
params.exposure_metric      = 'AUC_ug_L_h'
params.efficacy_endpoint    = 'tumor_shrinkage_pct'

process EXPOSURE_RESPONSE_MODELLING {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("er_results.json"),              emit: results
    tuple val(meta), path("er_output.txt"),                emit: output
    tuple val(meta), path("er_parameters.json"),           emit: er_params
    tuple val(meta), path("er_curve.csv"),                 emit: er_curve
    tuple val(meta), path("dose_recommendation.json"),     emit: dose_rec
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_ER_DATA='${params.er_data_json}'
    export PARAM_MODEL='${params.er_model}'
    export PARAM_TARGET_PCT='${params.target_effect_pct}'
    export PARAM_SAFETY_EXP='${params.safety_exposure_uM}'
    export PARAM_EXP_METRIC='${params.exposure_metric}'
    export PARAM_ENDPOINT='${params.efficacy_endpoint}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np
from scipy.optimize import curve_fit
from scipy.stats import pearsonr

def ac(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

def parse_er_data(raw):
    '''Parse E-R dataset from JSON or generate synthetic Phase I data.'''
    if raw and raw not in ('null','None',''):
        try:
            return json.loads(raw)
        except: pass
    # Synthetic demo: dose escalation E-R (sigmoidal)
    doses    = [10, 20, 40, 80, 160, 320, 640]
    exposures= [18, 39, 82, 175, 330, 580, 890]
    import random; random.seed(99)
    data = []
    for d, e in zip(doses, exposures):
        # True Emax=70, EC50=200, Hill=1.2
        true_eff = 70 * (e**1.2) / (200**1.2 + e**1.2)
        for _ in range(3):  # 3 replicates per dose
            noise = random.gauss(0, 5)
            data.append({'compound_id': 'CompoundA', 'dose_mg': d,
                         'exposure_metric': e + random.gauss(0,10),
                         'effect': max(0, true_eff + noise)})
    return data

# -- Emax model (Hill equation) ------------------------------------------------
def emax_model(E, emax, ec50, hill):
    '''Effect = Emax * E^hill / (EC50^hill + E^hill)'''
    E = np.array(E, dtype=float)
    return emax * E**hill / (ec50**hill + E**hill)

def linear_model(E, slope, intercept):
    return slope * np.array(E) + intercept

def power_model(E, a, b):
    return a * np.array(E) ** b

def fit_emax(exposures, effects):
    try:
        n = len(exposures)
        if n < 4: return None, None
        e = np.array(exposures, dtype=float)
        r = np.array(effects, dtype=float)
        emax0 = r.max() * 1.1
        ec50_0 = np.median(e)
        p0 = [emax0, ec50_0, 1.0]
        bounds = ([0, 0.001, 0.1], [500, 1e6, 10])
        popt, pcov = curve_fit(emax_model, e, r, p0=p0, bounds=bounds, maxfev=10000)
        r_pred = emax_model(e, *popt)
        ss_res = np.sum((r - r_pred)**2)
        ss_tot = np.sum((r - r.mean())**2)
        r2 = 1 - ss_res/ss_tot if ss_tot > 0 else 0
        se = np.sqrt(np.diag(pcov))
        return popt, {'R2': round(r2, 4), 'se': se.tolist(),
                      'n': n, 'ss_res': round(ss_res, 3)}
    except Exception as ex:
        print(f"WARNING: Emax fit failed: {ex}", file=sys.stderr)
        return None, None

def fit_linear(exposures, effects):
    try:
        e = np.array(exposures, dtype=float)
        r = np.array(effects, dtype=float)
        popt, _ = curve_fit(linear_model, e, r, p0=[0.1, 0])
        r_pred = linear_model(e, *popt)
        r2 = 1 - np.sum((r-r_pred)**2)/np.sum((r-r.mean())**2)
        return popt, {'R2': round(r2,4), 'n': len(e)}
    except: return None, None

def fit_power(exposures, effects):
    try:
        e = np.array(exposures, dtype=float)
        r = np.array(effects, dtype=float)
        r = np.maximum(r, 0.01)
        popt, _ = curve_fit(power_model, e, r, p0=[1, 0.5], bounds=([0,0],[1000,3]))
        r_pred = power_model(e, *popt)
        r2 = 1 - np.sum((r-r_pred)**2)/np.sum((r-r.mean())**2)
        return popt, {'R2': round(r2,4), 'n': len(e)}
    except: return None, None

def exposure_for_target(pct_target, popt, model):
    '''Invert the E-R model to find exposure achieving pct_target effect.'''
    if popt is None: return None
    if model == 'emax':
        emax, ec50, hill = popt
        if pct_target >= emax: return None
        # E = EC50 * (E_target / (Emax - E_target))^(1/hill)
        ratio = pct_target / (emax - pct_target)
        if ratio <= 0: return None
        return round(ec50 * ratio**(1/hill), 2)
    elif model == 'linear':
        slope, intercept = popt
        if slope <= 0: return None
        return round((pct_target - intercept) / slope, 2)
    elif model == 'power':
        a, b = popt
        if a <= 0 or b <= 0: return None
        return round((pct_target / a)**(1/b), 2)
    return None

# -- Process -------------------------------------------------------------------
raw_data    = os.environ.get('PARAM_ER_DATA', 'null')
model_type  = os.environ.get('PARAM_MODEL', 'emax').lower()
target_pct  = ac(os.environ.get('PARAM_TARGET_PCT'), 80)
safety_exp  = ac(os.environ.get('PARAM_SAFETY_EXP'))
exp_metric  = os.environ.get('PARAM_EXP_METRIC', 'AUC')
endpoint    = os.environ.get('PARAM_ENDPOINT', 'effect_pct')

er_data = parse_er_data(raw_data)
exposures = [d['exposure_metric'] for d in er_data if 'exposure_metric' in d]
effects   = [d['effect']          for d in er_data if 'effect' in d]
doses     = [d.get('dose_mg', None) for d in er_data]

if not exposures or len(exposures) < 3:
    print("ERROR: insufficient data points for E-R fitting (need >=3)", file=sys.stderr)
    sys.exit(1)

# Fit model
if model_type == 'emax':
    popt, fit_stats = fit_emax(exposures, effects)
    if popt is not None:
        emax_val, ec50_val, hill_val = popt
        params_out = {'Emax': round(emax_val, 2), 'EC50': round(ec50_val, 2),
                      'Hill_coeff': round(hill_val, 3), 'model': 'Emax (Hill)',
                      'exposure_metric': exp_metric}
    else:
        # Fallback linear
        popt, fit_stats = fit_linear(exposures, effects)
        params_out = {'slope': round(popt[0],4) if popt is not None else None,
                      'intercept': round(popt[1],4) if popt is not None else None,
                      'model': 'linear (Emax fallback)', 'exposure_metric': exp_metric}
        model_type = 'linear'
elif model_type == 'linear':
    popt, fit_stats = fit_linear(exposures, effects)
    params_out = {'slope': round(popt[0],4) if popt is not None else None,
                  'intercept': round(popt[1],4) if popt is not None else None,
                  'model': 'linear', 'exposure_metric': exp_metric}
elif model_type == 'power':
    popt, fit_stats = fit_power(exposures, effects)
    params_out = {'a': round(popt[0],4) if popt is not None else None,
                  'b': round(popt[1],4) if popt is not None else None,
                  'model': 'power law', 'exposure_metric': exp_metric}
else:
    popt, fit_stats = fit_emax(exposures, effects)
    model_type = 'emax'
    params_out = {}

if fit_stats:
    params_out.update(fit_stats)

# E-R curve points for plotting
exp_range  = np.linspace(min(exposures)*0.1, max(exposures)*2, 200)
if model_type == 'emax' and popt is not None:
    pred = emax_model(exp_range, *popt)
elif model_type == 'linear' and popt is not None:
    pred = linear_model(exp_range, *popt)
elif model_type == 'power' and popt is not None:
    pred = power_model(exp_range, *popt)
else:
    pred = np.zeros(200)

er_csv = [['exposure', 'predicted_effect', 'observed_effect', 'dose_mg']]
for i, (e_pt, p_pt) in enumerate(zip(exp_range, pred)):
    er_csv.append([round(e_pt, 2), round(float(p_pt), 3), '', ''])
for e_obs, eff_obs, d_obs in zip(exposures, effects, doses):
    er_csv.append([round(e_obs,2), '', round(eff_obs,2), d_obs or ''])

# Dose recommendations
targets = [50, target_pct, 90]
dose_recs = []
for t in targets:
    e_target = exposure_for_target(t, popt, model_type)
    dose_recs.append({
        f'E{t:.0f}_exposure': e_target,
        f'E{t:.0f}_label': f'{t:.0f}% of max effect',
        'exposure_metric': exp_metric,
    })

# Safety margin
safety_margin = None
safety_flag = None
if safety_exp and popt is not None and model_type == 'emax':
    emax_val, ec50_val, hill_val = popt
    effect_at_tec = emax_model([safety_exp], emax_val, ec50_val, hill_val)[0]
    e_target_exp = exposure_for_target(target_pct, popt, model_type)
    if e_target_exp:
        safety_margin = round(safety_exp / e_target_exp, 2)
        if safety_margin >= 10: safety_flag = 'ADEQUATE (>=10x margin)'
        elif safety_margin >= 3: safety_flag = 'ACCEPTABLE (3-10x; confirm in Phase I)'
        else: safety_flag = 'NARROW (<3x; dose-limiting toxicity risk)'

dose_rec_out = {
    'model': params_out.get('model', model_type),
    'R2': fit_stats.get('R2') if fit_stats else None,
    'target_exposures': dose_recs,
    'safety_margin_TEC_over_E{:.0f}'.format(target_pct): safety_margin,
    'safety_flag': safety_flag,
    'data_points_used': len(exposures),
    'endpoint': endpoint,
    'exposure_metric': exp_metric,
}

with open('er_parameters.json', 'w') as f:
    json.dump(params_out, f, indent=2)
with open('er_curve.csv', 'w', newline='') as f:
    csv.writer(f).writerows(er_csv)
with open('dose_recommendation.json', 'w') as f:
    json.dump(dose_rec_out, f, indent=2)
with open('er_results.json', 'w') as f:
    json.dump({'status': 'completed', 'parameters': params_out,
               'dose_recommendations': dose_recs, 'safety_margin': safety_margin}, f, indent=2)

r2_str = f"R2={fit_stats['R2']:.3f}" if fit_stats and fit_stats.get('R2') else 'R2=N/A'
report = ['=== EXPOSURE-RESPONSE MODELLING REPORT ===', '',
          f"Model: {params_out.get('model','unknown')} | {r2_str} | n={len(exposures)} obs",
          f"Endpoint: {endpoint} | Exposure metric: {exp_metric}", '']
if model_type == 'emax' and popt is not None:
    report += [f"Emax:  {params_out.get('Emax')} % effect",
               f"EC50:  {params_out.get('EC50')} {exp_metric}",
               f"Hill:  {params_out.get('Hill_coeff')}", '']
report.append('Target exposures:')
for dr in dose_recs:
    for k, v in dr.items():
        if 'exposure' in k and v:
            label_k = k.replace('_exposure','')
            report.append(f"  {label_k}: {v} {exp_metric}")
if safety_margin:
    report += ['', f"Safety margin (TEC/{target_pct}% dose): {safety_margin}x -- {safety_flag}"]

with open('er_output.txt', 'w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
exposure_response_modelling:
  python: "3.10"
  scipy: ">=1.10"
  numpy: ">=1.24"
  reference: "Mager & Jusko 2001; FDA E-R guidance 2019"
EOF
    """
}

workflow EXPOSURE_RESPONSE_WORKFLOW {
    take: meta_ch
    main: EXPOSURE_RESPONSE_MODELLING(meta_ch)
    emit:
        results  = EXPOSURE_RESPONSE_MODELLING.out.results
        er_params = EXPOSURE_RESPONSE_MODELLING.out.er_params
        er_curve = EXPOSURE_RESPONSE_MODELLING.out.er_curve
        dose_rec = EXPOSURE_RESPONSE_MODELLING.out.dose_rec
}

workflow {
    meta = [id: 'er_model_run', single_end: false]
    Channel.value(meta) | EXPOSURE_RESPONSE_WORKFLOW
}
