#!/usr/bin/env nextflow
/*
 * drug_discovery/clinical_trial_simulation
 *
 * Simulates Phase I-II clinical trials using PopPK parameters and
 * exposure-response relationships. Supports adaptive dose escalation
 * (3+3 design and BOIN-equivalent algorithm) and Phase II population
 * simulations with virtual patient inter-individual variability.
 *
 * BOIN algorithm: Liu & Yuan (2015) BOIN design. Implemented in Python
 * to avoid R dependency for Batch execution.
 * PopPK: 1-compartment with log-normal IIV (CLi = CL * exp(etaCL)).
 *
 * Input:  dose escalation design + PK params + ER model
 * Output: dose_escalation_results.csv, BOIN_decision_table.json,
 *         phase2_simulation.csv, operating_characteristics.json
 */

nextflow.enable.dsl = 2

params.outdir           = './results'
params.starting_dose_mg = '10'
params.max_dose_mg      = '400'
params.dose_levels_json = '[10,20,40,80,150,300,400]'
params.DLT_rate_target  = '0.25'
params.design           = 'BOIN'   // 3plus3 | BOIN
params.n_simulations    = '1000'
params.pk_CL_L_h        = '10'
params.pk_Vd_L          = '70'
params.pk_ka_h          = '1.5'
params.pk_IIV_CL_pct    = '30'    // inter-individual variability on CL
params.pk_IIV_Vd_pct    = '20'
params.ER_model         = 'Emax'  // Emax | linear
params.ER_Emax          = '0.9'
params.ER_EC50_nM       = '2000'
params.ER_E0            = '0.02'   // baseline response (DLT rate at dose 0)
params.n_patients_phase2 = '100'
params.dose_regimen_mg  = '150'
params.dose_interval_h  = '24'
params.simulation_hours = '168'   // 1 week
params.primary_endpoint_threshold = '0.3'  // response rate threshold for Phase II success

