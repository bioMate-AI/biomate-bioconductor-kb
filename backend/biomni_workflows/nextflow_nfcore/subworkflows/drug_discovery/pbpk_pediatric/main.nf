#!/usr/bin/env nextflow
/*
 * drug_discovery/pbpk_pediatric
 *
 * Paediatric PBPK simulation using age-appropriate physiological parameters.
 * Scales adult PK (CL, Vd) to neonatal, infant, toddler, child, and adolescent
 * populations using allometric body-weight scaling, CYP enzyme maturation
 * functions, GFR maturation (Schwartz formula), protein-binding maturation,
 * and age-stratified body composition.
 *
 * Scaling methods:
 *   1. Allometric body weight: CL ∝ BW^0.75, Vd ∝ BW^1.0 (Anderson & Holford 2008)
 *   2. CYP3A4/CYP2D6/CYP2C19 maturation: sigmoidal Hill model (Krekels 2012; Upreti 2016)
 *   3. GFR maturation: Schwartz formula adapted for neonates through adolescents
 *   4. Albumin maturation: 0.6× adult in neonates, normalises by 1 year
 *   5. Body composition: fat/water fraction by age group
 *
 * FDA/EMA compliance flags per ICH E11(R1) 2017:
 *   - Extrapolation unreliable for neonates with CYP-eliminated drugs
 *   - Dose flag if paediatric mg/kg > 2× adult mg/kg
 *
 * References:
 *   - Anderson & Holford 2008 Annu Rev Pharmacol Toxicol 48:303-332
 *   - Krekels et al. 2012 Br J Clin Pharmacol 74(3):525-536
 *   - Upreti & Wahlstrom 2016 AAPS J 18(1):171-184
 *   - ICH E11(R1) Addendum 2017 (paediatric study guidelines)
 *   - Schwartz et al. 1987 Pediatr Clin North Am (GFR maturation)
 *   - Johnson 2008 Clin Pharmacokinet 47(1):1-21 (protein binding maturation)
 */

nextflow.enable.dsl = 2

params.outdir                   = './results'
params.adult_cl_L_h             = '10.0'       // adult total clearance (L/h)
params.adult_vd_L               = '50.0'       // adult volume of distribution (L)
params.adult_mw_da              = '400.0'      // molecular weight (Da); used for allometric exponent refinement
params.route                    = 'iv'         // iv | oral
params.dose_mg_kg               = '1.0'        // dose in mg/kg (adult reference)
params.age_group                = 'all'        // neonate_0_1mo | infant_1_12mo | toddler_1_5y | child_5_12y | adolescent_12_18y | all
params.renal_clearance_fraction = '0.3'        // fraction of total CL attributable to renal elimination
params.hepatic_extraction       = '0.4'        // hepatic extraction ratio (0–1)
params.protein_binding_fraction = '0.85'       // adult plasma protein binding (fu = 1 - this value)
params.indication               = 'infectious' // oncology | infectious | rare_disease | neurology

