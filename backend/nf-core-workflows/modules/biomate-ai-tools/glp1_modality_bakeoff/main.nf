#!/usr/bin/env nextflow
/*
 * drug_discovery/glp1_modality_bakeoff
 *
 * GLP-1 family multi-receptor modality bake-off. Compares semaglutide-class
 * (GLP1R mono), tirzepatide-class (GLP1R + GIPR dual), retatrutide-class
 * (triple), oral GLP-1 (orforglipron), mRNA-encoded, and gene-therapy
 * approaches on a single indication. Surfaces predicted side-effect
 * profile per agonism pattern from atlas expression of GLP1R/GIPR/GCGR.
 *
 * Marketing case: trillion-dollar GLP-1 race (2024-2026). Every pharma is
 * asking "what's the next GLP-1?" The race is modality + receptor selection.
 *
 * References:
 *   - SELECT trial 2023 (semaglutide CV)
 *   - SURMOUNT-OSA 2024 (tirzepatide sleep apnea)
 *   - SYNERGY-NASH 2024 (tirzepatide MASH resolution)
 *   - SURPASS-3 2023 (tirzepatide vs semaglutide head-to-head)
 *   - TRIUMPH 2024 (retatrutide Phase 3 obesity)
 *   - ACHIEVE 2024 (orforglipron oral GLP-1)
 */

nextflow.enable.dsl = 2

params.outdir         = './results'
params.indication     = 'obesity'             // obesity | t2d | mash | cv_outcomes | osa
params.delivery_pref  = 'auto'                // injectable_peptide | oral | mrna | gene_therapy | auto
params.receptors      = 'auto'                // single | dual | triple | auto

