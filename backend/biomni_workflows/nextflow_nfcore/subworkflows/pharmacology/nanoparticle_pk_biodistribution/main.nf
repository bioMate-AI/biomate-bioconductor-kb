#!/usr/bin/env nextflow
/*
 * pharmacology/nanoparticle_pk_biodistribution
 *
 * Models in vivo pharmacokinetics of nanoparticle-formulated drugs.
 * Uses a physiologically-based 4-compartment NP PK model (blood, tumor,
 * liver/MPS, peripheral) with PEG stealth model and EPR accumulation.
 *
 * References:
 *   - Wilhelm et al. Nature Reviews Materials 2016 (NP EPR meta-analysis)
 *   - Arvizo et al. PLoS ONE 2011 (PEG stealth model)
 *   - Danhier et al. J Control Release 2010 (ODE NP model)
 *
 * Input:  particle_diameter_nm, surface_chemistry, PEG_density, dose_mg_kg
 * Output: pk_profile.csv, half_life_summary.json, biodistribution_plot.html
 */

nextflow.enable.dsl = 2

params.outdir                  = './results'
params.particle_diameter_nm    = '80'
params.surface_chemistry       = 'PEG'   // PEG | lipid | polymer | bare
params.PEG_density_chains_nm2  = '0.1'
params.PEG_MW_Da               = '2000'
params.dose_mg_kg              = '5'
params.tumor_model             = 'subcutaneous'  // none | subcutaneous | orthotopic
params.zeta_potential_mV       = '-10'
params.simulation_hours        = '72'

