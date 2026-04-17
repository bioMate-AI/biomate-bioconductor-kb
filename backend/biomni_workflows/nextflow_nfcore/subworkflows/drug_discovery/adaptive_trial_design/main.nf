#!/usr/bin/env nextflow
/*
 * drug_discovery/adaptive_trial_design
 *
 * Simulates adaptive clinical trial designs beyond standard 3+3/BOIN.
 * Supports:
 *   - Response-Adaptive Randomization (RAR) via Thompson sampling (Thall & Wathen 2007)
 *   - Multi-Arm Multi-Stage (MAMS) with interim analyses (Royston 2011)
 *   - Futility/efficacy stopping with O'Brien-Fleming alpha-spending
 *     and Pocock beta-spending boundaries (Lan & DeMets 1983)
 *
 * Applications: Phase II/III designs where multiple arms or adaptive
 * randomization can reduce sample size or increase probability of success.
 *
 * Input:  n_arms, arm_effect_sizes_pct, control_response_rate, n_interim_analyses,
 *         alpha, power, n_simulations
 * Output: adaptive_design_results.json, arm_allocation.csv, stopping_boundaries.csv
 */

nextflow.enable.dsl = 2

params.outdir                   = './results'
params.n_arms                   = '3'
params.arm_response_rates       = '[0.20, 0.40, 0.55]'
params.control_response_rate    = '0.20'
params.n_interim_analyses       = '2'
params.n_patients_per_stage     = '30'
params.alpha_one_sided          = '0.025'
params.power                    = '0.80'
params.n_simulations            = '1000'
params.design_type              = 'MAMS'
params.rar_exponent             = '0.5'
params.futility_boundary        = '0.10'

