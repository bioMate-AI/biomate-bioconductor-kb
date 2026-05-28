#!/usr/bin/env nextflow
/*
 * drug_discovery/modality_triage  (4-phase pipeline)
 *
 *   Phase A — Atlas Profile           : load atlas_expression.json (target tissue distribution)
 *   Phase B — CAR-T Viability         : B-cell / plasma-cell restriction; CAR-T verdict
 *   Phase C — ADC + Bispecific Eval   : internalization-friendly payloads; bispecific TCE eval
 *   Phase D — Modality Ranking        : composite ranking + IHC follow-up panel + final report
 *
 * Demo case (T05): BCMA → plasma cells (high) + plasmablasts (moderate), no critical-tissue
 * hits → CAR-T VIABLE (matches Abecma/Carvykti pattern).
 *
 * NOT a clinical decision tool. Output is triage to prioritize wet-lab IHC validation.
 *
 * References:
 *   - Morgan et al. 2010 Mol Ther 18:843 (HER2 CAR-T cardiopulmonary fatality)
 *   - Parkhurst et al. 2011 Mol Ther 19:620 (CEA CAR-T severe colitis)
 *   - Lamers et al. 2013 Mol Ther 21:904 (CAIX CAR-T hepatotoxicity)
 *   - Hassan et al. 2014 Cancer Immunol Res 2:1062 (MSLN target selection)
 *   - Quake lab 2022 Science (Tabula Sapiens)
 *   - Hamblett 2004 Clin Cancer Res (ADC DAR-PK relationship)
 *   - Bondeson & Crews 2017 Annu Rev Pharmacol (PROTAC design)
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.atlas_expression  = 'null'
params.target_gene       = 'null'
params.indication        = 'oncology'
params.modalities        = 'all'

// [Phase A] Atlas Profile — load atlas_expression.json and compute tissue-tier aggregates
process TRIAGE_ATLAS_PROFILE {
    tag "triage:phaseA:${params.target_gene}"
    label 'process_low'
    publishDir "${params.outdir}/phaseA_atlas", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("atlas_context.json"), emit: context
    path "phaseA_summary.txt",                    emit: summary

    script:
    """
    export PARAM_ATLAS='${params.atlas_expression}'
    export PARAM_GENE='${params.target_gene}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_MODALITIES='${params.modalities}'

    python3 << 'PYEOF'
import os, json

atlas_path = os.environ.get('PARAM_ATLAS', '').strip()
gene = os.environ.get('PARAM_GENE', '').strip()
if not gene or gene.lower() == 'null':
    gene = 'unknown'
gene = gene.upper()
indication = os.environ.get('PARAM_INDICATION', '').strip().lower()
if not indication or indication == 'null':
    indication = 'oncology'
modalities = os.environ.get('PARAM_MODALITIES', '').strip().lower()
if not modalities or modalities == 'null':
    modalities = 'all'

if atlas_path and atlas_path.lower() != 'null' and os.path.exists(atlas_path):
    with open(atlas_path) as f:
        atlas = json.load(f)
else:
    atlas = {'target_gene': gene, 'cell_type_profile': []}

profile = atlas.get('cell_type_profile', [])
gene = atlas.get('target_gene', gene) or gene

def max_expr_in_tier(profile, tier):
    matches = [r['mean_expression'] for r in profile if r['tissue_criticality'] == tier]
    return max(matches) if matches else 0.0

def cell_types_in_tier(profile, tier, threshold=0.5):
    return [r['cell_type'] for r in profile
            if r['tissue_criticality'] == tier and r['mean_expression'] > threshold]

max_high = max_expr_in_tier(profile, 'HIGH')
max_mod  = max_expr_in_tier(profile, 'MOD')
max_low  = max_expr_in_tier(profile, 'LOW')
high_hits = cell_types_in_tier(profile, 'HIGH', 0.5)
mod_hits  = cell_types_in_tier(profile, 'MOD',  0.5)
low_hits  = cell_types_in_tier(profile, 'LOW',  0.5)

# B-cell / plasma-cell restriction detection (drives CAR-T precedent matching)
b_or_plasma = [r for r in profile
               if any(tok in r['cell_type'].lower() for tok in ['b_cell','plasma_cell','plasmablast'])
               and r['mean_expression'] > 0.5]
restricted_lymphoid = (
    len(high_hits) == 0
    and max_mod <= 1.0
    and len(b_or_plasma) >= 1
)

ctx = {
    'target_gene':  gene,
    'indication':   indication,
    'modalities':   modalities,
    'atlas_source': atlas.get('data_source', 'unknown'),
    'profile':      profile,
    'max_high':     max_high,
    'max_mod':      max_mod,
    'max_low':      max_low,
    'high_hits':    high_hits,
    'mod_hits':     mod_hits,
    'low_hits':     low_hits,
    'b_or_plasma_cells': [r['cell_type'] for r in b_or_plasma],
    'restricted_lymphoid': restricted_lymphoid,
}
with open('atlas_context.json', 'w') as f:
    json.dump(ctx, f, indent=2)

lines = [
    "Phase A — Atlas Profile",
    f"  Target:           {gene}",
    f"  Indication:       {indication}",
    f"  Atlas source:     {ctx['atlas_source']}",
    f"  Cell types:       {len(profile)}",
    f"  Max HIGH expr:    {max_high:.2f}  (hits: {len(high_hits)})",
    f"  Max MOD  expr:    {max_mod:.2f}  (hits: {len(mod_hits)})",
    f"  B/plasma cells:   {ctx['b_or_plasma_cells']}",
    f"  Lymphoid-restricted: {restricted_lymphoid}",
]
with open('phaseA_summary.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase B] CAR-T Viability — score CAR-T using B-cell / plasma-cell restriction and critical-tissue hits
process TRIAGE_CART_VIABILITY {
    tag "triage:phaseB"
    label 'process_low'
    publishDir "${params.outdir}/phaseB_cart", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(ctx_json)

    output:
    tuple val(meta), path("cart_eval.json"), emit: cart
    path "phaseB_summary.txt",                emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${ctx_json}') as f:
    ctx = json.load(f)

max_high = ctx['max_high']; max_mod = ctx['max_mod']
high_hits = ctx['high_hits']; mod_hits = ctx['mod_hits']
restricted_lymphoid = ctx['restricted_lymphoid']

def score_cart():
    if max_high > 0.5:
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Expression > 0.5 in critical tissue(s): {high_hits[:3]}",
            'mitigation':'Logic-gated AND-NOT CAR (A2 Bio) or alternate modality',
            'precedent': 'HER2 CAR-T (Morgan 2010), CEA CAR-T (Parkhurst 2011), ROR1, EGFR CAR-T',
        }
    if max_mod > 3.0:
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Expression > 3.0 in moderate continuous-lining tissue(s): {mod_hits[:3]}",
            'mitigation':'Modality switch required',
            'precedent': 'CEA CAR-T severe colitis; MUC1 CAR-T epithelial toxicity',
        }
    if max_mod > 1.0:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Expression > 1.0 in moderate tissue(s): {mod_hits[:3]}",
            'mitigation':'Logic-gated CAR (AND, AND-NOT, SynNotch) or tumor-conditional activation',
            'precedent': 'A2 Biotherapeutics logic-gated CARs',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    "Expression restricted to LOW-criticality tissues" + (
            f" with B/plasma-cell-restricted profile {ctx['b_or_plasma_cells']}" if restricted_lymphoid else ""),
        'mitigation':'Standard 2nd-gen CAR; IHC top 2 normal tissues before IND',
        'precedent': 'CD19 CAR-T (Kymriah, Yescarta), BCMA CAR-T (Abecma, Carvykti), CD22 CAR-T',
    }

cart_eval = score_cart()
cart_eval['modality'] = 'car-t'

out = {**ctx, 'cart_eval': cart_eval}
with open('cart_eval.json', 'w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase B — CAR-T Viability",
    f"  Verdict:    {cart_eval['verdict']}  (risk={cart_eval['risk_tier']})",
    f"  Reason:     {cart_eval['reason'][:90]}",
    f"  Precedent:  {cart_eval['precedent']}",
]
with open('phaseB_summary.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase C] ADC + Bispecific Eval — score ADC payload tolerability and bispecific TCE viability
process TRIAGE_ADC_BISPECIFIC {
    tag "triage:phaseC"
    label 'process_low'
    publishDir "${params.outdir}/phaseC_adc_bispec", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(cart_json)

    output:
    tuple val(meta), path("adc_bispec_eval.json"), emit: adc_bispec
    path "phaseC_summary.txt",                      emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${cart_json}') as f:
    ctx = json.load(f)

max_high = ctx['max_high']; max_mod = ctx['max_mod']
high_hits = ctx['high_hits']; mod_hits = ctx['mod_hits']

def score_adc():
    if max_high > 2.5:
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Critical-tissue expression too high even for non-bystander payload: {high_hits[:3]}",
            'mitigation':'Bispecific TCE with tunable dose or radiopharm with shorter half-life',
            'precedent': '-',
        }
    if max_high > 0.5:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Moderate critical-tissue expression {max_high:.2f}",
            'mitigation':'Non-bystander payload (MMAF, DM1); DAR 2-3; cardiac/neural monitoring',
            'precedent': 'Kadcyla (DM1) tolerated despite low cardiac HER2',
        }
    if max_mod > 2.0:
        return {
            'verdict':   'VIABLE',
            'risk_tier': 'MEDIUM',
            'reason':    f"Moderate-tissue expression {max_mod:.2f} manageable with payload choice",
            'mitigation':'Bystander+ payload (MMAE) acceptable; GI/skin/hepatic monitoring',
            'precedent': 'Enhertu, Trodelvy approved',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    'Tumor-restricted; clean normal-tissue profile',
        'mitigation':'Standard ADC; payload by potency requirement',
        'precedent': '-',
    }

def score_bispecific_tce():
    if max_high > 1.5:
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Critical-tissue expression too high for T-cell engager: {high_hits[:3]}",
            'mitigation':'Different modality required',
            'precedent': '-',
        }
    if max_high > 0.5 or max_mod > 1.5:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Off-tumor expression present (high={max_high:.2f}, mod={max_mod:.2f})",
            'mitigation':'Step-dose escalation, CRS prophylaxis, on-switch TCE',
            'precedent': 'Tarlatamab (DLL3 TCE), Blinatumomab CRS protocols',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    'Restricted expression; favorable for T-cell engager',
        'mitigation':'Standard step-dose escalation; CRS monitoring',
        'precedent': 'Blinatumomab CD19xCD3 (approved)',
    }

adc_eval = score_adc(); adc_eval['modality'] = 'adc'
bispec_eval = score_bispecific_tce(); bispec_eval['modality'] = 'bispecific'

out = {**ctx, 'adc_eval': adc_eval, 'bispec_eval': bispec_eval}
with open('adc_bispec_eval.json', 'w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase C — ADC + Bispecific Eval",
    f"  ADC verdict:        {adc_eval['verdict']}  ({adc_eval['risk_tier']})",
    f"  Bispecific verdict: {bispec_eval['verdict']}  ({bispec_eval['risk_tier']})",
]
with open('phaseC_summary.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase D] Modality Ranking — composite ranking across all modalities + IHC follow-up panel + final report
process TRIAGE_MODALITY_RANKING {
    tag "triage:phaseD"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(adc_json)

    output:
    tuple val(meta), path("modality_triage_report.json"), emit: report_json
    tuple val(meta), path("modality_ranking.csv"),        emit: ranking_csv
    tuple val(meta), path("modality_triage.txt"),         emit: report
    tuple val(meta), path("ihc_followup_panel.txt"),      emit: ihc_panel
    path "versions.yml",                                    emit: versions

    script:
    """
    python3 << 'PYEOF'
import json, csv

with open('${adc_json}') as f:
    ctx = json.load(f)

profile = ctx['profile']
gene = ctx['target_gene']
indication = ctx['indication']
modalities = ctx['modalities']
max_high = ctx['max_high']; max_mod = ctx['max_mod']
high_hits = ctx['high_hits']; mod_hits = ctx['mod_hits']

def score_protac():
    if max_high > 2.0:
        return {
            'verdict':   'CAUTION', 'risk_tier': 'MEDIUM',
            'reason':    f"Ubiquitous critical-tissue expression: {high_hits[:3]}",
            'mitigation':'VHL-based PROTAC (tumor-enriched) instead of CRBN; tissue-restricted prodrug',
            'precedent': 'ARV-110 (AR, VHL); ARV-471 (ERa, CRBN, tolerated)',
        }
    return {
        'verdict':   'VIABLE', 'risk_tier': 'LOW',
        'reason':    'PROTAC less sensitive to normal-tissue expression than cell therapy / ADC',
        'mitigation':'Standard E3 selection',
        'precedent': 'PROTAC efficacy dominated by ternary complex and PK',
    }

def score_sirna_aso():
    return {
        'verdict':   'VIABLE', 'risk_tier': 'LOW',
        'reason':    'Knockdown modalities not strongly affected by baseline expression; delivery drives tissue exposure',
        'mitigation':'GalNAc (liver), intrathecal (CNS), LNP (muscle/spleen)',
        'precedent': 'Inclisiran (PCSK9), nusinersen (SMN2), givosiran (ALAS1)',
    }

def score_small_molecule():
    return {
        'verdict':   'NEEDS_DRUGGABILITY_CHECK', 'risk_tier': 'NA',
        'reason':    'Small-molecule viability determined by druggability, not normal-tissue expression',
        'mitigation':'Run pocket_detection_druggability or check Druggability Index',
        'precedent': '-',
    }

def score_mab():
    if max_high > 3.0:
        return {
            'verdict':   'CAUTION', 'risk_tier': 'MEDIUM',
            'reason':    f"Very high expression in critical tissue(s): {high_hits[:3]}; verify blockade is intended",
            'mitigation':'Standard mAb; confirm engagement on normal tissue is the therapeutic mechanism',
            'precedent': '-',
        }
    return {
        'verdict':   'VIABLE', 'risk_tier': 'LOW',
        'reason':    f"mAb tolerates broad expression: target blockade is the mechanism (HIGH {max_high:.2f}, MOD {max_mod:.2f})",
        'mitigation':'Standard IgG1/IgG4 scaffold; mechanism-of-action assay',
        'precedent': 'Marstacimab (TFPI), axatilimab (CSF1R), zolbetuximab (CLDN18.2)',
    }

# Assemble all modality evaluations
cart_eval   = ctx['cart_eval']
adc_eval    = ctx['adc_eval']
bispec_eval = ctx['bispec_eval']

ALL_EVALS = {
    'car-t':          cart_eval,
    'adc':            adc_eval,
    'bispecific':     bispec_eval,
    'mab':            {**score_mab(),            'modality': 'mab'},
    'protac':         {**score_protac(),         'modality': 'protac'},
    'sirna':          {**score_sirna_aso(),      'modality': 'sirna'},
    'aso':            {**score_sirna_aso(),      'modality': 'aso'},
    'small_molecule': {**score_small_molecule(), 'modality': 'small_molecule'},
}

if modalities == 'all':
    chosen = list(ALL_EVALS.keys())
else:
    chosen = [m.strip() for m in modalities.split(',') if m.strip() in ALL_EVALS]

results = [ALL_EVALS[m] for m in chosen]

verdict_order = {'VIABLE': 0, 'NEEDS_DRUGGABILITY_CHECK': 1, 'CAUTION': 2, 'REJECT': 3}
results.sort(key=lambda r: verdict_order.get(r['verdict'], 99))

primary = next((r for r in results if r['verdict'] == 'VIABLE'), None)
if primary is None:
    primary = next((r for r in results if r['verdict'] == 'CAUTION'), None)

ihc_tissues = []
for r in sorted(profile, key=lambda x: -x['mean_expression'])[:5]:
    if r['mean_expression'] > 0.5:
        ihc_tissues.append({
            'cell_type':         r['cell_type'],
            'mean_expression':   r['mean_expression'],
            'criticality':       r['tissue_criticality'],
            'antibody_strategy': 'Validate with 2+ orthogonal antibody clones; HPA IHC protocol; cross-check by flow on primary cells',
        })

triage_report = {
    'target_gene':           gene,
    'indication':            indication,
    'atlas_source':          ctx['atlas_source'],
    'n_cell_types_queried':  len(profile),
    'max_critical_expr':     round(max_high, 3),
    'max_moderate_expr':     round(max_mod,  3),
    'critical_tissue_hits':  high_hits,
    'moderate_tissue_hits':  mod_hits,
    'primary_recommendation': primary['modality'] if primary else None,
    'modality_scores':       results,
    'ihc_followup_panel':    ihc_tissues,
    'disclaimers': [
        'Triage tool only - not a substitute for IHC, flow cytometry, or proteomics validation',
        'RNA-level expression; surface protein accessibility not guaranteed',
        'Atlas data is healthy reference; tumor heterogeneity not captured',
        'Confirm with wet-lab on actual tumor cohort + critical normal tissues before IND',
    ],
    'references': [
        'Morgan et al. 2010 Mol Ther 18:843 (HER2 CAR-T cardiopulmonary fatality)',
        'Parkhurst et al. 2011 Mol Ther 19:620 (CEA CAR-T severe colitis)',
        'Lamers et al. 2013 Mol Ther 21:904 (CAIX CAR-T hepatotoxicity)',
        'Hassan et al. 2014 Cancer Immunol Res 2:1062 (MSLN target selection)',
        'Quake lab 2022 Science (Tabula Sapiens)',
        'Hamblett 2004 Clin Cancer Res (ADC DAR-PK relationship)',
        'Bondeson & Crews 2017 Annu Rev Pharmacol (PROTAC design)',
    ],
}

with open('modality_triage_report.json', 'w') as f:
    json.dump(triage_report, f, indent=2)

with open('modality_ranking.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['modality', 'verdict', 'risk_tier', 'reason',
                                       'mitigation', 'precedent'])
    w.writeheader()
    w.writerows(results)

verdict_sym = {'VIABLE': '+', 'CAUTION': '!', 'REJECT': 'x', 'NEEDS_DRUGGABILITY_CHECK': '?'}
lines = [
    "================================================================",
    "  Modality Triage Report",
    f"  Target: {gene}   |   Indication: {indication}",
    "================================================================",
    "",
    f"  Atlas source:           {ctx['atlas_source']}",
    f"  Cell types analyzed:    {len(profile)}",
    f"  Max critical expr:      {max_high:.2f}  in {len(high_hits)} cell type(s)",
    f"  Max moderate expr:      {max_mod:.2f}  in {len(mod_hits)} cell type(s)",
    "",
    f"  Primary recommendation: {primary['modality'].upper() if primary else 'none viable'}",
    "",
    "-- Per-Modality Verdicts --",
]
for r in results:
    sym = verdict_sym.get(r['verdict'], '?')
    lines.append(f"  {sym}  {r['modality']:<18} -> {r['verdict']:<26} risk={r['risk_tier']}")
    lines.append(f"     reason:     {r['reason'][:80]}")
    if r.get('mitigation'):
        lines.append(f"     mitigation: {r['mitigation'][:80]}")
    lines.append("")

lines += ["-- IHC Follow-Up Required --",
          "  Confirm top expressing tissues before any clinical/IND commitment:"]
for h in ihc_tissues:
    lines.append(f"  * {h['cell_type']:<28} (mean RNA {h['mean_expression']:.2f}, {h['criticality']})")

lines += ["", "-- Honest Disclaimers --"] + [f"  * {d}" for d in triage_report['disclaimers']]
lines += ["", "-- References --"] + [f"  - {r}" for r in triage_report['references']]

with open('modality_triage.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')

with open('ihc_followup_panel.txt', 'w') as f:
    f.write(f"IHC Follow-Up Panel for {gene}\\n")
    f.write("=" * 60 + "\\n\\n")
    if not ihc_tissues:
        f.write("No tissues show measurable RNA expression - no IHC panel required.\\n")
    else:
        f.write("Tissues to validate by IHC before committing to clinical development:\\n\\n")
        for h in ihc_tissues:
            f.write(f"  Tissue:        {h['cell_type']}\\n")
            f.write(f"  Mean RNA:      {h['mean_expression']:.2f}  (criticality: {h['criticality']})\\n")
            f.write(f"  Strategy:      {h['antibody_strategy']}\\n\\n")
    f.write("\\nReference: Human Protein Atlas (proteinatlas.org) for validated antibody clones.\\n")

print('\\n'.join(lines))
PYEOF

    python3 -c "print('modality_triage: 2.0')" > versions.yml
    """
}

workflow {
    meta = [id: 'modality_triage_run']
    Channel.value(meta) | TRIAGE_ATLAS_PROFILE
    TRIAGE_ATLAS_PROFILE.out.context   | TRIAGE_CART_VIABILITY
    TRIAGE_CART_VIABILITY.out.cart     | TRIAGE_ADC_BISPECIFIC
    TRIAGE_ADC_BISPECIFIC.out.adc_bispec | TRIAGE_MODALITY_RANKING
}
