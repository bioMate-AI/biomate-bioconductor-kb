#!/usr/bin/env nextflow
/*
 * drug_discovery/fcrn_antibody_pk
 *
 * FcRn-mediated antibody pharmacokinetics prediction and optimization.
 *
 * Split into 4 phases for BioMate UI phase cards:
 *   Phase A: VALIDATE_ANTIBODY_PARAMS
 *   Phase B: FCRN_PK_SIMULATION
 *   Phase C: COMPARE_FC_MUTATIONS
 *   Phase D: GENERATE_FINAL_REPORT
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.antibody_format     = 'igg1'
params.fc_mutation         = 'wt'
params.mw_kda              = '145'
params.dose_mg_kg          = '10'
params.route               = 'iv'
params.sc_volume_mL        = '1.0'
params.fcrn_affinity_ph6   = 'null'
params.species             = 'human'
params.indication          = 'oncology'
params.n_doses             = '1'

// ---------------------------------------------------------------------------
// Phase A: Input & Validation
// ---------------------------------------------------------------------------
process VALIDATE_ANTIBODY_PARAMS {
    tag 'validate'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    output:
    path "validated_ab_params.json", emit: validated_params

    script:
    """
    python3 << 'PYEOF'
import json

def pf(v, d=None):
    if v in (None, '', 'null'): return d
    try: return float(v)
    except: return d

def pi(v, d=1):
    try: return int(float(v))
    except: return d

ab_format  = '${params.antibody_format}'
fc_mut     = '${params.fc_mutation}'
mw_kda     = pf('${params.mw_kda}', 145.0)
dose       = pf('${params.dose_mg_kg}', 10.0)
route      = '${params.route}'
sc_vol     = pf('${params.sc_volume_mL}', 1.0)
kd_input   = pf('${params.fcrn_affinity_ph6}', None)
species    = '${params.species}'
indication = '${params.indication}'
n_doses    = pi('${params.n_doses}', 1)

warnings = []

valid_formats = ['igg1', 'igg2', 'igg4', 'scfv_fc', 'bite_fc', 'fab', 'nanobody']
if ab_format not in valid_formats:
    warnings.append('Unknown antibody format {}; defaulting to igg1'.format(ab_format))
    ab_format = 'igg1'

valid_mutations = ['wt', 'yte', 'ls', 'gasd_alie', 'aaa', 'psa', 'm252y_s254t_t256e']
if fc_mut not in valid_mutations:
    warnings.append('Unknown fc_mutation {}; defaulting to wt'.format(fc_mut))
    fc_mut = 'wt'

valid_routes = ['iv', 'sc', 'im']
if route not in valid_routes:
    warnings.append('Unknown route {}; defaulting to iv'.format(route))
    route = 'iv'

valid_species = ['human', 'monkey', 'mouse', 'rat']
if species not in valid_species:
    warnings.append('Unknown species {}; defaulting to human'.format(species))
    species = 'human'

if mw_kda < 10 or mw_kda > 2000:
    warnings.append('MW {} kDa is unusual for an antibody'.format(mw_kda))

if dose <= 0:
    warnings.append('dose_mg_kg must be > 0; set to 10')
    dose = 10.0

out = {
    'antibody_format': ab_format,
    'fc_mutation': fc_mut,
    'mw_kda': mw_kda,
    'dose_mg_kg': dose,
    'route': route,
    'sc_volume_mL': sc_vol,
    'fcrn_affinity_ph6': kd_input,
    'species': species,
    'indication': indication,
    'n_doses': n_doses,
    'validation_warnings': warnings,
}

with open('validated_ab_params.json', 'w') as f:
    json.dump(out, f, indent=2)

print('Antibody param validation complete. Warnings: {}'.format(len(warnings)))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase B: Core Computation (FcRn PK Simulation)
// ---------------------------------------------------------------------------
process FCRN_PK_SIMULATION {
    tag 'fcrn_pk'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params

    output:
    path "pk_profile.csv",       emit: pk_profile
    path "pk_parameters.json",   emit: pk_params

    script:
    """
    python3 << 'PYEOF'
import json, csv, math, random

with open('${validated_params}') as f:
    vp = json.load(f)

ab_format  = vp['antibody_format']
fc_mut     = vp['fc_mutation']
mw_kda     = vp['mw_kda']
dose       = vp['dose_mg_kg']
route      = vp['route']
kd_input   = vp['fcrn_affinity_ph6']
species    = vp['species']
n_doses    = vp['n_doses']

random.seed(42)

FORMAT_PK = {
    'igg1': {'t_half_days': 21, 'vd_L_kg': 0.07, 'cl_mL_h_kg': 0.18,
              'fcrn_kd_ph6_nM': 250, 'f_sc': 0.72, 'tmax_sc_h': 72},
    'igg2': {'t_half_days': 20, 'vd_L_kg': 0.06, 'cl_mL_h_kg': 0.19,
              'fcrn_kd_ph6_nM': 300, 'f_sc': 0.65, 'tmax_sc_h': 96},
    'igg4': {'t_half_days': 21, 'vd_L_kg': 0.07, 'cl_mL_h_kg': 0.18,
              'fcrn_kd_ph6_nM': 200, 'f_sc': 0.70, 'tmax_sc_h': 84},
    'scfv_fc': {'t_half_days': 14, 'vd_L_kg': 0.08, 'cl_mL_h_kg': 0.28,
                'fcrn_kd_ph6_nM': 350, 'f_sc': 0.60, 'tmax_sc_h': 60},
    'bite_fc': {'t_half_days': 1.5, 'vd_L_kg': 0.12, 'cl_mL_h_kg': 2.5,
                'fcrn_kd_ph6_nM': None, 'f_sc': 0.30, 'tmax_sc_h': 24,
                'note': 'BiTE without Fc: very short t1/2; FcRn recycling absent'},
    'fab':    {'t_half_days': 0.9, 'vd_L_kg': 0.06, 'cl_mL_h_kg': 3.8,
               'fcrn_kd_ph6_nM': None, 'f_sc': 0.40, 'tmax_sc_h': 12,
               'note': 'Fab fragment: renal clearance dominant; no FcRn'},
    'nanobody': {'t_half_days': 0.5, 'vd_L_kg': 0.05, 'cl_mL_h_kg': 7.2,
                 'fcrn_kd_ph6_nM': None, 'f_sc': 0.55, 'tmax_sc_h': 6,
                 'note': 'VHH: renal-dominant clearance; albumin fusion extends t1/2'},
}

MUT_EFFECTS = {
    'wt':             {'kd_fold': 1.0,  't_half_fold': 1.0,  'cl_fold': 1.0,
                       'ref': 'Baseline IgG1'},
    'yte':            {'kd_fold': 0.11, 't_half_fold': 2.4,  'cl_fold': 0.42,
                       'ref': 'M252Y/S254T/T256E (Dall Acqua 2006)'},
    'ls':             {'kd_fold': 0.18, 't_half_fold': 2.0,  'cl_fold': 0.50,
                       'ref': 'M428L/N434S (Zalevsky 2010 NatBiotech)'},
    'm252y_s254t_t256e': {'kd_fold': 0.11, 't_half_fold': 2.4, 'cl_fold': 0.42,
                          'ref': 'YTE (same as yte alias)'},
    'gasd_alie':      {'kd_fold': 0.08, 't_half_fold': 3.0,  'cl_fold': 0.33,
                       'ref': 'G236A/S239D + A327L/I332E (Bhatt 2012)'},
    'aaa':            {'kd_fold': 8.0,  't_half_fold': 0.35, 'cl_fold': 2.9,
                       'ref': 'N297A/L234A/L235A (effector null)'},
    'psa':            {'kd_fold': 0.05, 't_half_fold': 4.0,  'cl_fold': 0.25,
                       'ref': 'pH-switch antibody (Schlothauer 2016)'},
}

base_pk = FORMAT_PK.get(ab_format, FORMAT_PK['igg1'])
mut_eff = MUT_EFFECTS.get(fc_mut, MUT_EFFECTS['wt'])

base_kd = kd_input if kd_input else (base_pk.get('fcrn_kd_ph6_nM') or 250.0)
kd_ph6  = round(base_kd * mut_eff['kd_fold'], 1)
t_half  = round(base_pk['t_half_days'] * mut_eff['t_half_fold'], 1)
cl      = round(base_pk['cl_mL_h_kg'] * mut_eff['cl_fold'], 3)
vd      = base_pk['vd_L_kg']
f_sc    = base_pk['f_sc'] * (1 - 0.08 * (mut_eff['cl_fold'] - 1))
f_sc    = round(max(0.3, min(0.95, f_sc)), 2)

SPECIES_FACTORS = {'human': 1.0, 'monkey': 0.85, 'mouse': 0.35, 'rat': 0.50}
species_f = SPECIES_FACTORS.get(species, 1.0)
t_half_sp = round(t_half * species_f, 1)
cl_sp     = round(cl / species_f, 3)

ke    = math.log(2) / (t_half_sp * 24)
k12   = round(0.4 * ke, 5)
k21   = round(0.2 * ke, 5)
v1    = vd * 0.6
dose_ug_mL = dose / (v1 * 1000) * 1000

time_h = list(range(0, int(t_half_sp * 24 * 5) + 1, 6))

def pk_2comp_iv(t_arr, c0, ke_val, k12_val, k21_val):
    alpha_rate = 0.5 * ((k12_val + k21_val + ke_val) + math.sqrt((k12_val + k21_val + ke_val)**2 - 4*k21_val*ke_val))
    beta_rate  = 0.5 * ((k12_val + k21_val + ke_val) - math.sqrt(max(0, (k12_val + k21_val + ke_val)**2 - 4*k21_val*ke_val)))
    A = c0 * (alpha_rate - k21_val) / (alpha_rate - beta_rate)
    B = c0 * (k21_val - beta_rate)  / (alpha_rate - beta_rate)
    result = []
    for t in t_arr:
        c = A * math.exp(-alpha_rate * t) + B * math.exp(-beta_rate * t)
        result.append(max(0, c))
    return result

pk_conc_iv = pk_2comp_iv(time_h, dose_ug_mL, ke, k12, k21)

if route == 'sc':
    ka = math.log(2) / (base_pk.get('tmax_sc_h', 72) / 2)
    pk_conc = []
    for t in time_h:
        abs_term = f_sc * dose_ug_mL * ka / max(ka - ke, 0.001)
        c_sc = abs_term * (math.exp(-ke * t) - math.exp(-ka * t))
        pk_conc.append(round(max(0, c_sc), 4))
else:
    pk_conc = [round(c, 4) for c in pk_conc_iv]

cmax_raw = max(pk_conc)
cmax     = round(cmax_raw, 2)
tmax_h   = time_h[pk_conc.index(cmax_raw)]
auc_inf  = round(cmax / ke, 1) if route == 'iv' else round(
    sum((pk_conc[i] + pk_conc[i+1]) / 2 * (time_h[i+1] - time_h[i])
        for i in range(len(time_h)-1)), 1)

recycle_eff = 1 / (1 + (kd_ph6 / 150) ** 0.6)
recycle_eff = round(max(0.1, min(0.98, recycle_eff)), 3)

with open('pk_profile.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['time_h', 'concentration_ug_mL'])
    for i, t in enumerate(time_h):
        w.writerow([t, pk_conc[i]])

pk_params = {
    't_half_h': round(t_half_sp * 24, 1),
    't_half_days': t_half_sp,
    'CL_mL_h_kg': cl_sp,
    'Vd_L_kg': vd,
    'Cmax_ug_mL': cmax,
    'Tmax_h': tmax_h,
    'AUC_inf_ug_h_mL': auc_inf,
    'fcrn_kd_ph6_nM': kd_ph6,
    'recycling_efficiency': recycle_eff,
    'lysosomal_deg_fraction': round(1 - recycle_eff, 3),
    'route': route,
    'F_sc': f_sc if route == 'sc' else None,
    'fold_vs_wt': mut_eff['t_half_fold'],
    'mut_reference': mut_eff['ref'],
}

with open('pk_parameters.json', 'w') as f:
    json.dump(pk_params, f, indent=2)

print('FcRn PK simulation: t_half={} days, Cmax={} ug/mL'.format(t_half_sp, cmax))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase C: Analysis & QC (Mutation Comparison)
// ---------------------------------------------------------------------------
process COMPARE_FC_MUTATIONS {
    tag 'mut_compare'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path pk_params

    output:
    path "halflife_comparison.csv",  emit: halflife_csv
    path "allometric_scaling.json",  emit: allometric_json

    script:
    """
    python3 << 'PYEOF'
import json, csv, math

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${pk_params}') as f:
    pkp = json.load(f)

ab_format = vp['antibody_format']
species   = vp['species']
kd_input  = vp['fcrn_affinity_ph6']

FORMAT_PK = {
    'igg1': {'t_half_days': 21, 'vd_L_kg': 0.07, 'cl_mL_h_kg': 0.18, 'fcrn_kd_ph6_nM': 250},
    'igg2': {'t_half_days': 20, 'vd_L_kg': 0.06, 'cl_mL_h_kg': 0.19, 'fcrn_kd_ph6_nM': 300},
    'igg4': {'t_half_days': 21, 'vd_L_kg': 0.07, 'cl_mL_h_kg': 0.18, 'fcrn_kd_ph6_nM': 200},
    'scfv_fc': {'t_half_days': 14, 'vd_L_kg': 0.08, 'cl_mL_h_kg': 0.28, 'fcrn_kd_ph6_nM': 350},
    'bite_fc': {'t_half_days': 1.5, 'vd_L_kg': 0.12, 'cl_mL_h_kg': 2.5, 'fcrn_kd_ph6_nM': None},
    'fab':     {'t_half_days': 0.9, 'vd_L_kg': 0.06, 'cl_mL_h_kg': 3.8, 'fcrn_kd_ph6_nM': None},
    'nanobody':{'t_half_days': 0.5, 'vd_L_kg': 0.05, 'cl_mL_h_kg': 7.2, 'fcrn_kd_ph6_nM': None},
}

MUT_EFFECTS = {
    'wt':             {'kd_fold': 1.0,  't_half_fold': 1.0,  'cl_fold': 1.0},
    'yte':            {'kd_fold': 0.11, 't_half_fold': 2.4,  'cl_fold': 0.42},
    'ls':             {'kd_fold': 0.18, 't_half_fold': 2.0,  'cl_fold': 0.50},
    'm252y_s254t_t256e': {'kd_fold': 0.11, 't_half_fold': 2.4, 'cl_fold': 0.42},
    'gasd_alie':      {'kd_fold': 0.08, 't_half_fold': 3.0,  'cl_fold': 0.33},
    'aaa':            {'kd_fold': 8.0,  't_half_fold': 0.35, 'cl_fold': 2.9},
    'psa':            {'kd_fold': 0.05, 't_half_fold': 4.0,  'cl_fold': 0.25},
}

base_pk   = FORMAT_PK.get(ab_format, FORMAT_PK['igg1'])
base_kd   = kd_input if kd_input else (base_pk.get('fcrn_kd_ph6_nM') or 250.0)
wt_t_half = base_pk['t_half_days']

SPECIES_FACTORS = {'human': 1.0, 'monkey': 0.85, 'mouse': 0.35, 'rat': 0.50}
sf = SPECIES_FACTORS.get(species, 1.0)

mut_comparison = []
for mut_name, eff in MUT_EFFECTS.items():
    kd_m     = round(base_kd * eff['kd_fold'], 1) if base_kd else None
    t_half_m = round(base_pk['t_half_days'] * eff['t_half_fold'] * sf, 1)
    cl_m     = round(base_pk['cl_mL_h_kg'] * eff['cl_fold'] / sf, 3)
    auc_ratio = round(1.0 / eff['cl_fold'], 3)
    fold_vs_wt = round(eff['t_half_fold'], 2)
    mut_comparison.append({
        'mutation': mut_name,
        't_half_h': round(t_half_m * 24, 1),
        'fold_change_vs_WT': fold_vs_wt,
        'AUC_ratio': auc_ratio,
    })

with open('halflife_comparison.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['mutation', 't_half_h', 'fold_change_vs_WT', 'AUC_ratio'])
    for m in mut_comparison:
        w.writerow([m['mutation'], m['t_half_h'], m['fold_change_vs_WT'], m['AUC_ratio']])

# Allometric scaling: human -> other species
species_list = ['human', 'monkey', 'mouse', 'rat']
BODY_WEIGHTS = {'human': 70.0, 'monkey': 5.0, 'mouse': 0.025, 'rat': 0.25}

allometric = {}
for sp in species_list:
    bw    = BODY_WEIGHTS[sp]
    spf   = SPECIES_FACTORS[sp]
    allometric[sp] = {
        'BW_kg': bw,
        't_half_days': round(wt_t_half * spf, 2),
        'CL_mL_h_kg': round(base_pk['cl_mL_h_kg'] / spf, 3),
        'species_factor': spf,
    }

with open('allometric_scaling.json', 'w') as f:
    json.dump({'species_scaling': allometric, 'method': 'simple species factor (Deng 2012)'}, f, indent=2)

print('Mutation comparison complete: {} mutations evaluated'.format(len(mut_comparison)))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase D: Report & Export
// ---------------------------------------------------------------------------
process GENERATE_FINAL_REPORT {
    tag 'report'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path pk_params
    path halflife_csv
    path allometric_json

    output:
    path "antibody_pk_report.json", emit: report_json
    path "halflife_summary.html",   emit: html_report
    path "versions.yml",            emit: versions

    script:
    """
    python3 << 'PYEOF'
import json, csv

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${pk_params}') as f:
    pkp = json.load(f)
with open('${allometric_json}') as f:
    allo = json.load(f)

report = {
    'status': 'completed',
    'antibody_format': vp['antibody_format'],
    'fc_mutation': vp['fc_mutation'],
    'species': vp['species'],
    'indication': vp['indication'],
    'fcrn_binding': {
        'kd_ph6_nM': pkp['fcrn_kd_ph6_nM'],
        'recycling_efficiency': pkp['recycling_efficiency'],
        'lysosomal_degradation_fraction': pkp['lysosomal_deg_fraction'],
    },
    'pk_parameters': {
        't_half_days': pkp['t_half_days'],
        'CL_mL_h_kg': pkp['CL_mL_h_kg'],
        'Vd_L_kg': pkp['Vd_L_kg'],
        'Cmax_ug_mL': pkp['Cmax_ug_mL'],
        'AUC_inf_ug_h_mL': pkp['AUC_inf_ug_h_mL'],
        'fold_vs_wt': pkp['fold_vs_wt'],
    },
    'allometric_scaling': allo['species_scaling'],
    'references': [
        'Roopenian & Akilesh 2007 Nat Rev Immunol 7:715',
        'Deng et al. 2012 Drug Metab Dispos 40:1545',
        'Zalevsky et al. 2010 Nat Biotechnol 28:157',
        'Schlothauer et al. 2016 Protein Eng Des Sel',
    ],
}

with open('antibody_pk_report.json', 'w') as f:
    json.dump(report, f, indent=2)

mut_rows = ''
with open('${halflife_csv}') as f:
    reader = csv.DictReader(f)
    for row in reader:
        mut_rows += '<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>\\n'.format(
            row['mutation'], row['t_half_h'], row['fold_change_vs_WT'], row['AUC_ratio'])

html = '''<!DOCTYPE html>
<html>
<head><title>Antibody PK Report</title>
<style>
  body {{ font-family: Arial, sans-serif; margin: 24px; }}
  h2 {{ color: #2c3e50; }}
  table {{ border-collapse: collapse; width: 80%; margin-bottom: 20px; }}
  th {{ background: #2c3e50; color: white; padding: 8px 12px; text-align: left; }}
  td {{ padding: 6px 12px; border-bottom: 1px solid #ddd; }}
  tr:nth-child(even) {{ background: #f9f9f9; }}
</style>
</head>
<body>
<h2>FcRn Antibody PK: {ab_format} / {fc_mut}</h2>
<p><strong>Species:</strong> {species} | <strong>Route:</strong> {route} | <strong>Dose:</strong> {dose} mg/kg</p>
<h3>PK Parameters</h3>
<table>
<tr><th>Parameter</th><th>Value</th></tr>
<tr><td>Half-life (days)</td><td>{t_half}</td></tr>
<tr><td>Cmax (ug/mL)</td><td>{cmax}</td></tr>
<tr><td>AUC-inf (ug.h/mL)</td><td>{auc}</td></tr>
<tr><td>FcRn Kd pH6 (nM)</td><td>{kd}</td></tr>
<tr><td>Recycling efficiency</td><td>{recycle}</td></tr>
<tr><td>Fold vs WT</td><td>{fold}x</td></tr>
</table>
<h3>Half-life Comparison by Fc Mutation</h3>
<table>
<tr><th>Mutation</th><th>t-half (h)</th><th>Fold vs WT</th><th>AUC ratio</th></tr>
{mut_rows}
</table>
<p style="font-size:11px;color:#666;">
References: Roopenian &amp; Akilesh 2007; Deng et al. 2012; Zalevsky et al. 2010
</p>
</body></html>'''.format(
    ab_format=vp['antibody_format'],
    fc_mut=vp['fc_mutation'],
    species=vp['species'],
    route=vp['route'],
    dose=vp['dose_mg_kg'],
    t_half=pkp['t_half_days'],
    cmax=pkp['Cmax_ug_mL'],
    auc=pkp['AUC_inf_ug_h_mL'],
    kd=pkp['fcrn_kd_ph6_nM'],
    recycle=pkp['recycling_efficiency'],
    fold=pkp['fold_vs_wt'],
    mut_rows=mut_rows,
)

with open('halflife_summary.html', 'w') as f:
    f.write(html)

with open('versions.yml', 'w') as f:
    f.write('fcrn_antibody_pk:\\n  python: "3.10"\\n')

print('Antibody PK report generated.')
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Named workflow
// ---------------------------------------------------------------------------
workflow FCRN_PK_WORKFLOW {
    take: meta_ch

    main:
    VALIDATE_ANTIBODY_PARAMS()
    FCRN_PK_SIMULATION(VALIDATE_ANTIBODY_PARAMS.out.validated_params)
    COMPARE_FC_MUTATIONS(
        VALIDATE_ANTIBODY_PARAMS.out.validated_params,
        FCRN_PK_SIMULATION.out.pk_params
    )
    GENERATE_FINAL_REPORT(
        VALIDATE_ANTIBODY_PARAMS.out.validated_params,
        FCRN_PK_SIMULATION.out.pk_params,
        COMPARE_FC_MUTATIONS.out.halflife_csv,
        COMPARE_FC_MUTATIONS.out.allometric_json
    )

    emit:
    report_json  = GENERATE_FINAL_REPORT.out.report_json
    pk_profile   = FCRN_PK_SIMULATION.out.pk_profile
    halflife_csv = COMPARE_FC_MUTATIONS.out.halflife_csv
    html_report  = GENERATE_FINAL_REPORT.out.html_report
}

workflow {
    meta = [id: 'fcrn_run']
    Channel.value(meta) | FCRN_PK_WORKFLOW
}