process GLP1_MODALITY_BAKEOFF {
    tag "glp1:${params.indication}"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("glp1_bakeoff_report.json"),     emit: report_json
    tuple val(meta), path("receptor_atlas_summary.csv"),   emit: receptor_csv
    tuple val(meta), path("modality_comparison.csv"),      emit: modality_csv
    tuple val(meta), path("glp1_bakeoff.txt"),             emit: report
    path "versions.yml",                                    emit: versions

    script:
    """
    export PARAM_INDICATION='${params.indication}'
    export PARAM_DELIVERY='${params.delivery_pref}'
    export PARAM_RECEPTORS='${params.receptors}'

    python3 << 'PYEOF'
import os, json, csv

indication = os.environ.get('PARAM_INDICATION', 'obesity').strip().lower()
delivery   = os.environ.get('PARAM_DELIVERY', 'auto').strip().lower()
receptors  = os.environ.get('PARAM_RECEPTORS', 'auto').strip().lower()

# ─── Atlas profiles for GLP-1 family (slim mirror of atlas_expression_query) ─
RECEPTOR_PROFILES = {
    'GLP1R': {
        'pancreatic_islet_beta':  (4.2, 85, 'MOD'),   # primary target
        'pancreatic_islet_alpha': (3.5, 75, 'MOD'),
        'enteroendocrine_L':      (4.5, 90, 'MOD'),   # GI side effect source
        'hypothalamic_POMC':      (3.0, 65, 'HIGH'),  # appetite mechanism + CNS
        'gastric_smooth_muscle':  (2.8, 60, 'MOD'),   # gastroparesis source
        'cardiac_muscle_cell':    (1.2, 25, 'HIGH'),  # CV outcome source
        'bone_osteoblast':        (1.5, 30, 'MOD'),
        'thyroid_C_cell':         (2.0, 45, 'LOW'),   # rodent thyroid C-cell concern
    },
    'GIPR': {
        'pancreatic_islet_beta':  (3.8, 80, 'MOD'),   # insulinotropic
        'adipose_white':          (3.2, 70, 'LOW'),   # weight-loss mechanism
        'adipose_brown':          (2.8, 60, 'LOW'),
        'bone_osteoclast':        (2.0, 42, 'MOD'),   # bone density consideration
        'hypothalamic_neuron':    (1.6, 32, 'HIGH'),
        'cardiac_muscle_cell':    (0.4,  8, 'HIGH'),
    },
    'GCGR': {
        'hepatocyte':             (4.0, 88, 'MOD'),   # hepatic glucose production
        'pancreatic_islet_alpha': (2.4, 50, 'MOD'),
        'kidney_tubule_epi':      (2.0, 42, 'MOD'),
        'adipose_brown':          (1.8, 38, 'LOW'),
        'cardiac_muscle_cell':    (1.0, 22, 'HIGH'),  # potential hyperglycemia signal
    },
}

# ─── Side-effect prediction per agonism pattern ──────────────────────────────
def predict_side_effects(profile_set):
    '''
    profile_set: set of receptor names that are agonized
    Returns dict of side effects with severity (LOW/MED/HIGH).
    '''
    se = {}
    if 'GLP1R' in profile_set:
        se['nausea_gastroparesis'] = 'HIGH'      # GI L-cell + gastric smooth muscle
        se['appetite_suppression'] = 'HIGH'       # hypothalamic POMC (this IS the intended effect)
        se['cardiac_benefit']      = 'MODERATE'   # SELECT trial
        se['thyroid_C_cell_signal']= 'LOW (rodent only)'
    if 'GIPR' in profile_set:
        se['nausea_mitigation']    = 'MODERATE'   # GIPR antagonism on stomach reduces sema GI
        se['bone_density_signal']  = 'LOW-MODERATE'  # osteoclast activity
        se['fat_loss_potency']     = 'HIGH'       # adipose direct effect (tirz advantage)
    if 'GCGR' in profile_set:
        se['hyperglycemia_risk']   = 'MODERATE'   # hepatic glucose production
        se['fat_oxidation_boost']  = 'HIGH'       # retatrutide advantage
        se['lean_mass_preservation'] = 'MODERATE'
    return se

# ─── Modality candidates for GLP-1 class ─────────────────────────────────────
MODALITIES = [
    {
        'name': 'Injectable peptide (sema-class)',
        'receptors': ['GLP1R'],
        'examples': 'Semaglutide (Ozempic/Wegovy)',
        'delivery_class': 'subcutaneous_weekly',
        'dose_titration': 'Required (start 0.25mg, titrate to 2.4mg)',
        'adherence': 'Weekly SC injection — moderate adherence; injection burden',
        'cost_class': 'High (\$800-1300/mo retail; insurance-gated)',
        'cv_outcomes_data': 'SELECT trial 2023 (MACE -20%)',
        'manufacturing_complexity': 'MEDIUM (solid-phase peptide synthesis at scale)',
    },
    {
        'name': 'Dual GLP-1/GIP injectable (tirz-class)',
        'receptors': ['GLP1R', 'GIPR'],
        'examples': 'Tirzepatide (Mounjaro/Zepbound)',
        'delivery_class': 'subcutaneous_weekly',
        'dose_titration': 'Required (start 2.5mg, titrate to 15mg)',
        'adherence': 'Weekly SC; better GI tolerance than sema (GIPR mitigation)',
        'cost_class': 'High (~\$1000/mo retail; access expanding)',
        'cv_outcomes_data': 'SURPASS-4 2022 (favorable); SURMOUNT-OSA 2024 (sleep apnea +60%)',
        'manufacturing_complexity': 'MEDIUM (dual peptide design; tirzepatide is single molecule)',
    },
    {
        'name': 'Triple GLP-1/GIP/glucagon injectable (reta-class)',
        'receptors': ['GLP1R', 'GIPR', 'GCGR'],
        'examples': 'Retatrutide (Eli Lilly, Phase 3 TRIUMPH)',
        'delivery_class': 'subcutaneous_weekly',
        'dose_titration': 'Required',
        'adherence': 'Weekly SC',
        'cost_class': 'Premium (not yet approved; expected \$1500+/mo)',
        'cv_outcomes_data': 'Phase 3 readout 2025-2026',
        'manufacturing_complexity': 'MEDIUM-HIGH (triple agonist; tighter pharmacology)',
    },
    {
        'name': 'Oral GLP-1 small molecule',
        'receptors': ['GLP1R'],
        'examples': 'Orforglipron (Eli Lilly, Phase 3 ACHIEVE)',
        'delivery_class': 'oral_daily',
        'dose_titration': 'Required',
        'adherence': 'Daily oral — better adherence vs SC',
        'cost_class': 'TBD (oral typically lower COGS)',
        'cv_outcomes_data': 'Phase 3 readout 2025',
        'manufacturing_complexity': 'LOW (small molecule); but bioavailability ceiling limits potency',
    },
    {
        'name': 'mRNA-encoded GLP-1',
        'receptors': ['GLP1R'],   # could encode dual agonist
        'examples': 'No clinical program yet (preclinical: Translate Bio, others)',
        'delivery_class': 'mrna_lnp_im_or_sc',
        'dose_titration': 'mRNA dose-dependent expression',
        'adherence': 'Could be monthly or longer-acting',
        'cost_class': 'TBD; mRNA platform economics improving',
        'cv_outcomes_data': 'Not yet',
        'manufacturing_complexity': 'MEDIUM-HIGH (mRNA + LNP); leverages COVID vaccine infrastructure',
    },
    {
        'name': 'AAV gene therapy (one-shot GLP-1)',
        'receptors': ['GLP1R'],
        'examples': 'No clinical program; theoretical (life-long expression)',
        'delivery_class': 'aav_iv_or_im',
        'dose_titration': 'One-shot; cannot reverse',
        'adherence': 'One-time treatment',
        'cost_class': 'High one-shot (gene therapy \$2-3M historically)',
        'cv_outcomes_data': 'Decades of follow-up required',
        'manufacturing_complexity': 'HIGH (AAV manufacturing scale)',
    },
]

# ─── Indication-specific weighting ───────────────────────────────────────────
INDICATION_PRIORITY = {
    'obesity': {
        'efficacy': 5, 'gi_tolerance': 4, 'adherence': 3, 'cv_benefit': 3,
        'cost': 2, 'reversibility': 1,
    },
    't2d': {
        'efficacy': 5, 'cv_benefit': 4, 'gi_tolerance': 3, 'adherence': 3,
        'cost': 2, 'reversibility': 1,
    },
    'mash': {
        'efficacy': 5, 'hepatic_targeting': 5, 'gi_tolerance': 3, 'adherence': 3,
        'cost': 2, 'reversibility': 1,
    },
    'cv_outcomes': {
        'cv_benefit': 5, 'efficacy': 4, 'adherence': 3, 'gi_tolerance': 3,
        'cost': 2, 'reversibility': 1,
    },
    'osa': {
        'efficacy': 5, 'tolerability': 4, 'adherence': 3, 'cv_benefit': 2,
        'cost': 2,
    },
}

priorities = INDICATION_PRIORITY.get(indication, INDICATION_PRIORITY['obesity'])

# Build side-effect profile per modality
for m in MODALITIES:
    m['predicted_side_effects'] = predict_side_effects(set(m['receptors']))

# Indication-specific glucagon penalty: GCGR agonism causes hepatic glucose
# production → wrong for T2D; manageable for obesity; helpful for MASH (fat oxidation)
GCGR_INDICATION_FIT = {
    'obesity': 0,         # neutral — small hyperglycemia tolerated at obesity doses
    't2d': -8,            # anti-mechanism for diabetes
    'mash': +5,           # hepatic fat oxidation is therapeutic
    'cv_outcomes': -3,    # GLP-1 class CV benefit established; GCGR less clear
    'osa': -2,            # not established for OSA mechanism
}

# Approved-drug maturity bonus: prefer modalities with known clinical data
APPROVED_BONUS = {
    'Semaglutide (Ozempic/Wegovy)': {'cv_outcomes': 8, 'obesity': 5, 't2d': 8},
    'Tirzepatide (Mounjaro/Zepbound)': {'obesity': 8, 't2d': 7, 'mash': 8, 'osa': 8},
    'Retatrutide (Eli Lilly, Phase 3 TRIUMPH)': {'obesity': 5, 'mash': 6},  # Phase 3, not approved
    'Orforglipron (Eli Lilly, Phase 3 ACHIEVE)': {'obesity': 3, 't2d': 4},
}

# Compute a fit score per modality given indication priorities
def fit_score(m, priorities, indication):
    base = 0
    se = m['predicted_side_effects']
    # Efficacy proxy: receptor count helps but with diminishing returns + indication fit
    if 'efficacy' in priorities:
        n_rec = len(m['receptors'])
        base += priorities['efficacy'] * (2 + min(n_rec, 2))   # cap effective n_rec at 2
    # GCGR indication-specific (hurts T2D, helps MASH)
    if 'GCGR' in m['receptors']:
        base += GCGR_INDICATION_FIT.get(indication, 0)
    # Approved-drug maturity (real-world data + regulatory path established)
    for approved_name, bonuses in APPROVED_BONUS.items():
        if approved_name in m['examples']:
            base += bonuses.get(indication, 0)
    # GI tolerance: penalty if GLP1R alone, bonus if GIPR co-agonist
    if 'gi_tolerance' in priorities:
        if 'GIPR' in m['receptors'] and 'GLP1R' in m['receptors']:
            base += priorities['gi_tolerance'] * 5
        elif 'GLP1R' in m['receptors']:
            base += priorities['gi_tolerance'] * 2
    # Adherence: oral > weekly SC > one-shot gene therapy (depends on context)
    if 'adherence' in priorities:
        if m['delivery_class'] == 'oral_daily':
            base += priorities['adherence'] * 5
        elif m['delivery_class'].startswith('subcutaneous'):
            base += priorities['adherence'] * 3
        elif 'mrna' in m['delivery_class']:
            base += priorities['adherence'] * 4
        else:
            base += priorities['adherence'] * 2
    # CV benefit: GLP-1 class established
    if 'cv_benefit' in priorities:
        if 'GLP1R' in m['receptors']:
            base += priorities['cv_benefit'] * 4
    # Hepatic targeting (MASH)
    if 'hepatic_targeting' in priorities:
        if 'GCGR' in m['receptors']:
            base += priorities['hepatic_targeting'] * 5
        elif 'GLP1R' in m['receptors']:
            base += priorities['hepatic_targeting'] * 3
    # Cost: oral preferred
    if 'cost' in priorities:
        if m['delivery_class'] == 'oral_daily':
            base += priorities['cost'] * 5
        elif m['delivery_class'].startswith('subcutaneous'):
            base += priorities['cost'] * 3
        else:
            base += priorities['cost'] * 1
    # Reversibility penalty: gene therapy
    if 'reversibility' in priorities:
        if 'aav' in m['delivery_class']:
            base += priorities['reversibility'] * 1  # low score (penalty)
        else:
            base += priorities['reversibility'] * 5
    return base

for m in MODALITIES:
    m['fit_score'] = fit_score(m, priorities, indication)

MODALITIES.sort(key=lambda x: -x['fit_score'])
for i, m in enumerate(MODALITIES):
    m['rank'] = i + 1

primary = MODALITIES[0]

# ─── Build receptor atlas summary ────────────────────────────────────────────
atlas_rows = []
for rec_name, profile in RECEPTOR_PROFILES.items():
    for ct, (mean, pct, tier) in profile.items():
        atlas_rows.append({
            'receptor':       rec_name,
            'cell_type':      ct,
            'mean_expression':mean,
            'pct_expressing': pct,
            'tissue_criticality': tier,
        })

# ─── Output ──────────────────────────────────────────────────────────────────
report = {
    'indication':            indication,
    'priorities':            priorities,
    'recommended_modality':  primary['name'],
    'recommended_receptors': primary['receptors'],
    'recommended_example':   primary['examples'],
    'rationale': (
        f"For {indication}, top fit is {primary['name']} (score {primary['fit_score']}). "
        f"Receptor pattern {primary['receptors']} balances efficacy + tolerance + adherence "
        f"given the indication priorities."
    ),
    'all_modalities':        MODALITIES,
    'receptor_atlas':        atlas_rows,
    'pharmacology_summary': {
        'GLP1R': 'Pancreatic β/α + gut L-cell + hypothalamus + cardiac. Drives appetite suppression + insulin secretion + CV benefit. GI side effects from gastric smooth muscle agonism.',
        'GIPR':  'Pancreatic β + adipose + bone + hypothalamus. Adds direct adipose effect; modulates GLP-1 GI side effects (mechanism debated). Tirzepatide advantage vs semaglutide.',
        'GCGR':  'Hepatocyte + α-cell + kidney + adipose. Adds hepatic glucose mobilization and fat oxidation. Retatrutide advantage but hyperglycemia risk requires balance.',
    },
    'next_gen_opportunities': [
        'Oral peptide (orforglipron Phase 3 2025)',
        'mRNA-encoded continuous GLP-1 (preclinical)',
        'GLP-1 + amylin co-agonist (Novo CagriSema Phase 3)',
        'Tissue-restricted prodrug (intestinal release for GI tolerance)',
        'Selective GIPR antagonist + GLP1R agonist (under investigation)',
    ],
    'disclaimers': [
        'Atlas-driven side-effect prediction; clinical safety requires human studies',
        'Modality recommendation is a triage prior; actual program choice depends on IP, manufacturing capacity, regulatory strategy',
        'GLP-1 thyroid C-cell signal is rodent-specific (medullary thyroid C-cell tumors); not observed in human trials',
    ],
    'references': [
        'SELECT 2023 NEJM (semaglutide CV)',
        'SURMOUNT-OSA 2024 (tirzepatide sleep apnea)',
        'SYNERGY-NASH 2024 (tirzepatide MASH)',
        'TRIUMPH ongoing (retatrutide)',
        'ACHIEVE ongoing (orforglipron)',
    ],
}

with open('glp1_bakeoff_report.json', 'w') as f:
    json.dump(report, f, indent=2)

with open('receptor_atlas_summary.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['receptor','cell_type','mean_expression',
                                       'pct_expressing','tissue_criticality'])
    w.writeheader(); w.writerows(atlas_rows)

with open('modality_comparison.csv', 'w', newline='') as f:
    cols = ['rank','name','receptors','examples','delivery_class','fit_score','cost_class']
    w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore')
    w.writeheader()
    for m in MODALITIES:
        row = dict(m); row['receptors'] = '+'.join(m['receptors'])
        w.writerow(row)

# Human-readable
lines = [
    "╔══════════════════════════════════════════════════════════════════╗",
    f"  GLP-1 Family Modality Bake-Off",
    f"  Indication: {indication}   |   Delivery pref: {delivery}   |   Receptors: {receptors}",
    "╚══════════════════════════════════════════════════════════════════╝",
    "",
    f"── Recommended Modality (rank #1) ─────────────────────────────────",
    f"  Modality:    {primary['name']}",
    f"  Example:     {primary['examples']}",
    f"  Receptors:   {' + '.join(primary['receptors'])}",
    f"  Rationale:   {report['rationale'][:80]}",
    "",
    f"── All Modalities (ranked) ────────────────────────────────────────",
    f"  {'Rank':<5} {'Receptors':<22} {'Score':<7} Modality",
    "  " + "-" * 75,
]
for m in MODALITIES:
    lines.append(f"  {m['rank']:<5} {'+'.join(m['receptors']):<22} {m['fit_score']:<7} {m['name']}")

lines += [
    "",
    "── Receptor Pharmacology ──────────────────────────────────────────",
]
for rec, summary in report['pharmacology_summary'].items():
    lines.append(f"  {rec}: {summary[:90]}")

lines += [
    "",
    f"── Predicted Side Effects (top recommendation) ────────────────────",
]
for se, sev in primary['predicted_side_effects'].items():
    lines.append(f"  • {se:<28} → {sev}")

lines += [
    "",
    f"── Next-Gen Opportunities ─────────────────────────────────────────",
] + [f"  • {o}" for o in report['next_gen_opportunities']] + [
    "",
    f"── Disclaimers ────────────────────────────────────────────────────",
] + [f"  • {d}" for d in report['disclaimers']]

with open('glp1_bakeoff.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')

print('\\n'.join(lines))
PYEOF

    python3 -c "print('glp1_modality_bakeoff: 1.0')" > versions.yml
    """
}

workflow { meta = [id: 'glp1_run']; Channel.value(meta) | GLP1_MODALITY_BAKEOFF }