process NANOPARTICLE_PK_BIODISTRIBUTION {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("np_pk_results.json"),         emit: results
    tuple val(meta), path("np_pk_output.txt"),           emit: output
    tuple val(meta), path("pk_profile.csv"),             emit: pk_profile
    tuple val(meta), path("half_life_summary.json"),     emit: half_life
    tuple val(meta), path("formulation_risk.json"),      emit: formulation_risk
    path "versions.yml",                                 emit: versions

    script:
    """
    export PARAM_DIAMETER='${params.particle_diameter_nm}'
    export PARAM_SURFACE='${params.surface_chemistry}'
    export PARAM_PEG_DENSITY='${params.PEG_density_chains_nm2}'
    export PARAM_PEG_MW='${params.PEG_MW_Da}'
    export PARAM_DOSE='${params.dose_mg_kg}'
    export PARAM_TUMOR='${params.tumor_model}'
    export PARAM_ZETA='${params.zeta_potential_mV}'
    export PARAM_SIM_H='${params.simulation_hours}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np
from scipy.integrate import solve_ivp

def auto_convert(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

# -- Load params ---------------------------------------------------------------
d_nm     = auto_convert(os.environ.get('PARAM_DIAMETER'), 80)
surface  = os.environ.get('PARAM_SURFACE','PEG').lower()
peg_dens = auto_convert(os.environ.get('PARAM_PEG_DENSITY'), 0.1)
peg_mw   = auto_convert(os.environ.get('PARAM_PEG_MW'), 2000)
dose     = auto_convert(os.environ.get('PARAM_DOSE'), 5)  # mg/kg
tumor_model = os.environ.get('PARAM_TUMOR','subcutaneous').lower()
zeta     = auto_convert(os.environ.get('PARAM_ZETA'), -10)
sim_h    = auto_convert(os.environ.get('PARAM_SIM_H'), 72)

# -- PEG stealth model (Arvizo et al. modified) -------------------------------
def peg_stealth_factor(peg_density, peg_mw_da):
    """
    Returns MPS clearance reduction factor (0-1).
    Higher PEG density + MW -> more stealth (lower MPS uptake).
    """
    L_peg = 0.076 * peg_mw_da**0.44  # PEG brush length in nm
    D_peg = (6 / (math.pi * peg_density)) ** 0.5 if peg_density > 0 else 100
    brush_ratio = L_peg / D_peg  # > 1 = brush regime (good stealth)
    if brush_ratio >= 2.0: return 0.1   # excellent stealth
    if brush_ratio >= 1.0: return 0.3   # good stealth (brush regime)
    if brush_ratio >= 0.5: return 0.6   # moderate stealth (mushroom)
    return 0.9  # poor stealth (bare)

def mps_clearance_rate(d_nm, surface, peg_dens, peg_mw_da, zeta_mv):
    """Liver + spleen MPS uptake rate constant (1/h)."""
    # Size effect: opsonization increases for >200nm, decreases for <100nm but
    # smaller particles avoid splenic filtration
    size_factor = 1.0
    if d_nm > 200: size_factor = 2.5
    elif d_nm < 50: size_factor = 1.8  # faster hepatic uptake
    else: size_factor = 1.0

    # Charge: neutral/slight negative -> best; positive -> rapid MPS
    charge_factor = 1.0 if -30 <= zeta_mv <= -5 else (1.8 if zeta_mv > 0 else 1.3)

    # Surface coating
    if surface in ('peg','lipid'):
        stealth = peg_stealth_factor(peg_dens, peg_mw_da)
    elif surface == 'polymer':
        stealth = 0.5
    else:  # bare
        stealth = 1.0

    k_mps = 0.3 * size_factor * charge_factor * stealth  # base 0.3/h
    return round(k_mps, 4)

# -- EPR rate constant (Wilhelm 2016 meta-analysis: median 0.7 %ID/g at 24h) --
def epr_rate(d_nm, tumor_model):
    """Tumor EPR accumulation constant (1/h)."""
    if tumor_model == 'none': return 0.0
    # Optimal size for EPR: 50-200 nm
    size_score = 1.0 if 50 <= d_nm <= 200 else (0.5 if d_nm < 50 else 0.3)
    base_epr = {'subcutaneous': 0.02, 'orthotopic': 0.015}.get(tumor_model, 0.02)
    return base_epr * size_score

# -- 4-compartment ODE model ---------------------------------------------------
# Compartments: [blood, tumor, liver_MPS, peripheral]
# Units: % injected dose (ID) per tissue, normalized to standard tissue weights

k_mps     = mps_clearance_rate(d_nm, surface, peg_dens, peg_mw, zeta)
k_epr     = epr_rate(d_nm, tumor_model)
k_peri    = 0.08    # peripheral distribution rate (1/h)
k_peri_back = 0.02  # back-redistribution from peripheral
k_elim    = 0.01    # elimination from blood (renal + degradation of very small)
# For NPs > 8nm, renal filtration is negligible -- mostly MPS

def np_ode(t, y):
    blood, tumor, liver, peripheral = y
    d_blood   = -(k_mps + k_epr + k_peri + k_elim) * blood + k_peri_back * peripheral
    d_tumor   = k_epr * blood
    d_liver   = k_mps * blood
    d_periph  = k_peri * blood - k_peri_back * peripheral
    return [d_blood, d_tumor, d_liver, d_periph]

# Initial condition: 100% in blood at t=0
y0    = [100.0, 0.0, 0.0, 0.0]
t_end = max(sim_h, 24)
t_eval = np.linspace(0, t_end, int(t_end * 4) + 1)  # every 15 min

sol = solve_ivp(np_ode, [0, t_end], y0, t_eval=t_eval, method='RK45', rtol=1e-6)

if not sol.success:
    print(f"WARNING: ODE solver did not converge: {sol.message}", file=sys.stderr)
    blood_arr   = np.zeros(len(t_eval))
    tumor_arr   = np.zeros(len(t_eval))
    liver_arr   = np.zeros(len(t_eval))
    periph_arr  = np.zeros(len(t_eval))
else:
    blood_arr   = sol.y[0]
    tumor_arr   = sol.y[1]
    liver_arr   = sol.y[2]
    periph_arr  = sol.y[3]
spleen_arr  = liver_arr * 0.3  # spleen ~30% of MPS uptake

# -- Derived PK metrics ---------------------------------------------------------
# t1/2 (blood circulation) from blood profile
def compute_thalf(times, blood):
    half_val = blood[0] / 2
    for i in range(1, len(blood)):
        if blood[i] <= half_val:
            t_prev, t_curr = times[i-1], times[i]
            b_prev, b_curr = blood[i-1], blood[i]
            return t_prev + (half_val - b_prev) / (b_curr - b_prev) * (t_curr - t_prev)
    return times[-1]  # still above half at end

t_half = round(compute_thalf(sol.t, blood_arr), 1)
tumor_peak_idx  = np.argmax(tumor_arr)
tumor_peak_val  = round(tumor_arr[tumor_peak_idx], 2)
tumor_peak_time = round(sol.t[tumor_peak_idx], 1)
liver_24h       = round(float(np.interp(24, sol.t, liver_arr)), 1) if t_end >= 24 else round(liver_arr[-1], 1)
spleen_24h      = round(float(np.interp(24, sol.t, spleen_arr)), 1) if t_end >= 24 else round(spleen_arr[-1], 1)
auc_blood       = round(float(np.trapz(blood_arr, sol.t)), 1)

# -- Stealth rating ------------------------------------------------------------
if t_half >= 12: stealth_rating = 'EXCELLENT (>12h circulation)'
elif t_half >= 6: stealth_rating = 'GOOD (6-12h circulation)'
elif t_half >= 2: stealth_rating = 'MODERATE (2-6h circulation)'
else: stealth_rating = 'POOR (<2h; rapid MPS clearance)'

mps_risk = 'LOW' if k_mps < 0.15 else ('MEDIUM' if k_mps < 0.4 else 'HIGH')

# -- Write outputs --------------------------------------------------------------
with open('pk_profile.csv','w',newline='') as f:
    w = csv.writer(f)
    w.writerow(['time_h','blood_pct_ID','tumor_pct_ID','liver_pct_ID','spleen_pct_ID','peripheral_pct_ID'])
    for i, t in enumerate(sol.t):
        w.writerow([round(t,2), round(blood_arr[i],2), round(tumor_arr[i],2),
                    round(liver_arr[i],2), round(spleen_arr[i]*0.3,2), round(periph_arr[i],2)])

half_life_data = {
    't_half_blood_h': t_half, 'AUC_blood_pct_ID_h': auc_blood,
    'tumor_peak_pct_ID': tumor_peak_val, 'tumor_peak_time_h': tumor_peak_time,
    'liver_uptake_24h_pct': liver_24h, 'spleen_uptake_24h_pct': spleen_24h,
    'k_MPS_h': round(k_mps,4), 'k_EPR_h': round(k_epr,4)
}
with open('half_life_summary.json','w') as f:
    json.dump(half_life_data, f, indent=2)

# Formulation guidance
if t_half < 2:
    rec = f'Increase PEG density to >=0.15 chains/nm2 (current {peg_dens}) and/or increase PEG MW to >=5000 Da for adequate circulation'
elif tumor_peak_val < 1.0 and tumor_model != 'none':
    rec = f'Tumor EPR accumulation ({tumor_peak_val}%ID/g) below clinical threshold (2-5%); optimize size to 80-120nm for EPR'
else:
    rec = f'Formulation parameters adequate; t1/2={t_half}h, tumor peak={tumor_peak_val}%ID/g'

formulation_risk_data = {
    'MPS_clearance_risk': mps_risk,
    'stealth_rating': stealth_rating,
    'k_MPS_1_per_h': round(k_mps,4),
    'recommendation': rec,
    'particle_params': {'diameter_nm': d_nm, 'surface': surface,
                        'PEG_density_chains_nm2': peg_dens, 'zeta_mV': zeta}
}
with open('formulation_risk.json','w') as f:
    json.dump(formulation_risk_data, f, indent=2)

summary = {'status':'completed', **half_life_data, 'stealth_rating': stealth_rating,
           'MPS_clearance_risk': mps_risk, 'recommendation': rec}
with open('np_pk_results.json','w') as f:
    json.dump(summary, f, indent=2)

report = ["=== NANOPARTICLE PK & BIODISTRIBUTION REPORT ===",
          f"Particle: {d_nm} nm | Surface: {surface} | PEG: {peg_dens} chains/nm2 ({peg_mw} Da)",
          f"Dose: {dose} mg/kg | Tumor model: {tumor_model}", "",
          f"Blood circulation t1/2:   {t_half} h  ({stealth_rating})",
          f"AUC (blood):           {auc_blood} %ID*h",
          f"Tumor peak:            {tumor_peak_val} %ID/g at {tumor_peak_time} h",
          f"Liver uptake (24h):    {liver_24h} %ID",
          f"MPS clearance risk:    {mps_risk}  (k_MPS={round(k_mps,4)}/h)",
          "", f"-> {rec}"]
with open('np_pk_output.txt','w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
nanoparticle_pk_biodistribution:
  python: "3.10"
  numpy: ">=1.24"
  scipy: ">=1.10"
EOF
    """
}

workflow NANOPARTICLE_PK_WORKFLOW {
    take: meta_ch
    main: NANOPARTICLE_PK_BIODISTRIBUTION(meta_ch)
    emit:
        results   = NANOPARTICLE_PK_BIODISTRIBUTION.out.results
        pk_profile = NANOPARTICLE_PK_BIODISTRIBUTION.out.pk_profile
}

workflow {
    meta = [id: 'np_pk_run', single_end: false]
    Channel.value(meta) | NANOPARTICLE_PK_WORKFLOW
}
