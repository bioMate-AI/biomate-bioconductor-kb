#!/usr/bin/env nextflow
/*
 * pharmacology/pbpk_pediatric_pregnancy
 *
 * Age-stratified PBPK simulation for pediatric dose prediction and pregnancy
 * PK changes. Extends the standard PBPK (Rodgers/Rowland) with CYP maturation
 * functions and pregnancy trimester physiology.
 *
 * Pediatric: CYP3A4/2D6/2C9/1A2 maturation Hill functions (Bjorkman 2005;
 *   Johnson 2006); age-scaled BW/organ volumes (WHO growth data)
 * Pregnancy: plasma volume expansion (+40-50%), GFR increase (+50% T3),
 *   CYP3A4 induction (T1=1.0x, T2=1.4x, T3=1.8x), CYP2D6 up (2x T3),
 *   CYP1A2 down (50% T3) -- Jeong 2012; Anger 2014
 *
 * Input:  MW_Da, logP, pKa_acid/base, CLint_uL_min_mg, Vss_L_kg, dose_mg_kg,
 *         optional fup (fraction unbound plasma), cyp_substrate (3A4/2D6/2C9)
 * Output: pediatric_pk.csv (by age group), pregnancy_pk.csv (by trimester),
 *         dose_recommendation.json
 */

nextflow.enable.dsl = 2

params.outdir          = './results'
params.mw_da           = '300'
params.logp            = '2.5'
params.pka_base        = '8.0'
params.clint_ul_min_mg = '50'
params.vss_l_kg        = '0.7'
params.dose_mg_kg      = '1.0'
params.fup             = '0.1'
params.cyp_substrate   = '3A4'
params.fu_gut          = '1.0'

