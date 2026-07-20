#!/usr/bin/env nextflow
/*
 * drug_discovery/pbpk_pediatric
 *
 * Paediatric PBPK simulation using age-appropriate physiological parameters.
 *
 * Split into 4 phases for BioMate UI phase cards:
 *   Phase A: VALIDATE_COMPOUND_PARAMS
 *   Phase B: PBPK_PEDIATRIC_SIMULATE
 *   Phase C: EVALUATE_MATURATION
 *   Phase D: GENERATE_FINAL_REPORT
 */

nextflow.enable.dsl = 2

params.outdir                   = './results'
params.adult_cl_L_h             = '10.0'
params.adult_vd_L               = '50.0'
params.adult_mw_da              = '400.0'
params.route                    = 'iv'
params.dose_mg_kg               = '1.0'
params.age_group                = 'all'
params.renal_clearance_fraction = '0.3'
params.hepatic_extraction       = '0.4'
params.protein_binding_fraction = '0.85'
params.indication               = 'infectious'

// ---------------------------------------------------------------------------
// Phase A: Input & Validation
// ---------------------------------------------------------------------------
// [Phase A] Compound Parameter Validation
process VALIDATE_COMPOUND_PARAMS {
    tag 'validate'
    label 'process_low'
    publishDir path: "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    output:
    path "validated_params.json", emit: validated_params

    script:
    """
    python3 << 'PYEOF'
import json

def pf(v, d=1.0):
    try: return float(v)
    except: return d

def pclamp(v, lo, hi):
    return max(lo, min(hi, v))

adult_cl    = pf('${params.adult_cl_L_h}', 10.0)
adult_vd    = pf('${params.adult_vd_L}', 50.0)
adult_mw    = pf('${params.adult_mw_da}', 400.0)
route       = '${params.route}'
dose_mg_kg  = pf('${params.dose_mg_kg}', 1.0)
age_group   = '${params.age_group}'
renal_frac  = pclamp(pf('${params.renal_clearance_fraction}', 0.3), 0.0, 1.0)
hep_extract = pclamp(pf('${params.hepatic_extraction}', 0.4), 0.0, 1.0)
ppb         = pclamp(pf('${params.protein_binding_fraction}', 0.85), 0.0, 0.999)
indication  = '${params.indication}'

warnings = []

if adult_cl <= 0:
    warnings.append('adult_cl_L_h must be > 0; set to 10')
    adult_cl = 10.0
if adult_vd <= 0:
    warnings.append('adult_vd_L must be > 0; set to 50')
    adult_vd = 50.0
if dose_mg_kg <= 0:
    warnings.append('dose_mg_kg must be > 0; set to 1.0')
    dose_mg_kg = 1.0

valid_routes = ['iv', 'oral']
if route not in valid_routes:
    warnings.append('Unknown route {}; defaulting to iv'.format(route))
    route = 'iv'

valid_ages = ['neonate_0_1mo', 'infant_1_12mo', 'toddler_1_5y', 'child_5_12y', 'adolescent_12_18y', 'all']
if age_group not in valid_ages:
    warnings.append('Unknown age_group {}; defaulting to all'.format(age_group))
    age_group = 'all'

out = {
    'adult_cl_L_h': adult_cl,
    'adult_vd_L': adult_vd,
    'adult_mw_da': adult_mw,
    'route': route,
    'dose_mg_kg': dose_mg_kg,
    'age_group': age_group,
    'renal_clearance_fraction': renal_frac,
    'hepatic_extraction': hep_extract,
    'protein_binding_fraction': ppb,
    'fu_adult': round(1.0 - ppb, 4),
    'indication': indication,
    'validation_warnings': warnings,
}

with open('validated_params.json', 'w') as f:
    json.dump(out, f, indent=2)

print('Pediatric PBPK validation complete. Warnings: {}'.format(len(warnings)))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase B: Core Computation (Pediatric PBPK Simulation)
// ---------------------------------------------------------------------------
// [Phase B] Pediatric PBPK Simulation (5 Cohorts)
process PBPK_PEDIATRIC_SIMULATE {
    tag 'peds_sim'
    label 'process_medium'
    publishDir path: "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params

    output:
    path "pediatric_pk_profiles.csv", emit: pk_profiles
    path "age_group_params.json",     emit: age_group_params

    script:
    """
    python3 << 'PYEOF'
import json, csv, math, random

with open('${validated_params}') as f:
    vp = json.load(f)

adult_cl    = vp['adult_cl_L_h']
adult_vd    = vp['adult_vd_L']
route       = vp['route']
dose_mg_kg  = vp['dose_mg_kg']
age_group   = vp['age_group']
renal_frac  = vp['renal_clearance_fraction']
hep_extract = vp['hepatic_extraction']
ppb         = vp['protein_binding_fraction']
fu_adult    = vp['fu_adult']
indication  = vp['indication']

ADULT_BW_KG = 70.0
hepatic_cl   = adult_cl * (1.0 - renal_frac)
renal_cl_L_h = adult_cl * renal_frac

AGE_PARAMS = {
    'neonate_0_1mo': {
        'label': 'Neonate (0-1 month)', 'BW_kg': 3.5, 'BSA_m2': 0.22,
        'age_midpoint_y': 0.04, 'organ_liver_kg': 0.130, 'organ_kidney_kg': 0.025,
        'blood_flow_liver_L_h': 5.5, 'fat_fraction': 0.15, 'water_fraction': 0.74,
        'albumin_frac': 0.60, 'gfr_frac': 0.22,
    },
    'infant_1_12mo': {
        'label': 'Infant (1-12 months)', 'BW_kg': 8.0, 'BSA_m2': 0.42,
        'age_midpoint_y': 0.5, 'organ_liver_kg': 0.320, 'organ_kidney_kg': 0.065,
        'blood_flow_liver_L_h': 14.4, 'fat_fraction': 0.22, 'water_fraction': 0.65,
        'albumin_frac': 0.88, 'gfr_frac': 0.65,
    },
    'toddler_1_5y': {
        'label': 'Toddler (1-5 years)', 'BW_kg': 15.0, 'BSA_m2': 0.65,
        'age_midpoint_y': 3.0, 'organ_liver_kg': 0.560, 'organ_kidney_kg': 0.120,
        'blood_flow_liver_L_h': 28.0, 'fat_fraction': 0.18, 'water_fraction': 0.62,
        'albumin_frac': 1.00, 'gfr_frac': 0.90,
    },
    'child_5_12y': {
        'label': 'Child (5-12 years)', 'BW_kg': 30.0, 'BSA_m2': 1.05,
        'age_midpoint_y': 8.5, 'organ_liver_kg': 0.890, 'organ_kidney_kg': 0.220,
        'blood_flow_liver_L_h': 50.4, 'fat_fraction': 0.20, 'water_fraction': 0.60,
        'albumin_frac': 1.00, 'gfr_frac': 1.05,
    },
    'adolescent_12_18y': {
        'label': 'Adolescent (12-18 years)', 'BW_kg': 55.0, 'BSA_m2': 1.55,
        'age_midpoint_y': 15.0, 'organ_liver_kg': 1.350, 'organ_kidney_kg': 0.280,
        'blood_flow_liver_L_h': 76.0, 'fat_fraction': 0.22, 'water_fraction': 0.59,
        'albumin_frac': 1.00, 'gfr_frac': 1.00,
    },
}
ALL_GROUPS = ['neonate_0_1mo', 'infant_1_12mo', 'toddler_1_5y', 'child_5_12y', 'adolescent_12_18y']
groups_to_run = ALL_GROUPS if age_group in ('all', '') else ([age_group] if age_group in AGE_PARAMS else ALL_GROUPS)

def _pna_to_pma_weeks(age_y):
    return 40.0 + age_y * 52.0

def cyp3a4_maturation(age_y):
    pma = _pna_to_pma_weeks(age_y)
    TM50, hill = 38.4, 3.65
    return pma**hill / (TM50**hill + pma**hill)

def cyp2d6_maturation(age_y):
    pma = _pna_to_pma_weeks(age_y)
    TM50, hill = 12.9, 3.40
    return pma**hill / (TM50**hill + pma**hill)

def cyp2c19_maturation(age_y):
    pma = _pna_to_pma_weeks(age_y)
    TM50, hill = 26.4, 2.59
    return pma**hill / (TM50**hill + pma**hill)

def hepatic_maturation_factor(age_y):
    return 0.5 * cyp3a4_maturation(age_y) + 0.3 * cyp2d6_maturation(age_y) + 0.2 * cyp2c19_maturation(age_y)

def fu_pediatric(fu_adult_val, albumin_frac):
    ppb_adult_val = 1.0 - fu_adult_val
    ppb_peds = ppb_adult_val * albumin_frac
    return 1.0 - ppb_peds

def clint_from_adult_hepatic_cl(cl_hepatic_L_h, qh_adult=96.0, fu_adult_val=0.15):
    denom = qh_adult - cl_hepatic_L_h
    if denom <= 0:
        denom = 0.1
    return qh_adult * cl_hepatic_L_h / denom / fu_adult_val

def hepatic_cl_pediatric(cl_hep_adult, bw_kg, age_y, fu_peds_val, qh_peds):
    cl_int_adult = clint_from_adult_hepatic_cl(cl_hep_adult, 96.0, fu_adult)
    allometric   = (bw_kg / ADULT_BW_KG) ** 0.75
    mat_factor   = hepatic_maturation_factor(age_y)
    cl_int_peds  = cl_int_adult * allometric * mat_factor
    num = qh_peds * fu_peds_val * cl_int_peds
    den = qh_peds + fu_peds_val * cl_int_peds
    return num / den if den > 0 else 0.0

def renal_cl_pediatric(renal_cl_adult, bw_kg, gfr_frac):
    allometric = (bw_kg / ADULT_BW_KG) ** 0.75
    return renal_cl_adult * allometric * gfr_frac

def vd_pediatric(vd_adult_L, bw_kg, water_frac, adult_water=0.60):
    allometric = bw_kg / ADULT_BW_KG
    water_adj  = water_frac / adult_water if adult_water > 0 else 1.0
    return vd_adult_L * allometric * water_adj

def compute_pk(cl_L_h, vd_L, dose_mgkg, bw_kg, route_str):
    dose_mg = dose_mgkg * bw_kg
    ke = cl_L_h / vd_L if vd_L > 0 else 0.001
    t_half = math.log(2) / ke if ke > 0 else float('inf')
    if route_str == 'iv':
        cmax_mg_L = dose_mg / vd_L if vd_L > 0 else 0.0
        auc = dose_mg / cl_L_h if cl_L_h > 0 else float('inf')
    else:
        F   = max(0.01, 1.0 - hep_extract)
        ka  = 2.0
        tmax = math.log(ka / ke) / (ka - ke) if ka != ke and ka > ke else 0.5
        tmax = max(0.25, min(tmax, 4.0))
        cmax_mg_L = (F * dose_mg * ka / (vd_L * (ka - ke))) * (
                    math.exp(-ke * tmax) - math.exp(-ka * tmax)) if abs(ka - ke) > 1e-6 else 0.0
        auc = F * dose_mg / cl_L_h if cl_L_h > 0 else float('inf')
    return {
        'CL_L_h': round(cl_L_h, 4),
        'Vd_L': round(vd_L, 4),
        't_half_h': round(t_half, 3),
        'Cmax_mg_L': round(cmax_mg_L, 4),
        'AUC_mg_h_L': round(auc, 4),
    }

adult_pk    = compute_pk(adult_cl, adult_vd, dose_mg_kg, ADULT_BW_KG, route)
adult_auc   = adult_pk['AUC_mg_h_L']

results_by_group = {}
profile_rows = []

for grp in groups_to_run:
    p          = AGE_PARAMS[grp]
    bw         = p['BW_kg']
    age_y      = p['age_midpoint_y']
    gfr_frac   = p['gfr_frac']
    alb_frac   = p['albumin_frac']
    qh         = p['blood_flow_liver_L_h']
    water_frac = p['water_fraction']

    fu_peds     = fu_pediatric(fu_adult, alb_frac)
    cl_hep_peds = hepatic_cl_pediatric(hepatic_cl, bw, age_y, fu_peds, qh)
    cl_ren_peds = renal_cl_pediatric(renal_cl_L_h, bw, gfr_frac)
    cl_total    = cl_hep_peds + cl_ren_peds
    vd_peds     = vd_pediatric(adult_vd, bw, water_frac)
    pk          = compute_pk(cl_total, vd_peds, dose_mg_kg, bw, route)

    # For time-course (simple 1-cmt with 20 time points for profiles CSV)
    ke_grp = cl_total / vd_peds if vd_peds > 0 else 0.001
    dose_mg = dose_mg_kg * bw
    for t_idx in range(21):
        t_h = t_idx * (pk['t_half_h'] * 3 / 20.0)
        if route == 'iv':
            conc = (dose_mg / vd_peds) * math.exp(-ke_grp * t_h) if vd_peds > 0 else 0.0
        else:
            F  = max(0.01, 1.0 - hep_extract)
            ka = 2.0
            conc = max(0.0, (F * dose_mg * ka / (vd_peds * max(ka - ke_grp, 0.001))) *
                       (math.exp(-ke_grp * t_h) - math.exp(-ka * t_h)))
        profile_rows.append({'age_group': grp, 'time_h': round(t_h, 2),
                              'concentration_mg_L': round(max(0, conc), 5)})

    results_by_group[grp] = {
        'age_group': grp,
        'label': p['label'],
        'BW_kg': bw,
        'fu_plasma': round(fu_peds, 4),
        'CL_L_h': pk['CL_L_h'],
        'CL_hepatic_L_h': round(cl_hep_peds, 4),
        'CL_renal_L_h': round(cl_ren_peds, 4),
        'Vd_L': pk['Vd_L'],
        't_half_h': pk['t_half_h'],
        'Cmax_mg_L': pk['Cmax_mg_L'],
        'AUC_mg_h_L': pk['AUC_mg_h_L'],
        'cyp3a4_maturation': round(cyp3a4_maturation(age_y), 3),
        'cyp2d6_maturation': round(cyp2d6_maturation(age_y), 3),
        'gfr_frac': round(gfr_frac, 3),
        'albumin_frac': round(alb_frac, 3),
    }

with open('pediatric_pk_profiles.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['age_group', 'time_h', 'concentration_mg_L'])
    w.writeheader()
    for row in profile_rows:
        w.writerow(row)

age_params_out = {
    'adult_reference': adult_pk,
    'adult_auc': adult_auc,
    'age_groups': results_by_group,
    'route': route,
    'dose_mg_kg': dose_mg_kg,
    'hep_extract': hep_extract,
}

with open('age_group_params.json', 'w') as f:
    json.dump(age_params_out, f, indent=2)

print('Pediatric simulation complete: {} age groups'.format(len(results_by_group)))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase C: Analysis & QC (Maturation + Dose Recommendations)
// ---------------------------------------------------------------------------
// [Phase C] CYP & GFR Maturation Analysis
process EVALUATE_MATURATION {
    tag 'maturation'
    label 'process_low'
    publishDir path: "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path age_group_params

    output:
    path "cyp_maturation.csv",      emit: cyp_csv
    path "dose_recommendation.json", emit: dose_rec

    script:
    """
    python3 << 'PYEOF'
import json, csv, math

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${age_group_params}') as f:
    agp = json.load(f)

adult_auc  = agp['adult_auc']
dose_mg_kg = agp['dose_mg_kg']
route      = agp['route']
hep_extract = vp['hepatic_extraction']
groups     = agp['age_groups']

def _pna_to_pma_weeks(age_y):
    return 40.0 + age_y * 52.0

AGE_PARAMS = {
    'neonate_0_1mo':     {'age_midpoint_y': 0.04, 'gfr_frac': 0.22},
    'infant_1_12mo':     {'age_midpoint_y': 0.5,  'gfr_frac': 0.65},
    'toddler_1_5y':      {'age_midpoint_y': 3.0,  'gfr_frac': 0.90},
    'child_5_12y':       {'age_midpoint_y': 8.5,  'gfr_frac': 1.05},
    'adolescent_12_18y': {'age_midpoint_y': 15.0, 'gfr_frac': 1.00},
}

def cyp3a4_mat(age_y):
    pma = _pna_to_pma_weeks(age_y)
    TM50, hill = 38.4, 3.65
    return pma**hill / (TM50**hill + pma**hill)

def cyp2d6_mat(age_y):
    pma = _pna_to_pma_weeks(age_y)
    TM50, hill = 12.9, 3.40
    return pma**hill / (TM50**hill + pma**hill)

def gfr_fraction(age_y, grp):
    return AGE_PARAMS[grp]['gfr_frac']

with open('cyp_maturation.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['age_group', 'CYP3A4_fraction', 'CYP2D6_fraction', 'GFR_fraction'])
    for grp, params in AGE_PARAMS.items():
        age_y = params['age_midpoint_y']
        w.writerow([grp,
                    round(cyp3a4_mat(age_y), 3),
                    round(cyp2d6_mat(age_y), 3),
                    round(params['gfr_frac'], 3)])

dose_recs = {}
warnings = []
for grp, r in groups.items():
    cl_peds = r['CL_L_h']
    bw      = r['BW_kg']
    F       = max(0.01, 1.0 - hep_extract) if route == 'oral' else 1.0
    if route == 'iv':
        dose_total_mg = adult_auc * cl_peds
    else:
        dose_total_mg = adult_auc * cl_peds / F
    rec_dose = dose_total_mg / bw if bw > 0 else float('inf')
    rec_dose = round(rec_dose, 4)

    grp_warnings = []
    if grp == 'neonate_0_1mo':
        grp_warnings.append('ICH E11(R1): neonatal extrapolation unreliable; independent study required')
    if rec_dose > dose_mg_kg * 2.0:
        grp_warnings.append('Recommended dose {:.2f} mg/kg > 2x adult; dose capping recommended'.format(rec_dose))
    if grp_warnings:
        warnings.extend(grp_warnings)

    dose_recs[grp] = {
        'label': r['label'],
        'BW_kg': bw,
        'recommended_dose_mg_kg': rec_dose,
        'recommended_dose_mg': round(rec_dose * bw, 3),
        'auc_ratio_vs_adult': round(r['AUC_mg_h_L'] / adult_auc, 3) if adult_auc > 0 else None,
        'compliance_warnings': grp_warnings,
    }

out = {
    'dose_recommendations': dose_recs,
    'ich_e11_warnings': warnings,
}

with open('dose_recommendation.json', 'w') as f:
    json.dump(out, f, indent=2)

print('Maturation evaluation complete: {} groups'.format(len(dose_recs)))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase D: Report & Export
// ---------------------------------------------------------------------------
// [Phase D] Dose Recommendation Report
process GENERATE_FINAL_REPORT {
    tag 'report'
    label 'process_low'
    publishDir path: "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path age_group_params
    path cyp_csv
    path dose_rec

    output:
    path "pediatric_pk_report.json", emit: report_json
    path "pediatric_summary.html",   emit: html_report
    path "versions.yml",             emit: versions

    script:
    """
    python3 << 'PYEOF'
import json, csv

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${age_group_params}') as f:
    agp = json.load(f)
with open('${dose_rec}') as f:
    dr = json.load(f)

report = {
    'status': 'completed',
    'indication': vp['indication'],
    'route': vp['route'],
    'adult_reference': agp['adult_reference'],
    'age_groups': agp['age_groups'],
    'dose_recommendations': dr['dose_recommendations'],
    'ich_e11_warnings': dr['ich_e11_warnings'],
    'references': [
        'Anderson & Holford 2008 Annu Rev Pharmacol Toxicol 48:303-332',
        'Krekels et al. 2012 Br J Clin Pharmacol 74(3):525-536',
        'ICH E11(R1) Addendum 2017',
        'Rhodin et al. 2009 Pediatr Nephrol 24(1):67-76',
    ],
}

with open('pediatric_pk_report.json', 'w') as f:
    json.dump(report, f, indent=2)

table_rows = ''
for grp, r in agp['age_groups'].items():
    rec = dr['dose_recommendations'].get(grp, {})
    table_rows += '<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>\\n'.format(
        r['label'], r['BW_kg'], r['t_half_h'],
        r['Cmax_mg_L'], r['AUC_mg_h_L'],
        rec.get('recommended_dose_mg_kg', 'N/A'))

cyp_rows = ''
with open('${cyp_csv}') as f:
    reader = csv.DictReader(f)
    for row in reader:
        cyp_rows += '<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>\\n'.format(
            row['age_group'], row['CYP3A4_fraction'], row['CYP2D6_fraction'], row['GFR_fraction'])

warn_html = ''
for w in dr.get('ich_e11_warnings', []):
    warn_html += '<p style="background:#fff3cd;padding:4px 8px;border-radius:3px;">{}</p>\\n'.format(w)

html = '''<!DOCTYPE html>
<html>
<head><title>Paediatric PBPK Report</title>
<style>
  body {{ font-family: Arial, sans-serif; margin: 24px; }}
  h2 {{ color: #2c3e50; }}
  table {{ border-collapse: collapse; width: 95%; margin-bottom: 20px; }}
  th {{ background: #2c3e50; color: white; padding: 8px 12px; text-align: left; }}
  td {{ padding: 6px 12px; border-bottom: 1px solid #ddd; }}
  tr:nth-child(even) {{ background: #f9f9f9; }}
</style>
</head>
<body>
<h2>Paediatric PBPK Report</h2>
<p><strong>Indication:</strong> {indication} | <strong>Route:</strong> {route} | <strong>Adult CL:</strong> {adult_cl} L/h</p>
<h3>Age Group PK Summary</h3>
<table>
<tr><th>Age Group</th><th>BW (kg)</th><th>t-half (h)</th><th>Cmax (mg/L)</th><th>AUC (mg.h/L)</th><th>Rec. Dose (mg/kg)</th></tr>
{table_rows}
</table>
<h3>Enzyme Maturation (CYP + GFR fractions vs adult)</h3>
<table>
<tr><th>Age Group</th><th>CYP3A4</th><th>CYP2D6</th><th>GFR fraction</th></tr>
{cyp_rows}
</table>
<h3>ICH E11(R1) Compliance Warnings</h3>
{warn_html}
<p style="font-size:11px;color:#666;margin-top:24px;">
References: Anderson &amp; Holford 2008; ICH E11(R1) 2017; Rhodin et al. 2009
</p>
</body></html>'''.format(
    indication=vp['indication'],
    route=vp['route'],
    adult_cl=vp['adult_cl_L_h'],
    table_rows=table_rows,
    cyp_rows=cyp_rows,
    warn_html=warn_html if warn_html else '<p style="color:green;">No ICH E11 warnings.</p>',
)

with open('pediatric_summary.html', 'w') as f:
    f.write(html)

with open('versions.yml', 'w') as f:
    f.write('pbpk_pediatric:\\n  python: "3.10"\\n')

print('Pediatric PK report generated.')
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Named workflow
// ---------------------------------------------------------------------------
workflow PBPK_PEDIATRIC_WORKFLOW {
    take: meta_ch

    main:
    VALIDATE_COMPOUND_PARAMS()
    PBPK_PEDIATRIC_SIMULATE(VALIDATE_COMPOUND_PARAMS.out.validated_params)
    EVALUATE_MATURATION(
        VALIDATE_COMPOUND_PARAMS.out.validated_params,
        PBPK_PEDIATRIC_SIMULATE.out.age_group_params
    )
    GENERATE_FINAL_REPORT(
        VALIDATE_COMPOUND_PARAMS.out.validated_params,
        PBPK_PEDIATRIC_SIMULATE.out.age_group_params,
        EVALUATE_MATURATION.out.cyp_csv,
        EVALUATE_MATURATION.out.dose_rec
    )

    emit:
    report_json  = GENERATE_FINAL_REPORT.out.report_json
    pk_profiles  = PBPK_PEDIATRIC_SIMULATE.out.pk_profiles
    dose_rec     = EVALUATE_MATURATION.out.dose_rec
    html_report  = GENERATE_FINAL_REPORT.out.html_report
}

workflow {
    meta = [id: 'peds_run']
    Channel.value(meta) | PBPK_PEDIATRIC_WORKFLOW
}
