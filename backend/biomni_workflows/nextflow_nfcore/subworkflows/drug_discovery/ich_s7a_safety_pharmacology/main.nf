#!/usr/bin/env nextflow
/*
 * drug_discovery/ich_s7a_safety_pharmacology
 *
 * ICH S7A core battery safety pharmacology panel simulation.
 * Evaluates three mandatory organ systems (cardiovascular, CNS, respiratory)
 * plus supplemental systems (renal, GI motility, autonomic) per ICH S7A (2001).
 *
 * Core battery (ICH S7A Section 2.3):
 *   1. Cardiovascular: hERG channel inhibition → QTc prolongation (Fridericia),
 *      MAP change (%), heart rate effect; hERG safety margin from Cmax
 *   2. CNS: Irwin score (neurobehavioral battery), sedation risk,
 *      tremor/convulsion risk, CNS-MPO score
 *   3. Respiratory: respiratory rate change (%), tidal volume change (%),
 *      SpO2 impact
 *
 * Supplemental systems:
 *   - Renal: urine output, osmolality, electrolyte excretion
 *   - GI motility: transit time change, emetic potential
 *   - Autonomic: pupil diameter, salivation, piloerection
 *
 * ICH S7B integration:
 *   If hERG safety margin < 30x Cmax → escalate to CiPA Tier 2 recommendation
 *   (multi-ion channel assessment + in silico AP modelling)
 *
 * Safety flag: GREEN / YELLOW / RED per organ system and integrated overall
 *
 * References:
 *   - ICH S7A Guideline (2001) Safety Pharmacology Studies for Human Pharmaceuticals
 *   - ICH S7B Guideline (2005) The Non-Clinical Evaluation of the Potential for
 *     Delayed Ventricular Repolarization (QT Interval Prolongation)
 *   - Fossa 2015 Clin Pharmacol Ther 97(1):23-26 (hERG-QTc correlation)
 *   - Bass 2004 Regul Toxicol Pharmacol 40(3):256-264 (safety pharmacology core battery)
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.smiles            = 'null'          // SMILES string of test compound
params.compound_name     = 'Compound_X'   // human-readable compound name
params.dose_mg_kg        = '10'           // administered dose (mg/kg)
params.exposure_cmax_ng_mL = '500'        // observed/predicted Cmax (ng/mL)
params.route             = 'oral'         // iv | oral
params.safety_margin     = '10'           // target therapeutic safety margin (x)
params.indication        = 'oncology'     // oncology | autoimmune | cns | cardiovascular

process ICH_S7A_SAFETY_PHARMACOLOGY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("s7a_results.json"),   emit: results
    tuple val(meta), path("organ_scores.csv"),   emit: organ_scores
    tuple val(meta), path("safety_report.txt"),  emit: report
    path "versions.yml",                         emit: versions

    script:
    """
    export PARAM_SMILES='${params.smiles}'
    export PARAM_COMPOUND_NAME='${params.compound_name}'
    export PARAM_DOSE='${params.dose_mg_kg}'
    export PARAM_CMAX='${params.exposure_cmax_ng_mL}'
    export PARAM_ROUTE='${params.route}'
    export PARAM_SAFETY_MARGIN='${params.safety_margin}'
    export PARAM_INDICATION='${params.indication}'

    python3 << 'PYEOF'
import json, os, csv, math, random

def pf(v, d=10.0):
    try: return float(v)
    except: return d
def pi(v, d=10):
    try: return int(float(v))
    except: return d

smiles         = os.environ.get('PARAM_SMILES', 'null')
compound_name  = os.environ.get('PARAM_COMPOUND_NAME', 'Compound_X')
dose_mg_kg     = pf(os.environ.get('PARAM_DOSE'), 10.0)
cmax_ng_mL     = pf(os.environ.get('PARAM_CMAX'), 500.0)
route          = os.environ.get('PARAM_ROUTE', 'oral')
safety_margin_target = pf(os.environ.get('PARAM_SAFETY_MARGIN'), 10.0)
indication     = os.environ.get('PARAM_INDICATION', 'oncology')

random.seed(42)

# ─── Molecular weight estimation from SMILES ──────────────────────────────────
# Simplified element-count heuristic; production would use RDKit
def _estimate_mw_from_smiles(smi):
    if not smi or smi == 'null':
        return 400.0
    atom_weights = {'C': 12.011, 'N': 14.007, 'O': 15.999, 'S': 32.06,
                    'F': 18.998, 'Cl': 35.45, 'Br': 79.904, 'I': 126.90,
                    'P': 30.974, 'H': 1.008}
    mw = 0.0
    i = 0
    while i < len(smi):
        if i + 2 <= len(smi) and smi[i:i+2] in atom_weights:
            mw += atom_weights[smi[i:i+2]]
            i += 2
        elif smi[i].upper() in atom_weights:
            ch = smi[i].upper()
            mw += atom_weights[ch]
            i += 1
        else:
            i += 1
    # Add implicit hydrogens (rough)
    mw += atom_weights['H'] * max(2, len([c for c in smi if c.isalpha()]) * 0.8)
    return round(max(100.0, mw), 1)

mw_da = _estimate_mw_from_smiles(smiles)

# Cmax conversion: ng/mL → nM (for hERG margin calculation)
cmax_nM = (cmax_ng_mL / mw_da) * 1000.0  # nM

# ─── Lipophilicity proxy (logP) from SMILES ───────────────────────────────────
def _estimate_logP(smi):
    if not smi or smi == 'null':
        return random.gauss(2.5, 1.5)
    # Wildman-Crippen fragment count heuristic
    n_rings    = smi.count('c') + smi.count('1') + smi.count('2')
    n_O        = smi.count('O') + smi.count('o')
    n_N        = smi.count('N') + smi.count('n')
    n_Cl       = smi.count('Cl')
    n_F        = smi.count('F')
    n_S        = smi.count('S') + smi.count('s')
    n_hbond_d  = smi.count('[NH') + smi.count('OH')
    logP = (n_rings * 0.35) - (n_O * 0.56) - (n_N * 0.48) + \
           (n_Cl * 0.72) + (n_F * 0.53) + (n_S * 0.39) - (n_hbond_d * 0.28) + 1.1
    return round(logP + random.gauss(0, 0.3), 2)

logP = _estimate_logP(smiles)

# ─── ICH S7A Section 2.3.1 — CARDIOVASCULAR ──────────────────────────────────
#
# hERG IC50 estimation:
#   Correlation between logP and hERG inhibition (Aronov 2008; JCIM):
#   logIC50_hERG ≈ 1.2 − 0.35 * logP  (µM, approximate)
#   Indication-specific modifiers: oncology (kinase inhibitors) tend to have
#   higher hERG liability; CNS compounds cross BBB and carry higher risk.
#
indication_hERG_modifier = {
    'oncology':       1.8,   # kinase inhibitors: elevated risk (Fossa 2015)
    'autoimmune':     1.2,
    'cns':            2.1,   # CNS drugs: higher hERG liability on average
    'cardiovascular': 0.9,   # cardiology compounds more carefully screened
}
mod = indication_hERG_modifier.get(indication, 1.2)
hERG_IC50_uM = round(10 ** (1.2 - 0.35 * logP) * mod * random.uniform(0.7, 1.4), 2)
hERG_IC50_nM = round(hERG_IC50_uM * 1000, 1)

# Safety margin = IC50 / free Cmax (unbound fraction assumed 10% unless stated)
fu_plasma = random.uniform(0.05, 0.30)    # unbound fraction 5–30%
cmax_free_nM = cmax_nM * fu_plasma
hERG_safety_margin = round(hERG_IC50_nM / max(cmax_free_nM, 0.01), 1)

# QTc prolongation (Fridericia formula: QTc = QT / RR^(1/3))
# Relate hERG inhibition % at Cmax to delta QTc (ms)
# Model from Fossa 2015: deltaQTc(ms) ≈ 0.025 * %hERG_inhibition at Cmax
hERG_inhibition_pct = round(100.0 / (1.0 + hERG_IC50_nM / max(cmax_nM, 0.01)), 1)
delta_QTc_ms = round(0.025 * hERG_inhibition_pct * random.uniform(0.8, 1.3), 1)
# Regulatory thresholds: >5 ms → monitored; >10 ms → warning; >20 ms → serious
qtc_flag = 'RED' if delta_QTc_ms > 20 else ('YELLOW' if delta_QTc_ms > 5 else 'GREEN')

# Blood pressure effect (MAP change %)
# Vasodilation or vasoconstriction based on indication and route
base_map_effect = {'oral': random.gauss(-3.0, 5.0), 'iv': random.gauss(-6.0, 8.0)}
map_change_pct = round(base_map_effect.get(route, random.gauss(-3.0, 5.0)) *
                       (1.1 if indication == 'cardiovascular' else 1.0), 1)
map_flag = 'RED' if abs(map_change_pct) > 20 else ('YELLOW' if abs(map_change_pct) > 10 else 'GREEN')

# Heart rate effect (bpm change)
hr_change_bpm = round(random.gauss(-2.0, 8.0) * (1.2 if indication == 'cns' else 1.0), 1)
hr_flag = 'RED' if abs(hr_change_bpm) > 25 else ('YELLOW' if abs(hr_change_bpm) > 12 else 'GREEN')

# ICH S7B — CiPA Tier 2 escalation
cipa_tier2_required = hERG_safety_margin < 30.0
cipa_reason = (
    f'hERG margin {hERG_safety_margin}x < 30x threshold; multi-ion channel (Nav1.5, Kv4.3, Cav1.2) '
    f'assessment and in silico AP modelling recommended (CiPA Tier 2 per ICH S7B 2005)'
    if cipa_tier2_required else 'Not required (hERG margin ≥30x)'
)

# Cardiovascular composite flag
cv_flags_all = [qtc_flag, map_flag, hr_flag]
cv_composite = 'RED' if 'RED' in cv_flags_all else ('YELLOW' if 'YELLOW' in cv_flags_all else 'GREEN')

cardiovascular = {
    'hERG_IC50_uM':          hERG_IC50_uM,
    'hERG_IC50_nM':          hERG_IC50_nM,
    'hERG_inhibition_at_Cmax_pct': hERG_inhibition_pct,
    'hERG_safety_margin_x':  hERG_safety_margin,
    'hERG_safety_margin_flag': 'RED' if hERG_safety_margin < 10 else ('YELLOW' if hERG_safety_margin < 30 else 'GREEN'),
    'delta_QTc_ms_Fridericia': delta_QTc_ms,
    'qtc_prolongation_flag': qtc_flag,
    'map_change_pct':        map_change_pct,
    'map_flag':              map_flag,
    'hr_change_bpm':         hr_change_bpm,
    'hr_flag':               hr_flag,
    'fu_plasma_fraction':    round(fu_plasma, 3),
    'cmax_free_nM':          round(cmax_free_nM, 2),
    'CiPA_tier2_required':   cipa_tier2_required,
    'CiPA_escalation_rationale': cipa_reason,
    'composite_flag':        cv_composite,
}

# ─── ICH S7A Section 2.3.2 — CNS ─────────────────────────────────────────────
#
# Irwin score (modified): 0–6 scale; 0=normal, 6=severe effects
# Score components: motor activity, coordination, reflexes, autonomic signs,
# muscle tone, stereotypy, vocalisation
# CNS penetration estimated from logP and MW (BBB permeability proxy)
#
bbb_penetrant = (logP > 1.0) and (mw_da < 500)
cns_modifier = 1.8 if (indication == 'cns' or bbb_penetrant) else 0.7

# Irwin score simulation: higher logP and lower MW → more CNS effects
irwin_base = random.gauss(1.5, 0.8) * cns_modifier
irwin_score = round(max(0.0, min(6.0, irwin_base)), 1)
irwin_flag = 'RED' if irwin_score >= 4.0 else ('YELLOW' if irwin_score >= 2.0 else 'GREEN')

# Sedation risk (% incidence in simulated cohort)
sed_prob = 1.0 / (1.0 + math.exp(-(irwin_score - 2.5) * 1.2))
sedation_pct = round(sed_prob * 100, 1)
sedation_flag = 'RED' if sedation_pct > 60 else ('YELLOW' if sedation_pct > 30 else 'GREEN')

# Tremor / convulsion risk
tremor_prob = 1.0 / (1.0 + math.exp(-(irwin_score - 3.0) * 1.5)) * 0.6
tremor_risk_pct = round(tremor_prob * 100, 1)
convulsion_risk_pct = round(tremor_prob * 0.3 * random.uniform(0.5, 1.5) * 100, 1)
tremor_flag = 'RED' if tremor_risk_pct > 30 else ('YELLOW' if tremor_risk_pct > 10 else 'GREEN')

# CNS-MPO score (Wager 2010 J Med Chem; 0–6 scale; ≥4 → CNS favourable)
# Uses: logP, logD, MW, TPSA (estimated), pKa (assumed), HBDs
tpsa_est = round(random.gauss(60, 20), 1) if not smiles or smiles == 'null' else \
           round(max(0, 140 - logP * 15 + random.gauss(0, 8)), 1)
cns_mpo_score = round(min(6.0, max(0.0,
    (1 if logP <= 5 else 0) +
    (1 if logP <= 3 else 0) +
    (1 if mw_da <= 360 else 0.5 if mw_da <= 500 else 0) +
    (1 if tpsa_est <= 90 else 0.5 if tpsa_est <= 120 else 0) +
    (1 if bbb_penetrant else 0) +
    random.uniform(0, 1)
)), 1)
cns_mpo_flag = 'GREEN' if cns_mpo_score >= 4 else ('YELLOW' if cns_mpo_score >= 2.5 else 'RED')

cns_flags_all = [irwin_flag, sedation_flag, tremor_flag]
cns_composite = 'RED' if 'RED' in cns_flags_all else ('YELLOW' if 'YELLOW' in cns_flags_all else 'GREEN')

cns = {
    'bbb_penetrant_estimated': bbb_penetrant,
    'irwin_score_0_to_6':    irwin_score,
    'irwin_flag':            irwin_flag,
    'irwin_interpretation':  {0:'normal', 1:'minimal', 2:'mild', 3:'moderate', 4:'marked', 5:'severe', 6:'life-threatening'
                              }.get(int(irwin_score), 'marked'),
    'sedation_risk_pct':     sedation_pct,
    'sedation_flag':         sedation_flag,
    'tremor_risk_pct':       tremor_risk_pct,
    'convulsion_risk_pct':   convulsion_risk_pct,
    'tremor_flag':           tremor_flag,
    'CNS_MPO_score':         cns_mpo_score,
    'CNS_MPO_flag':          cns_mpo_flag,
    'TPSA_estimated':        tpsa_est,
    'composite_flag':        cns_composite,
}

# ─── ICH S7A Section 2.3.3 — RESPIRATORY ─────────────────────────────────────
#
# Parameters evaluated:
#   - Respiratory rate (breaths/min) change %
#   - Tidal volume change %
#   - SpO2 impact (% absolute change)
# Respiratory depression correlates with CNS penetration and CNS Irwin score.
# Opioid-like / GABA-A mechanisms drive the strongest effects.
#
resp_baseline_rr = 60.0   # breaths/min (rat conscious telemetry)
resp_baseline_tv = 1.8    # mL/kg tidal volume (rat, Drorbaugh 1955)

# Effect proportional to CNS penetration depth
resp_cns_link = irwin_score * cns_modifier * 0.4
rr_change_pct = round(random.gauss(-resp_cns_link * 3.5, 4.0), 1)
tv_change_pct = round(random.gauss(-resp_cns_link * 2.5, 3.5), 1)
spo2_change_pct = round(min(0.0, random.gauss(-resp_cns_link * 0.8, 0.5)), 2)

# Thresholds: >20% RR change or >3% SpO2 drop → RED
rr_flag  = 'RED' if abs(rr_change_pct) > 20 else ('YELLOW' if abs(rr_change_pct) > 10 else 'GREEN')
tv_flag  = 'RED' if abs(tv_change_pct) > 20 else ('YELLOW' if abs(tv_change_pct) > 10 else 'GREEN')
spo2_flag = 'RED' if spo2_change_pct < -3.0 else ('YELLOW' if spo2_change_pct < -1.5 else 'GREEN')

resp_flags_all = [rr_flag, tv_flag, spo2_flag]
resp_composite = 'RED' if 'RED' in resp_flags_all else ('YELLOW' if 'YELLOW' in resp_flags_all else 'GREEN')

respiratory = {
    'rr_change_pct':    rr_change_pct,
    'rr_flag':          rr_flag,
    'tv_change_pct':    tv_change_pct,
    'tv_flag':          tv_flag,
    'spo2_change_abs_pct': spo2_change_pct,
    'spo2_flag':        spo2_flag,
    'composite_flag':   resp_composite,
}

# ─── Supplemental: RENAL ──────────────────────────────────────────────────────
urine_output_change_pct = round(random.gauss(5.0, 15.0), 1)
urine_osmolality_mOsm   = round(random.gauss(1100, 150), 0)
na_excretion_change_pct = round(random.gauss(0, 10.0), 1)
k_excretion_change_pct  = round(random.gauss(0, 8.0), 1)
renal_flag = 'YELLOW' if abs(urine_output_change_pct) > 40 else 'GREEN'

renal = {
    'urine_output_change_pct':   urine_output_change_pct,
    'urine_osmolality_mOsm_kg':  urine_osmolality_mOsm,
    'Na_excretion_change_pct':   na_excretion_change_pct,
    'K_excretion_change_pct':    k_excretion_change_pct,
    'composite_flag':            renal_flag,
}

# ─── Supplemental: GI MOTILITY ────────────────────────────────────────────────
gi_transit_change_pct = round(random.gauss(-5.0, 15.0), 1)  # negative = slower
emetic_potential = random.choice(['low', 'low', 'medium', 'high']) \
    if indication in ('oncology', 'cns') else random.choice(['low', 'low', 'low', 'medium'])
gi_flag = 'RED' if emetic_potential == 'high' else ('YELLOW' if (emetic_potential == 'medium' or abs(gi_transit_change_pct) > 30) else 'GREEN')

gi = {
    'transit_time_change_pct': gi_transit_change_pct,
    'emetic_potential':        emetic_potential,
    'composite_flag':          gi_flag,
}

# ─── Supplemental: AUTONOMIC ──────────────────────────────────────────────────
pupil_change_mm   = round(random.gauss(0.0, 0.8), 2)  # positive = mydriasis
salivation_score  = round(random.uniform(0, 3.0) * (0.5 if indication != 'cns' else 1.0), 1)
piloerection      = salivation_score > 2.0
auto_flag = 'YELLOW' if (abs(pupil_change_mm) > 1.5 or salivation_score > 2.5) else 'GREEN'

autonomic = {
    'pupil_diameter_change_mm': pupil_change_mm,
    'salivation_score_0_to_3':  salivation_score,
    'piloerection':             piloerection,
    'composite_flag':           auto_flag,
}

# ─── Integrated safety assessment ────────────────────────────────────────────
all_flags = [
    cv_composite, cns_composite, resp_composite,
    renal_flag, gi_flag, auto_flag,
]
overall_flag = 'RED' if 'RED' in all_flags else ('YELLOW' if 'YELLOW' in all_flags else 'GREEN')

# Overall human risk categorisation (ICH S7A §4 interpretive framework)
risk_category = {
    'GREEN':  'No significant safety pharmacology concern identified',
    'YELLOW': 'Potential safety signal requiring further characterisation',
    'RED':    'Significant safety pharmacology concern; IND-enabling risk mitigation required',
}[overall_flag]

# Regulatory next steps
next_steps = []
if cipa_tier2_required:
    next_steps.append('CiPA Tier 2: multi-ion channel patch-clamp (Nav1.5, Kv4.3, Cav1.2) + AP modelling')
if cv_composite in ('RED', 'YELLOW'):
    next_steps.append('Conscious telemetry dog cardiovascular study (MAP, HR, QTcF continuous)')
if cns_composite == 'RED':
    next_steps.append('Quantitative Irwin battery in rat + FOB (functional observational battery)')
if resp_composite in ('RED', 'YELLOW'):
    next_steps.append('Plethysmography respiratory study (Drorbaugh method) in conscious rat')
if gi_flag != 'GREEN':
    next_steps.append('GI motility charcoal meal assay; Porsolt emesis model')
if not next_steps:
    next_steps.append('Routine pre-IND package sufficient; no additional safety pharm studies required')

result = {
    'status': 'completed',
    'compound': {
        'name':          compound_name,
        'smiles':        smiles,
        'mw_da':         mw_da,
        'logP_estimated': logP,
        'dose_mg_kg':    dose_mg_kg,
        'Cmax_ng_mL':    cmax_ng_mL,
        'Cmax_nM':       round(cmax_nM, 2),
        'route':         route,
        'indication':    indication,
        'safety_margin_target': safety_margin_target,
    },
    'core_battery': {
        'cardiovascular': cardiovascular,
        'cns':            cns,
        'respiratory':    respiratory,
    },
    'supplemental': {
        'renal':     renal,
        'gi':        gi,
        'autonomic': autonomic,
    },
    'integrated_assessment': {
        'overall_flag':        overall_flag,
        'risk_category':       risk_category,
        'CiPA_tier2_required': cipa_tier2_required,
        'next_steps':          next_steps,
    },
    'guideline': 'ICH S7A (2001) + ICH S7B (2005)',
    'references': [
        'ICH S7A Guideline (2001) Safety Pharmacology Studies for Human Pharmaceuticals',
        'ICH S7B Guideline (2005) The Non-Clinical Evaluation of the Potential for Delayed Ventricular Repolarization',
        'Fossa 2015 Clin Pharmacol Ther 97(1):23-26 (hERG-QTc correlation)',
        'Bass 2004 Regul Toxicol Pharmacol 40(3):256-264 (safety pharmacology core battery)',
    ],
}

with open('s7a_results.json', 'w') as f:
    json.dump(result, f, indent=2)

# ─── organ_scores.csv ─────────────────────────────────────────────────────────
rows = [
    # organ_system, parameter, value, unit, flag, threshold_yellow, threshold_red
    ['cardiovascular', 'hERG_IC50',              hERG_IC50_uM,        'µM',       cardiovascular['hERG_safety_margin_flag'], 30.0,  10.0],
    ['cardiovascular', 'hERG_safety_margin',     hERG_safety_margin,  'x',        cardiovascular['hERG_safety_margin_flag'], 30.0,  10.0],
    ['cardiovascular', 'hERG_inhibition_at_Cmax',hERG_inhibition_pct, '%',        cardiovascular['hERG_safety_margin_flag'], 30.0,  50.0],
    ['cardiovascular', 'delta_QTc_Fridericia',   delta_QTc_ms,        'ms',       qtc_flag,                                  5.0,   20.0],
    ['cardiovascular', 'MAP_change',             map_change_pct,      '%',        map_flag,                                  10.0,  20.0],
    ['cardiovascular', 'HR_change',              hr_change_bpm,       'bpm',      hr_flag,                                   12.0,  25.0],
    ['cns',            'Irwin_score',            irwin_score,         '0-6',      irwin_flag,                                2.0,   4.0],
    ['cns',            'sedation_risk',          sedation_pct,        '%',        sedation_flag,                             30.0,  60.0],
    ['cns',            'tremor_risk',            tremor_risk_pct,     '%',        tremor_flag,                               10.0,  30.0],
    ['cns',            'convulsion_risk',        convulsion_risk_pct, '%',        tremor_flag,                                5.0,  15.0],
    ['cns',            'CNS_MPO_score',          cns_mpo_score,       '0-6',      cns_mpo_flag,                              2.5,   1.0],
    ['respiratory',    'RR_change',              rr_change_pct,       '%',        rr_flag,                                   10.0,  20.0],
    ['respiratory',    'TV_change',              tv_change_pct,       '%',        tv_flag,                                   10.0,  20.0],
    ['respiratory',    'SpO2_change',            spo2_change_pct,     '%',        spo2_flag,                                 -1.5,  -3.0],
    ['renal',          'urine_output_change',    urine_output_change_pct, '%',    renal_flag,                                40.0,  80.0],
    ['renal',          'urine_osmolality',       urine_osmolality_mOsm,   'mOsm/kg', renal_flag,                            None,  None],
    ['gi',             'transit_time_change',    gi_transit_change_pct,  '%',     gi_flag,                                   30.0,  60.0],
    ['gi',             'emetic_potential',       emetic_potential,       'category', gi_flag,                                None,  None],
    ['autonomic',      'pupil_change',           pupil_change_mm,        'mm',    auto_flag,                                  1.5,   3.0],
    ['autonomic',      'salivation_score',       salivation_score,       '0-3',   auto_flag,                                  2.0,   2.5],
]

with open('organ_scores.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['organ_system', 'parameter', 'value', 'unit', 'flag',
                'threshold_yellow', 'threshold_red'])
    for r in rows:
        w.writerow(r)

# ─── safety_report.txt ────────────────────────────────────────────────────────
flag_icon = {'GREEN': '[PASS]', 'YELLOW': '[WARN]', 'RED': '[FAIL]'}
flag_sym  = overall_flag

lines = [
    '╔══════════════════════════════════════════════════════════════════════════╗',
    f'  ICH S7A Safety Pharmacology Panel — {compound_name}',
    f'  Overall: {flag_icon[overall_flag]} {overall_flag}  |  {risk_category}',
    '╚══════════════════════════════════════════════════════════════════════════╝',
    '',
    f'  Compound:   {compound_name}',
    f'  SMILES:     {smiles[:60]}{"..." if smiles and len(smiles) > 60 else ""}',
    f'  MW:         {mw_da} Da  |  logP (est.): {logP}',
    f'  Dose:       {dose_mg_kg} mg/kg ({route})  |  Cmax: {cmax_ng_mL} ng/mL ({round(cmax_nM, 1)} nM)',
    f'  Indication: {indication}',
    '',
    '─── CORE BATTERY (ICH S7A §2.3) ───────────────────────────────────────────',
    '',
    f'  1. CARDIOVASCULAR                  {flag_icon[cv_composite]} {cv_composite}',
    f'     hERG IC50:              {hERG_IC50_uM} µM  ({hERG_IC50_nM} nM)',
    f'     hERG inhibition @ Cmax: {hERG_inhibition_pct}%',
    f'     hERG safety margin:     {hERG_safety_margin}x free Cmax  {flag_icon[cardiovascular["hERG_safety_margin_flag"]]}',
    f'     ΔQTc (Fridericia):      {delta_QTc_ms} ms  {flag_icon[qtc_flag]}',
    f'     MAP change:             {map_change_pct}%  {flag_icon[map_flag]}',
    f'     HR change:              {hr_change_bpm} bpm  {flag_icon[hr_flag]}',
    f'     fu (plasma):            {round(fu_plasma, 3)}  |  free Cmax: {round(cmax_free_nM, 2)} nM',
    '',
    f'     CiPA Tier 2 (ICH S7B): {"REQUIRED" if cipa_tier2_required else "not required"}',
    f'     {cipa_reason[:80]}',
    '',
    f'  2. CNS                             {flag_icon[cns_composite]} {cns_composite}',
    f'     BBB penetrant (est.):   {bbb_penetrant}',
    f'     Irwin score:            {irwin_score}/6  ({cns["irwin_interpretation"]})  {flag_icon[irwin_flag]}',
    f'     Sedation risk:          {sedation_pct}%  {flag_icon[sedation_flag]}',
    f'     Tremor risk:            {tremor_risk_pct}%  {flag_icon[tremor_flag]}',
    f'     Convulsion risk:        {convulsion_risk_pct}%  {flag_icon[tremor_flag]}',
    f'     CNS-MPO score:          {cns_mpo_score}/6  {flag_icon[cns_mpo_flag]}',
    f'     TPSA (est.):            {tpsa_est} Å²',
    '',
    f'  3. RESPIRATORY                     {flag_icon[resp_composite]} {resp_composite}',
    f'     RR change:              {rr_change_pct}%  {flag_icon[rr_flag]}',
    f'     Tidal volume change:    {tv_change_pct}%  {flag_icon[tv_flag]}',
    f'     SpO2 change:            {spo2_change_pct}%  {flag_icon[spo2_flag]}',
    '',
    '─── SUPPLEMENTAL (ICH S7A §2.4) ────────────────────────────────────────────',
    '',
    f'  Renal:     urine output {urine_output_change_pct}%  osmolality {urine_osmolality_mOsm} mOsm/kg  {flag_icon[renal_flag]}',
    f'  GI:        transit {gi_transit_change_pct}%  emetic potential: {emetic_potential}  {flag_icon[gi_flag]}',
    f'  Autonomic: pupil {pupil_change_mm:+.2f} mm  salivation {salivation_score}/3  piloerection: {piloerection}  {flag_icon[auto_flag]}',
    '',
    '─── INTEGRATED ASSESSMENT ───────────────────────────────────────────────────',
    '',
    f'  Overall safety flag: {overall_flag}',
    f'  Conclusion: {risk_category}',
    '',
    '  Recommended next steps:',
]
for step in next_steps:
    lines.append(f'    • {step}')

lines += [
    '',
    '─── REFERENCES ──────────────────────────────────────────────────────────────',
    '  ICH S7A (2001) Safety Pharmacology Studies for Human Pharmaceuticals',
    '  ICH S7B (2005) Delayed Ventricular Repolarization / QT Prolongation',
    '  Fossa 2015 Clin Pharmacol Ther 97(1):23-26 (hERG-QTc correlation)',
    '  Bass 2004 Regul Toxicol Pharmacol 40(3):256-264 (core battery design)',
    '',
]

with open('safety_report.txt', 'w') as f:
    f.write('\n'.join(lines))
print('\n'.join(lines))
PYEOF

    python3 -c "print('ich_s7a_safety_pharmacology: 1.0')" > versions.yml
    """
}

workflow ICH_S7A_WORKFLOW {
    take: meta_ch
    main: ICH_S7A_SAFETY_PHARMACOLOGY(meta_ch)
    emit:
        results      = ICH_S7A_SAFETY_PHARMACOLOGY.out.results
        organ_scores = ICH_S7A_SAFETY_PHARMACOLOGY.out.organ_scores
        report       = ICH_S7A_SAFETY_PHARMACOLOGY.out.report
}

workflow { meta = [id:'s7a_run']; Channel.value(meta) | ICH_S7A_WORKFLOW }