process PBPK_PEDIATRIC {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("pediatric_pk_results.json"),  emit: results
    tuple val(meta), path("age_group_pk.csv"),           emit: age_group_pk
    tuple val(meta), path("dose_recommendations.csv"),   emit: dose_recommendations
    tuple val(meta), path("pk_report.txt"),              emit: report
    path "versions.yml",                                 emit: versions

    script:
    """
    export PARAM_ADULT_CL='${params.adult_cl_L_h}'
    export PARAM_ADULT_VD='${params.adult_vd_L}'
    export PARAM_ADULT_MW='${params.adult_mw_da}'
    export PARAM_ROUTE='${params.route}'
    export PARAM_DOSE_MG_KG='${params.dose_mg_kg}'
    export PARAM_AGE_GROUP='${params.age_group}'
    export PARAM_RENAL_FRAC='${params.renal_clearance_fraction}'
    export PARAM_HEP_EXTRACT='${params.hepatic_extraction}'
    export PARAM_PPB='${params.protein_binding_fraction}'
    export PARAM_INDICATION='${params.indication}'

    python3 << 'PYEOF'
import json, os, csv, math, random

random.seed(42)

# ─── Parameter parsing helpers ────────────────────────────────────────────────
def pf(v, d=1.0):
    try: return float(v)
    except: return d

def pclamp(v, lo, hi):
    return max(lo, min(hi, v))

adult_cl     = pf(os.environ.get('PARAM_ADULT_CL'),   10.0)
adult_vd     = pf(os.environ.get('PARAM_ADULT_VD'),   50.0)
adult_mw     = pf(os.environ.get('PARAM_ADULT_MW'),   400.0)
route        = os.environ.get('PARAM_ROUTE',          'iv').lower()
dose_mg_kg   = pf(os.environ.get('PARAM_DOSE_MG_KG'), 1.0)
age_group    = os.environ.get('PARAM_AGE_GROUP',      'all').lower()
renal_frac   = pclamp(pf(os.environ.get('PARAM_RENAL_FRAC'),    0.3), 0.0, 1.0)
hep_extract  = pclamp(pf(os.environ.get('PARAM_HEP_EXTRACT'),   0.4), 0.0, 1.0)
ppb          = pclamp(pf(os.environ.get('PARAM_PPB'),           0.85), 0.0, 0.999)
indication   = os.environ.get('PARAM_INDICATION', 'infectious').lower()

fu_adult     = 1.0 - ppb   # unbound fraction, adult

# ─── Adult reference values ────────────────────────────────────────────────────
ADULT_BW_KG   = 70.0
ADULT_GFR_ML_MIN = 120.0   # mL/min/1.73m² (standard adult)
# Derived: hepatic CL and renal CL components
hepatic_cl   = adult_cl * (1.0 - renal_frac)
renal_cl_L_h = adult_cl * renal_frac

# ─── Age group physiological parameters ───────────────────────────────────────
# Sources: Willmann 2003 ClinPharmacokinet; Johnson 2008 ClinPharmacokinet;
#          Anderson & Holford 2008; Rhodin et al. 2009 (GFR maturation)
#
# Columns: label, BW_kg, BSA_m2, age_midpoint_y,
#          organ_liver_kg, organ_kidney_kg, blood_flow_liver_L_h,
#          fat_fraction, water_fraction,
#          albumin_frac_of_adult (Johnson 2008 Fig 2)
AGE_PARAMS = {
    'neonate_0_1mo': {
        'label':               'Neonate (0–1 month)',
        'BW_kg':               3.5,
        'BSA_m2':              0.22,
        'age_midpoint_y':      0.04,    # ~2 weeks postnatal
        'organ_liver_kg':      0.130,
        'organ_kidney_kg':     0.025,
        'blood_flow_liver_L_h': 5.5,
        'fat_fraction':        0.15,
        'water_fraction':      0.74,
        'albumin_frac':        0.60,    # 60% of adult albumin (Johnson 2008)
        'gfr_frac':            0.22,    # fraction of adult GFR (Rhodin 2009)
    },
    'infant_1_12mo': {
        'label':               'Infant (1–12 months)',
        'BW_kg':               8.0,
        'BSA_m2':              0.42,
        'age_midpoint_y':      0.5,
        'organ_liver_kg':      0.320,
        'organ_kidney_kg':     0.065,
        'blood_flow_liver_L_h': 14.4,
        'fat_fraction':        0.22,
        'water_fraction':      0.65,
        'albumin_frac':        0.88,    # nearly adult by 12 months
        'gfr_frac':            0.65,
    },
    'toddler_1_5y': {
        'label':               'Toddler (1–5 years)',
        'BW_kg':               15.0,
        'BSA_m2':              0.65,
        'age_midpoint_y':      3.0,
        'organ_liver_kg':      0.560,
        'organ_kidney_kg':     0.120,
        'blood_flow_liver_L_h': 28.0,
        'fat_fraction':        0.18,
        'water_fraction':      0.62,
        'albumin_frac':        1.00,
        'gfr_frac':            0.90,
    },
    'child_5_12y': {
        'label':               'Child (5–12 years)',
        'BW_kg':               30.0,
        'BSA_m2':              1.05,
        'age_midpoint_y':      8.5,
        'organ_liver_kg':      0.890,
        'organ_kidney_kg':     0.220,
        'blood_flow_liver_L_h': 50.4,
        'fat_fraction':        0.20,
        'water_fraction':      0.60,
        'albumin_frac':        1.00,
        'gfr_frac':            1.05,    # slight super-adult GFR normalised per kg
    },
    'adolescent_12_18y': {
        'label':               'Adolescent (12–18 years)',
        'BW_kg':               55.0,
        'BSA_m2':              1.55,
        'age_midpoint_y':      15.0,
        'organ_liver_kg':      1.350,
        'organ_kidney_kg':     0.280,
        'blood_flow_liver_L_h': 76.0,
        'fat_fraction':        0.22,
        'water_fraction':      0.59,
        'albumin_frac':        1.00,
        'gfr_frac':            1.00,
    },
}

ALL_GROUPS = ['neonate_0_1mo', 'infant_1_12mo', 'toddler_1_5y', 'child_5_12y', 'adolescent_12_18y']

if age_group == 'all':
    groups_to_run = ALL_GROUPS
elif age_group in AGE_PARAMS:
    groups_to_run = [age_group]
else:
    groups_to_run = ALL_GROUPS  # fallback

# ─── CYP maturation functions (sigmoidal Hill model) ──────────────────────────
# Krekels et al. 2012 BJCP; Upreti & Wahlstrom 2016 AAPS J
# MF(age) = age^Hill / (TM50^Hill + age^Hill)
# where age is post-menstrual age (PMA) in weeks; TM50 and Hill are enzyme-specific
# For simplicity we use postnatal age converted to PMA assuming 40-week gestation.

def _pna_to_pma_weeks(postnatal_age_y):
    """Convert postnatal age (years) to post-menstrual age (weeks)."""
    return 40.0 + postnatal_age_y * 52.0

def cyp3a4_maturation(postnatal_age_y):
    """CYP3A4 maturation factor (0–1). TM50=38.4 wk PMA, Hill=3.65 (Upreti 2016)."""
    pma = _pna_to_pma_weeks(postnatal_age_y)
    TM50, hill = 38.4, 3.65
    return pma**hill / (TM50**hill + pma**hill)

def cyp2d6_maturation(postnatal_age_y):
    """CYP2D6 maturation factor. TM50=12.9 wk PMA, Hill=3.40 (Krekels 2012 Table 1)."""
    pma = _pna_to_pma_weeks(postnatal_age_y)
    TM50, hill = 12.9, 3.40
    return pma**hill / (TM50**hill + pma**hill)

def cyp2c19_maturation(postnatal_age_y):
    """CYP2C19 maturation factor. TM50=26.4 wk PMA, Hill=2.59 (Upreti 2016)."""
    pma = _pna_to_pma_weeks(postnatal_age_y)
    TM50, hill = 26.4, 2.59
    return pma**hill / (TM50**hill + pma**hill)

def hepatic_maturation_factor(age_y):
    """
    Composite CYP maturation for hepatic CL.
    Assume CYP3A4 dominant (largest hepatic CYP); weight 0.5 CYP3A4 + 0.3 CYP2D6 + 0.2 CYP2C19.
    Adult reference: all maturation factors → 1.0.
    """
    f3a4  = cyp3a4_maturation(age_y)
    f2d6  = cyp2d6_maturation(age_y)
    f2c19 = cyp2c19_maturation(age_y)
    return 0.5 * f3a4 + 0.3 * f2d6 + 0.2 * f2c19

# ─── GFR maturation (Schwartz / Rhodin model) ─────────────────────────────────
# GFR(age) = GFR_adult * gfr_frac (pre-tabulated above from Rhodin 2009 population data)
# For scaled renal CL: CL_renal_peds = CL_renal_adult * (GFR_peds / GFR_adult) * allometric_factor

def renal_cl_pediatric(renal_cl_adult_L_h, bw_kg, gfr_frac):
    """
    Scale adult renal CL to paediatric using:
      1. Allometric size scaling (BW^0.75) relative to adult 70 kg
      2. GFR maturation correction
    """
    allometric = (bw_kg / ADULT_BW_KG) ** 0.75
    return renal_cl_adult_L_h * allometric * gfr_frac

# ─── Protein binding maturation ───────────────────────────────────────────────
# Johnson 2008 ClinPharmacokinet: albumin lower in neonates (0.6× adult).
# AGP (alpha-1 acid glycoprotein) also reduced but less studied.
# fu_peds = 1 - (ppb_adult * albumin_frac_of_adult)
# Corrected fu propagates through unbound hepatic CL (Wells-Stein model).

def fu_pediatric(fu_adult_val, albumin_frac):
    """Unbound fraction in paediatric plasma."""
    ppb_adult_val = 1.0 - fu_adult_val
    ppb_peds = ppb_adult_val * albumin_frac
    return 1.0 - ppb_peds

# ─── Hepatic CL: Wells-Stein model ────────────────────────────────────────────
# CL_hepatic = Q_h * fu * CL_int / (Q_h + fu * CL_int)
# CL_int derived from adult CL_hepatic; scaled for paediatric fu + CYP maturation + Q_h.

def clint_from_adult_hepatic_cl(cl_hepatic_L_h, qh_adult_L_h=96.0, fu_adult_val=0.15):
    """Back-calculate adult intrinsic CL from adult hepatic CL (Wells-Stein)."""
    # CL_h = Qh * fu * CLint / (Qh + fu * CLint)
    # => fu * CLint = Qh * CL_h / (Qh - CL_h)
    denom = qh_adult_L_h - cl_hepatic_L_h
    if denom <= 0:
        denom = 0.1  # avoid div/0 for high-extraction drugs
    return qh_adult_L_h * cl_hepatic_L_h / denom / fu_adult_val

ADULT_QH_L_H = 96.0   # hepatic blood flow adult (L/h; Willmann 2003)

def hepatic_cl_pediatric(cl_hepatic_adult_L_h, bw_kg, age_y, fu_peds_val, qh_peds_L_h):
    """
    Paediatric hepatic CL via scaled CLint:
      CLint_peds = CLint_adult * mat_factor * allometric
      Then Wells-Stein with paediatric fu and Qh.
    """
    fu_adult_val = fu_adult
    cl_int_adult = clint_from_adult_hepatic_cl(cl_hepatic_adult_L_h, ADULT_QH_L_H, fu_adult_val)
    allometric   = (bw_kg / ADULT_BW_KG) ** 0.75
    mat_factor   = hepatic_maturation_factor(age_y)
    cl_int_peds  = cl_int_adult * allometric * mat_factor
    # Wells-Stein
    num = qh_peds_L_h * fu_peds_val * cl_int_peds
    den = qh_peds_L_h + fu_peds_val * cl_int_peds
    return num / den if den > 0 else 0.0

# ─── Volume of distribution scaling ───────────────────────────────────────────
# Vd ∝ BW^1.0 (Anderson & Holford 2008); also adjusted for tissue/plasma water fractions.

def vd_pediatric(vd_adult_L, bw_kg, fat_frac, water_frac,
                 adult_fat=0.21, adult_water=0.60):
    """
    Allometric Vd scaling with body composition adjustment.
    Vd_peds = Vd_adult * (BW_peds/BW_adult)^1.0 * (water_frac_peds/water_frac_adult)
    Fat fraction adjustment is secondary for hydrophilic drugs.
    """
    allometric   = bw_kg / ADULT_BW_KG
    water_adj    = water_frac / adult_water if adult_water > 0 else 1.0
    return vd_adult_L * allometric * water_adj

# ─── NCA-derived PK endpoints ─────────────────────────────────────────────────

def compute_pk(cl_L_h, vd_L, dose_mg_kg, bw_kg, route_str):
    """
    Compute t½, Cmax, AUC for a 1-compartment model.
    IV bolus:  Cmax = dose/Vd;  AUC = dose/CL
    Oral (F assumed from hep_extract): Cmax estimated from Tmax~0.5h (lag);
      AUC = F * dose / CL;  Cmax ~ F * dose / Vd * exp(-ke * Tmax)
    """
    dose_mg = dose_mg_kg * bw_kg
    ke      = cl_L_h / vd_L if vd_L > 0 else 0.001
    t_half  = math.log(2) / ke if ke > 0 else float('inf')

    if route_str == 'iv':
        cmax_mg_L = dose_mg / vd_L if vd_L > 0 else 0.0
        auc       = dose_mg / cl_L_h if cl_L_h > 0 else float('inf')
    else:
        # oral: bioavailability F = 1 - hep_extract (hepatic first-pass only)
        F         = max(0.01, 1.0 - hep_extract)
        ka        = 2.0    # absorption rate constant (h⁻¹); typical oral
        tmax      = math.log(ka / ke) / (ka - ke) if ka != ke and ka > ke else 0.5
        tmax      = max(0.25, min(tmax, 4.0))
        # Bateman equation Cmax
        cmax_mg_L = (F * dose_mg * ka / (vd_L * (ka - ke))) * (
                    math.exp(-ke * tmax) - math.exp(-ka * tmax)) if abs(ka - ke) > 1e-6 else 0.0
        auc       = F * dose_mg / cl_L_h if cl_L_h > 0 else float('inf')

    return {
        'CL_L_h':         round(cl_L_h,  4),
        'Vd_L':           round(vd_L,    4),
        't_half_h':       round(t_half,  3),
        'Cmax_mg_L':      round(cmax_mg_L, 4),
        'AUC_mg_h_L':     round(auc,      4),
    }

# ─── Dose recommendation (target-AUC matching) ────────────────────────────────

def dose_recommendation(adult_auc, peds_cl, bw_kg, route_str):
    """
    Compute paediatric dose in mg/kg that reproduces adult AUC.
    For oral: accounts for paediatric F = 1 - hep_extract.
    """
    if route_str == 'iv':
        # AUC = dose_total / CL  => dose_total = AUC * CL
        dose_total_mg = adult_auc * peds_cl
    else:
        F = max(0.01, 1.0 - hep_extract)
        dose_total_mg = adult_auc * peds_cl / F
    return dose_total_mg / bw_kg if bw_kg > 0 else float('inf')

# ─── Adult reference PK ───────────────────────────────────────────────────────
adult_pk = compute_pk(adult_cl, adult_vd, dose_mg_kg, ADULT_BW_KG, route)
adult_auc = adult_pk['AUC_mg_h_L']

# ─── Simulate each age group ──────────────────────────────────────────────────
results_by_group = {}
warnings_by_group = {}

for grp in groups_to_run:
    p = AGE_PARAMS[grp]
    bw         = p['BW_kg']
    age_y      = p['age_midpoint_y']
    gfr_frac   = p['gfr_frac']
    alb_frac   = p['albumin_frac']
    qh         = p['blood_flow_liver_L_h']
    fat_frac   = p['fat_fraction']
    water_frac = p['water_fraction']

    # Protein binding
    fu_peds = fu_pediatric(fu_adult, alb_frac)

    # Hepatic CL (Wells-Stein + CYP maturation + allometric)
    cl_hep_peds = hepatic_cl_pediatric(hepatic_cl, bw, age_y, fu_peds, qh)

    # Renal CL (allometric + GFR maturation)
    cl_ren_peds = renal_cl_pediatric(renal_cl_L_h, bw, gfr_frac)

    # Total paediatric CL
    cl_total_peds = cl_hep_peds + cl_ren_peds

    # Vd (allometric + body composition)
    vd_peds = vd_pediatric(adult_vd, bw, fat_frac, water_frac)

    # PK endpoints
    pk = compute_pk(cl_total_peds, vd_peds, dose_mg_kg, bw, route)

    # Dose recommendation (target adult AUC)
    rec_dose = dose_recommendation(adult_auc, cl_total_peds, bw, route)
    rec_dose = round(rec_dose, 4)

    # FDA/EMA compliance warnings (ICH E11(R1) 2017)
    grp_warnings = []
    cyp3a4_mat = cyp3a4_maturation(age_y)
    cyp_flag = cyp3a4_mat < 0.50

    if grp == 'neonate_0_1mo':
        grp_warnings.append(
            'ICH E11(R1): Extrapolation from adult data unreliable for neonates; '
            'CYP3A4 maturation {:.0f}% adult; independent neonatal PK study required.'.format(
                cyp3a4_mat * 100))
    if cyp_flag and grp != 'neonate_0_1mo':
        grp_warnings.append(
            'CYP3A4 maturation {:.0f}% adult; elevated exposure risk; '
            'monitor closely.'.format(cyp3a4_mat * 100))
    if rec_dose > dose_mg_kg * 2.0:
        grp_warnings.append(
            'Recommended paediatric dose ({:.2f} mg/kg) exceeds 2x adult mg/kg '
            '({:.2f} mg/kg); dose capping recommended.'.format(rec_dose, dose_mg_kg))
    if rec_dose < 0.1 * dose_mg_kg:
        grp_warnings.append(
            'Recommended paediatric dose ({:.4f} mg/kg) < 10% of adult mg/kg; '
            'verify model validity.'.format(rec_dose))

    # Maturation factors for reporting
    mf = {
        'CYP3A4': round(cyp3a4_maturation(age_y), 3),
        'CYP2D6': round(cyp2d6_maturation(age_y), 3),
        'CYP2C19': round(cyp2c19_maturation(age_y), 3),
        'composite_hepatic': round(hepatic_maturation_factor(age_y), 3),
        'GFR_frac_adult': round(gfr_frac, 3),
        'albumin_frac_adult': round(alb_frac, 3),
    }

    results_by_group[grp] = {
        'age_group':           grp,
        'label':               p['label'],
        'physiology': {
            'BW_kg':           bw,
            'BSA_m2':          p['BSA_m2'],
            'age_midpoint_y':  age_y,
            'fat_fraction':    fat_frac,
            'water_fraction':  water_frac,
            'liver_weight_kg': p['organ_liver_kg'],
            'kidney_weight_kg':p['organ_kidney_kg'],
            'hepatic_blood_flow_L_h': qh,
        },
        'maturation_factors':  mf,
        'pk': {
            'CL_L_h':          pk['CL_L_h'],
            'CL_hepatic_L_h':  round(cl_hep_peds, 4),
            'CL_renal_L_h':    round(cl_ren_peds, 4),
            'Vd_L':            pk['Vd_L'],
            't_half_h':        pk['t_half_h'],
            'Cmax_mg_L':       pk['Cmax_mg_L'],
            'AUC_mg_h_L':      pk['AUC_mg_h_L'],
            'fu_plasma':       round(fu_peds, 4),
        },
        'dose_recommendation_mg_kg': rec_dose,
        'compliance_warnings':       grp_warnings,
    }
    warnings_by_group[grp] = grp_warnings

# ─── Assemble full result ──────────────────────────────────────────────────────
result = {
    'status': 'completed',
    'indication': indication,
    'route': route,
    'adult_reference': {
        'CL_L_h':       round(adult_cl, 4),
        'Vd_L':         round(adult_vd, 4),
        'dose_mg_kg':   dose_mg_kg,
        'CL_hepatic_L_h': round(hepatic_cl, 4),
        'CL_renal_L_h': round(renal_cl_L_h, 4),
        'fu_plasma':    round(fu_adult, 4),
        'AUC_mg_h_L':   adult_pk['AUC_mg_h_L'],
        't_half_h':     adult_pk['t_half_h'],
        'Cmax_mg_L':    adult_pk['Cmax_mg_L'],
    },
    'age_groups': results_by_group,
    'simulation_settings': {
        'allometric_exponent_CL':  0.75,
        'allometric_exponent_Vd':  1.00,
        'hepatic_model':           'Wells-Stein (Qh * fu * CLint / (Qh + fu * CLint))',
        'cyp_maturation_model':    'Hill sigmoidal (Krekels 2012; Upreti 2016)',
        'gfr_maturation_model':    'Rhodin 2009 population GFR fractions',
        'protein_binding_model':   'Albumin fraction scaling (Johnson 2008)',
        'body_composition_source': 'Willmann 2003 ClinPharmacokinet physiology database',
    },
    'references': [
        'Anderson BJ & Holford NH 2008 Annu Rev Pharmacol Toxicol 48:303-332 (allometric scaling)',
        'Krekels EH et al. 2012 Br J Clin Pharmacol 74(3):525-536 (CYP maturation)',
        'Upreti VV & Wahlstrom JL 2016 AAPS J 18(1):171-184 (paediatric PBPK maturation)',
        'ICH E11(R1) Addendum 2017 — Clinical Investigation of Medicinal Products in the Paediatric Population',
        'Rhodin MM et al. 2009 Pediatr Nephrol 24(1):67-76 (GFR maturation)',
        'Johnson TN 2008 Clin Pharmacokinet 47(1):1-21 (protein binding maturation)',
        'Willmann S et al. 2003 Clin Pharmacokinet 42(14):1271-1289 (physiology database)',
    ],
}

with open('pediatric_pk_results.json', 'w') as f:
    json.dump(result, f, indent=2)

# ─── age_group_pk.csv ─────────────────────────────────────────────────────────
with open('age_group_pk.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow([
        'age_group', 'label', 'BW_kg', 'BSA_m2', 'fu_plasma',
        'CL_L_h', 'CL_hepatic_L_h', 'CL_renal_L_h',
        'Vd_L', 't_half_h', 'Cmax_mg_L', 'AUC_mg_h_L',
        'CYP3A4_mat', 'CYP2D6_mat', 'CYP2C19_mat', 'GFR_frac_adult',
        'albumin_frac_adult', 'compliance_flag',
    ])
    for grp, r in results_by_group.items():
        pk  = r['pk']
        mf  = r['maturation_factors']
        phy = r['physiology']
        w.writerow([
            grp,
            r['label'],
            phy['BW_kg'],
            phy['BSA_m2'],
            pk['fu_plasma'],
            pk['CL_L_h'],
            pk['CL_hepatic_L_h'],
            pk['CL_renal_L_h'],
            pk['Vd_L'],
            pk['t_half_h'],
            pk['Cmax_mg_L'],
            pk['AUC_mg_h_L'],
            mf['CYP3A4'],
            mf['CYP2D6'],
            mf['CYP2C19'],
            mf['GFR_frac_adult'],
            mf['albumin_frac_adult'],
            'YES' if r['compliance_warnings'] else 'NO',
        ])

# ─── dose_recommendations.csv ─────────────────────────────────────────────────
with open('dose_recommendations.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow([
        'age_group', 'label', 'BW_kg',
        'adult_dose_mg_kg', 'recommended_dose_mg_kg', 'recommended_dose_mg',
        'expected_AUC_mg_h_L', 'adult_AUC_mg_h_L', 'AUC_ratio',
        'dose_flag', 'compliance_warnings',
    ])
    for grp, r in results_by_group.items():
        rec    = r['dose_recommendation_mg_kg']
        bw     = r['physiology']['BW_kg']
        pk     = r['pk']
        # Expected AUC at recommended dose
        exp_auc = adult_auc   # by construction
        auc_ratio = round(pk['AUC_mg_h_L'] / adult_auc, 3) if adult_auc > 0 else None
        flag   = 'HIGH' if rec > dose_mg_kg * 2.0 else ('LOW' if rec < dose_mg_kg * 0.1 else 'OK')
        w.writerow([
            grp,
            r['label'],
            bw,
            dose_mg_kg,
            round(rec, 4),
            round(rec * bw, 3),
            round(exp_auc, 4),
            round(adult_auc, 4),
            auc_ratio,
            flag,
            ' | '.join(r['compliance_warnings']) if r['compliance_warnings'] else 'none',
        ])

# ─── pk_report.txt ────────────────────────────────────────────────────────────
lines = [
    '╔══════════════════════════════════════════════════════════════════════════╗',
    '  Paediatric PBPK Simulation Report',
    f'  Indication: {indication.upper()} | Route: {route.upper()}',
    '╚══════════════════════════════════════════════════════════════════════════╝',
    '',
    '  Adult Reference',
    '  ─────────────────────────────────────────────',
    f'  CL (total):     {adult_cl:.3f} L/h   (hepatic {hepatic_cl:.3f} + renal {renal_cl_L_h:.3f})',
    f'  Vd:             {adult_vd:.3f} L',
    f'  fu (plasma):    {fu_adult:.3f}',
    f'  t½:             {adult_pk["t_half_h"]:.3f} h',
    f'  AUC:            {adult_pk["AUC_mg_h_L"]:.4f} mg·h/L  (at {dose_mg_kg} mg/kg)',
    f'  Cmax:           {adult_pk["Cmax_mg_L"]:.4f} mg/L',
    '',
    '  Scaling Methods',
    '  ─────────────────────────────────────────────',
    '  CL:  Allometric BW^0.75 + CYP maturation (Hill; Krekels 2012) + GFR maturation',
    '  Vd:  Allometric BW^1.0  + body water fraction adjustment',
    '  fu:  Albumin fraction scaling (Johnson 2008; 0.60x adult in neonates)',
    '  GFR: Rhodin 2009 population maturation fractions',
    '',
    '  Age Group Results',
    '  ─────────────────────────────────────────────',
]

for grp in groups_to_run:
    r   = results_by_group[grp]
    pk  = r['pk']
    mf  = r['maturation_factors']
    rec = r['dose_recommendation_mg_kg']
    auc_ratio = pk['AUC_mg_h_L'] / adult_auc if adult_auc > 0 else float('nan')
    lines += [
        '',
        f'  [{r["label"]}]',
        f'    BW: {r["physiology"]["BW_kg"]} kg  |  BSA: {r["physiology"]["BSA_m2"]} m²',
        f'    Maturation — CYP3A4: {mf["CYP3A4"]:.2f}  CYP2D6: {mf["CYP2D6"]:.2f}'
        f'  CYP2C19: {mf["CYP2C19"]:.2f}  GFR: {mf["GFR_frac_adult"]:.2f}x adult',
        f'    Albumin: {mf["albumin_frac_adult"]:.2f}x adult  |  fu: {pk["fu_plasma"]:.3f}',
        f'    CL: {pk["CL_L_h"]:.4f} L/h  '
        f'(hep {pk["CL_hepatic_L_h"]:.4f} + ren {pk["CL_renal_L_h"]:.4f})',
        f'    Vd: {pk["Vd_L"]:.4f} L  |  t½: {pk["t_half_h"]:.3f} h',
        f'    AUC: {pk["AUC_mg_h_L"]:.4f} mg·h/L  '
        f'(ratio vs adult: {auc_ratio:.2f}x)',
        f'    Cmax: {pk["Cmax_mg_L"]:.4f} mg/L',
        f'    Recommended dose: {rec:.4f} mg/kg',
    ]
    if r['compliance_warnings']:
        for w in r['compliance_warnings']:
            lines.append(f'    ⚠ {w}')

lines += [
    '',
    '  References',
    '  ─────────────────────────────────────────────',
    '  Anderson & Holford 2008 Annu Rev Pharmacol Toxicol 48:303-332',
    '  Krekels et al. 2012 Br J Clin Pharmacol 74(3):525-536',
    '  Upreti & Wahlstrom 2016 AAPS J 18(1):171-184',
    '  ICH E11(R1) Addendum 2017',
    '  Rhodin et al. 2009 Pediatr Nephrol 24(1):67-76',
    '  Johnson 2008 Clin Pharmacokinet 47(1):1-21',
]

with open('pk_report.txt', 'w') as f:
    f.write('\n'.join(lines))
print('\n'.join(lines))
PYEOF

    python3 -c "print('pbpk_pediatric: 1.0')" > versions.yml
    """
}

workflow PBPK_PEDIATRIC_WORKFLOW {
    take: meta_ch
    main: PBPK_PEDIATRIC(meta_ch)
    emit:
        results             = PBPK_PEDIATRIC.out.results
        age_group_pk        = PBPK_PEDIATRIC.out.age_group_pk
        dose_recommendations = PBPK_PEDIATRIC.out.dose_recommendations
        report              = PBPK_PEDIATRIC.out.report
}

workflow { meta = [id:'peds_run']; Channel.value(meta) | PBPK_PEDIATRIC_WORKFLOW }
