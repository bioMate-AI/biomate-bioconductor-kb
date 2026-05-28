#!/usr/bin/env nextflow
/*
 * drug_discovery/bispecific_format_triage  (4-phase pipeline)
 *
 *   Phase A — Mechanism Inference     : input validation, precedent lookup, cis/trans classification
 *   Phase B — Format Scoring Matrix   : score 5 formats × 6 axes
 *   Phase C — Composite Ranking       : mechanism+indication weighting → ranked CSV
 *   Phase D — Report Synthesis        : recommendation + human-readable summary
 *
 * Marketing case: Ivonescimab (PD-1×VEGF CrossMab, HARMONi-2 Oct 2024) beat
 * Keytruda head-to-head. Workflow recovers CrossMab as #1 choice.
 *
 * References:
 *   - Labrijn 2019 Nat Rev Drug Discov (bispecific format review)
 *   - Kontermann 2015 Drug Discov Today (engineering strategies)
 *   - Wang et al. 2024 HARMONi-2 (Ivonescimab vs pembrolizumab)
 */

nextflow.enable.dsl = 2

params.outdir     = './results'
params.target_a   = 'null'
params.target_b   = 'null'
params.indication = 'oncology'
params.mechanism  = 'auto'      // cis_engagement | trans_engagement | auto

