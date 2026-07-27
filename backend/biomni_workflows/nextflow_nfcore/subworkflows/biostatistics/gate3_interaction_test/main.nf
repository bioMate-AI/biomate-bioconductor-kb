#!/usr/bin/env nextflow
/*
 * biostatistics/gate3_interaction_test
 *
 * THE GATE-3 TEST — is a biomarker PREDICTIVE (changes which treatment is better)
 * or merely PROGNOSTIC (identifies who does badly)? This is the test that decides
 * whether a stratification has commercial value to a drug developer. Nearly every
 * published stratification fails it (canonical example: PROFILE, biomarker x
 * treatment interaction 1%, p=0.944).
 *
 * Given a biomarker-stratified trial dataset (patient, biomarker status, treatment
 * arm, outcome), this computes:
 *   - per-stratum treatment effects (biomarker+ vs biomarker-)
 *   - the BIOMARKER x TREATMENT INTERACTION (estimate, 95% CI, p) — the gate-3 test
 *   - the fraction of DECISIONS CHANGED by acting on the biomarker (the single most
 *     predictive number for commercial viability, which almost nobody reports)
 *   - a gate-3 verdict: PREDICTIVE / prognostic-only / no-signal
 *
 * Handles binary outcomes (risk-difference interaction, delta-method SE) and
 * continuous outcomes (OLS with an interaction term). stdlib-only.
 *
 * References: FDA-NIH BEST framework; REMARK/STARD; PROFILE (Lancet Gastro 2024).
 *
 * INPUT (REQUIRED): trial CSV with columns (names flexible):
 *   patient_id, biomarker, treatment, outcome
 *   - biomarker  : positive/negative (1/0, pos/neg, or --biomarker_positive label)
 *   - treatment  : experimental/control (1/0, or --treatment_experimental label)
 *   - outcome    : binary (0/1, responder) or continuous (e.g. MG-ADL change)
 * OUTPUT: gate3_results.json, interaction_report.md, subgroup_effects.csv, versions.yml
 */

nextflow.enable.dsl = 2

params.outdir       = './results'
params.trial_file   = 'NONE'        // REQUIRED path to real stratified-trial CSV
params.analysis     = 'gate3 interaction test'
params.outcome_type = 'auto'        // auto | binary | continuous
params.biomarker_positive   = ''    // label counted as biomarker-positive (else 1/pos/yes/true)
params.treatment_experimental = ''  // label counted as experimental arm (else 1/exp/treated/b)
params.default_treatment    = 'control'  // standard-of-care arm for % decisions changed: control|experimental
params.higher_is_better     = 'true'     // is a higher outcome the better result?
params.min_interaction      = '0.10'     // |interaction| below this = not meaningful even if significant
params.alpha                = '0.05'

