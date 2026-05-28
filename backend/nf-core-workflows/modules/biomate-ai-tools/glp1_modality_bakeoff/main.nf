#!/usr/bin/env nextflow
/*
 * drug_discovery/glp1_modality_bakeoff  (4-phase pipeline)
 *
 *   Phase A — Receptor Atlas Profile : GLP1R/GIPR/GCGR tissue expression
 *   Phase B — Modality Scoring       : score 6 modalities × 6 axes
 *   Phase C — Indication Weighting   : MASH→GCGR bonus; T2D→GCGR liability
 *   Phase D — Top Recommendation     : final rationale + ranked CSV
 *
 * Marketing case: trillion-dollar GLP-1 race. Demo: MASH → retatrutide-class
 * triple agonist (GLP1R + GIPR + GCGR) wins on hepatocyte GCGR fat oxidation.
 *
 * References:
 *   - SELECT 2023 (semaglutide CV)
 *   - SURMOUNT-OSA 2024 / SURPASS-3 / SYNERGY-NASH 2024 (tirzepatide)
 *   - TRIUMPH 2024 (retatrutide Phase 3)
 *   - ACHIEVE 2024 (orforglipron oral GLP-1)
 */

nextflow.enable.dsl = 2

params.outdir        = './results'
params.indication    = 'mash'        // obesity | t2d | mash | cv_outcomes | osa
params.disease       = 'null'        // alias for indication
params.modalities    = 'auto'        // comma list: sema,tirz,reta,orfor,mrna,aav | auto
params.delivery_pref = 'auto'        // injectable_peptide | oral | mrna | gene_therapy | auto

