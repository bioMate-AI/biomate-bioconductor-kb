#!/usr/bin/env nextflow
/*
 * pharmacology/exposure_response_modeling
 *
 * Fits a sigmoid Emax/Hill exposure-response (E-R) model to patient
 * concentration-effect data and produces parameters that feed directly into
 * the phase2_dose_justification workflow.
 *
 * This workflow bridges population PK outputs and Phase II dose justification:
 *
 *   Chain: nlmixr2_population_pk → (individual AUC predictions) →
 *          exposure_response_modeling → phase2_dose_justification
 *
 *   Individual AUC predictions come from the nlmixr2 individual_ebv output CSV
 *   (eta predictions × population params). Merge those AUC values with observed
 *   effect data, supply as --patient_data_csv, and the fitted er_params.json
 *   can be passed directly to phase2_dose_justification --er_params_json.
 *
 * Model:
 *   effect_pct = Emax * AUC^hill / (EC50^hill + AUC^hill)
 *
 * Fitting strategy:
 *   - scipy.optimize.curve_fit (Levenberg-Marquardt / Trust Region Reflective)
 *   - Bootstrap resampling (default 200 replicates) for 95% CI on all parameters
 *   - If --emax_fixed is non-zero, Emax is held fixed and only EC50 + Hill are fit
 *   - Identifiability check: warns when data do not span more than 1/3 of the
 *     saturation plateau (AUC_max / EC50 < 2.0)
 *
 * References:
 *   - Holford NH & Sheiner LB. Pharmacol Ther. 1982;10(2):143-166.
 *     (original Emax model derivation)
 *   - Gabrielsson J & Weiner D. Pharmacokinetic/Pharmacodynamic Data Analysis.
 *     4th ed. Swedish Pharmaceutical Press, 2006. (Hill model fitting practice)
 *   - FDA. Exposure-Response Relationships -- Study Design, Data Analysis, and
 *     Regulatory Applications. CDER/CBER, 2023.
 *     https://www.fda.gov/media/128793/download
 *   - Bonate PL. Pharmacokinetic-Pharmacodynamic Modeling and Simulation.
 *     2nd ed. Springer, 2011. (bootstrap CI for PK/PD models)
 *
 * Input CSV format (--patient_data_csv):
 *   Required columns: patient_id, dose_mg, auc_obs, effect_pct, timepoint
 *   The 'auc_obs' column is used as the exposure metric by default.
 *   If --exposure_metric is set, that column name is used instead.
 *
 * Outputs:
 *   er_params.json         -- feeds directly into phase2_dose_justification
 *                             --er_params_json (keys: ec50_uM, emax_pct, hill,
 *                             r_squared, and 95% CI bounds)
 *   er_fit_report.txt      -- human-readable fit quality summary
 *   er_dose_response.csv   -- predicted vs observed per patient
 */

nextflow.enable.dsl = 2

params.outdir           = './results'
params.patient_data_csv = null
params.exposure_metric  = 'AUC_ug_L_h'
params.emax_fixed       = '0'         // 0 = estimate from data; >0 = fix to this value
params.hill_bounds      = '0.5,4.0'   // min,max for Hill coefficient
params.bootstrap_n      = '200'
params.compound_name    = 'Compound'

if (!params.patient_data_csv) {
    error "Please provide --patient_data_csv (CSV with patient_id, dose_mg, auc_obs, effect_pct, timepoint)"
}

process EXPOSURE_RESPONSE_MODELING {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)
    path(patient_data)

    output:
    tuple val(meta), path("er_params.json"),          emit: er_params
    tuple val(meta), path("er_fit_report.txt"),        emit: report
    tuple val(meta), path("er_dose_response.csv"),     emit: dose_response
    tuple val(meta), path("er_modeling_output.txt"),   emit: output
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_CSV='${patient_data}'
    export PARAM_EXP_METRIC='${params.exposure_metric}'
    export PARAM_EMAX_FIXED='${params.emax_fixed}'
    export PARAM_HILL_BOUNDS='${params.hill_bounds}'
    export PARAM_BOOTSTRAP_N='${params.bootstrap_n}'
    export PARAM_COMPOUND='${params.compound_name}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np
import pandas as pd
from scipy.optimize import curve_fit

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def ac(v, default=None):
    '''Parse numeric env var with graceful fallback.'''
    if v in (None, '', 'null', 'None'):
        return default
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def emax_hill(auc, emax, ec50, hill):
    """
    Sigmoid Hill (Emax) model.
    effect_pct = Emax * AUC^hill / (EC50^hill + AUC^hill)
    """
    auc = np.asarray(auc, dtype=float)
    auc = np.maximum(auc, 0.0)
    return emax * (auc ** hill) / (ec50 ** hill + auc ** hill)