process GATE3_INTERACTION_TEST {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("gate3_results.json"),     emit: results
    tuple val(meta), path("interaction_report.md"),  emit: report
    tuple val(meta), path("subgroup_effects.csv"),   emit: subgroups
    path "versions.yml",                             emit: versions

    script:
    """
    export PARAM_TRIAL='${params.trial_file}'
    export PARAM_ANALYSIS='${params.analysis}'
    export PARAM_OUTCOME_TYPE='${params.outcome_type}'
    export PARAM_BM_POS='${params.biomarker_positive}'
    export PARAM_TX_EXP='${params.treatment_experimental}'
    export PARAM_DEFAULT_TX='${params.default_treatment}'
    export PARAM_HIB='${params.higher_is_better}'
    export PARAM_MIN_INT='${params.min_interaction}'
    export PARAM_ALPHA='${params.alpha}'

    python3 << 'PYEOF'
import os, sys, json, csv, math

def _f(v, d=None):
    if v in (None, '', 'null', 'None', 'NA', 'nan'): return d
    try: return float(v)
    except Exception: return d

def norm_cdf(z):
    return 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))

def two_sided_p(z):
    return 2.0 * (1.0 - norm_cdf(abs(z)))

trial   = os.environ.get('PARAM_TRIAL', 'NONE')
analysis = os.environ.get('PARAM_ANALYSIS', 'gate3 interaction test')
otype   = (os.environ.get('PARAM_OUTCOME_TYPE') or 'auto').lower()
bm_pos_lbl = (os.environ.get('PARAM_BM_POS') or '').strip().lower()
tx_exp_lbl = (os.environ.get('PARAM_TX_EXP') or '').strip().lower()
default_tx = (os.environ.get('PARAM_DEFAULT_TX') or 'control').lower()
hib     = (os.environ.get('PARAM_HIB') or 'true').lower() in ('true','1','yes')
min_int = _f(os.environ.get('PARAM_MIN_INT'), 0.10)
alpha   = _f(os.environ.get('PARAM_ALPHA'), 0.05)
z_crit  = 1.959964  # ~alpha 0.05 two-sided; report uses alpha for the verdict

def fail(msg):
    with open('gate3_results.json','w') as f:
        json.dump({'status':'failed','error':msg}, f, indent=2)
    with open('subgroup_effects.csv','w') as f:
        f.write('stratum,arm,n,outcome\\n')
    with open('interaction_report.md','w') as f:
        f.write('# Gate-3 interaction test — FAILED\\n\\n%s\\n' % msg)
    with open('versions.yml','w') as f:
        f.write('gate3_interaction_test:\\n  status: "failed"\\n')
    sys.exit(1)

if (not trial) or trial in ('NONE','') or not os.path.exists(trial):
    fail('--trial_file is required (patient_id, biomarker, treatment, outcome). No synthetic data is generated.')

with open(trial, newline='') as fh:
    rows = list(csv.DictReader(fh))
if not rows:
    fail('trial_file has no rows')

def col(row, *names):
    for n in names:
        for k in row:
            if k.strip().lower() == n:
                return row[k]
    return None

def is_pos_biomarker(v):
    s = str(v).strip().lower()
    if bm_pos_lbl:
        return s == bm_pos_lbl
    return s in ('1','1.0','pos','positive','yes','true','refractory','refractory_risk','high','+')

def is_experimental(v):
    s = str(v).strip().lower()
    if tx_exp_lbl:
        return s == tx_exp_lbl
    return s in ('1','1.0','exp','experimental','treated','treatment','b','drug','active')

# parse
data = []
for r in rows:
    bm = col(r, 'biomarker', 'biomarker_status', 'stratum', 'subgroup', 'telitacicept_candidate', 'predicted_fcrn_response')
    tx = col(r, 'treatment', 'arm', 'treatment_arm', 'drug')
    oc = col(r, 'outcome', 'response', 'responder', 'result', 'mgadl_delta', 'mg_adl_change', 'endpoint')
    if bm is None or tx is None or oc is None:
        continue
    ocf = _f(oc)
    if ocf is None:
        s = str(oc).strip().lower()
        ocf = 1.0 if s in ('1','yes','true','responder','response','remission') else (0.0 if s in ('0','no','false','nonresponder','non-responder') else None)
    if ocf is None:
        continue
    data.append({'bm': 1 if is_pos_biomarker(bm) else 0,
                 'tx': 1 if is_experimental(tx) else 0,
                 'y': ocf})

if len(data) < 8:
    fail('too few usable rows (%d) for an interaction test' % len(data))

# outcome type
uniq = set(round(d['y'],6) for d in data)
if otype == 'auto':
    otype = 'binary' if uniq <= {0.0, 1.0} else 'continuous'

# ---- per-cell summaries (2x2: biomarker x treatment) ----
def cell(bm, tx):
    ys = [d['y'] for d in data if d['bm']==bm and d['tx']==tx]
    n = len(ys)
    mean = sum(ys)/n if n else float('nan')
    return ys, n, mean

cells = {}
for bm in (0,1):
    for tx in (0,1):
        ys, n, mean = cell(bm, tx)
        cells[(bm,tx)] = {'ys':ys,'n':n,'mean':mean}
for k in cells:
    if cells[k]['n'] == 0:
        fail('empty cell %s — need patients in every biomarker x treatment combination' % str(k))

# treatment effect per stratum (experimental - control), oriented so + = benefit
def orient(x):
    return x if hib else -x

eff = {}
for bm in (0,1):
    diff = cells[(bm,1)]['mean'] - cells[(bm,0)]['mean']
    eff[bm] = orient(diff)

interaction = eff[1] - eff[0]   # difference in treatment benefit, biomarker+ minus biomarker-

# ---- SE of the interaction ----
if otype == 'binary':
    # risk-difference scale; var(rate)=p(1-p)/n; interaction var = sum over 4 cells
    var = 0.0
    for k in cells:
        p = cells[k]['mean']; n = cells[k]['n']
        var += (p*(1-p))/n if n else 0.0
    se = math.sqrt(var) if var>0 else float('nan')
else:
    # continuous; var(mean)=s^2/n per cell; interaction var = sum
    var = 0.0
    for k in cells:
        ys = cells[k]['ys']; n = len(ys)
        if n >= 2:
            m = cells[k]['mean']
            s2 = sum((y-m)**2 for y in ys)/(n-1)
            var += s2/n
    se = math.sqrt(var) if var>0 else float('nan')

z = interaction/se if (se and se>0) else 0.0
p_int = two_sided_p(z)
ci_lo = interaction - z_crit*se
ci_hi = interaction + z_crit*se

# main treatment effect (pooled), for prognostic-vs-predictive contrast
pooled_exp = [d['y'] for d in data if d['tx']==1]
pooled_ctl = [d['y'] for d in data if d['tx']==0]
main_eff = orient(sum(pooled_exp)/len(pooled_exp) - sum(pooled_ctl)/len(pooled_ctl))

# ---- % of decisions changed (the biomarker's INCREMENTAL value) ----
# Compare a biomarker-GUIDED policy against the MARKER-BLIND policy (give everyone
# the arm that is better on average). A stratum/average "prefers experimental" only
# if its benefit is MEANINGFUL (>= min_interaction) — a tiny positive effect should
# not commit a patient to a costlier/riskier arm. Decisions changed = patients whose
# guided arm differs from the marker-blind arm. This isolates what the biomarker adds.
blind_exp = main_eff >= min_int
changed = 0
policy = {}
for bm in (0,1):
    guided_exp = eff[bm] >= min_int
    policy[bm] = 'experimental' if guided_exp else 'control'
    if guided_exp != blind_exp:
        changed += sum(1 for d in data if d['bm']==bm)
pct_changed = round(100.0*changed/len(data), 1)

# ---- gate-3 verdict ----
significant = p_int < alpha
meaningful  = abs(interaction) >= min_int
if significant and meaningful:
    verdict = 'GATE 3 — PREDICTIVE'
    verdict_note = ('The biomarker changes which treatment is better (significant, '
                    'meaningful interaction). This is the form with commercial value.')
elif abs(main_eff) >= min_int and not (significant and meaningful):
    verdict = 'PROGNOSTIC / MAIN-EFFECT ONLY — not predictive'
    verdict_note = ('A treatment effect exists but does not differ by biomarker status: '
                    'the biomarker does not change the decision. Commercially worthless as '
                    'a predictive marker (the PROFILE failure mode).')
else:
    verdict = 'NO SIGNAL'
    verdict_note = 'Neither a predictive interaction nor a clear main effect at this sample size.'

result = {
    'status': 'completed',
    'analysis': analysis,
    'n_patients': len(data),
    'outcome_type': otype,
    'strata_effects': {
        'biomarker_negative': round(eff[0], 4),
        'biomarker_positive': round(eff[1], 4),
    },
    'interaction': {
        'estimate': round(interaction, 4),
        'se': round(se, 4) if se==se else None,
        'ci95': [round(ci_lo,4), round(ci_hi,4)],
        'z': round(z, 4), 'p_value': round(p_int, 6),
        'scale': 'risk difference' if otype=='binary' else 'mean difference',
    },
    'main_treatment_effect': round(main_eff, 4),
    'decisions_changed_pct': pct_changed,
    'biomarker_guided_policy': policy,
    'marker_blind_choice': 'experimental' if blind_exp else 'control',
    'gate3_verdict': verdict,
    'verdict_note': verdict_note,
    'thresholds': {'alpha': alpha, 'min_interaction': min_int, 'higher_is_better': hib},
}
with open('gate3_results.json','w') as f:
    json.dump(result, f, indent=2)

with open('subgroup_effects.csv','w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['stratum','arm','n','mean_outcome'])
    for bm in (0,1):
        for tx in (0,1):
            w.writerow(['biomarker+' if bm else 'biomarker-',
                        'experimental' if tx else 'control',
                        cells[(bm,tx)]['n'], round(cells[(bm,tx)]['mean'],4)])

def fmt(x): return '—' if x is None else (f'{x:.3f}' if isinstance(x,float) else str(x))
L = []
L.append(f'# Gate-3 Interaction Test — {analysis}')
L.append('')
L.append(f'**Patients:** {len(data)}  |  **Outcome:** {otype}  |  **Verdict:** **{verdict}**')
L.append('')
L.append('> Gate 3 asks the only question with commercial value: does the biomarker change '
         '*which treatment is better* (predictive), or merely identify who does badly '
         '(prognostic)? A predictive claim requires a biomarker × treatment **interaction**, '
         'not a main effect.')
L.append('')
L.append('## Treatment effect by biomarker stratum')
L.append('')
L.append('| Stratum | Treatment benefit (experimental − control) |')
L.append('|---|---:|')
L.append(f'| Biomarker− | {fmt(eff[0])} |')
L.append(f'| Biomarker+ | {fmt(eff[1])} |')
L.append('')
L.append('## The interaction (the gate-3 test)')
L.append('')
L.append(f'- **Interaction estimate:** {fmt(interaction)} '
         f'({"risk difference" if otype=="binary" else "mean difference"})')
L.append(f'- **95% CI:** [{fmt(ci_lo)}, {fmt(ci_hi)}]  |  **p = {p_int:.4f}**')
L.append(f'- **Main treatment effect (pooled):** {fmt(main_eff)} '
         f'(for the prognostic-vs-predictive contrast)')
L.append('')
L.append('## Decisions changed')
L.append('')
L.append(f'Acting on the biomarker changes the treatment decision for **{pct_changed}%** of '
         f'patients versus the marker-blind choice (give everyone the on-average-better arm = '
         f'{result["marker_blind_choice"]}). This isolates the biomarker\\'s incremental value '
         '— 100% of the tested population is never the right denominator.')
L.append('')
L.append(f'## Verdict — {verdict}')
L.append('')
L.append(verdict_note)
L.append('')
L.append('_Interaction testing per FDA–NIH BEST / REMARK / STARD. A predictive claim '
         'supported only by a main effect is not a predictive claim._')
with open('interaction_report.md','w') as f:
    f.write('\\n'.join(L) + '\\n')

print('=== GATE-3: %s | n=%d | interaction=%.3f (p=%.4f) | decisions changed=%.1f%% | %s ===' % (
    analysis, len(data), interaction, p_int, pct_changed, verdict))

with open('versions.yml','w') as f:
    f.write('gate3_interaction_test:\\n  python: "3.10"\\n  basis: "biomarker x treatment interaction (FDA-NIH BEST)"\\n')
PYEOF
    """
}

workflow GATE3_INTERACTION_WORKFLOW {
    take: meta_ch
    main: GATE3_INTERACTION_TEST(meta_ch)
    emit:
        results = GATE3_INTERACTION_TEST.out.results
        report  = GATE3_INTERACTION_TEST.out.report
}

workflow {
    meta = [id: 'gate3_run', single_end: false]
    Channel.value(meta) | GATE3_INTERACTION_WORKFLOW
}