// [Phase A] Receptor Atlas Profile — GLP1R/GIPR/GCGR tissue expression atlas
process GLP1_RECEPTOR_ATLAS {
    tag "glp1:phaseA:${params.indication}"
    label 'process_low'
    publishDir "${params.outdir}/phaseA_atlas", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("receptor_atlas.json"), emit: atlas
    path "phaseA_summary.txt",                    emit: summary

    script:
    """
    export PARAM_INDICATION='${params.indication}'
    export PARAM_DISEASE='${params.disease}'
    export PARAM_MODALITIES='${params.modalities}'
    export PARAM_DELIVERY='${params.delivery_pref}'

    python3 << 'PYEOF'
import os, json

indication = os.environ.get('PARAM_INDICATION', '').strip().lower()
if not indication or indication == 'null':
    indication = 'obesity'
disease = os.environ.get('PARAM_DISEASE', '').strip().lower()
if not disease or disease == 'null':
    disease = indication
# disease alias overrides indication when explicitly passed
if disease and disease != indication and disease in ('obesity','t2d','mash','cv_outcomes','osa'):
    indication = disease
modalities = os.environ.get('PARAM_MODALITIES', '').strip().lower()
if not modalities or modalities == 'null':
    modalities = 'auto'
delivery = os.environ.get('PARAM_DELIVERY', '').strip().lower()
if not delivery or delivery == 'null':
    delivery = 'auto'

RECEPTOR_PROFILES = {
    'GLP1R': {
        'pancreatic_islet_beta':  (4.2, 85, 'MOD'),
        'pancreatic_islet_alpha': (3.5, 75, 'MOD'),
        'enteroendocrine_L':      (4.5, 90, 'MOD'),
        'hypothalamic_POMC':      (3.0, 65, 'HIGH'),
        'gastric_smooth_muscle':  (2.8, 60, 'MOD'),
        'cardiac_muscle_cell':    (1.2, 25, 'HIGH'),
        'bone_osteoblast':        (1.5, 30, 'MOD'),
        'thyroid_C_cell':         (2.0, 45, 'LOW'),
    },
    'GIPR': {
        'pancreatic_islet_beta':  (3.8, 80, 'MOD'),
        'adipose_white':          (3.2, 70, 'LOW'),
        'adipose_brown':          (2.8, 60, 'LOW'),
        'bone_osteoclast':        (2.0, 42, 'MOD'),
        'hypothalamic_neuron':    (1.6, 32, 'HIGH'),
        'cardiac_muscle_cell':    (0.4,  8, 'HIGH'),
    },
    'GCGR': {
        'hepatocyte':             (4.0, 88, 'MOD'),
        'pancreatic_islet_alpha': (2.4, 50, 'MOD'),
        'kidney_tubule_epi':      (2.0, 42, 'MOD'),
        'adipose_brown':          (1.8, 38, 'LOW'),
        'cardiac_muscle_cell':    (1.0, 22, 'HIGH'),
    },
}

atlas_rows = []
for rec_name, profile in RECEPTOR_PROFILES.items():
    for ct, (mean, pct, tier) in profile.items():
        atlas_rows.append({
            'receptor': rec_name, 'cell_type': ct,
            'mean_expression': mean, 'pct_expressing': pct,
            'tissue_criticality': tier,
        })

out = {
    'indication': indication,
    'disease': disease,
    'modalities_filter': modalities,
    'delivery_pref': delivery,
    'receptor_profiles': RECEPTOR_PROFILES,
    'receptor_atlas': atlas_rows,
    'hepatocyte_gcgr_pct': RECEPTOR_PROFILES['GCGR']['hepatocyte'][1],
}
with open('receptor_atlas.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    f"Phase A — Receptor Atlas Profile",
    f"  Indication:        {indication}",
    f"  Modalities filter: {modalities}",
    f"  GLP1R cell types:  {len(RECEPTOR_PROFILES['GLP1R'])}",
    f"  GIPR cell types:   {len(RECEPTOR_PROFILES['GIPR'])}",
    f"  GCGR cell types:   {len(RECEPTOR_PROFILES['GCGR'])}",
    f"  Hepatocyte GCGR:   {out['hepatocyte_gcgr_pct']}% expressing (MASH-relevant)",
]
with open('phaseA_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase B] Modality Scoring — score 6 GLP-1 modalities on 6 axes
process GLP1_MODALITY_SCORING {
    tag "glp1:phaseB"
    label 'process_low'
    publishDir "${params.outdir}/phaseB_scoring", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(atlas_json)

    output:
    tuple val(meta), path("modality_scores.json"), path(atlas_json), emit: scores
    path "phaseB_summary.txt",                                       emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${atlas_json}') as f:
    ctx = json.load(f)

modalities_filter = ctx.get('modalities_filter','auto')

MODALITIES = [
    {
        'key': 'sema',
        'name': 'Injectable peptide (sema-class)',
        'receptors': ['GLP1R'],
        'examples': 'Semaglutide (Ozempic/Wegovy)',
        'delivery_class': 'subcutaneous_weekly',
        'axes': {'efficacy':3,'gi_tolerance':2,'adherence':3,'cv_benefit':5,'cost':2,'maturity':5},
        'cost_class': 'High (\$800-1300/mo)',
        'cv_outcomes_data': 'SELECT 2023 (MACE -20%)',
    },
    {
        'key': 'tirz',
        'name': 'Dual GLP-1/GIP injectable (tirz-class)',
        'receptors': ['GLP1R','GIPR'],
        'examples': 'Tirzepatide (Mounjaro/Zepbound)',
        'delivery_class': 'subcutaneous_weekly',
        'axes': {'efficacy':4,'gi_tolerance':4,'adherence':3,'cv_benefit':4,'cost':2,'maturity':5},
        'cost_class': 'High (\$1000/mo)',
        'cv_outcomes_data': 'SURPASS-4 / SURMOUNT-OSA / SYNERGY-NASH',
    },
    {
        'key': 'reta',
        'name': 'Triple GLP-1/GIP/glucagon injectable (reta-class)',
        'receptors': ['GLP1R','GIPR','GCGR'],
        'examples': 'Retatrutide (Eli Lilly, Phase 3 TRIUMPH)',
        'delivery_class': 'subcutaneous_weekly',
        'axes': {'efficacy':5,'gi_tolerance':3,'adherence':3,'cv_benefit':3,'cost':1,'maturity':3},
        'cost_class': 'Premium TBD (\$1500+/mo)',
        'cv_outcomes_data': 'Phase 3 2025-2026',
    },
    {
        'key': 'orfor',
        'name': 'Oral GLP-1 small molecule',
        'receptors': ['GLP1R'],
        'examples': 'Orforglipron (Eli Lilly, Phase 3 ACHIEVE)',
        'delivery_class': 'oral_daily',
        'axes': {'efficacy':3,'gi_tolerance':3,'adherence':5,'cv_benefit':3,'cost':4,'maturity':3},
        'cost_class': 'TBD oral COGS lower',
        'cv_outcomes_data': 'Phase 3 readout 2025',
    },
    {
        'key': 'mrna',
        'name': 'mRNA-encoded GLP-1',
        'receptors': ['GLP1R'],
        'examples': 'No clinical program yet',
        'delivery_class': 'mrna_lnp_im_or_sc',
        'axes': {'efficacy':3,'gi_tolerance':3,'adherence':4,'cv_benefit':2,'cost':2,'maturity':1},
        'cost_class': 'TBD',
        'cv_outcomes_data': 'Preclinical',
    },
    {
        'key': 'aav',
        'name': 'AAV gene therapy (one-shot GLP-1)',
        'receptors': ['GLP1R'],
        'examples': 'Theoretical',
        'delivery_class': 'aav_iv_or_im',
        'axes': {'efficacy':3,'gi_tolerance':2,'adherence':5,'cv_benefit':2,'cost':1,'maturity':1},
        'cost_class': 'High one-shot',
        'cv_outcomes_data': 'None',
    },
]

if modalities_filter and modalities_filter != 'auto':
    wanted = {x.strip() for x in modalities_filter.split(',')}
    filtered = [m for m in MODALITIES if m['key'] in wanted]
    if filtered:
        MODALITIES = filtered

out = {**ctx, 'modalities': MODALITIES, 'scoring_axes': ['efficacy','gi_tolerance','adherence','cv_benefit','cost','maturity']}
with open('modality_scores.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase B — Modality Scoring",
    f"  Modalities evaluated: {len(MODALITIES)}",
    f"  Axes: efficacy, gi_tolerance, adherence, cv_benefit, cost, maturity",
]
for m in MODALITIES:
    lines.append(f"    - {m['key']:<6} {'+'.join(m['receptors']):<18} {m['name']}")
with open('phaseB_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase C] Indication Weighting — MASH→GCGR bonus; T2D→GCGR liability → ranked CSV
process GLP1_INDICATION_WEIGHTING {
    tag "glp1:phaseC"
    label 'process_low'
    publishDir "${params.outdir}/phaseC_weighting", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(scores_json), path(atlas_json)

    output:
    tuple val(meta), path("modality_ranking.json"), path("glp1_modality_ranking.csv"), emit: ranked
    path "phaseC_summary.txt",                                                          emit: summary

    script:
    """
    python3 << 'PYEOF'
import json, csv

with open('${scores_json}') as f:
    ctx = json.load(f)

indication = ctx['indication']
MODALITIES = ctx['modalities']

INDICATION_PRIORITY = {
    'obesity':     {'efficacy':5,'gi_tolerance':4,'adherence':3,'cv_benefit':3,'cost':2,'maturity':3},
    't2d':         {'efficacy':5,'cv_benefit':4,'gi_tolerance':3,'adherence':3,'cost':2,'maturity':4},
    'mash':        {'efficacy':5,'hepatic_targeting':5,'gi_tolerance':3,'adherence':3,'cost':2,'maturity':3},
    'cv_outcomes': {'cv_benefit':5,'efficacy':4,'adherence':3,'gi_tolerance':3,'cost':2,'maturity':5},
    'osa':         {'efficacy':5,'gi_tolerance':4,'adherence':3,'cv_benefit':2,'cost':2,'maturity':4},
}

GCGR_INDICATION_FIT = {
    'obesity': 0, 't2d': -8, 'mash': +10, 'cv_outcomes': -3, 'osa': -2,
}

priorities = INDICATION_PRIORITY.get(indication, INDICATION_PRIORITY['obesity'])

def composite(m, priorities, indication):
    score = 0
    for axis, w in priorities.items():
        if axis == 'hepatic_targeting':
            if 'GCGR' in m['receptors']:
                score += w * 5
            elif 'GLP1R' in m['receptors']:
                score += w * 3
            continue
        v = m['axes'].get(axis, 0)
        score += w * v
    if 'GCGR' in m['receptors']:
        score += GCGR_INDICATION_FIT.get(indication, 0)
    return score

scored = []
for m in MODALITIES:
    s = composite(m, priorities, indication)
    max_axis = sum(priorities.values()) * 5
    pct = round(100 * s / max(max_axis, 1), 1)
    scored.append({**m, 'composite_score': s, 'percent': pct})
scored.sort(key=lambda x: -x['composite_score'])
for i, s in enumerate(scored):
    s['rank'] = i + 1

out = {**ctx, 'priorities': priorities, 'gcgr_fit': GCGR_INDICATION_FIT.get(indication, 0), 'ranking': scored}
with open('modality_ranking.json','w') as f:
    json.dump(out, f, indent=2)

cols = ['rank','key','name','receptors','examples','delivery_class','composite_score','percent','cost_class']
with open('glp1_modality_ranking.csv','w',newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore')
    w.writeheader()
    for s in scored:
        row = dict(s); row['receptors'] = '+'.join(s['receptors'])
        w.writerow(row)

lines = [
    "Phase C — Indication Weighting",
    f"  Indication:  {indication}",
    f"  GCGR fit:    {GCGR_INDICATION_FIT.get(indication, 0):+d}",
    f"  Priorities:  {priorities}",
    "  Top 3:",
]
for s in scored[:3]:
    lines.append(f"    #{s['rank']} {s['key']:<6} {'+'.join(s['receptors']):<18} score={s['composite_score']:<4} pct={s['percent']}%")
with open('phaseC_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase D] Top Recommendation — final rationale + JSON/TXT/CSV report
process GLP1_TOP_RECOMMENDATION {
    tag "glp1:phaseD"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(ranking_json), path(ranking_csv)

    output:
    tuple val(meta), path("glp1_bakeoff_report.json"),    emit: report_json
    tuple val(meta), path("glp1_modality_ranking.csv"),   emit: ranking_csv
    tuple val(meta), path("glp1_summary.txt"),            emit: report
    path "versions.yml",                                   emit: versions

    script:
    """
    python3 << 'PYEOF'
import json

with open('${ranking_json}') as f:
    ctx = json.load(f)

scored = ctx['ranking']
primary = scored[0]
indication = ctx['indication']

report = {
    'indication':            indication,
    'disease':               ctx.get('disease', indication),
    'priorities':            ctx['priorities'],
    'gcgr_indication_fit':   ctx['gcgr_fit'],
    'recommended_modality':  primary['name'],
    'recommended_key':       primary['key'],
    'recommended_receptors': primary['receptors'],
    'recommended_example':   primary['examples'],
    'rationale': (
        f"For {indication}, top fit is {primary['name']} (composite {primary['composite_score']}, "
        f"{primary['percent']}%). Receptor pattern {'+'.join(primary['receptors'])} balances the "
        f"axes weighted for this indication."
        + (" GCGR agonism is therapeutic in MASH via hepatic fat oxidation." if 'GCGR' in primary['receptors'] and indication == 'mash' else "")
    ),
    'modality_ranking':      scored,
    'receptor_atlas':        ctx.get('receptor_atlas', []),
    'pharmacology_summary': {
        'GLP1R': 'β/α-cell + L-cell + hypothalamus + cardiac. Appetite + insulin + CV benefit; GI side effects.',
        'GIPR':  'β-cell + adipose + bone + hypothalamus. Adipose effect; mitigates GI side effects (tirz advantage).',
        'GCGR':  'Hepatocyte + α-cell + kidney + adipose. Hepatic fat oxidation (reta advantage); hyperglycemia risk in T2D.',
    },
    'disclaimers': [
        'Atlas-driven triage; clinical safety requires human studies',
        'Modality recommendation is a prior; program choice also depends on IP, manufacturing, regulatory',
        'GLP-1 thyroid C-cell signal is rodent-specific',
    ],
    'references': [
        'SELECT 2023 NEJM',
        'SURMOUNT-OSA 2024',
        'SYNERGY-NASH 2024',
        'TRIUMPH 2024 retatrutide',
        'ACHIEVE 2024 orforglipron',
    ],
}
with open('glp1_bakeoff_report.json','w') as f:
    json.dump(report, f, indent=2)

lines = [
    "===================================================================",
    f"  GLP-1 Family Modality Bake-Off",
    f"  Indication: {indication}",
    "===================================================================",
    "",
    f"-- Top Recommendation (rank #1) --",
    f"  Modality:   {primary['name']}",
    f"  Example:    {primary['examples']}",
    f"  Receptors:  {' + '.join(primary['receptors'])}",
    f"  Score:      {primary['composite_score']}  ({primary['percent']}%)",
    f"  Rationale:  {report['rationale']}",
    "",
    f"-- Full Ranking --",
    f"  {'Rank':<5} {'Key':<7} {'Receptors':<20} {'Score':<7} Modality",
    "  " + "-" * 70,
]
for s in scored:
    lines.append(f"  {s['rank']:<5} {s['key']:<7} {'+'.join(s['receptors']):<20} {s['composite_score']:<7} {s['name']}")

lines += ["", "-- Receptor Pharmacology --"]
for rec, summary in report['pharmacology_summary'].items():
    lines.append(f"  {rec}: {summary}")

lines += ["", "-- Disclaimers --"] + [f"  * {d}" for d in report['disclaimers']]

with open('glp1_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF

    python3 -c "print('glp1_modality_bakeoff: 2.0')" > versions.yml
    cp ${ranking_csv} glp1_modality_ranking.csv
    """
}

workflow {
    meta = [id: 'glp1_run']
    Channel.value(meta) | GLP1_RECEPTOR_ATLAS
    GLP1_RECEPTOR_ATLAS.out.atlas        | GLP1_MODALITY_SCORING
    GLP1_MODALITY_SCORING.out.scores     | GLP1_INDICATION_WEIGHTING
    GLP1_INDICATION_WEIGHTING.out.ranked | GLP1_TOP_RECOMMENDATION
}