// [Phase A] Mechanism Inference — precedent lookup and cis/trans engagement classification
process BISPEC_MECHANISM_INFERENCE {
    tag "bispec:phaseA:${params.target_a}_x_${params.target_b}"
    label 'process_low'
    publishDir "${params.outdir}/phaseA_mechanism", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("mechanism_inference.json"), emit: mechanism
    path "phaseA_summary.txt",                          emit: summary

    script:
    """
    export PARAM_A='${params.target_a}'
    export PARAM_B='${params.target_b}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_MECHANISM='${params.mechanism}'

    python3 << 'PYEOF'
import os, json

target_a = os.environ.get('PARAM_A', '').strip()
if not target_a or target_a.lower() == 'null':
    target_a = 'PDCD1'
target_a = target_a.upper()
target_b = os.environ.get('PARAM_B', '').strip()
if not target_b or target_b.lower() == 'null':
    target_b = 'KDR'
target_b = target_b.upper()
indication = os.environ.get('PARAM_INDICATION', 'oncology').strip().lower()
mechanism  = os.environ.get('PARAM_MECHANISM', 'auto').strip().lower()

KNOWN_BISPECIFICS = {
    ('PDCD1','KDR'):    {'format':'CrossMab','mechanism':'cis_engagement',
                          'drug':'Ivonescimab (Akeso/Summit, HARMONi-2 Oct 2024)',
                          'rationale':'PD-1 on TILs meets VEGFR2 on tumor microvessels — cis engagement on tumor endothelium-T cell interface'},
    ('CD3','CD19'):     {'format':'BiTE','mechanism':'trans_engagement',
                          'drug':'Blinatumomab (Amgen, Blincyto 2014)',
                          'rationale':'T cell × B cell, trans engagement'},
    ('CD3','BCMA'):     {'format':'KiH','mechanism':'trans_engagement',
                          'drug':'Teclistamab (J&J, Tecvayli 2022)',
                          'rationale':'T cell × plasma cell trans engagement; IgG-like half-life for SC dosing'},
    ('CD3','GPRC5D'):   {'format':'KiH','mechanism':'trans_engagement',
                          'drug':'Talquetamab (J&J, Talvey 2023)',
                          'rationale':'T cell × plasma cell; IgG-like half-life'},
    ('CD3','DLL3'):     {'format':'BiTE','mechanism':'trans_engagement',
                          'drug':'Tarlatamab (Amgen, Imdelltra 2024)',
                          'rationale':'T cell × SCLC neuroendocrine'},
    ('CD3','CD20'):     {'format':'CrossMab','mechanism':'trans_engagement',
                          'drug':'Glofitamab (Roche, Columvi 2023)',
                          'rationale':'T cell × B cell; CrossMab 2:1 binding stoichiometry'},
    ('ANG2','VEGFA'):   {'format':'CrossMab','mechanism':'cis_engagement',
                          'drug':'Faricimab (Roche, Vabysmo 2022)',
                          'rationale':'Both on neovasculature — cis engagement'},
    ('HER2','HER3'):    {'format':'CrossMab','mechanism':'cis_engagement',
                          'drug':'Zenocutuzumab (Merus, Bizengri Dec 2024)',
                          'rationale':'Both on tumor cells — cis engagement; NRG1 fusion driver'},
    ('EGFR','MET'):     {'format':'KiH','mechanism':'cis_engagement',
                          'drug':'Amivantamab (J&J, Rybrevant 2021)',
                          'rationale':'Both on tumor cells — cis engagement; common bypass mechanism'},
    ('VEGFA','PDCD1'):  {'format':'CrossMab','mechanism':'cis_engagement',
                          'drug':'Ivonescimab variant',
                          'rationale':'Equivalent to PDCD1 × KDR (VEGFR2)'},
}

def norm_pair(a,b):
    return tuple(sorted([a,b]))

pair = norm_pair(target_a, target_b)
known = None
for k,v in KNOWN_BISPECIFICS.items():
    if norm_pair(*k) == pair:
        known = v
        break

if mechanism == 'auto':
    if known:
        inferred = known['mechanism']
        source = f"precedent ({known['drug']})"
    elif 'CD3' in (target_a, target_b):
        inferred = 'trans_engagement'
        source = 'CD3 anchor — TCE convention'
    else:
        inferred = 'cis_engagement'
        source = 'no precedent; defaulting to cis'
else:
    inferred = mechanism
    source = 'user-specified'

out = {
    'target_a': target_a,
    'target_b': target_b,
    'pair_canonical': list(pair),
    'indication': indication,
    'inferred_mechanism': inferred,
    'mechanism_source': source,
    'known_precedent': known,
}
with open('mechanism_inference.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    f"Phase A — Mechanism Inference",
    f"  Targets:    {target_a} x {target_b}",
    f"  Indication: {indication}",
    f"  Mechanism:  {inferred}  (source: {source})",
]
if known:
    lines += [f"  Precedent:  {known['drug']}", f"              {known['rationale']}"]
else:
    lines += [f"  Precedent:  (none in known cache — de novo design)"]
with open('phaseA_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase B] Format Scoring Matrix — score 5 bispecific formats on 6 biophysical axes
process BISPEC_FORMAT_SCORING {
    tag "bispec:phaseB"
    label 'process_low'
    publishDir "${params.outdir}/phaseB_scoring", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(mechanism_json)

    output:
    tuple val(meta), path("format_scores.json"), path(mechanism_json), emit: scores
    path "phaseB_summary.txt",                                          emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${mechanism_json}') as f:
    ctx = json.load(f)

FORMATS = {
    'BiTE': {
        'half_life': 1, 'cis_engagement': 1, 'trans_engagement': 5,
        'manufacturing': 4, 'ada_risk': 3, 'affinity_asymmetry': 3,
        'characteristics': 'Single-chain bispecific, no Fc, hours half-life, continuous infusion required',
    },
    'CrossMab': {
        'half_life': 5, 'cis_engagement': 5, 'trans_engagement': 3,
        'manufacturing': 4, 'ada_risk': 4, 'affinity_asymmetry': 4,
        'characteristics': 'Native IgG architecture with engineered light chain pairing; full Fc',
    },
    'KiH': {
        'half_life': 5, 'cis_engagement': 4, 'trans_engagement': 5,
        'manufacturing': 3, 'ada_risk': 4, 'affinity_asymmetry': 4,
        'characteristics': 'Knob-into-hole Fc heterodimerization; widely used',
    },
    'DVD-Ig': {
        'half_life': 5, 'cis_engagement': 4, 'trans_engagement': 3,
        'manufacturing': 2, 'ada_risk': 2, 'affinity_asymmetry': 2,
        'characteristics': 'Tandem variable domains; complex; falling out of favor',
    },
    'Nanobody_fusion': {
        'half_life': 2, 'cis_engagement': 3, 'trans_engagement': 4,
        'manufacturing': 4, 'ada_risk': 3, 'affinity_asymmetry': 4,
        'characteristics': 'VHH-VHH fusion; small (~30 kDa); CNS penetrant; fast PK',
    },
}

out = {**ctx, 'format_scores': FORMATS}
with open('format_scores.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase B — Format Scoring Matrix",
    "  Scored 5 formats on 6 axes:",
    "    half_life, cis_engagement, trans_engagement, manufacturing, ada_risk, affinity_asymmetry",
    "  Formats: " + ', '.join(FORMATS.keys()),
]
with open('phaseB_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase C] Composite Ranking — apply mechanism+indication weighting → sorted CSV
process BISPEC_COMPOSITE_RANKING {
    tag "bispec:phaseC"
    label 'process_low'
    publishDir "${params.outdir}/phaseC_ranking", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(scores_json), path(mechanism_json)

    output:
    tuple val(meta), path("format_ranking.json"), path("format_ranking.csv"), emit: ranked
    path "phaseC_summary.txt",                                                  emit: summary

    script:
    """
    python3 << 'PYEOF'
import json, csv

with open('${scores_json}') as f:
    ctx = json.load(f)

mech = ctx['inferred_mechanism']
ind  = ctx['indication']
FORMATS = ctx['format_scores']

def composite_score(fmt_props, mech, ind):
    if mech == 'cis_engagement':
        w = {'cis_engagement':4,'half_life':3,'affinity_asymmetry':2,'manufacturing':2,'ada_risk':1,'trans_engagement':0}
    elif mech == 'trans_engagement':
        w = {'trans_engagement':4,'manufacturing':3,'ada_risk':3,'half_life':1,'cis_engagement':0,'affinity_asymmetry':2}
    else:
        w = {k:1 for k in fmt_props if k != 'characteristics'}
    if 'cns' in ind or 'brain' in ind or 'glioma' in ind:
        w['half_life'] = max(w.get('half_life',0), 1)
    score = sum(w.get(k,0)*v for k,v in fmt_props.items() if k != 'characteristics')
    max_possible = sum(w.values()) * 5
    return score, round(100 * score / max(max_possible,1), 1)

scored = []
for fmt_name, props in FORMATS.items():
    raw, pct = composite_score(props, mech, ind)
    flags = []
    if fmt_name == 'DVD-Ig':
        flags.append('Aggregation risk; complex manufacturing; falling out of favor')
    if fmt_name == 'Nanobody_fusion':
        flags.append('Humanization required; short half-life unless Fc-fused')
    if fmt_name == 'BiTE':
        flags.append('Continuous IV infusion or SC pump required')
    scored.append({
        'format': fmt_name, 'composite_score': raw, 'percent': pct,
        'characteristics': props['characteristics'],
        'manufacturing_flags': flags,
        **{k:v for k,v in props.items() if k != 'characteristics'},
    })
scored.sort(key=lambda x: -x['composite_score'])
for i,s in enumerate(scored):
    s['rank'] = i + 1

out = {**ctx, 'format_ranking': scored}
with open('format_ranking.json','w') as f:
    json.dump(out, f, indent=2)

cols = ['rank','format','composite_score','percent','half_life','cis_engagement',
        'trans_engagement','manufacturing','ada_risk','affinity_asymmetry']
with open('format_ranking.csv','w',newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore')
    w.writeheader(); w.writerows(scored)

lines = ["Phase C — Composite Ranking", f"  Weighting: {mech} + indication={ind}", "  Top 3:"]
for s in scored[:3]:
    lines.append(f"    #{s['rank']} {s['format']:<18} score={s['composite_score']:<3} pct={s['percent']}%")
with open('phaseC_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase D] Report Synthesis — final recommendation + human-readable report
process BISPEC_REPORT_SYNTHESIS {
    tag "bispec:phaseD"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(ranking_json), path(ranking_csv)

    output:
    tuple val(meta), path("bispecific_format_report.json"), emit: report_json
    tuple val(meta), path("format_ranking.csv"),            emit: ranking_csv
    tuple val(meta), path("bispecific_summary.txt"),        emit: report
    path "versions.yml",                                     emit: versions

    script:
    """
    python3 << 'PYEOF'
import json

with open('${ranking_json}') as f:
    ctx = json.load(f)

scored = ctx['format_ranking']
primary = scored[0]
known = ctx.get('known_precedent')

report = {
    'target_a': ctx['target_a'],
    'target_b': ctx['target_b'],
    'pair_canonical': ctx['pair_canonical'],
    'indication': ctx['indication'],
    'inferred_mechanism': ctx['inferred_mechanism'],
    'mechanism_source': ctx.get('mechanism_source'),
    'known_precedent': known,
    'recommended_format': primary['format'],
    'recommendation_rationale': (
        f"Mechanism inferred as {ctx['inferred_mechanism']}. "
        f"Top format: {primary['format']} (score {primary['composite_score']}, {primary['percent']}%). "
        + (f"Matches precedent {known['drug']}." if known else "No exact precedent in cache.")
    ),
    'format_ranking': scored,
    'disclaimers': [
        'Format triage is a starting point; biophysical optimization determines final clinical viability',
        'Manufacturing yield and ADA risk require empirical validation',
        'Atlas-driven co-expression analysis assumes RNA-protein concordance — confirm with surface IHC',
    ],
    'references': [
        'Labrijn et al. 2019 Nat Rev Drug Discov 18:585',
        'Kontermann & Brinkmann 2015 Drug Discov Today 20:838',
        'Wang et al. 2024 HARMONi-2',
        'Krishnamurthy & Jimeno 2017 (BiTE clinical experience)',
    ],
}
with open('bispecific_format_report.json','w') as f:
    json.dump(report, f, indent=2)

lines = [
    "═══════════════════════════════════════════════════════════════════",
    f"  Bispecific Format Triage",
    f"  Targets: {ctx['target_a']} x {ctx['target_b']}   |   Indication: {ctx['indication']}",
    f"  Inferred mechanism: {ctx['inferred_mechanism']}",
    "═══════════════════════════════════════════════════════════════════",
    "",
]
if known:
    lines += [
        f"-- Known Precedent --",
        f"  Drug:      {known['drug']}",
        f"  Format:    {known['format']}",
        f"  Rationale: {known['rationale']}",
        "",
    ]
lines += [
    f"-- Recommended Format: {primary['format']} --",
    f"  Composite score:  {primary['composite_score']}  ({primary['percent']}%)",
    f"  Characteristics:  {primary['characteristics']}",
    "",
    f"-- Full Ranking --",
    f"  {'Rank':<5} {'Format':<22} {'Score':<7} Pct",
    "  " + "-" * 50,
]
for s in scored:
    lines.append(f"  {s['rank']:<5} {s['format']:<22} {s['composite_score']:<7} {s['percent']}%")

lines += ["", "-- Manufacturing & Immunogenicity Flags --"]
for s in scored[:3]:
    if s['manufacturing_flags']:
        lines.append(f"  {s['format']}:")
        for fl in s['manufacturing_flags']:
            lines.append(f"    * {fl}")

lines += ["", "-- Disclaimers --"] + [f"  * {d}" for d in report['disclaimers']]

with open('bispecific_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF

    python3 -c "print('bispecific_format_triage: 2.0')" > versions.yml
    cp ${ranking_csv} format_ranking.csv
    """
}

workflow {
    meta = [id: 'bispec_run']
    Channel.value(meta) | BISPEC_MECHANISM_INFERENCE
    BISPEC_MECHANISM_INFERENCE.out.mechanism | BISPEC_FORMAT_SCORING
    BISPEC_FORMAT_SCORING.out.scores         | BISPEC_COMPOSITE_RANKING
    BISPEC_COMPOSITE_RANKING.out.ranked      | BISPEC_REPORT_SYNTHESIS
}
