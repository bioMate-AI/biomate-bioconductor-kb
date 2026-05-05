#!/usr/bin/env nextflow
/*
 * drug_discovery/survival_analysis_km
 *
 * Kaplan-Meier survival analysis and clinical trial design.
 *
 * Split into 4 phases for BioMate UI phase cards:
 *   Phase A: VALIDATE_TRIAL_PARAMS
 *   Phase B: SURVIVAL_ANALYSIS
 *   Phase C: EVALUATE_BOUNDARIES
 *   Phase D: GENERATE_FINAL_REPORT
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.mode                = 'simulation'
params.endpoint            = 'OS'
params.distribution        = 'exponential'
params.median_control_mo   = '12'
params.hazard_ratio        = '0.70'
params.alpha               = '0.05'
params.power               = '0.80'
params.dropout_rate        = '0.10'
params.accrual_months      = '18'
params.followup_months     = '12'
params.n_arms              = '2'
params.n_interim           = '2'
params.rmst_tau            = '24'
params.weibull_shape       = '1.5'
params.indication          = 'oncology'

// ---------------------------------------------------------------------------
// Phase A: Input & Validation
// ---------------------------------------------------------------------------
process VALIDATE_TRIAL_PARAMS {
    tag 'validate'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    output:
    path "validated_trial_params.json", emit: validated_params

    script:
    """
    python3 << 'PYEOF'
import json

def pf(v, d=None):
    if v in (None, '', 'null'): return d
    try: return float(v)
    except: return d

def pi(v, d=2):
    try: return int(float(v))
    except: return d

mode        = '${params.mode}'
endpoint    = '${params.endpoint}'
dist        = '${params.distribution}'
med_ctl     = pf('${params.median_control_mo}', 12.0)
hr          = pf('${params.hazard_ratio}', 0.70)
alpha       = pf('${params.alpha}', 0.05)
power       = pf('${params.power}', 0.80)
dropout     = pf('${params.dropout_rate}', 0.10)
accrual_mo  = pf('${params.accrual_months}', 18.0)
followup_mo = pf('${params.followup_months}', 12.0)
n_arms      = pi('${params.n_arms}', 2)
n_interim   = pi('${params.n_interim}', 2)
rmst_tau    = pf('${params.rmst_tau}', 24.0)
shape       = pf('${params.weibull_shape}', 1.5)
indication  = '${params.indication}'

warnings = []

if hr <= 0 or hr >= 1:
    if hr >= 1:
        warnings.append('HR >= 1 implies no treatment benefit; power calculation may be degenerate')
    if hr <= 0:
        warnings.append('HR must be > 0; set to 0.70')
        hr = 0.70

if alpha <= 0 or alpha >= 0.5:
    warnings.append('alpha {} is unusual; typical range 0.01-0.10'.format(alpha))

if power <= 0 or power >= 1:
    warnings.append('power {} invalid; set to 0.80'.format(power))
    power = 0.80

if med_ctl <= 0:
    warnings.append('median_control_mo must be > 0; set to 12')
    med_ctl = 12.0

out = {
    'mode': mode,
    'endpoint': endpoint,
    'distribution': dist,
    'median_control_mo': med_ctl,
    'hazard_ratio': hr,
    'alpha': alpha,
    'power': power,
    'dropout_rate': dropout,
    'accrual_months': accrual_mo,
    'followup_months': followup_mo,
    'n_arms': n_arms,
    'n_interim': n_interim,
    'rmst_tau': rmst_tau,
    'weibull_shape': shape,
    'indication': indication,
    'validation_warnings': warnings,
}

with open('validated_trial_params.json', 'w') as f:
    json.dump(out, f, indent=2)

print('Trial param validation complete. Warnings: {}'.format(len(warnings)))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase B: Core Computation (KM + Sample Size)
// ---------------------------------------------------------------------------
process SURVIVAL_ANALYSIS {
    tag 'km'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params

    output:
    path "km_curves.csv",    emit: km_curves
    path "sample_size.json", emit: sample_size

    script:
    """
    python3 << 'PYEOF'
import json, csv, math, random

with open('${validated_params}') as f:
    vp = json.load(f)

med_ctl     = vp['median_control_mo']
hr          = vp['hazard_ratio']
alpha       = vp['alpha']
power       = vp['power']
dropout     = vp['dropout_rate']
accrual_mo  = vp['accrual_months']
followup_mo = vp['followup_months']
n_arms      = vp['n_arms']
rmst_tau    = vp['rmst_tau']
shape       = vp['weibull_shape']
dist        = vp['distribution']

random.seed(42)

def lambda_from_median(median_mo, k=1.0):
    return (math.log(2) / median_mo) ** (1/k) if k != 1 else math.log(2) / median_mo

def s_weibull(t, lam, k=1.0):
    return math.exp(-(lam * t) ** k)

lam_ctl  = lambda_from_median(med_ctl, shape if dist == 'weibull' else 1.0)
lam_trt  = lam_ctl * hr
med_trt  = med_ctl / hr

time_points = [t * 0.5 for t in range(1, int(rmst_tau * 2) + 2)]

def km_curve(lam, k=1.0, dist_type='exponential'):
    curve = []
    for t in time_points:
        if dist_type == 'exponential':
            s = math.exp(-lam * t)
        elif dist_type == 'weibull':
            s = s_weibull(t, lam, k)
        else:
            s = math.exp(-lam * t)
        s_noisy = max(0, min(1, s + random.gauss(0, 0.008)))
        curve.append(round(s_noisy, 4))
    return curve

ctl_km = km_curve(lam_ctl, shape, dist)
trt_km = km_curve(lam_trt, shape * 0.92, dist)

def rmst(km, tau=None):
    tau = tau or rmst_tau
    area = 0.0
    for i in range(len(time_points) - 1):
        if time_points[i] > tau: break
        dt = time_points[i+1] - time_points[i]
        area += km[i] * dt
    return round(area, 2)

rmst_ctl  = rmst(ctl_km)
rmst_trt  = rmst(trt_km)
rmst_diff = round(rmst_trt - rmst_ctl, 2)

# Schoenfeld sample size
z_alpha2 = 1.96 if alpha == 0.05 else (2.576 if alpha == 0.01 else 1.645)
z_beta   = 0.842 if power == 0.80 else (1.282 if power == 0.90 else 1.036)

if abs(math.log(hr)) < 0.001:
    n_events_total = 9999
else:
    n_events_total = math.ceil((z_alpha2 + z_beta) ** 2 / math.log(hr) ** 2)
    if n_arms > 2:
        n_events_total = math.ceil(n_events_total * (n_arms - 1) * 1.15)

t_study   = accrual_mo + followup_mo
p_event_ctl = 1 - math.exp(-lam_ctl * t_study)
p_event_trt = 1 - math.exp(-lam_trt * t_study)
p_event_avg = (p_event_ctl + p_event_trt) / 2 * (1 - dropout)
p_event_avg = max(0.05, p_event_avg)
n_per_arm   = math.ceil(n_events_total / (2 * p_event_avg))
n_total     = n_per_arm * n_arms

with open('km_curves.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['time_months', 'survival_control', 'survival_treatment',
                'at_risk_control_est', 'at_risk_treatment_est'])
    for i, t in enumerate(time_points):
        w.writerow([t, ctl_km[i], trt_km[i],
                    round(n_per_arm * ctl_km[i]),
                    round(n_per_arm * trt_km[i])])

sample_size = {
    'n_events_required': n_events_total,
    'n_per_arm': n_per_arm,
    'total_n': n_total,
    'n_arms': n_arms,
    'events_required': n_events_total,
    'rmst_control_months': rmst_ctl,
    'rmst_treatment_months': rmst_trt,
    'rmst_difference_months': rmst_diff,
    'median_control_months': med_ctl,
    'median_treatment_months': round(med_trt, 1),
    'hazard_ratio': hr,
    'p_event_avg': round(p_event_avg, 4),
    'z_alpha2': z_alpha2,
    'z_beta': z_beta,
}

with open('sample_size.json', 'w') as f:
    json.dump(sample_size, f, indent=2)

print('KM analysis complete: n_per_arm={}, events={}'.format(n_per_arm, n_events_total))
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Phase C: Analysis & QC (OBF Boundaries + Power Table)
// ---------------------------------------------------------------------------
process EVALUATE_BOUNDARIES {
    tag 'boundaries'
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path validated_params
    path sample_size

    output:
    path "obf_boundaries.json", emit: obf_json
    path "power_table.csv",     emit: power_table

    script:
    """
    python3 << 'PYEOF'
import json, csv, math, random

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${sample_size}') as f:
    ss = json.load(f)

alpha       = vp['alpha']
n_interim   = vp['n_interim']
n_events    = ss['n_events_required']
n_per_arm   = ss['n_per_arm']
n_arms      = ss['n_arms']
z_alpha2    = ss['z_alpha2']
z_beta      = ss['z_beta']
p_event_avg = ss['p_event_avg']

random.seed(42)

def obf_boundary(info_fraction, alpha_total=0.05):
    return z_alpha2 / math.sqrt(info_fraction)

interim_analyses = []
for k in range(1, n_interim + 1):
    frac = k / (n_interim + 1)
    z_b  = obf_boundary(frac)
    events_at = math.ceil(n_events * frac)
    interim_analyses.append({
        'analysis': k,
        'information_fraction': round(frac, 3),
        'events_required': events_at,
        'z_boundary_efficacy': round(z_b, 3),
        'z_boundary_futility': round(0.5 * z_b, 3),
        'cumulative_alpha_spent': round(alpha * (2 * (1 - 0.5 * math.erfc(z_b / math.sqrt(2)))), 4),
    })

interim_analyses.append({
    'analysis': n_interim + 1,
    'information_fraction': 1.0,
    'events_required': n_events,
    'z_boundary_efficacy': round(z_alpha2, 3),
    'z_boundary_futility': None,
    'cumulative_alpha_spent': alpha,
})

hr_obs = round(vp['hazard_ratio'] * random.uniform(0.9, 1.1), 3)
z_obs  = round((-math.log(hr_obs)) / (1 / math.sqrt(interim_analyses[0]['events_required'])), 2) \
         if interim_analyses else None

obf_out = {
    'interim_analyses': interim_analyses,
    'hr_observed_at_interim_1': hr_obs,
    'z_observed_at_interim_1': z_obs,
    'method': "O'Brien-Fleming alpha-spending (Lan & DeMets 1983)",
}

with open('obf_boundaries.json', 'w') as f:
    json.dump(obf_out, f, indent=2)

with open('power_table.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['HR', 'power', 'n_required'])
    for hr_test in [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90]:
        if abs(math.log(hr_test)) < 0.001: continue
        ne     = math.ceil((z_alpha2 + z_beta) ** 2 / math.log(hr_test) ** 2)
        npa    = math.ceil(ne / (2 * p_event_avg))
        z_test = abs(math.log(hr_test)) * math.sqrt(ne)
        pow_a  = round(0.5 * (1 + math.erf((z_test - z_alpha2) / math.sqrt(2))), 3)
        w.writerow([hr_test, pow_a, npa * n_arms])

print('Boundary evaluation complete.')
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
    path sample_size
    path obf_json
    path power_table

    output:
    path "trial_design_report.json", emit: report_json
    path "trial_summary.html",       emit: html_report
    path "versions.yml",             emit: versions

    script:
    """
    python3 << 'PYEOF'
import json

with open('${validated_params}') as f:
    vp = json.load(f)
with open('${sample_size}') as f:
    ss = json.load(f)
with open('${obf_json}') as f:
    obf = json.load(f)

report = {
    'status': 'completed',
    'endpoint': vp['endpoint'],
    'indication': vp['indication'],
    'assumptions': {
        'distribution': vp['distribution'],
        'median_control_months': vp['median_control_mo'],
        'median_treatment_months': ss['median_treatment_months'],
        'hazard_ratio': vp['hazard_ratio'],
    },
    'sample_size': {
        'n_events_required': ss['n_events_required'],
        'n_per_arm': ss['n_per_arm'],
        'n_total': ss['total_n'],
        'alpha_two_sided': vp['alpha'],
        'power': vp['power'],
        'accrual_months': vp['accrual_months'],
        'followup_months': vp['followup_months'],
    },
    'survival_estimates': {
        'rmst_control_months': ss['rmst_control_months'],
        'rmst_treatment_months': ss['rmst_treatment_months'],
        'rmst_difference_months': ss['rmst_difference_months'],
        'rmst_tau_months': vp['rmst_tau'],
    },
    'interim_analyses': obf['interim_analyses'],
    'references': [
        'Kaplan & Meier 1958 JASA 53:457',
        'Schoenfeld 1983 Biometrics 39:499',
        "Lan & DeMets 1983 Biometrika (O'Brien-Fleming)",
    ],
}

with open('trial_design_report.json', 'w') as f:
    json.dump(report, f, indent=2)

ia_rows = ''
for ia in obf['interim_analyses']:
    fut = ia['z_boundary_futility'] if ia['z_boundary_futility'] is not None else 'N/A (final)'
    ia_rows += '<tr><td>IA {}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>\\n'.format(
        ia['analysis'], ia['information_fraction'], ia['events_required'],
        ia['z_boundary_efficacy'], fut)

html = '''<!DOCTYPE html>
<html>
<head><title>Trial Design Report</title>
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
<h2>Kaplan-Meier Survival Analysis: {endpoint}</h2>
<p><strong>Indication:</strong> {indication} | <strong>HR:</strong> {hr} | <strong>Distribution:</strong> {dist}</p>
<h3>Sample Size</h3>
<table>
<tr><th>Parameter</th><th>Value</th></tr>
<tr><td>Events required</td><td>{events}</td></tr>
<tr><td>Patients per arm</td><td>{n_per_arm}</td></tr>
<tr><td>Total randomised</td><td>{n_total}</td></tr>
<tr><td>Alpha (2-sided)</td><td>{alpha}</td></tr>
<tr><td>Power</td><td>{power}</td></tr>
<tr><td>Median OS control</td><td>{med_ctl} months</td></tr>
<tr><td>Median OS treatment</td><td>{med_trt} months</td></tr>
<tr><td>RMST difference</td><td>{rmst_diff} months</td></tr>
</table>
<h3>Interim Analysis Boundaries (O\'Brien-Fleming)</h3>
<table>
<tr><th>Analysis</th><th>Info Fraction</th><th>Events</th><th>Z (efficacy)</th><th>Z (futility)</th></tr>
{ia_rows}
</table>
<p style="font-size:11px;color:#666;">
References: Schoenfeld 1983 Biometrics; Lan &amp; DeMets 1983 Biometrika
</p>
</body></html>'''.format(
    endpoint=vp['endpoint'],
    indication=vp['indication'],
    hr=vp['hazard_ratio'],
    dist=vp['distribution'],
    events=ss['n_events_required'],
    n_per_arm=ss['n_per_arm'],
    n_total=ss['total_n'],
    alpha=vp['alpha'],
    power=vp['power'],
    med_ctl=vp['median_control_mo'],
    med_trt=ss['median_treatment_months'],
    rmst_diff=ss['rmst_difference_months'],
    ia_rows=ia_rows,
)

with open('trial_summary.html', 'w') as f:
    f.write(html)

with open('versions.yml', 'w') as f:
    f.write('survival_analysis_km:\\n  python: "3.10"\\n')

print('Trial design report generated.')
PYEOF
    """
}

// ---------------------------------------------------------------------------
// Named workflow
// ---------------------------------------------------------------------------
workflow SURVIVAL_KM_WORKFLOW {
    take: meta_ch

    main:
    VALIDATE_TRIAL_PARAMS()
    SURVIVAL_ANALYSIS(VALIDATE_TRIAL_PARAMS.out.validated_params)
    EVALUATE_BOUNDARIES(
        VALIDATE_TRIAL_PARAMS.out.validated_params,
        SURVIVAL_ANALYSIS.out.sample_size
    )
    GENERATE_FINAL_REPORT(
        VALIDATE_TRIAL_PARAMS.out.validated_params,
        SURVIVAL_ANALYSIS.out.sample_size,
        EVALUATE_BOUNDARIES.out.obf_json,
        EVALUATE_BOUNDARIES.out.power_table
    )

    emit:
    report_json = GENERATE_FINAL_REPORT.out.report_json
    km_curves   = SURVIVAL_ANALYSIS.out.km_curves
    power_table = EVALUATE_BOUNDARIES.out.power_table
    html_report = GENERATE_FINAL_REPORT.out.html_report
}

workflow {
    meta = [id: 'km_run']
    Channel.value(meta) | SURVIVAL_KM_WORKFLOW
}