def emax_hill_fixed_emax(auc, ec50, hill, emax_fixed):
    """Emax-fixed variant: only EC50 and Hill are free."""
    return emax_hill(auc, emax_fixed, ec50, hill)


def r_squared(y_obs, y_pred):
    """Coefficient of determination."""
    y_obs = np.asarray(y_obs, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    ss_res = np.sum((y_obs - y_pred) ** 2)
    ss_tot = np.sum((y_obs - np.mean(y_obs)) ** 2)
    if ss_tot < 1e-12:
        return 1.0 if ss_res < 1e-12 else 0.0
    return float(1.0 - ss_res / ss_tot)


def rmse(y_obs, y_pred):
    return float(np.sqrt(np.mean((np.asarray(y_obs) - np.asarray(y_pred)) ** 2)))


# ---------------------------------------------------------------------------
# Read environment
# ---------------------------------------------------------------------------

csv_path      = os.environ.get('PARAM_CSV', 'patient_data.csv')
exp_metric    = os.environ.get('PARAM_EXP_METRIC', 'AUC_ug_L_h').strip()
emax_fixed    = ac(os.environ.get('PARAM_EMAX_FIXED', '0'), 0.0)
hill_bounds_s = os.environ.get('PARAM_HILL_BOUNDS', '0.5,4.0')
bootstrap_n   = int(ac(os.environ.get('PARAM_BOOTSTRAP_N', '200'), 200))
compound      = os.environ.get('PARAM_COMPOUND', 'Compound').strip()

try:
    hmin, hmax = [float(x.strip()) for x in hill_bounds_s.split(',')]
except (ValueError, AttributeError):
    hmin, hmax = 0.5, 4.0

fix_emax = emax_fixed > 0.0

# ---------------------------------------------------------------------------
# Load patient data
# ---------------------------------------------------------------------------

try:
    df = pd.read_csv(csv_path)
except Exception as e:
    print(f"ERROR: Cannot read patient_data_csv ({e})", file=sys.stderr)
    sys.exit(1)

# Normalise column names (lowercase, strip whitespace)
df.columns = [c.strip().lower() for c in df.columns]

# Resolve exposure column: prefer exact match of exp_metric (lowercased),
# then fall back to 'auc_obs', then first numeric column that isn't effect_pct
exp_col = exp_metric.lower()
if exp_col not in df.columns:
    if 'auc_obs' in df.columns:
        exp_col = 'auc_obs'
    else:
        numeric_cols = [c for c in df.columns
                        if df[c].dtype in (float, int) and c not in ('effect_pct', 'dose_mg')]
        if numeric_cols:
            exp_col = numeric_cols[0]
            print(f"WARNING: exposure column '{exp_metric}' not found; using '{exp_col}'",
                  file=sys.stderr)
        else:
            print("ERROR: Cannot identify an exposure column in the CSV.", file=sys.stderr)
            sys.exit(1)

if 'effect_pct' not in df.columns:
    print("ERROR: CSV must contain 'effect_pct' column.", file=sys.stderr)
    sys.exit(1)

# Drop rows with NaN in key columns
df = df.dropna(subset=[exp_col, 'effect_pct'])
auc_vals    = df[exp_col].values.astype(float)
effect_vals = df['effect_pct'].values.astype(float)
n_patients  = len(df['patient_id'].unique()) if 'patient_id' in df.columns else len(df)

print(f"INFO: Loaded {len(df)} rows from {n_patients} patients. "
      f"Exposure column: '{exp_col}'", file=sys.stderr)
print(f"INFO: AUC range: [{auc_vals.min():.2f}, {auc_vals.max():.2f}] | "
      f"Effect range: [{effect_vals.min():.1f}%, {effect_vals.max():.1f}%]",
      file=sys.stderr)

if len(auc_vals) < 4:
    print("ERROR: Need at least 4 observations for E-R fitting.", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Initial parameter guesses and bounds
# ---------------------------------------------------------------------------

emax_obs  = float(effect_vals.max()) * 1.15   # inflate slightly; true Emax > observed max
ec50_init = float(np.median(auc_vals))
hill_init = 1.2

if fix_emax:
    # Free params: [ec50, hill]
    p0     = [ec50_init, hill_init]
    lo     = [1e-6, hmin]
    hi     = [auc_vals.max() * 20.0, hmax]
    fit_fn = lambda auc, ec50, hill: emax_hill_fixed_emax(auc, ec50, hill, emax_fixed)
else:
    # Free params: [emax, ec50, hill]
    p0     = [emax_obs, ec50_init, hill_init]
    lo     = [effect_vals.max() * 0.5, 1e-6, hmin]
    hi     = [200.0, auc_vals.max() * 20.0, hmax]
    fit_fn = emax_hill

# ---------------------------------------------------------------------------
# Primary fit
# ---------------------------------------------------------------------------

try:
    popt, pcov = curve_fit(
        fit_fn, auc_vals, effect_vals,
        p0=p0, bounds=(lo, hi),
        maxfev=20000,
    )
except RuntimeError as e:
    print(f"ERROR: curve_fit did not converge: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: curve_fit failed: {e}", file=sys.stderr)
    sys.exit(1)

if fix_emax:
    ec50_fit, hill_fit = popt
    emax_fit = emax_fixed
else:
    emax_fit, ec50_fit, hill_fit = popt

pred_vals = emax_hill(auc_vals, emax_fit, ec50_fit, hill_fit)
r2_fit    = r_squared(effect_vals, pred_vals)
rmse_fit  = rmse(effect_vals, pred_vals)

print(f"INFO: Primary fit — Emax={emax_fit:.2f}%, EC50={ec50_fit:.4f}, "
      f"Hill={hill_fit:.4f}, R²={r2_fit:.4f}, RMSE={rmse_fit:.3f}",
      file=sys.stderr)

# Identifiability warning
auc_max_ratio = auc_vals.max() / ec50_fit if ec50_fit > 0 else 0.0
if auc_max_ratio < 2.0:
    print(f"WARNING: AUC_max/EC50 = {auc_max_ratio:.2f} < 2.0. "
          "Data may not span enough of the saturation plateau to reliably estimate "
          "Emax and EC50 simultaneously. Consider fixing Emax via --emax_fixed.",
          file=sys.stderr)

# ---------------------------------------------------------------------------
# Bootstrap 95% confidence intervals
# ---------------------------------------------------------------------------

rng = np.random.default_rng(42)
n_obs = len(auc_vals)

boot_emax = []
boot_ec50 = []
boot_hill = []

failed_boots = 0
for _ in range(bootstrap_n):
    idx = rng.integers(0, n_obs, size=n_obs)
    auc_b    = auc_vals[idx]
    effect_b = effect_vals[idx]
    try:
        pb, _ = curve_fit(
            fit_fn, auc_b, effect_b,
            p0=p0, bounds=(lo, hi),
            maxfev=5000,
        )
        if fix_emax:
            boot_ec50.append(pb[0])
            boot_hill.append(pb[1])
            boot_emax.append(emax_fixed)
        else:
            boot_emax.append(pb[0])
            boot_ec50.append(pb[1])
            boot_hill.append(pb[2])
    except Exception:
        failed_boots += 1

if failed_boots > 0:
    print(f"INFO: {failed_boots}/{bootstrap_n} bootstrap replicates failed to converge "
          "(excluded from CI).", file=sys.stderr)

def ci95(samples):
    """Return [2.5th, 97.5th] percentile CI, or [None, None] if too few samples."""
    s = [x for x in samples if x is not None and math.isfinite(x)]
    if len(s) < 10:
        return [None, None]
    return [round(float(np.percentile(s, 2.5)), 4),
            round(float(np.percentile(s, 97.5)), 4)]

ec50_ci  = ci95(boot_ec50)
emax_ci  = ci95(boot_emax)
hill_ci  = ci95(boot_hill)

print(f"INFO: Bootstrap CI (n={bootstrap_n - failed_boots} valid) — "
      f"EC50 [{ec50_ci[0]}, {ec50_ci[1]}], "
      f"Emax [{emax_ci[0]}, {emax_ci[1]}], "
      f"Hill [{hill_ci[0]}, {hill_ci[1]}]",
      file=sys.stderr)

# ---------------------------------------------------------------------------
# Build er_params.json (keys match phase2_dose_justification.parse_er_params)
# ---------------------------------------------------------------------------
# phase2_dose_justification accepts both camelCase (EC50, Emax, Hill_coeff, R2)
# and snake_case (ec50_uM, emax_pct, hill, r_squared) variants.
# We emit both for maximum forward-compatibility.

er_params = {
    # -- Primary keys consumed by phase2_dose_justification --
    "ec50_uM":          round(float(ec50_fit), 4),   # exposure in same unit as input AUC
    "emax_pct":         round(float(emax_fit), 4),
    "hill":             round(float(hill_fit), 4),
    "r_squared":        round(float(r2_fit), 6),
    # -- Alternate camelCase keys (parse_er_params also checks these) --
    "EC50":             round(float(ec50_fit), 4),
    "Emax":             round(float(emax_fit), 4),
    "Hill_coeff":       round(float(hill_fit), 4),
    "R2":               round(float(r2_fit), 6),
    # -- CI bounds --
    "ec50_ci95":        ec50_ci,
    "emax_ci95":        emax_ci,
    "hill_ci95":        hill_ci,
    # -- Metadata --
    "n_patients":       int(n_patients),
    "n_observations":   int(len(df)),
    "exposure_metric":  exp_metric,
    "exposure_column_used": exp_col,
    "emax_was_fixed":   fix_emax,
    "rmse":             round(float(rmse_fit), 4),
    "model":            "Emax_sigmoid_Hill",
    "fit_method":       f"scipy_curve_fit_bootstrap{bootstrap_n}",
    "bootstrap_n_valid": int(bootstrap_n - failed_boots),
    "identifiability_auc_max_over_ec50": round(float(auc_max_ratio), 3),
}

with open('er_params.json', 'w') as f:
    json.dump(er_params, f, indent=2)

# ---------------------------------------------------------------------------
# Predicted vs observed CSV (er_dose_response.csv)
# ---------------------------------------------------------------------------

dose_col_present = 'dose_mg' in df.columns
pid_col_present  = 'patient_id' in df.columns

with open('er_dose_response.csv', 'w', newline='') as f:
    fieldnames = ['patient_id', 'dose_mg', 'auc_obs', 'effect_pct_obs',
                  'effect_pct_pred', 'residual']
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for i, row in df.reset_index(drop=True).iterrows():
        auc_i    = float(row[exp_col])
        obs_i    = float(row['effect_pct'])
        pred_i   = float(emax_hill(auc_i, emax_fit, ec50_fit, hill_fit))
        w.writerow({
            'patient_id':       row.get('patient_id', i) if pid_col_present else i,
            'dose_mg':          row.get('dose_mg', '') if dose_col_present else '',
            'auc_obs':          round(auc_i, 4),
            'effect_pct_obs':   round(obs_i, 3),
            'effect_pct_pred':  round(pred_i, 3),
            'residual':         round(obs_i - pred_i, 3),
        })

# ---------------------------------------------------------------------------
# Human-readable fit report (er_fit_report.txt)
# ---------------------------------------------------------------------------

def ci_str(ci):
    if ci[0] is None or ci[1] is None:
        return 'insufficient bootstrap samples'
    return f'[{ci[0]:.4f}, {ci[1]:.4f}]'

report_lines = [
    '=' * 72,
    f'EXPOSURE-RESPONSE MODELING REPORT  --  {compound}',
    'Model: Emax / Hill (sigmoid)',
    'Reference: Holford & Sheiner 1982; FDA E-R Guidance 2023',
    '=' * 72,
    '',
    'INPUT DATA',
    f'  CSV file         : {csv_path}',
    f'  Patients         : {n_patients}',
    f'  Observations     : {len(df)}',
    f'  Exposure metric  : {exp_metric}  (column: {exp_col})',
    f'  AUC range        : {auc_vals.min():.2f} – {auc_vals.max():.2f}',
    f'  Effect range     : {effect_vals.min():.1f}% – {effect_vals.max():.1f}%',
    '',
    'MODEL EQUATION',
    '  effect_pct = Emax × AUC^hill / (EC50^hill + AUC^hill)',
    '',
    'FITTED PARAMETERS',
    f'  Emax  : {emax_fit:.4f} %           {"(FIXED)" if fix_emax else "(estimated)"}',
    f'          95% CI: {ci_str(emax_ci)}',
    f'  EC50  : {ec50_fit:.4f} {exp_metric}',
    f'          95% CI: {ci_str(ec50_ci)}',
    f'  Hill  : {hill_fit:.4f}  (bounds: [{hmin}, {hmax}])',
    f'          95% CI: {ci_str(hill_ci)}',
    '',
    'GOODNESS OF FIT',
    f'  R²    : {r2_fit:.4f}  ' +
    ('(excellent)' if r2_fit >= 0.85 else
     '(good)' if r2_fit >= 0.70 else
     '(moderate — consider additional data or model refinement)'),
    f'  RMSE  : {rmse_fit:.4f} % effect',
    '',
    'BOOTSTRAP CONFIDENCE INTERVALS',
    f'  Replicates requested : {bootstrap_n}',
    f'  Converged            : {bootstrap_n - failed_boots}',
    f'  Failed               : {failed_boots}',
    '',
    'IDENTIFIABILITY CHECK',
    f'  AUC_max / EC50 = {auc_max_ratio:.2f}  ' +
    ('(OK — data span sufficient plateau)' if auc_max_ratio >= 2.0
     else '(WARNING — data may not span plateau; Emax and EC50 estimates may be unreliable)'),
    '',
    'DOWNSTREAM WIRING',
    '  er_params.json → phase2_dose_justification --er_params_json',
    '  Chain: nlmixr2_population_pk → exposure_response_modeling → phase2_dose_justification',
    '',
    'OUTPUT FILES',
    '  er_params.json        -- machine-readable parameters for phase2_dose_justification',
    '  er_dose_response.csv  -- predicted vs observed per patient',
    '  er_fit_report.txt     -- this report',
    '=' * 72,
]

report_text = '\n'.join(report_lines)
with open('er_fit_report.txt', 'w') as f:
    f.write(report_text)

# ---------------------------------------------------------------------------
# Console summary (er_modeling_output.txt)
# ---------------------------------------------------------------------------

summary_lines = [
    '=== EXPOSURE-RESPONSE MODELING COMPLETE ===',
    '',
    f'Compound   : {compound}',
    f'Patients   : {n_patients}  |  Observations: {len(df)}',
    f'Model      : Emax (sigmoid Hill)',
    f'Emax       : {emax_fit:.4f}%  {"[FIXED]" if fix_emax else ""}',
    f'EC50       : {ec50_fit:.4f}  ({exp_metric})',
    f'Hill       : {hill_fit:.4f}',
    f'R²         : {r2_fit:.4f}',
    f'RMSE       : {rmse_fit:.4f}% effect',
    '',
    'er_params.json is ready for phase2_dose_justification --er_params_json.',
]
summary_text = '\n'.join(summary_lines)
with open('er_modeling_output.txt', 'w') as f:
    f.write(summary_text)
print(summary_text)

# ---------------------------------------------------------------------------
# Validation assertions (print to stderr for debugging)
# ---------------------------------------------------------------------------

assert ec50_fit > 0, f"FAIL: ec50 must be > 0, got {ec50_fit}"
assert emax_fit > 0, f"FAIL: emax must be > 0, got {emax_fit}"
assert hill_fit > 0, f"FAIL: hill must be > 0, got {hill_fit}"
assert 0.0 <= r2_fit <= 1.0, f"FAIL: r_squared must be in [0, 1], got {r2_fit}"

print(f"VALIDATION PASS: ec50={ec50_fit:.4f} > 0, emax={emax_fit:.4f} > 0, "
      f"hill={hill_fit:.4f} > 0, r_squared={r2_fit:.4f} in [0,1]",
      file=sys.stderr)
PYEOF

    cat << 'EOF' > versions.yml
exposure_response_modeling:
  python: "3.10"
  scipy: ">=1.10"
  numpy: ">=1.24"
  pandas: ">=1.5"
  references: >-
    Holford & Sheiner Pharmacol Ther 1982;10:143-166;
    FDA CDER/CBER 2023 E-R Guidance https://www.fda.gov/media/128793/download;
    Bonate PL Pharmacokinetic-Pharmacodynamic Modeling and Simulation 2011
EOF
    """
}

workflow EXPOSURE_RESPONSE_MODELING_WORKFLOW {
    take: meta_ch
    main:
        ch_data = Channel.fromPath(params.patient_data_csv)
        EXPOSURE_RESPONSE_MODELING(meta_ch, ch_data)
    emit:
        er_params     = EXPOSURE_RESPONSE_MODELING.out.er_params
        report        = EXPOSURE_RESPONSE_MODELING.out.report
        dose_response = EXPOSURE_RESPONSE_MODELING.out.dose_response
        output        = EXPOSURE_RESPONSE_MODELING.out.output
        versions      = EXPOSURE_RESPONSE_MODELING.out.versions
}

workflow {
    meta = [id: 'er_modeling_run', single_end: false]
    Channel.value(meta) | EXPOSURE_RESPONSE_MODELING_WORKFLOW
}
