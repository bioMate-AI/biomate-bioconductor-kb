#!/usr/bin/env nextflow
/*
 * pharmacology/pbpk_disease_state
 *
 * Disease-state PBPK submodels for renal and hepatic impairment, required for
 * all IND/NDA submissions involving drugs renally or hepatically cleared.
 * Implements mechanistic impairment models per:
 *   - FDA Guidance for Industry: Pharmacokinetics in Patients with Impaired
 *     Renal Function (2010); ICH E7
 *   - FDA Guidance for Industry: Pharmacokinetics in Patients with Impaired
 *     Hepatic Function (2003); Child-Pugh classification
 *
 * Computes AUC_ratio and Cmax_ratio (impaired/normal) across all impairment
 * grades, recommends dose adjustments, generates FDA label language for the
 * "Use in Specific Populations" section (§4.2 / §8.6–8.7), and produces a
 * CTD §5.2.4 (M4S) special-populations exposure-ratio summary table.
 *
 * References:
 *   - FDA Guidance: PK in Renal Impairment (2010)
 *   - FDA Guidance: PK in Hepatic Impairment (2003)
 *   - ICH E7 (Studies in Support of Special Populations: Geriatrics)
 *   - Rowland & Tozer, Clinical Pharmacokinetics Ch. 11–12 (5th ed.)
 *   - Wilkinson GR, Drug Metab Dispos 2005 (hepatic well-stirred model)
 *   - Nolin TD et al., Adv Chronic Kidney Dis 2010 (renal CL scaling)
 *
 * Input:  cl_renal_fraction, cl_hepatic_fraction, fu_plasma, vd_lkg,
 *         logP, high_extraction_ratio, drug_name, primary_indication
 * Output: disease_state_pk_report.json, specific_populations_label_text.txt,
 *         exposure_ratio_table.csv
 */

nextflow.enable.dsl = 2

params.outdir                 = './results'
params.cl_renal_fraction      = '0.3'
params.cl_hepatic_fraction    = '0.6'
params.fu_plasma              = '0.1'
params.vd_lkg                 = '0.5'
params.logP                   = '2.0'
params.high_extraction_ratio  = 'false'
params.drug_name              = 'CompoundX'
params.primary_indication     = 'not specified'
// Optional: path to pk_summary.json from predict_admet_properties output.
// When provided, fu_plasma / cl_renal_fraction / cl_hepatic_fraction / vd_lkg / logP
// are auto-populated from ADMET predictions (manual params take precedence if non-default).
params.admet_json             = ''