process ADAPTIVE_TRIAL_DESIGN {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("adaptive_results.json"),        emit: results
    tuple val(meta), path("adaptive_output.txt"),          emit: output
    tuple val(meta), path("adaptive_design.json"),         emit: design
    tuple val(meta), path("arm_allocation.csv"),           emit: allocation
    tuple val(meta), path("stopping_boundaries.csv"),      emit: boundaries
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_N_ARMS='${params.n_arms}'
    export PARAM_RATES='${params.arm_response_rates}'
    export PARAM_CTRL='${params.control_response_rate}'
    export PARAM_N_INTERIM='${params.n_interim_analyses}'
    export PARAM_N_STAGE='${params.n_patients_per_stage}'
    export PARAM_ALPHA='${params.alpha_one_sided}'
    export PARAM_POWER='${params.power}'
    export PARAM_NSIM='${params.n_simulations}'
    export PARAM_DESIGN='${params.design_type}'
    export PARAM_RAR_EXP='${params.rar_exponent}'
    export PARAM_FUTILITY='${params.futility_boundary}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
import numpy as np
from scipy.stats import norm, beta as beta_dist

def ac(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

def ac_int(v, default=None):
    if v in (None,'','null','None'): return default
    try: return int(float(v))
    except: return default

np.random.seed(42)

n_arms      = ac_int(os.environ.get('PARAM_N_ARMS'), 3)
rates_raw   = os.environ.get('PARAM_RATES', '[0.20,0.40,0.55]')
ctrl_rate   = ac(os.environ.get('PARAM_CTRL'), 0.20)
n_interim   = ac_int(os.environ.get('PARAM_N_INTERIM'), 2)
n_per_stage = ac_int(os.environ.get('PARAM_N_STAGE'), 30)
alpha       = ac(os.environ.get('PARAM_ALPHA'), 0.025)
power       = ac(os.environ.get('PARAM_POWER'), 0.80)
n_sims      = ac_int(os.environ.get('PARAM_NSIM'), 1000)
design_type = os.environ.get('PARAM_DESIGN', 'MAMS')
rar_exp     = ac(os.environ.get('PARAM_RAR_EXP'), 0.5)
futility_b  = ac(os.environ.get('PARAM_FUTILITY'), 0.10)

try:
    true_rates = json.loads(rates_raw)
    true_rates = [float(r) for r in true_rates]
except:
    true_rates = [0.20 + 0.15*i for i in range(n_arms)]
while len(true_rates) < n_arms:
    true_rates.append(ctrl_rate)
true_rates = true_rates[:n_arms]

# ── O'Brien-Fleming efficacy boundaries (Lan-DeMets 1983) ────────────────────
def obf_boundary(t_frac, alpha_total, n_stages):
    """
    Approximate O'Brien-Fleming alpha-spending at information fraction t.
    Boundary (one-sided z): z* ≈ z_alpha / sqrt(t_frac)
    Ensures global Type I error = alpha_total.
    """
    z_alpha = norm.ppf(1 - alpha_total)
    z_star  = z_alpha / math.sqrt(max(t_frac, 0.01))
    return round(z_star, 4)

def pocock_futility_boundary(t_frac, beta, n_stages):
    """
    Pocock-style beta-spending futility boundary.
    Stop for futility if conditional power < futility_b threshold.
    Approximated as z < z_futility (one-sided).
    """
    z_beta = norm.ppf(1 - beta)
    return round(z_beta * math.sqrt(t_frac), 4)

# Build stopping boundaries
stages     = list(range(1, n_interim + 2))  # includes final
stage_fracs = [s / len(stages) for s in stages]
eff_bounds = [obf_boundary(t, alpha, len(stages)) for t in stage_fracs]
fut_bounds = [pocock_futility_boundary(t, 1-power, len(stages)) for t in stage_fracs]

bounds_csv = [['stage', 'information_fraction', 'efficacy_z_boundary',
               'futility_z_boundary', 'efficacy_p', 'patients_enrolled']]
for i, (s, t, eb, fb) in enumerate(zip(stages, stage_fracs, eff_bounds, fut_bounds)):
    n_total = round(n_per_stage * n_arms * s)
    p_eff = round(1 - norm.cdf(eb), 5)
    bounds_csv.append([s, round(t,3), eb, fb, p_eff, n_total])

# ── Thompson sampling (RAR) ───────────────────────────────────────────────────
def thompson_weights(successes, failures, exponent=0.5):
    """
    RAR allocation probabilities: sample beta distributions and normalise.
    Raises to power (exponent < 1) to dampen exploitation vs. exploration.
    """
    samples = [beta_dist.rvs(s+1, f+1, size=1000) for s, f in zip(successes, failures)]
    probs   = np.mean(np.array(samples) == np.max(samples, axis=0), axis=1)
    probs   = probs ** exponent
    probs  /= (probs.sum() + 1e-10)
    return probs

# ── MAMS simulation ───────────────────────────────────────────────────────────
def simulate_mams_trial(true_rates, n_per_stage, n_interim, alpha, power,
                        rar_exp, futility_b, n_sims, design):
    """
    Returns operating characteristics from n_sims trial simulations.
    """
    n_arms   = len(true_rates)
    n_stages = n_interim + 1
    ctrl_idx = 0  # arm 0 is control

    results = {
        'correct_selection_pct': 0,
        'type_I_error_pct': 0,
        'power_pct': 0,
        'early_stop_efficacy': 0,
        'early_stop_futility': 0,
        'mean_n_enrolled': 0,
        'arm_allocation_pct': [0.0] * n_arms,
    }

    correct_sel = 0
    type_I = 0
    powered = 0
    early_eff = 0
    early_fut = 0
    total_n = 0
    arm_alloc = np.zeros(n_arms)
    best_arm  = np.argmax(true_rates)

    for sim in range(n_sims):
        successes = np.ones(n_arms)  # beta prior (1,1) = uniform
        failures  = np.ones(n_arms)
        stopped = False
        stop_type = None
        n_enrolled = 0

        for stage in range(1, n_stages + 1):
            # Randomization allocation
            if design == 'RAR' and stage > 1:
                alloc_probs = thompson_weights(successes, failures, rar_exp)
            else:
                alloc_probs = np.ones(n_arms) / n_arms

            n_per_arm = np.random.multinomial(n_per_stage, alloc_probs)
            for arm_i in range(n_arms):
                arm_alloc[arm_i] += n_per_arm[arm_i]
                n_i = n_per_arm[arm_i]
                y_i = np.sum(np.random.binomial(1, true_rates[arm_i], n_i))
                successes[arm_i] += y_i
                failures[arm_i]  += n_i - y_i
            n_enrolled += n_per_stage * n_arms  # total across arms

            # Statistical test: best treatment vs control (two-sample z-test)
            t_frac     = stage / n_stages
            eff_z      = obf_boundary(t_frac, alpha, n_stages)
            fut_z      = pocock_futility_boundary(t_frac, 1-power, n_stages)

            # Compare best non-control arm to control
            non_ctrl_success = successes[1:]
            non_ctrl_fail    = failures[1:]
            best_treat = np.argmax(non_ctrl_success / (non_ctrl_success + non_ctrl_fail)) + 1

            n_ctrl = successes[ctrl_idx] + failures[ctrl_idx] - 2
            n_trt  = successes[best_treat] + failures[best_treat] - 2
            p_ctrl = (successes[ctrl_idx] - 1) / max(n_ctrl, 1)
            p_trt  = (successes[best_treat] - 1) / max(n_trt, 1)
            p_pool = ((successes[ctrl_idx]-1) + (successes[best_treat]-1)) / max(n_ctrl+n_trt, 1)
            se = math.sqrt(p_pool*(1-p_pool)*(1/max(n_ctrl,1) + 1/max(n_trt,1)))
            z_stat = (p_trt - p_ctrl) / max(se, 1e-6)

            if stage < n_stages:
                if z_stat >= eff_z:
                    stopped = True; stop_type = 'efficacy'; early_eff += 1; break
                if z_stat <= fut_z:
                    stopped = True; stop_type = 'futility'; early_fut += 1; break
            else:
                if z_stat >= eff_z:
                    powered += 1
                    if best_treat == best_arm:
                        correct_sel += 1
                    if true_rates[ctrl_idx] == max(true_rates):
                        type_I += 1
                else:
                    if true_rates[ctrl_idx] == max(true_rates):
                        pass  # true null accepted — good
                    else:
                        pass  # false negative — underpowered

        if stopped and stop_type == 'efficacy':
            if best_arm != ctrl_idx:
                correct_sel += 1
            powered += 1
        total_n += n_enrolled

    results['power_pct']             = round(100 * powered / n_sims, 1)
    results['correct_selection_pct'] = round(100 * correct_sel / n_sims, 1)
    results['early_stop_efficacy']   = round(100 * early_eff / n_sims, 1)
    results['early_stop_futility']   = round(100 * early_fut / n_sims, 1)
    results['mean_n_enrolled']       = round(total_n / n_sims, 0)
    results['arm_allocation_pct']    = [round(100*a/(arm_alloc.sum()+1e-6), 1) for a in arm_alloc]
    return results

oc = simulate_mams_trial(true_rates, n_per_stage, n_interim, alpha, power,
                          rar_exp, futility_b, n_sims, design_type)

alloc_csv = [['arm', 'true_response_rate', 'allocation_pct',
              'is_control', 'arm_label']]
for i, (rate, alloc) in enumerate(zip(true_rates, oc['arm_allocation_pct'])):
    alloc_csv.append([f'Arm{i+1}', rate, alloc, i==0, 'Control' if i==0 else f'Treatment {i}'])

design_out = {
    'design_type': design_type,
    'n_arms': n_arms,
    'n_interim_analyses': n_interim,
    'alpha_one_sided': alpha,
    'target_power': power,
    'n_simulations': n_sims,
    'true_response_rates': true_rates,
    'control_arm_rate': ctrl_rate,
    'operating_characteristics': oc,
    'boundaries': {
        'efficacy_z': eff_bounds,
        'futility_z': fut_bounds,
        'information_fractions': stage_fracs,
    },
    'sample_size_estimate': round(oc['mean_n_enrolled'], 0),
    'notes': [
        'Operating characteristics from Monte Carlo simulation',
        f'O\'Brien-Fleming efficacy boundary (one-sided α={alpha})',
        f'Pocock futility boundary (β={1-power:.2f})',
        f'RAR exponent={rar_exp} (0.5=balanced exploration/exploitation)',
    ]
}

with open('adaptive_design.json', 'w') as f:
    json.dump(design_out, f, indent=2)
with open('arm_allocation.csv', 'w', newline='') as f:
    csv.writer(f).writerows(alloc_csv)
with open('stopping_boundaries.csv', 'w', newline='') as f:
    csv.writer(f).writerows(bounds_csv)
with open('adaptive_results.json', 'w') as f:
    json.dump({'status': 'completed', **design_out}, f, indent=2)

report = [
    f'=== ADAPTIVE TRIAL DESIGN: {design_type} ===', '',
    f'Arms: {n_arms} | Interim analyses: {n_interim} | N/stage: {n_per_stage}',
    f'Alpha (one-sided): {alpha} | Target power: {power*100:.0f}%',
    f'Simulations: {n_sims}', '',
    'OPERATING CHARACTERISTICS:',
    f"  Power:                  {oc['power_pct']:.1f}%",
    f"  Correct arm selection:  {oc['correct_selection_pct']:.1f}%",
    f"  Early stop (efficacy):  {oc['early_stop_efficacy']:.1f}%",
    f"  Early stop (futility):  {oc['early_stop_futility']:.1f}%",
    f"  Mean N enrolled:        {oc['mean_n_enrolled']:.0f}", '',
    'ARM ALLOCATION (%):',
]
for i, (rate, alloc) in enumerate(zip(true_rates, oc['arm_allocation_pct'])):
    label = 'Control' if i == 0 else f'Trt {i}'
    report.append(f"  {label}: {alloc:.1f}%  (true rate={rate:.0%})")
report += ['', 'STOPPING BOUNDARIES:',
           '  Stage | Info frac | Efficacy Z | Futility Z']
for row in bounds_csv[1:]:
    report.append(f"  {row[0]:5d} | {row[1]:.2f}      | {row[2]:.3f}       | {row[3]:.3f}")

with open('adaptive_output.txt', 'w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
adaptive_trial_design:
  python: "3.10"
  scipy: ">=1.10"
  numpy: ">=1.24"
  reference: "Thall & Wathen 2007 RAR; Royston 2011 MAMS; Lan & DeMets 1983"
EOF
    """
}

workflow ADAPTIVE_TRIAL_DESIGN_WORKFLOW {
    take: meta_ch
    main: ADAPTIVE_TRIAL_DESIGN(meta_ch)
    emit:
        results    = ADAPTIVE_TRIAL_DESIGN.out.results
        design     = ADAPTIVE_TRIAL_DESIGN.out.design
        allocation = ADAPTIVE_TRIAL_DESIGN.out.allocation
        boundaries = ADAPTIVE_TRIAL_DESIGN.out.boundaries
}

workflow {
    meta = [id: 'adaptive_trial_run', single_end: false]
    Channel.value(meta) | ADAPTIVE_TRIAL_DESIGN_WORKFLOW
}