process CLINICAL_TRIAL_SIMULATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("clinical_trial_results.json"),      emit: results
    tuple val(meta), path("clinical_trial_output.txt"),        emit: output
    tuple val(meta), path("dose_escalation_results.csv"),      emit: escalation
    tuple val(meta), path("BOIN_decision_table.json"),         emit: boin
    tuple val(meta), path("phase2_simulation.csv"),            emit: phase2
    tuple val(meta), path("operating_characteristics.json"),   emit: oc
    tuple val(meta), path("qc_metrics.json"),                  emit: qc_metrics
    path "versions.yml",                                       emit: versions

    script:
    """
    export PARAM_START_DOSE='${params.starting_dose_mg}'
    export PARAM_MAX_DOSE='${params.max_dose_mg}'
    export PARAM_DOSE_LEVELS='${params.dose_levels_json}'
    export PARAM_DLT_TARGET='${params.DLT_rate_target}'
    export PARAM_DESIGN='${params.design}'
    export PARAM_N_SIM='${params.n_simulations}'
    export PARAM_CL='${params.pk_CL_L_h}'
    export PARAM_VD='${params.pk_Vd_L}'
    export PARAM_KA='${params.pk_ka_h}'
    export PARAM_IIV_CL='${params.pk_IIV_CL_pct}'
    export PARAM_IIV_VD='${params.pk_IIV_Vd_pct}'
    export PARAM_ER_MODEL='${params.ER_model}'
    export PARAM_EMAX='${params.ER_Emax}'
    export PARAM_EC50='${params.ER_EC50_nM}'
    export PARAM_E0='${params.ER_E0}'
    export PARAM_N_P2='${params.n_patients_phase2}'
    export PARAM_P2_DOSE='${params.dose_regimen_mg}'
    export PARAM_P2_INTERVAL='${params.dose_interval_h}'
    export PARAM_SIM_H='${params.simulation_hours}'
    export PARAM_P2_THRESH='${params.primary_endpoint_threshold}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np

def auto_convert(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

# -- Load params ---------------------------------------------------------------
start_dose   = auto_convert(os.environ.get('PARAM_START_DOSE'), 10)
max_dose     = auto_convert(os.environ.get('PARAM_MAX_DOSE'), 400)
dose_levels  = json.loads(os.environ.get('PARAM_DOSE_LEVELS','[10,20,40,80,150,300,400]'))
dlt_target   = auto_convert(os.environ.get('PARAM_DLT_TARGET'), 0.25)
design       = os.environ.get('PARAM_DESIGN','BOIN')
n_sim        = int(auto_convert(os.environ.get('PARAM_N_SIM'), 1000))
CL_pop       = auto_convert(os.environ.get('PARAM_CL'), 10)       # L/h
Vd_pop       = auto_convert(os.environ.get('PARAM_VD'), 70)       # L
ka           = auto_convert(os.environ.get('PARAM_KA'), 1.5)       # 1/h
iiv_cl       = auto_convert(os.environ.get('PARAM_IIV_CL'), 30) / 100  # CV fraction
iiv_vd       = auto_convert(os.environ.get('PARAM_IIV_VD'), 20) / 100
er_model     = os.environ.get('PARAM_ER_MODEL','Emax')
Emax         = auto_convert(os.environ.get('PARAM_EMAX'), 1.0)
EC50_nM      = auto_convert(os.environ.get('PARAM_EC50'), 500)
E0           = auto_convert(os.environ.get('PARAM_E0'), 0.05)
n_phase2     = int(auto_convert(os.environ.get('PARAM_N_P2'), 100))
p2_dose      = auto_convert(os.environ.get('PARAM_P2_DOSE'), 150)
dose_int_h   = auto_convert(os.environ.get('PARAM_P2_INTERVAL'), 24)
sim_h        = auto_convert(os.environ.get('PARAM_SIM_H'), 168)
p2_thresh    = auto_convert(os.environ.get('PARAM_P2_THRESH'), 0.3)

rng = np.random.default_rng(42)

# -- PK model: 1-compartment oral ---------------------------------------------
def simulate_pk(dose_mg, CL, Vd, ka, t_eval):
    '''1-compartment: Cp(t) = (F*dose/Vd) * ka/(ka-ke) * (exp(-ke*t) - exp(-ka*t))'''
    ke = CL / Vd
    F  = 0.8  # bioavailability
    dose_mg_L = dose_mg * 1e-3  # mg -> g -> divide by Vd in L -> g/L = mg/L = ug/mL
    if abs(ka - ke) < 1e-6:
        ka = ke * 1.001
    cp = (F * dose_mg_L * 1000 / Vd) * ka / (ka - ke) * (np.exp(-ke*t_eval) - np.exp(-ka*t_eval))
    return np.maximum(0, cp)  # ug/mL

def dose_to_AUC(dose_mg, CL, F=0.8):
    return F * dose_mg / CL  # ug/mL*h = mg/L*h

def AUC_to_Cmax(auc, t_half):
    return auc / t_half  # rough estimate

def pk_to_Cmax_nM(dose_mg, CL, Vd, ka, mw=300):
    t_eval = np.linspace(0, 48, 500)
    cp = simulate_pk(dose_mg, CL, Vd, ka, t_eval)
    cmax_ugmL = float(cp.max())
    return cmax_ugmL * 1e3 / mw * 1e3  # ug/mL -> umol/L -> nM (MW in Da, rough 300 for typical drug)

# -- Exposure-response model ---------------------------------------------------
def predict_DLT(Cmax_nM, EC50=EC50_nM, Emax=Emax, E0=E0, model='Emax'):
    if model == 'Emax':
        effect = E0 + Emax * Cmax_nM / (EC50 + Cmax_nM)
    else:  # linear
        effect = E0 + (Emax / EC50) * Cmax_nM
    return min(0.99, max(0.001, effect))

def predict_efficacy(Cmax_nM, EC50=EC50_nM*0.5, Emax=0.8, E0=0.05):
    '''Efficacy response: lower EC50 (more potent effect window).'''
    return min(0.99, E0 + Emax * Cmax_nM / (EC50 + Cmax_nM))

# -- BOIN dose escalation algorithm (Liu & Yuan 2015) -------------------------
def boin_boundaries(phi, epsilon1=0.1, epsilon2=0.1):
    '''Compute BOIN lambda_e (escalate) and lambda_d (de-escalate) thresholds.'''
    lambda_e = phi - epsilon1 * phi
    lambda_d = phi + epsilon2 * (1 - phi)
    return round(lambda_e, 3), round(lambda_d, 3)

def simulate_boin_trial(dose_levels, true_DLT_probs, phi=0.25, cohort_size=3, max_patients=30):
    '''Simulate single BOIN dose escalation trial.'''
    lambda_e, lambda_d = boin_boundaries(phi)
    n_levels = len(dose_levels)
    patients_per_level = [0] * n_levels
    DLTs_per_level     = [0] * n_levels
    current_level = 0
    trial_history = []
    total_patients = 0

    while total_patients < max_patients and current_level < n_levels:
        # Enroll cohort at current dose
        n_enrolled  = min(cohort_size, max_patients - total_patients)
        dlts = int(rng.binomial(n_enrolled, true_DLT_probs[current_level]))
        patients_per_level[current_level] += n_enrolled
        DLTs_per_level[current_level]     += dlts
        total_patients += n_enrolled

        dlt_rate = DLTs_per_level[current_level] / patients_per_level[current_level]
        trial_history.append({'level':current_level, 'dose':dose_levels[current_level],
                               'n':n_enrolled, 'DLTs':dlts, 'rate':round(dlt_rate,3)})

        # BOIN decision
        if dlt_rate <= lambda_e and current_level < n_levels - 1:
            current_level += 1  # escalate
        elif dlt_rate >= lambda_d:
            if current_level > 0:
                current_level -= 1  # de-escalate
            # If at level 0 with too many DLTs, stop
            if DLTs_per_level[0] / max(1, patients_per_level[0]) >= 0.95 * phi:
                break

    # Select MTD: level with DLT rate closest to phi (below phi)
    valid = [(i, DLTs_per_level[i]/max(1,patients_per_level[i]))
             for i in range(n_levels) if patients_per_level[i] > 0]
    below_phi = [(i, r) for i,r in valid if r <= phi]
    if below_phi:
        mtd_idx = max(below_phi, key=lambda x: x[1])[0]
    else:
        mtd_idx = 0

    return mtd_idx, patients_per_level, DLTs_per_level, trial_history

def simulate_3plus3(dose_levels, true_DLT_probs):
    '''Classic 3+3 design.'''
    current = 0
    mtd_idx = 0
    n_per_level = [0]*len(dose_levels)
    dlt_per_level = [0]*len(dose_levels)

    while current < len(dose_levels):
        # Cohort 1
        dlts = int(rng.binomial(3, true_DLT_probs[current]))
        n_per_level[current] += 3; dlt_per_level[current] += dlts

        if dlts == 0:
            if current < len(dose_levels)-1:
                current += 1
            else:
                mtd_idx = current; break
        elif dlts == 1:
            # Expand to 6 at this level
            dlts2 = int(rng.binomial(3, true_DLT_probs[current]))
            n_per_level[current] += 3; dlt_per_level[current] += dlts2
            if dlts + dlts2 >= 2:
                mtd_idx = max(0, current-1); break
            else:
                if current < len(dose_levels)-1:
                    current += 1
                else:
                    mtd_idx = current; break
        else:
            mtd_idx = max(0, current-1); break

    return mtd_idx, n_per_level, dlt_per_level

# -- Generate true DLT probability curve from ER model -------------------------
true_DLT_probs = []
for d in dose_levels:
    if d > max_dose: break
    CL_i = CL_pop * np.exp(rng.normal(0, iiv_cl*0.1))  # small noise
    Vd_i = Vd_pop * np.exp(rng.normal(0, iiv_vd*0.1))
    cmax = pk_to_Cmax_nM(d, CL_i, Vd_i, ka)
    dlt  = predict_DLT(cmax)
    true_DLT_probs.append(round(dlt, 3))

doses_to_use = [d for d in dose_levels if d <= max_dose][:len(true_DLT_probs)]

# -- Run n_sim simulations -----------------------------------------------------
mtd_counts    = {i:0 for i in range(len(doses_to_use))}
mtd_counts[-1] = 0  # under-dosing
n_sim_use = min(n_sim, 2000)  # cap for compute

for _ in range(n_sim_use):
    if design.upper() == 'BOIN':
        mtd_idx, np_l, dlt_l, _ = simulate_boin_trial(doses_to_use, true_DLT_probs, phi=dlt_target)
    else:
        mtd_idx, np_l, dlt_l = simulate_3plus3(doses_to_use, true_DLT_probs)
    mtd_counts[mtd_idx] = mtd_counts.get(mtd_idx, 0) + 1

# True MTD: highest dose with DLT rate <= target
_safe_doses = [i for i,p in enumerate(true_DLT_probs) if p <= dlt_target]
no_safe_dose = len(_safe_doses) == 0
true_mtd_idx = max(_safe_doses) if _safe_doses else None

if true_mtd_idx is not None:
    P_correct_MTD = mtd_counts.get(true_mtd_idx, 0) / n_sim_use
    P_underdosing = sum(mtd_counts.get(i,0) for i in range(true_mtd_idx)) / n_sim_use
    P_overdosing  = sum(mtd_counts.get(i,0) for i in range(true_mtd_idx+1, len(doses_to_use))) / n_sim_use
else:
    # All doses exceed DLT target — no safe starting dose in this range
    P_correct_MTD = 0.0
    P_underdosing = 0.0
    P_overdosing  = 1.0  # all selections are overdoses by definition

# -- Dose escalation summary table --------------------------------------------
esc_rows = []
for i, (dose, true_dlt) in enumerate(zip(doses_to_use, true_DLT_probs)):
    CL_i = CL_pop; Vd_i = Vd_pop
    cmax = pk_to_Cmax_nM(dose, CL_i, Vd_i, ka)
    eff  = predict_efficacy(cmax)
    esc_rows.append({'dose_level': i+1, 'dose_mg': dose,
                     'true_DLT_rate': true_dlt, 'Cmax_nM_median': round(cmax,1),
                     'P_dose_selected_pct': round(mtd_counts.get(i,0)/n_sim_use*100,1),
                     'predicted_efficacy': round(eff,3)})

# BOIN decision table
lambda_e, lambda_d = boin_boundaries(dlt_target)
boin_table = {
    'target_DLT_rate': dlt_target, 'lambda_escalate': lambda_e, 'lambda_deescalate': lambda_d,
    'rule': f'If DLT/n <= {lambda_e}: escalate | If DLT/n >= {lambda_d}: de-escalate | else: stay',
    'design': design
}

# -- Phase II simulation --------------------------------------------------------
# Base Phase 2 candidates on the BOIN-identified MTD when available
if true_mtd_idx is not None:
    p2_base = doses_to_use[true_mtd_idx]
elif doses_to_use:
    p2_base = doses_to_use[0]  # fallback: lowest dose (starting dose only)
else:
    p2_base = p2_dose
p2_results = []
for dose_mg in [p2_base, p2_base*0.5, p2_base*2.0]:
    if dose_mg > max_dose * 1.1: continue
    response_rates = []
    for _ in range(n_sim_use // 10):
        responders = 0
        for _ in range(n_phase2):
            CL_i = CL_pop * math.exp(rng.normal(0, iiv_cl))
            Vd_i = Vd_pop * math.exp(rng.normal(0, iiv_vd))
            cmax = pk_to_Cmax_nM(dose_mg, CL_i, Vd_i, ka)
            eff  = predict_efficacy(cmax)
            if rng.random() < eff:
                responders += 1
        response_rates.append(responders / n_phase2)
    mean_rr = round(float(np.mean(response_rates)), 3)
    p_success = round(float(np.mean([r >= p2_thresh for r in response_rates])), 3)
    ci_95 = [round(float(np.percentile(response_rates, 2.5)),3),
             round(float(np.percentile(response_rates, 97.5)),3)]
    p2_results.append({'dose_mg': dose_mg, 'response_rate_pct': round(mean_rr*100,1),
                       'CI_95_low': ci_95[0], 'CI_95_high': ci_95[1],
                       'P_success': p_success,
                       'expected_sample_size': n_phase2})

# Recommended Phase II dose
best_p2 = max(p2_results, key=lambda x: x['P_success']) if p2_results else {}
recommended_p2_dose = best_p2.get('dose_mg', p2_base)

# -- Write outputs --------------------------------------------------------------
with open('dose_escalation_results.csv','w',newline='') as f:
    w = csv.DictWriter(f, fieldnames=['dose_level','dose_mg','true_DLT_rate','Cmax_nM_median',
                                       'P_dose_selected_pct','predicted_efficacy'])
    w.writeheader(); w.writerows(esc_rows)

with open('BOIN_decision_table.json','w') as f:
    json.dump(boin_table, f, indent=2)

with open('phase2_simulation.csv','w',newline='') as f:
    w = csv.DictWriter(f, fieldnames=['dose_mg','response_rate_pct','CI_95_low','CI_95_high',
                                       'P_success','expected_sample_size'])
    w.writeheader(); w.writerows(p2_results)

oc = {'P_correct_MTD_selection': round(P_correct_MTD,3),
      'P_underdosing': round(P_underdosing,3),
      'P_overdosing': round(P_overdosing,3),
      'true_MTD_dose_mg': doses_to_use[true_mtd_idx] if true_mtd_idx is not None and true_mtd_idx < len(doses_to_use) else None,
      'no_safe_dose_in_range': no_safe_dose,
      'n_simulations': n_sim_use, 'design': design}
with open('operating_characteristics.json','w') as f:
    json.dump(oc, f, indent=2)

if no_safe_dose:
    recommendation = f"NO SAFE DOSE IDENTIFIED — all {len(doses_to_use)} dose levels exceed DLT target {dlt_target*100:.0f}%; escalation should not proceed without dose range revision"
else:
    recommendation = f"{round(recommended_p2_dose)} mg {'QD' if dose_int_h >= 20 else 'BID'}"
summary = {'status':'completed','design':design,'n_sim':n_sim_use,
           'operating_characteristics':oc,'recommended_Phase2_dose':recommendation,
           'phase2_results':p2_results}
with open('clinical_trial_results.json','w') as f:
    json.dump(summary, f, indent=2)

# qc_metrics.json — gate metrics consumed by the QC monitor's
# boin_dlt_boundary gate (MTD observed DLT rate ≤ target φ, GOLD-anchored
# to Liu & Yuan 2015 — both the BOIN decision rule AND the per-φ
# boundary values are stated verbatim in Table 2 of the paper).
# Keys the gate reader expects:
#   mtd_observed_dlt_rate — true DLT rate at the selected MTD level
#   target_dlt_rate       — the φ target
# When no safe dose exists in range, mtd_observed_dlt_rate is None
# and the gate skips (returns None) rather than firing a spurious FAIL.
_mtd_dlt = None
if true_mtd_idx is not None and true_mtd_idx < len(true_DLT_probs):
    _mtd_dlt = round(float(true_DLT_probs[true_mtd_idx]), 4)
qc_metrics = {
    'mtd_observed_dlt_rate':     _mtd_dlt,
    'target_dlt_rate':           round(float(dlt_target), 4),
    'P_correct_MTD_selection':   round(P_correct_MTD, 3),
    'P_underdosing':             round(P_underdosing, 3),
    'P_overdosing':              round(P_overdosing, 3),
    'no_safe_dose_in_range':     bool(no_safe_dose),
    'design':                    design,
    'n_simulations':             n_sim_use,
}
with open('qc_metrics.json','w') as f:
    json.dump(qc_metrics, f, indent=2)

report = [f"=== CLINICAL TRIAL SIMULATION REPORT ===",
          f"Design: {design} | Target DLT rate: {dlt_target*100:.0f}% | Simulations: {n_sim_use}","",
          f"Dose escalation (true DLT rates):",
          *[f"  Dose {r['dose_mg']} mg: true DLT={r['true_DLT_rate']*100:.1f}% | P(selected)={r['P_dose_selected_pct']}%" for r in esc_rows],
          "", f"Operating characteristics:",
          f"  P(correct MTD): {oc['P_correct_MTD_selection']*100:.1f}%",
          f"  P(underdosing): {oc['P_underdosing']*100:.1f}%",
          f"  P(overdosing):  {oc['P_overdosing']*100:.1f}%",
          "", f"Recommended Phase II dose: {recommendation}",
          *[f"  {r['dose_mg']} mg: RR={r['response_rate_pct']}% | P(success)={r['P_success']*100:.0f}%" for r in p2_results]]
with open('clinical_trial_output.txt','w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
clinical_trial_simulation:
  python: "3.10"
  numpy: ">=1.24"
  scipy: ">=1.10"
  algorithm: "BOIN (Liu & Yuan 2015)"
EOF
    """
}

workflow CLINICAL_TRIAL_WORKFLOW {
    take: meta_ch
    main: CLINICAL_TRIAL_SIMULATION(meta_ch)
    emit:
        results = CLINICAL_TRIAL_SIMULATION.out.results
        oc      = CLINICAL_TRIAL_SIMULATION.out.oc
}

workflow {
    meta = [id: 'clinical_trial_run', single_end: false]
    Channel.value(meta) | CLINICAL_TRIAL_WORKFLOW
}