process PBPK_DISEASE_STATE {
    tag { meta.id }
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("ds_results.json"),                       emit: results
    tuple val(meta), path("ds_output.txt"),                         emit: output
    tuple val(meta), path("disease_state_pk_report.json"),          emit: pk_report
    tuple val(meta), path("specific_populations_label_text.txt"),   emit: label_text
    tuple val(meta), path("exposure_ratio_table.csv"),              emit: exposure_table
    path "versions.yml",                                            emit: versions

    script:
    """
    export PARAM_CLR_FRAC='${params.cl_renal_fraction}'
    export PARAM_CLH_FRAC='${params.cl_hepatic_fraction}'
    export PARAM_FU='${params.fu_plasma}'
    export PARAM_VD='${params.vd_lkg}'
    export PARAM_LOGP='${params.logP}'
    export PARAM_HIGH_ER='${params.high_extraction_ratio}'
    export PARAM_DRUG='${params.drug_name}'
    export PARAM_INDICATION='${params.primary_indication}'
    export PARAM_ADMET_JSON='${params.admet_json}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def ac(v, default=None):
    if v in (None, '', 'null', 'None'): return default
    try: return float(v)
    except: return default

def to_bool(v): return str(v).strip().lower() in ('true', '1', 'yes')

def safe_round(x, n=4):
    try: return round(float(x), n)
    except: return None

# ---------------------------------------------------------------------------
# Auto-populate from ADMET pk_summary.json if provided
# Manual params take precedence over ADMET predictions (non-default only)
# ---------------------------------------------------------------------------
_admet_file = os.environ.get('PARAM_ADMET_JSON', '').strip()
_admet_pk   = {}
_admet_source = 'manual'
if _admet_file and os.path.isfile(_admet_file):
    try:
        with open(_admet_file) as _f:
            _admet_pk = json.load(_f)
        _admet_source = f"admet_prediction ({_admet_file})"
        print(f"INFO: Loaded ADMET PK properties from {_admet_file}", file=sys.stderr)
        print(f"  fu_plasma={_admet_pk.get('fu_plasma')} clr_frac={_admet_pk.get('cl_renal_fraction')} vd={_admet_pk.get('vd_lkg')} logP={_admet_pk.get('logP')}", file=sys.stderr)
        print(f"  NOTE: These are predictions — confirm experimentally before regulatory submission.", file=sys.stderr)
    except Exception as _e:
        print(f"WARNING: Could not read ADMET JSON '{_admet_file}': {_e}", file=sys.stderr)

# Default param values (Nextflow placeholders)
_DEFAULT_CLR = 0.30
_DEFAULT_CLH = 0.60
_DEFAULT_FU  = 0.10
_DEFAULT_VD  = 0.50
_DEFAULT_LOGP = 2.00

def _param_or_admet(env_key, default, admet_key, admet_default=None):
    '''Return env param if non-default, else ADMET prediction, else default.'''
    env_val = ac(os.environ.get(env_key), None)
    if env_val is not None and abs(env_val - default) > 1e-6:
        return env_val   # user explicitly set a non-default value
    if _admet_pk and admet_key in _admet_pk and _admet_pk[admet_key] is not None:
        return float(_admet_pk[admet_key])
    return env_val if env_val is not None else default

# ---------------------------------------------------------------------------
# Load parameters
# ---------------------------------------------------------------------------
clr_frac   = _param_or_admet('PARAM_CLR_FRAC', _DEFAULT_CLR, 'cl_renal_fraction',   0.30)
clh_frac   = _param_or_admet('PARAM_CLH_FRAC', _DEFAULT_CLH, 'cl_hepatic_fraction', 0.60)
fu         = _param_or_admet('PARAM_FU',        _DEFAULT_FU,  'fu_plasma',           0.10)   # fu_plasma
# P0 fix: warn when fu < 0.05 — generic albumin correction can be off 2-3x
# for tight binders (warfarin fu=0.01, diazepam fu=0.02). The correction
# uses a fixed binding constant valid for moderate binders (Rowland & Tozer Ch.11).
_fu_warning = (
    f"WARNING: fu_plasma={fu:.3f} < 0.05 (highly protein-bound). "
    "The albumin binding correction uses a generic constant; for tight binders "
    "(warfarin, diazepam, phenytoin) the true fu shift in hepatic impairment may "
    "differ 2-3x from this estimate. Recommend measuring fu in disease-state plasma."
) if fu < 0.05 else None
vd_lkg     = _param_or_admet('PARAM_VD',    _DEFAULT_VD,   'vd_lkg',  0.50)   # L/kg
logP       = _param_or_admet('PARAM_LOGP',  _DEFAULT_LOGP, 'logP',    2.00)
high_er    = to_bool(os.environ.get('PARAM_HIGH_ER', 'false'))
drug_name  = os.environ.get('PARAM_DRUG', 'CompoundX').strip()
indication = os.environ.get('PARAM_INDICATION', 'not specified').strip()

# Normalise fractions so they sum to 1 (allow non-hepatic/non-renal remainder)
cl_other_frac = max(0.0, 1.0 - clr_frac - clh_frac)

# Reference physiology (healthy adult, Willmann 2003)
BW_kg_normal      = 70.0
GFR_normal_mL_min = 120.0   # mL/min (eGFR in healthy adult)
albumin_normal    = 4.5      # g/dL
LBF_normal_L_h    = 90.0    # hepatic blood flow (L/h)

# ===========================================================================
# 1. RENAL IMPAIRMENT SUBMODEL
#    Per FDA Guidance 2010 / Nolin et al. 2010:
#      CLr_impaired = CLr_normal * (GFR_patient / GFR_normal)^0.75
#    Protein binding correction for hypoalbuminemia (severe/ESRD):
#      fu_impaired = fu_normal / (1 + (albumin_normal/albumin_actual - 1)*
#                                     (1 - fu_normal))
#    Volume of distribution correction for edema (hydrophilic drugs, logP < 1):
#      Vd_impaired = Vd_normal * edema_factor
# ===========================================================================
RENAL_GRADES = [
    # (label,      GFR_mL_min, albumin_g_dL, edema_factor)
    ('Normal',     120,        4.5,          1.00),
    ('Mild',        75,        4.2,          1.05),
    ('Moderate',    45,        3.8,          1.15),
    ('Severe',      22,        3.2,          1.30),
    ('ESRD',         8,        2.8,          1.40),
]

def fu_hypoalbuminemia(fu_norm, alb_actual, alb_norm=4.5):
    '''Corrected unbound fraction under hypoalbuminemia.
    Derived from two-site binding model: fu_imp = fu_norm /
    (1 + (alb_norm/alb_actual - 1) * (1 - fu_norm)).
    Ref: Rowland & Tozer Ch 11; Nolin 2010.
    '''
    if alb_actual <= 0 or alb_norm <= 0:
        return fu_norm
    ratio = alb_norm / alb_actual
    denom = 1.0 + (ratio - 1.0) * (1.0 - fu_norm)
    return min(1.0, fu_norm / denom) if denom > 0 else fu_norm

def renal_cl_ratio(gfr_patient, gfr_normal=120.0, exponent=0.75):
    '''Scaled renal clearance ratio (Nolin 2010 power-law).'''
    if gfr_normal <= 0: return 1.0
    return (gfr_patient / gfr_normal) ** exponent

def vd_edema_correction(vd_norm, logP, edema_factor):
    '''Hydrophilic drugs (logP < 1) accumulate in oedema fluid.
    Correction factor interpolated linearly between 1.0 (logP>=1) and
    edema_factor (logP<=-1). Ref: Rowland & Tozer Ch 12.
    '''
    if logP >= 1.0:
        return vd_norm
    # Linear interpolation: at logP=1 → factor=1; at logP=-1 → factor=edema_factor
    weight = min(1.0, (1.0 - logP) / 2.0)
    return vd_norm * (1.0 + (edema_factor - 1.0) * weight)

renal_results = []
for grade_label, gfr, albumin, edema_f in RENAL_GRADES:
    # --- Clearance adjustments ---
    clr_ratio  = renal_cl_ratio(gfr, GFR_normal_mL_min)
    # Hypoalbuminemia increases fu → slightly increases non-renal hepatic CL
    fu_imp     = fu_hypoalbuminemia(fu, albumin)
    fu_ratio   = fu_imp / fu if fu > 0 else 1.0

    # Total CL ratio (weighted by route fractions):
    #   CL_total_imp / CL_total_norm =
    #     clr_frac * clr_ratio          (renal component scaled by GFR)
    #   + clh_frac * clh_factor_renal   (hepatic unaffected by renal disease ≈ 1)
    #   + cl_other_frac * 1.0           (unchanged)
    # For high-extraction hepatic drugs, fu change affects CL_h via fu*(CLint)
    # For renal impairment we assume hepatic CL is unchanged (different organ)
    cl_total_ratio = (clr_frac * clr_ratio
                      + clh_frac * 1.0
                      + cl_other_frac * 1.0)

    # Vd correction
    vd_imp = vd_edema_correction(vd_lkg * BW_kg_normal, logP, edema_f)
    vd_norm_L = vd_lkg * BW_kg_normal
    vd_ratio  = vd_imp / vd_norm_L if vd_norm_L > 0 else 1.0

    # AUC_ratio = CL_normal / CL_impaired  (AUC = Dose/CL)
    auc_ratio  = 1.0 / cl_total_ratio if cl_total_ratio > 0 else 99.0
    # Cmax_ratio: for 1-compartment oral:  Cmax ≈ F*D/(Vd*ka/(ka-ke)) ×1/Vd
    # Simplified: Cmax_ratio ≈ 1 / (cl_total_ratio * vd_ratio) for 1-cmt IV
    # For oral, Cmax depends on ka/ke ratio; conservative approximation:
    #   Cmax_ratio ≈ auc_ratio / vd_ratio (assuming same t_max shift)
    cmax_ratio = auc_ratio / vd_ratio if vd_ratio > 0 else auc_ratio

    # Dose recommendation
    if auc_ratio <= 1.25:
        dose_adj = 1.0
        dose_label = 'No dose adjustment required'
    elif auc_ratio <= 2.0:
        dose_adj = round(1.0 / auc_ratio, 2)
        dose_label = f'Reduce dose to {int(dose_adj*100)}% of normal dose'
    elif auc_ratio <= 5.0:
        dose_adj = round(1.0 / auc_ratio, 2)
        dose_label = f'Reduce dose to {int(dose_adj*100)}% of normal dose; monitor closely'
    else:
        dose_adj = None
        dose_label = 'CONTRAINDICATED (AUC ratio > 5)'

    renal_results.append({
        'organ':           'renal',
        'grade':           grade_label,
        'GFR_mL_min':      gfr,
        'albumin_g_dL':    albumin,
        'fu_impaired':     safe_round(fu_imp, 4),
        'fu_ratio':        safe_round(fu_ratio, 3),
        'CLr_ratio':       safe_round(clr_ratio, 3),
        'CL_total_ratio':  safe_round(cl_total_ratio, 3),
        'Vd_ratio':        safe_round(vd_ratio, 3),
        'AUC_ratio':       safe_round(auc_ratio, 3),
        'Cmax_ratio':      safe_round(cmax_ratio, 3),
        'dose_fraction':   dose_adj,
        'dose_recommendation': dose_label,
        'contraindicated': auc_ratio > 5.0,
    })

# ===========================================================================
# 2. HEPATIC IMPAIRMENT SUBMODEL
#    Per FDA Guidance 2003, Child-Pugh classification:
#      CLH = LBF * (fu * CLint) / (LBF + fu * CLint)  [well-stirred model]
#    High-extraction drugs: CLH ≈ LBF (flow-limited)
#      → CLH_impaired / CLH_normal = LBF_impaired / LBF_normal
#    Low-extraction drugs: CLH ≈ fu * CLint (capacity-limited)
#      → CLH_impaired / CLH_normal =
#           (fu_impaired * CLint_impaired) / (fu_normal * CLint_normal)
# ===========================================================================
# Functional hepatocyte fraction and LBF fraction per Child-Pugh class
# Source: FDA 2003 Guidance Table 1; Pugh 1973; Forrest 2022 review
HEPATIC_GRADES = [
    # (label,     CP_score_range, hepatocyte_frac, lbf_frac, albumin_g_dL)
    ('Normal',    '—',            1.00,            1.00,     4.5),
    ('Mild (A)',  '5–6',          0.80,            0.90,     3.8),
    ('Moderate (B)', '7–9',       0.60,            0.80,     3.0),
    ('Severe (C)', '10–15',       0.35,            0.65,     2.3),
]

# Reference intrinsic clearance (relative units = 1.0 for normal)
# CLint_impaired = CLint_normal * hepatocyte_frac
# fu_impaired (albumin-mediated, per Rowland & Tozer Ch.11; Wilkinson 2005):
#   fu_imp = fu_normal / (1 - (1 - fu_normal) * (1 - alb_actual/alb_normal))
#   At normal albumin: alb_ratio=1 → fu_imp = fu_normal (identity; correct)
def fu_albumin_hepatic(fu_norm, alb_actual, alb_norm=4.5):
    '''fu correction for hepatic impairment via albumin reduction.
    Uses the two-site binding model derived from Wilkinson 2005:
      fu_imp = fu_norm / (1 - (1 - fu_norm) * (1 - alb_actual/alb_norm))
    This correctly returns fu_norm when alb_actual == alb_norm (normal state).
    Ref: Wilkinson GR Drug Metab Dispos 2005; FDA 2003 Guidance §3.2;
         Rowland & Tozer Clinical Pharmacokinetics Ch.11 5th ed.'''
    if alb_actual <= 0 or alb_norm <= 0:
        return fu_norm
    alb_ratio = alb_actual / alb_norm
    denom = 1.0 - (1.0 - fu_norm) * (1.0 - alb_ratio)
    return min(1.0, fu_norm / denom) if denom > 0 else fu_norm

def clh_well_stirred(lbf_mL_h, fu_p, clint_rel, lbf_normal_mL_h,
                     high_er=False):
    '''
    CLH (well-stirred model) in relative units (ratio to normal).
    lbf_mL_h:       actual LBF (mL/h) for this grade
    fu_p:           unbound fraction in plasma (possibly impairment-adjusted)
    clint_rel:      CLint relative to normal (0–1)
    high_er:        True if hepatic extraction ratio > 0.7 (flow-limited)
    Returns CLH_ratio = CLH_impaired / CLH_normal.
    '''
    lbf_n   = lbf_normal_mL_h          # mL/h, normal
    fu_n    = fu                        # fu_plasma in normal subject
    # Normal CLH (well-stirred), assuming CLint_normal = CLint_ref
    # We use CLint_ref = CLint such that CLH_normal = clh_frac * CL_total_normal
    # For ratio computation we only need relative CLH:
    if high_er:
        # Flow-limited: CLH ≈ Q_H → CLH_ratio = lbf_impaired / lbf_normal
        return lbf_mL_h / lbf_n
    else:
        # Capacity-limited (low-ER): CLH ≈ fu*CLint
        # CLH_ratio = (fu_imp * CLint_imp) / (fu_n * CLint_n)
        # But also apply well-stirred correction for each:
        #   CLH = Q*(fu*CLint)/(Q + fu*CLint)
        # We parameterise CLint_ref so that CLH_normal = clh_frac * CL_total
        # For ratio: use Q_norm and Q_imp, fu_norm and fu_imp, CLint_norm and CLint_imp
        # CLint_imp = CLint_norm * clint_rel (hepatocyte fraction)
        # Let R_n = fu_n * CLint_n; R_i = fu_imp * CLint_imp = fu_imp * CLint_n * clint_rel
        # CLH_n = lbf_n * R_n / (lbf_n + R_n)
        # CLH_i = lbf_i * R_i / (lbf_i + R_i)
        # Assume CLint_n such that extraction ratio E_n = 0.3 (typical low-ER)
        E_n     = 0.30
        CLint_n = lbf_n * E_n / (fu_n * (1.0 - E_n)) if fu_n > 0 else lbf_n
        R_n = fu_n * CLint_n
        CLH_n = lbf_n * R_n / (lbf_n + R_n) if (lbf_n + R_n) > 0 else 1.0
        fu_imp_val = fu_p
        R_i = fu_imp_val * CLint_n * clint_rel
        CLH_i = lbf_mL_h * R_i / (lbf_mL_h + R_i) if (lbf_mL_h + R_i) > 0 else 0.0
        return CLH_i / CLH_n if CLH_n > 0 else 0.0

LBF_NORMAL_mL_h = LBF_normal_L_h * 1000.0   # 90,000 mL/h

hepatic_results = []
for grade_label, cp_range, hep_frac, lbf_frac, albumin in HEPATIC_GRADES:
    lbf_imp_mL_h = LBF_NORMAL_mL_h * lbf_frac
    fu_imp = fu_albumin_hepatic(fu, albumin)
    fu_ratio = fu_imp / fu if fu > 0 else 1.0

    clh_ratio = clh_well_stirred(lbf_imp_mL_h, fu_imp, hep_frac,
                                  LBF_NORMAL_mL_h, high_er=high_er)

    # Total CL ratio (weighted):
    cl_total_ratio = (clr_frac * 1.0          # renal unaffected by liver disease
                      + clh_frac * clh_ratio
                      + cl_other_frac * 1.0)

    auc_ratio  = 1.0 / cl_total_ratio if cl_total_ratio > 0 else 99.0
    # Vd: hepatic impairment can increase Vd due to ascites/hypoalbuminemia
    # Approximate correction: logP < 1 → Vd increases by (1 + 0.15*(1-hep_frac))
    vd_ascites = 1.0 + 0.15 * (1.0 - hep_frac) if logP < 1.0 else 1.0
    cmax_ratio = auc_ratio / vd_ascites

    if auc_ratio <= 1.25:
        dose_adj = 1.0
        dose_label = 'No dose adjustment required'
    elif auc_ratio <= 2.0:
        dose_adj = safe_round(1.0 / auc_ratio, 2)
        dose_label = f'Reduce dose to {int(round(1.0/auc_ratio, 2)*100)}% of normal dose'
    elif auc_ratio <= 5.0:
        dose_adj = safe_round(1.0 / auc_ratio, 2)
        dose_label = f'Reduce dose to {int(round(1.0/auc_ratio, 2)*100)}% of normal dose; monitor LFTs'
    else:
        dose_adj = None
        dose_label = 'CONTRAINDICATED (AUC ratio > 5)'

    hepatic_results.append({
        'organ':              'hepatic',
        'grade':              grade_label,
        'child_pugh_score':   cp_range,
        'hepatocyte_frac':    hep_frac,
        'lbf_fraction':       lbf_frac,
        'albumin_g_dL':       albumin,
        'fu_impaired':        safe_round(fu_imp, 4),
        'fu_ratio':           safe_round(fu_ratio, 3),
        'CLH_ratio':          safe_round(clh_ratio, 3),
        'CL_total_ratio':     safe_round(cl_total_ratio, 3),
        'AUC_ratio':          safe_round(auc_ratio, 3),
        'Cmax_ratio':         safe_round(cmax_ratio, 3),
        'dose_fraction':      dose_adj,
        'dose_recommendation': dose_label,
        'contraindicated':    auc_ratio > 5.0,
    })

# ===========================================================================
# 3. FDA LABEL LANGUAGE GENERATOR
#    "Use in Specific Populations" — §8.6 (renal) and §8.7 (hepatic)
#    Template language follows FDA-approved NDA label conventions.
# ===========================================================================

def renal_label_section(results, drug_name, indication):
    '''Generate §8.6 Renal Impairment label text.'''
    lines = [
        f'8.6 Renal Impairment',
        '',
        (f'{drug_name} is {_pct_renal_cleared(results):.0f}% renally cleared. '
         f'The pharmacokinetics of {drug_name} were evaluated in patients with '
         f'varying degrees of renal impairment classified by estimated '
         f'glomerular filtration rate (eGFR).'),
        '',
    ]

    ci_any = any(r['contraindicated'] for r in results if r['grade'] != 'Normal')
    adj_any = any((not r['contraindicated'] and r['AUC_ratio'] > 1.25)
                  for r in results if r['grade'] != 'Normal')

    if ci_any:
        ci_grades = [r['grade'] for r in results
                     if r['grade'] != 'Normal' and r['contraindicated']]
        lines.append(
            f'{drug_name} is CONTRAINDICATED in patients with '
            + _oxford(ci_grades) + ' renal impairment (AUC increase >5-fold).'
        )

    for r in results:
        if r['grade'] == 'Normal': continue
        auc = r['AUC_ratio']
        cmax = r['Cmax_ratio']
        if r['contraindicated']:
            lines.append(
                f'  {r["grade"]} renal impairment (eGFR {r["GFR_mL_min"]} mL/min): '
                f'AUC increased {auc:.1f}-fold; Cmax increased {cmax:.1f}-fold. '
                f'Use is contraindicated.'
            )
        elif auc > 1.25:
            pct = int(round(r['dose_fraction'] * 100)) if r['dose_fraction'] else 'N/A'
            lines.append(
                f'  {r["grade"]} renal impairment (eGFR {r["GFR_mL_min"]} mL/min): '
                f'AUC increased {auc:.1f}-fold; Cmax increased {cmax:.1f}-fold. '
                f'Reduce dose to {pct}% of the recommended dose.'
            )
        else:
            lines.append(
                f'  {r["grade"]} renal impairment (eGFR {r["GFR_mL_min"]} mL/min): '
                f'AUC increased {auc:.2f}-fold. No dose adjustment is required.'
            )

    if not adj_any and not ci_any:
        lines.append(f'No dose adjustment is required for patients with renal impairment.')

    lines += [
        '',
        (f'End-stage renal disease (ESRD) patients on dialysis were not '
         f'specifically studied. Refer to Section 12.3 for details.')
        if any(r['grade'] == 'ESRD' for r in results) else '',
    ]
    return '\n'.join(l for l in lines if l is not None)

def hepatic_label_section(results, drug_name, indication):
    '''Generate §8.7 Hepatic Impairment label text.'''
    lines = [
        f'8.7 Hepatic Impairment',
        '',
        (f'The pharmacokinetics of {drug_name} were evaluated in patients with '
         f'mild (Child-Pugh A, score 5–6), moderate (Child-Pugh B, score 7–9), '
         f'and severe (Child-Pugh C, score 10–15) hepatic impairment. '
         f'{drug_name} is {_pct_hepatic_cleared(results):.0f}% hepatically eliminated.'),
        '',
    ]

    ci_grades = [r['grade'] for r in results
                 if r['grade'] != 'Normal' and r['contraindicated']]
    if ci_grades:
        lines.append(
            f'{drug_name} is CONTRAINDICATED in patients with '
            + _oxford(ci_grades) + ' hepatic impairment (AUC increase >5-fold).'
        )

    for r in results:
        if r['grade'] == 'Normal': continue
        auc = r['AUC_ratio']
        cmax = r['Cmax_ratio']
        if r['contraindicated']:
            lines.append(
                f'  {r["grade"]} (Child-Pugh {r["child_pugh_score"]}): '
                f'AUC increased {auc:.1f}-fold; Cmax increased {cmax:.1f}-fold. '
                f'Use is contraindicated.'
            )
        elif auc > 1.25:
            pct = int(round(r['dose_fraction'] * 100)) if r['dose_fraction'] else 'N/A'
            lines.append(
                f'  {r["grade"]} (Child-Pugh {r["child_pugh_score"]}): '
                f'AUC increased {auc:.1f}-fold; Cmax increased {cmax:.1f}-fold. '
                f'Reduce the dose to {pct}% of the recommended dose.'
            )
        else:
            lines.append(
                f'  {r["grade"]} (Child-Pugh {r["child_pugh_score"]}): '
                f'AUC increased {auc:.2f}-fold. No dose adjustment is required.'
            )

    lines += [
        '',
        f'Patients with hepatic impairment should be monitored for adverse reactions.',
    ]
    return '\n'.join(lines)

def _pct_renal_cleared(results):
    return clr_frac * 100.0

def _pct_hepatic_cleared(results):
    return clh_frac * 100.0

def _oxford(items):
    if not items: return ''
    if len(items) == 1: return items[0]
    return ', '.join(items[:-1]) + f', and {items[-1]}'

# Build full label section
label_parts = [
    f'USE IN SPECIFIC POPULATIONS',
    f'Drug: {drug_name}',
    f'Indication: {indication}',
    f'Generated: FDA 2003/2010 Guidance Templates',
    '',
    '=' * 72,
    '',
    renal_label_section(renal_results, drug_name, indication),
    '',
    '=' * 72,
    '',
    hepatic_label_section(hepatic_results, drug_name, indication),
    '',
    '=' * 72,
    '',
    'NOTE: This label language was computer-generated using mechanistic PBPK',
    'impairment models per FDA Guidance for Industry (Renal 2010; Hepatic 2003)',
    'and requires clinical validation before regulatory submission.',
]
label_text = '\n'.join(label_parts)

# ===========================================================================
# 4. CTD §5.2.4 SPECIAL POPULATIONS EXPOSURE RATIO TABLE (M4S format)
# ===========================================================================
all_rows = []
# Header
all_rows.append([
    'Impairment_Type', 'Grade', 'Score_or_GFR',
    'fu_ratio', 'CL_total_ratio',
    'AUC_ratio', 'Cmax_ratio',
    'Dose_Adjustment', 'Contraindicated',
])
for r in renal_results:
    if r['grade'] == 'Normal': continue
    all_rows.append([
        'Renal', r['grade'],
        f'eGFR {r["GFR_mL_min"]} mL/min',
        r['fu_ratio'], r['CL_total_ratio'],
        r['AUC_ratio'], r['Cmax_ratio'],
        r['dose_recommendation'],
        'YES' if r['contraindicated'] else 'NO',
    ])
for r in hepatic_results:
    if r['grade'] == 'Normal': continue
    all_rows.append([
        'Hepatic', r['grade'],
        f'Child-Pugh {r["child_pugh_score"]}',
        r['fu_ratio'], r['CL_total_ratio'],
        r['AUC_ratio'], r['Cmax_ratio'],
        r['dose_recommendation'],
        'YES' if r['contraindicated'] else 'NO',
    ])

with open('exposure_ratio_table.csv', 'w', newline='') as f:
    csv.writer(f).writerows(all_rows)

# ===========================================================================
# 5. FULL JSON REPORT
# ===========================================================================
pk_report = {
    'drug_name':         drug_name,
    'indication':        indication,
    'input_params': {
        'cl_renal_fraction':   clr_frac,
        'cl_hepatic_fraction': clh_frac,
        'cl_other_fraction':   cl_other_frac,
        'fu_plasma':           fu,
        'vd_lkg':              vd_lkg,
        'logP':                logP,
        'high_extraction_ratio': high_er,
    },
    'renal_impairment':   renal_results,
    'hepatic_impairment': hepatic_results,
    'references': [
        'FDA Guidance: PK in Renal Impairment (2010)',
        'FDA Guidance: PK in Hepatic Impairment (2003)',
        'ICH E7 Special Populations (1993)',
        'Nolin TD et al., Adv Chronic Kidney Dis 2010 (CLr scaling)',
        'Wilkinson GR, Drug Metab Dispos 2005 (well-stirred model)',
        'Rowland & Tozer, Clinical Pharmacokinetics Ch.11-12, 5th ed.',
        'Pugh RN et al., Br J Surg 1973 (Child-Pugh classification)',
    ],
    'status': 'completed',
    'protein_binding_warning': _fu_warning,
    'parameter_source': _admet_source,
    'admet_prediction_disclaimer': (
        _admet_pk.get('disclaimer') if _admet_pk else None
    ),
}

with open('disease_state_pk_report.json', 'w') as f:
    json.dump(pk_report, f, indent=2)

with open('specific_populations_label_text.txt', 'w') as f:
    f.write(label_text)

# ===========================================================================
# 6. PLAIN-TEXT SUMMARY
# ===========================================================================
def worst_auc(results):
    return max((r['AUC_ratio'] for r in results if r['grade'] != 'Normal'), default=1.0)

renal_worst = worst_auc(renal_results)
hepatic_worst = worst_auc(hepatic_results)

renal_ci_grades  = [r['grade'] for r in renal_results  if r['contraindicated']]
hepatic_ci_grades= [r['grade'] for r in hepatic_results if r['contraindicated']]

report_lines = [
    f'=== PBPK DISEASE-STATE REPORT: {drug_name} ===',
    f'Indication: {indication}',
    '',
    f'Input Parameters:',
    f'  Renal CL fraction:   {clr_frac:.1%}',
    f'  Hepatic CL fraction: {clh_frac:.1%}',
    f'  fu_plasma:           {fu}',
    f'  Vd:                  {vd_lkg} L/kg',
    f'  logP:                {logP}',
    f'  High-ER:             {high_er}',
    '',
    '--- RENAL IMPAIRMENT SUMMARY ---',
    f'Worst-case AUC ratio (ESRD): {renal_worst:.2f}x',
]
for r in renal_results:
    if r['grade'] == 'Normal': continue
    ci_flag = ' [CONTRAINDICATED]' if r['contraindicated'] else ''
    report_lines.append(
        f'  {r["grade"]:<22s} eGFR={r["GFR_mL_min"]:3d}  '
        f'AUC={r["AUC_ratio"]:.2f}x  Cmax={r["Cmax_ratio"]:.2f}x  '
        f'{r["dose_recommendation"]}{ci_flag}'
    )

report_lines += [
    '',
    '--- HEPATIC IMPAIRMENT SUMMARY ---',
    f'Worst-case AUC ratio (Child-Pugh C): {hepatic_worst:.2f}x',
]
for r in hepatic_results:
    if r['grade'] == 'Normal': continue
    ci_flag = ' [CONTRAINDICATED]' if r['contraindicated'] else ''
    report_lines.append(
        f'  {r["grade"]:<22s} CP={r["child_pugh_score"]}  '
        f'AUC={r["AUC_ratio"]:.2f}x  Cmax={r["Cmax_ratio"]:.2f}x  '
        f'{r["dose_recommendation"]}{ci_flag}'
    )

if renal_ci_grades or hepatic_ci_grades:
    report_lines += ['', '*** CONTRAINDICATION FLAGS ***']
    if renal_ci_grades:
        report_lines.append(f'  Renal:   {_oxford(renal_ci_grades)}')
    if hepatic_ci_grades:
        report_lines.append(f'  Hepatic: {_oxford(hepatic_ci_grades)}')

report_lines += [
    '',
    'Label text written to: specific_populations_label_text.txt',
    'Exposure table written to: exposure_ratio_table.csv',
    'Full JSON written to: disease_state_pk_report.json',
]

summary_text = '\n'.join(report_lines)

with open('ds_output.txt', 'w') as f:
    f.write(summary_text)
print(summary_text)

with open('ds_results.json', 'w') as f:
    json.dump({
        'status': 'completed',
        'drug_name': drug_name,
        'renal_worst_auc_ratio': safe_round(renal_worst, 3),
        'hepatic_worst_auc_ratio': safe_round(hepatic_worst, 3),
        'renal_contraindicated_grades': renal_ci_grades,
        'hepatic_contraindicated_grades': hepatic_ci_grades,
    }, f, indent=2)

PYEOF

    cat << 'EOF' > versions.yml
pbpk_disease_state:
  python: "3.10"
  numpy: ">=1.24"
  scipy: ">=1.10"
  references: >
    FDA Guidance Renal Impairment 2010;
    FDA Guidance Hepatic Impairment 2003;
    ICH E7; Rowland & Tozer 5th ed.;
    Nolin 2010; Wilkinson 2005; Pugh 1973
EOF
    """
}

workflow PBPK_DISEASE_STATE_WORKFLOW {
    take: meta_ch
    main: PBPK_DISEASE_STATE(meta_ch)
    emit:
        results       = PBPK_DISEASE_STATE.out.results
        pk_report     = PBPK_DISEASE_STATE.out.pk_report
        label_text    = PBPK_DISEASE_STATE.out.label_text
        exposure_table = PBPK_DISEASE_STATE.out.exposure_table
}

workflow {
    meta = [id: 'pbpk_disease_state_run', single_end: false]
    Channel.value(meta) | PBPK_DISEASE_STATE_WORKFLOW
}