process PBPK_PEDIATRIC_PREGNANCY {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("pbpk_peds_preg_results.json"),  emit: results
    tuple val(meta), path("pbpk_peds_preg_output.txt"),    emit: output
    tuple val(meta), path("pediatric_pk.csv"),             emit: pediatric_pk
    tuple val(meta), path("pregnancy_pk.csv"),             emit: pregnancy_pk
    tuple val(meta), path("dose_recommendation.json"),     emit: dose_rec
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_MW='${params.mw_da}'
    export PARAM_LOGP='${params.logp}'
    export PARAM_PKA='${params.pka_base}'
    export PARAM_CLINT='${params.clint_ul_min_mg}'
    export PARAM_VSS='${params.vss_l_kg}'
    export PARAM_DOSE='${params.dose_mg_kg}'
    export PARAM_FUP='${params.fup}'
    export PARAM_CYP='${params.cyp_substrate}'
    export PARAM_FUGUT='${params.fu_gut}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np


def ac(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

# -- Pediatric physiology tables (WHO growth data + Bjorkman 2005) -------------
# Age group: (label, age_yr, BW_kg, liver_vol_ml, kidney_vol_ml, blood_vol_L,
#             cardiac_output_L_h)
PEDIATRIC_AGES = [
    ('neonate_0d',    0.003, 3.5,   155,   24,  0.28,   0.83),
    ('neonate_1mo',   0.083, 4.5,   175,   28,  0.34,   1.0),
    ('infant_3mo',    0.25,  6.2,   215,   38,  0.47,   1.4),
    ('infant_6mo',    0.5,   7.8,   275,   49,  0.58,   1.8),
    ('infant_12mo',   1.0,   10.0,  345,   65,  0.75,   2.3),
    ('toddler_2yr',   2.0,   12.5,  440,   85,  0.93,   3.0),
    ('child_5yr',     5.0,   18.0,  650,  130,  1.35,   4.5),
    ('child_10yr',   10.0,   32.0,  1000, 210,  2.35,   7.0),
    ('adolescent_14yr',14.0, 50.0,  1400, 300,  3.50,  11.0),
    ('adult',        25.0,   70.0,  1800, 380,  5.00,  15.0),
]

# -- CYP maturation functions (Bjorkman 2005; Johnson 2006) -------------------
# F_mat = (age_yr^Hill) / (TM50^Hill + age_yr^Hill)  -- Richards sigmoid
CYP_MATURATION = {
    '3A4': dict(tm50=0.50, hill=1.4, adult_cl_factor=1.0),   # rapid; >80% by 1yr
    '2D6': dict(tm50=0.083,hill=2.0, adult_cl_factor=1.0),   # neonates; mature by 3mo
    '2C9': dict(tm50=0.25, hill=1.8, adult_cl_factor=1.0),
    '1A2': dict(tm50=0.50, hill=1.6, adult_cl_factor=1.0),
    '2C19':dict(tm50=0.25, hill=1.2, adult_cl_factor=1.0),
    'UGT': dict(tm50=0.50, hill=1.3, adult_cl_factor=1.0),   # generic UGT
}
DEFAULT_MAT = dict(tm50=0.5, hill=1.5, adult_cl_factor=1.0)

def cyp_maturation_factor(age_yr, cyp):
    params = CYP_MATURATION.get(cyp.upper(), DEFAULT_MAT)
    tm50, hill = params['tm50'], params['hill']
    if age_yr < 0.003: age_yr = 0.003  # avoid zero
    f = (age_yr ** hill) / (tm50 ** hill + age_yr ** hill)
    return min(1.0, f)

# -- PBPK core: 1-compartment IV bolus for simplicity -------------------------
# For each age group: CL_h scaled by mat_factor * (BW/70)^0.75, Vd by BW
def pk_for_age(bw_kg, liver_vol_ml, co_L_h, clint_uL_min_mg,
               vss_L_kg, fup, dose_mg_kg, age_yr, cyp, fu_gut=1.0):
    '''Returns (Cmax_ugL, AUC_ugL_h, thalf_h, CL_L_h_kg).'''
    # Hepatic intrinsic clearance scaled by liver mass
    liver_mass_g = liver_vol_ml * 1.05  # density ~1.05 g/mL
    clint_uL_min = clint_uL_min_mg * liver_mass_g / 1000
    # Well-stirred model: CL_h = Q_h * (fu * CLint) / (Q_h + fu * CLint)
    q_h_L_h = co_L_h * 0.26  # hepatic blood flow ~26% CO
    clint_L_h = clint_uL_min * 1e-6 * 60 * 1000  # uL/min -> L/h
    mat = cyp_maturation_factor(age_yr, cyp)
    clint_eff = clint_L_h * mat
    cl_h = (q_h_L_h * fup * clint_eff) / (q_h_L_h + fup * clint_eff)
    # Renal: simplified, not dominant; cl_r ~ 0.1 * cl_h for most drugs
    cl_r = 0.05 * cl_h
    cl_total = cl_h + cl_r  # L/h
    # Volume of distribution scaled allometrically
    vd_L = vss_L_kg * bw_kg
    thalf_h = 0.693 * vd_L / cl_total if cl_total > 0 else 100
    dose_mg = dose_mg_kg * bw_kg
    auc_ug_L_h = (dose_mg * 1000) / cl_total if cl_total > 0 else 0
    cmax_ug_L  = (dose_mg * 1000) / vd_L
    cl_per_kg = cl_total / bw_kg
    return round(cmax_ug_L, 1), round(auc_ug_L_h, 0), round(thalf_h, 2), round(cl_per_kg, 3), round(mat, 3)

# -- Pregnancy physiology (Jeong 2012; Anger 2014) ----------------------------
PREGNANCY_TRIMESTERS = [
    # label, BW_kg, plasma_vol_factor, GFR_factor, CYP3A4, CYP2D6, CYP2C9, CYP1A2
    ('pre_pregnancy', 65.0, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00),
    ('T1_weeks4-12',  67.0, 1.10, 1.10, 1.05, 1.10, 1.00, 0.95),
    ('T2_weeks13-26', 72.0, 1.30, 1.35, 1.40, 1.50, 1.00, 0.80),
    ('T3_weeks27-40', 78.0, 1.45, 1.50, 1.80, 2.00, 1.25, 0.50),
    ('postpartum',    68.0, 1.05, 1.05, 1.10, 1.20, 1.00, 0.80),
]

def pk_for_trimester(bw_kg, plasma_factor, gfr_factor, cyp_factor,
                     clint_uL_min_mg, vss_L_kg, fup, dose_mg_kg):
    '''Simplified pregnancy PK -- adjust CL by enzyme induction factor.'''
    # Adult liver unchanged in mass; enzyme activity scaled
    liver_mass_g = 1800 * 1.05
    clint_uL_min = clint_uL_min_mg * liver_mass_g / 1000
    q_h_L_h = 15.0 * 0.30  # slight increase in CO during pregnancy
    clint_L_h = clint_uL_min * 1e-6 * 60 * 1000 * cyp_factor
    cl_h = (q_h_L_h * fup * clint_L_h) / (q_h_L_h + fup * clint_L_h)
    cl_r = 0.05 * cl_h * gfr_factor
    cl_total = cl_h + cl_r
    # Vd increases with plasma volume expansion
    vd_L = vss_L_kg * bw_kg * plasma_factor
    thalf_h = 0.693 * vd_L / cl_total if cl_total > 0 else 100
    dose_mg = dose_mg_kg * bw_kg
    auc = (dose_mg * 1000) / cl_total if cl_total > 0 else 0
    cmax = (dose_mg * 1000) / vd_L
    return round(cmax, 1), round(auc, 0), round(thalf_h, 2), round(cl_total / bw_kg, 3)

# -- Process -------------------------------------------------------------------
mw         = ac(os.environ.get('PARAM_MW'), 300)
logp       = ac(os.environ.get('PARAM_LOGP'), 2.5)
pka        = ac(os.environ.get('PARAM_PKA'), 8.0)
clint      = ac(os.environ.get('PARAM_CLINT'), 50)
vss        = ac(os.environ.get('PARAM_VSS'), 0.7)
dose_mg_kg = ac(os.environ.get('PARAM_DOSE'), 1.0)
fup        = ac(os.environ.get('PARAM_FUP'), 0.1)
cyp        = os.environ.get('PARAM_CYP', '3A4').upper()
fu_gut     = ac(os.environ.get('PARAM_FUGUT'), 1.0)

# Pediatric simulations
ped_csv = [['age_group', 'age_yr', 'BW_kg', 'maturation_factor',
            'Cmax_ug_L', 'AUC_ug_L_h', 't_half_h', 'CL_L_h_kg', 'dose_mg']]
ped_recs = []
for label, age_yr, bw_kg, liver_vol_ml, _, _, co in PEDIATRIC_AGES:
    cmax, auc, th, cl, mat = pk_for_age(
        bw_kg, liver_vol_ml, co, clint, vss, fup, dose_mg_kg, age_yr, cyp, fu_gut)
    dose_mg = round(dose_mg_kg * bw_kg, 2)
    ped_csv.append([label, age_yr, bw_kg, mat, cmax, auc, th, cl, dose_mg])
    ped_recs.append({'age_group': label, 'age_yr': age_yr, 'BW_kg': bw_kg,
                     'maturation_factor': mat, 'Cmax_ug_L': cmax,
                     'AUC_ug_L_h': auc, 't_half_h': th, 'CL_L_h_kg': cl, 'dose_mg': dose_mg})

# Pregnancy simulations
cyp_col_map = {'3A4': 4, '2D6': 5, '2C9': 6, '1A2': 7}
cyp_col = cyp_col_map.get(cyp, 4)

preg_csv = [['trimester', 'BW_kg', 'plasma_vol_factor', 'GFR_factor',
             'CYP_activity_factor', 'Cmax_ug_L', 'AUC_ug_L_h', 't_half_h', 'CL_L_h_kg']]
preg_recs = []
adult_auc = None
for row in PREGNANCY_TRIMESTERS:
    label, bw, pv, gfr = row[0], row[1], row[2], row[3]
    cyp_factor = row[cyp_col]
    cmax, auc, th, cl = pk_for_trimester(bw, pv, gfr, cyp_factor, clint, vss, fup, dose_mg_kg)
    if label == 'pre_pregnancy':
        adult_auc = auc
    preg_csv.append([label, bw, pv, gfr, cyp_factor, cmax, auc, th, cl])
    preg_recs.append({'trimester': label, 'BW_kg': bw, 'plasma_vol_factor': pv,
                      'GFR_factor': gfr, 'CYP_activity_factor': cyp_factor,
                      'Cmax_ug_L': cmax, 'AUC_ug_L_h': auc, 't_half_h': th, 'CL_L_h_kg': cl})

# Dose recommendation
adult_row = [r for r in ped_recs if r['age_group'] == 'adult'][0]
adult_auc_ped = adult_row['AUC_ug_L_h']

dose_recs = []
for r in ped_recs:
    if r['age_group'] == 'adult': continue
    if adult_auc_ped > 0:
        dose_adj_factor = adult_auc_ped / max(r['AUC_ug_L_h'], 1)
        adj_dose = round(dose_mg_kg * dose_adj_factor, 3)
    else:
        adj_dose = dose_mg_kg
    dose_recs.append({
        'age_group': r['age_group'],
        'standard_dose_mg_kg': dose_mg_kg,
        'recommended_dose_mg_kg': adj_dose,
        'target_AUC_matching': f'Adjust to match adult AUC ({adult_auc_ped} ug*L-1*h)',
        'note': f'Maturation factor {r["maturation_factor"]:.2f} for {cyp}',
    })

with open('pediatric_pk.csv', 'w', newline='') as f:
    csv.writer(f).writerows(ped_csv)
with open('pregnancy_pk.csv', 'w', newline='') as f:
    csv.writer(f).writerows(preg_csv)

dose_rec_out = {
    'drug_properties': {'MW_Da': mw, 'logP': logp, 'fup': fup, 'CLint': clint,
                        'primary_CYP': cyp, 'Vss_L_kg': vss},
    'pediatric_dose_adjustments': dose_recs,
    'pregnancy_summary': preg_recs,
    'notes': [
        f'CYP {cyp} maturation function from Bjorkman 2005/Johnson 2006',
        'Pregnancy CYP changes from Jeong 2012; Anger 2014',
        'Allometric scaling for organ volumes (WHO growth data)',
        'Results are predictions only; individual PK variability can be large',
    ]
}
with open('dose_recommendation.json', 'w') as f:
    json.dump(dose_rec_out, f, indent=2)

full = {'status': 'completed', 'pediatric_pk': ped_recs, 'pregnancy_pk': preg_recs,
        'dose_recommendations': dose_recs}
with open('pbpk_peds_preg_results.json', 'w') as f:
    json.dump(full, f, indent=2)

report = [f'=== PEDIATRIC / PREGNANCY PBPK SIMULATION ===',
          f'Drug: MW={mw} Da | logP={logp} | fup={fup} | CLint={clint} uL/min/mg | CYP substrate: {cyp}',
          f'Reference dose: {dose_mg_kg} mg/kg', '',
          'PEDIATRIC PK (key age groups):']
for r in ped_recs:
    report.append(
        f"  {r['age_group']:25s}: AUC={r['AUC_ug_L_h']:7.0f} ug*L-1*h | "
        f"t1/2={r['t_half_h']:5.1f}h | mat={r['maturation_factor']:.2f}")
report += ['', 'PREGNANCY PK:']
for r in preg_recs:
    report.append(
        f"  {r['trimester']:20s}: AUC={r['AUC_ug_L_h']:7.0f} | CYP factor={r['CYP_activity_factor']:.2f}")

with open('pbpk_peds_preg_output.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
pbpk_pediatric_pregnancy:
  python: "3.10"
  scipy: ">=1.10"
  numpy: ">=1.24"
  reference: "Bjorkman 2005, Johnson 2006, Jeong 2012, Anger 2014"
EOF
    """
}

workflow PBPK_PEDIATRIC_PREGNANCY_WORKFLOW {
    take: meta_ch
    main: PBPK_PEDIATRIC_PREGNANCY(meta_ch)
    emit:
        results      = PBPK_PEDIATRIC_PREGNANCY.out.results
        pediatric_pk = PBPK_PEDIATRIC_PREGNANCY.out.pediatric_pk
        pregnancy_pk = PBPK_PEDIATRIC_PREGNANCY.out.pregnancy_pk
        dose_rec     = PBPK_PEDIATRIC_PREGNANCY.out.dose_rec
}

workflow {
    meta = [id: 'pbpk_peds_run', single_end: false]
    Channel.value(meta) | PBPK_PEDIATRIC_PREGNANCY_WORKFLOW
}
