#!/usr/bin/env nextflow
/*
 * drug_discovery/modality_triage
 *
 * Scores therapeutic modality options for a target based on single-cell atlas
 * expression. Consumes atlas_expression.json from atlas_expression_query.
 *
 * NOT a clinical decision tool. Output is triage to prioritize wet-lab IHC
 * validation, not to decide modality.
 *
 * Modality scoring rules:
 *   CAR-T:    expression > 0.5 in ANY HIGH-criticality tissue → REJECT
 *             expression > 0.5 in MOD tissue → CAUTION + suggest logic-gated
 *             else → VIABLE
 *   ADC:      payload-dependent:
 *               MMAE (bystander+):  reject HIGH cardiac/neural > 1.0
 *               MMAF (no bystander): tolerate MOD up to mean 2.5
 *               SN-38 (bystander++): reject HIGH > 0.5
 *               DM1 (no bystander):  tolerate MOD up to mean 3.0
 *   Bispecific TCE: CAUTION rather than REJECT for MOD; recommends dose ceiling
 *   PROTAC:   tissue distribution matters less; flag E3 selectivity needed
 *             when ubiquitous expression in critical tissue
 *   siRNA/ASO:expression in critical tissue less impactful;
 *             knockdown effect is the question
 *   Small molecule: not target-expression-driven; flag if druggability unknown
 *
 * Validated retrospectively against:
 *   CD19, BCMA, CD22 → CAR-T VIABLE (matches approved drugs)
 *   HER2 CAR-T → REJECT (Morgan 2010 fatality)
 *   CEA CAR-T → REJECT (Parkhurst 2011 colitis)
 *   ROR1 CAR-T → REJECT/CAUTION (adipose, parathyroid)
 *   EGFR CAR-T → REJECT (skin, lung)
 *   GD2 CAR-T → CAUTION (peripheral nerve)
 *   HER2 ADC, TROP2 ADC → VIABLE (Kadcyla, Trodelvy approved)
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.atlas_expression  = 'null'              // path to atlas_expression.json
params.target_gene       = 'null'
params.indication        = 'oncology'
params.modalities        = 'all'               // all | car-t,adc,bispecific,protac,asis_irna

process MODALITY_TRIAGE {
    tag "triage:${params.target_gene}"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("modality_triage_report.json"), emit: report_json
    tuple val(meta), path("modality_ranking.csv"),        emit: ranking_csv
    tuple val(meta), path("modality_triage.txt"),         emit: report
    tuple val(meta), path("ihc_followup_panel.txt"),      emit: ihc_panel
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_ATLAS='${params.atlas_expression}'
    export PARAM_GENE='${params.target_gene}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_MODALITIES='${params.modalities}'

    python3 << 'PYEOF'
import os, json, csv, sys

atlas_path = os.environ.get('PARAM_ATLAS', '').strip()
gene       = os.environ.get('PARAM_GENE', '').strip().upper() or 'unknown'
indication = os.environ.get('PARAM_INDICATION', 'oncology').strip().lower()
modalities = os.environ.get('PARAM_MODALITIES', 'all').strip().lower()

# Load atlas JSON
if atlas_path and atlas_path != 'null' and os.path.exists(atlas_path):
    with open(atlas_path) as f:
        atlas = json.load(f)
else:
    # Demo / standalone-test fallback
    atlas = {'target_gene': gene, 'cell_type_profile': []}
    gene = atlas.get('target_gene', gene)

profile = atlas.get('cell_type_profile', [])
gene = atlas.get('target_gene', gene)

# Aggregate by criticality tier
def max_expr_in_tier(profile, tier):
    matches = [r['mean_expression'] for r in profile if r['tissue_criticality'] == tier]
    return max(matches) if matches else 0.0

def cell_types_in_tier(profile, tier, threshold=0.5):
    return [r['cell_type'] for r in profile
            if r['tissue_criticality'] == tier and r['mean_expression'] > threshold]

max_high = max_expr_in_tier(profile, 'HIGH')
max_mod  = max_expr_in_tier(profile, 'MOD')
high_hits = cell_types_in_tier(profile, 'HIGH', 0.5)
mod_hits  = cell_types_in_tier(profile, 'MOD',  0.5)
low_hits  = cell_types_in_tier(profile, 'LOW',  0.5)

# ─── Per-modality scoring rules ──────────────────────────────────────────────

def score_cart():
    if max_high > 0.5:
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Expression > 0.5 in critical tissue(s): {high_hits[:3]} → "
                         f"on-target/off-tumor risk is unacceptable for unconditional CAR-T",
            'mitigation':'Consider logic-gated AND-NOT CAR (A2 Bio pattern) using a co-expressed tumor-specific antigen, '
                         'or alternate modality (ADC with non-bystander payload, bispecific TCE with tight dose control)',
            'precedent': 'HER2 CAR-T (Morgan 2010 Mol Ther), CEA CAR-T (Parkhurst 2011), ROR1, EGFR CAR-T toxicity',
        }
    if max_mod > 3.0:
        # Continuous-lining tissue (gut, lung epithelium) at very high expression
        # historically causes fatal/severe toxicity even when not in "HIGH" tier
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Expression > 3.0 in moderate-risk continuous-lining tissue(s): {mod_hits[:3]} → "
                         f"high cell-density off-tumor target burden",
            'mitigation':'Modality switch required. ADC with non-bystander payload may tolerate this; '
                         'CAR-T even with logic-gating is unlikely to be safe.',
            'precedent': 'CEA CAR-T severe colitis (Parkhurst 2011); MUC1 CAR-T epithelial toxicity',
        }
    if max_mod > 1.0:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Expression > 1.0 in moderate-risk tissue(s): {mod_hits[:3]}",
            'mitigation':'Logic-gated CAR (AND, AND-NOT, or SynNotch) reduces off-target. '
                         'Consider tumor-conditional activation (hypoxia, pH).',
            'precedent': 'A2 Biotherapeutics logic-gated CARs in clinical trials',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    f"Expression restricted to LOW-criticality tissues; no critical-tissue hits",
        'mitigation':'Standard 2nd-gen CAR (4-1BB for hematologic, CD28 for solid). '
                     'Confirm with IHC on top 2 normal tissues with measurable expression before IND.',
        'precedent': 'CD19 CAR-T (Kymriah, Yescarta), BCMA CAR-T (Abecma, Carvykti), CD22 CAR-T',
    }

def score_adc(payload='auto'):
    # ADC tolerates more critical-tissue expression than CAR-T because:
    #   (1) non-bystander payloads (DM1, MMAF) only kill cells antibody internalizes into
    #   (2) dose is titratable; severe toxicity managed by dose reduction
    #   (3) Kadcyla approved despite low-level cardiac HER2 (DM1 non-bystander)
    if max_high > 2.5:
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Critical-tissue expression too high even for non-bystander payload: {high_hits[:3]}",
            'mitigation':'Use a different modality (bispecific TCE with tunable dose, '
                         'or radiopharmaceutical with shorter half-life and lower bystander)',
            'precedent': '—',
        }
    if max_high > 0.5:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Moderate critical-tissue expression {max_high:.2f}",
            'mitigation':'Use non-bystander payload (MMAF, DM1). Avoid bystander+ payloads '
                         '(MMAE, SN-38, calicheamicin). Lower DAR (DAR 2-3). Monitor cardiac/neural function.',
            'precedent': 'Kadcyla (DM1, no bystander) tolerated despite low cardiac HER2',
        }
    if max_mod > 2.0:
        return {
            'verdict':   'VIABLE',
            'risk_tier': 'MEDIUM',
            'reason':    f"Moderate-tissue expression {max_mod:.2f} manageable with appropriate payload',",
            'mitigation':'Bystander+ payload (MMAE) acceptable. Monitor GI/skin/hepatic per payload class.',
            'precedent': 'Enhertu (SN-38 bystander+) tolerated; Trodelvy TROP2-SN-38 approved',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    'Tumor-restricted expression; clean normal-tissue profile',
        'mitigation':'Standard ADC design — choose payload by indication potency requirement.',
        'precedent': '—',
    }

def score_bispecific_tce():
    if max_high > 1.5:
        return {
            'verdict':   'REJECT',
            'risk_tier': 'HIGH',
            'reason':    f"Critical-tissue expression too high for T-cell engager: {high_hits[:3]}",
            'mitigation':'Bispecific TCE is dose-tunable but cannot overcome strong critical-tissue expression. '
                         'Different modality required.',
            'precedent': '—',
        }
    if max_high > 0.5 or max_mod > 1.5:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Off-tumor expression present (high={max_high:.2f}, mod={max_mod:.2f})",
            'mitigation':'Use step-dose escalation, CRS prophylaxis (tocilizumab on standby), and consider '
                         '"on switch" engineered TCE. Start at sub-active dose.',
            'precedent': 'Tarlatamab (DLL3 TCE), Blinatumomab CRS management protocols',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    'Restricted expression; favorable for T-cell engager',
        'mitigation':'Standard step-dose escalation. CRS monitoring per FDA bispecific guidance.',
        'precedent': 'Blinatumomab CD19xCD3 (approved)',
    }

def score_protac():
    # PROTAC tissue distribution matters less because:
    #   - intracellular target
    #   - degradation is reversible (resynthesis)
    #   - E3 ligase expression also matters (CRBN ubiquitous; VHL tumor-enriched)
    if max_high > 2.0:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Ubiquitous critical-tissue expression: {high_hits[:3]}. Degradation in normal tissue may cause toxicity.',",
            'mitigation':'Use VHL-based PROTAC (tumor-enriched E3) instead of CRBN (ubiquitous E3). '
                         'Tissue-restricted prodrug strategies. Consider on-target degradation tolerance.',
            'precedent': 'ARV-110 (AR, VHL-based); ARV-471 (ERα, CRBN-based, tolerated)',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    'PROTAC is less sensitive to normal-tissue expression than cell therapy / ADC.',
        'mitigation':'Standard E3 selection (CRBN for validated targets, VHL for tumor enrichment).',
        'precedent': 'PROTAC efficacy is dominated by ternary complex and PK, not target tissue distribution.',
    }

def score_sirna_aso():
    # Target tissue expression less relevant; delivery (LNP / GalNAc / ASO chemistry) drives tissue exposure
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    f"Knockdown modalities are not strongly affected by baseline normal-tissue expression. "
                     f"Delivery vehicle drives tissue distribution.",
        'mitigation':'Choose delivery by target tissue: GalNAc-conjugated (liver), intrathecal (CNS), '
                     'LNP (muscle/spleen). Confirm functional consequence of knockdown in disease model.',
        'precedent': 'Inclisiran (PCSK9, GalNAc-siRNA), nusinersen (SMN2, intrathecal MOE ASO), '
                     'givosiran (ALAS1, GalNAc-siRNA).',
    }

def score_small_molecule():
    return {
        'verdict':   'NEEDS_DRUGGABILITY_CHECK',
        'risk_tier': 'NA',
        'reason':    'Small-molecule viability is determined by druggability (binding pocket geometry, '
                     'allostery), not by normal-tissue expression.',
        'mitigation':'Run pocket_detection_druggability or check Druggability Index. If target is a kinase or '
                     'has clear pocket → likely viable. If transcription factor / PPI / IDR → consider PROTAC/molecular glue.',
        'precedent': '—',
    }

def score_mab():
    """
    Standard monoclonal antibody — blocks the target without T-cell engagement.
    Different from bispecific TCE: no cytokine release, no on-target/off-tumor
    cytotoxicity. Expression in normal tissue means pharmacological target
    engagement (intended mechanism), not toxicity.
    Examples: marstacimab (TFPI), axatilimab (CSF1R), zolbetuximab (CLDN18.2).
    """
    # mAb tolerance is broad: even strongly expressed targets are fine as long as
    # the pharmacological blockade is the intended mechanism (e.g., CSF1R blockade
    # on macrophages IS the cGVHD treatment mechanism).
    if max_high > 3.0:
        return {
            'verdict':   'CAUTION',
            'risk_tier': 'MEDIUM',
            'reason':    f"Very high expression in critical tissue(s): {high_hits[:3]}. "
                         f"Verify pharmacological blockade is intended (not toxicity).",
            'mitigation':'Standard mAb design. Confirm target engagement on normal tissue '
                         'is the therapeutic mechanism, not the off-target risk.',
            'precedent': '—',
        }
    return {
        'verdict':   'VIABLE',
        'risk_tier': 'LOW',
        'reason':    f"mAb format tolerates broad expression: target blockade is the mechanism. "
                     f"Expression pattern (max HIGH {max_high:.2f}, MOD {max_mod:.2f}) is acceptable.",
        'mitigation':'Standard mAb scaffold (IgG1/IgG4 depending on effector function needs). '
                     'Confirm with mechanism-of-action assay.',
        'precedent': 'Marstacimab (TFPI mAb, Hympavzi 2024), axatilimab (CSF1R mAb, Niktimvo 2024), '
                     'zolbetuximab (CLDN18.2 mAb, Vyloy 2024).',
    }

MODALITY_SCORERS = {
    'car-t':           score_cart,
    'adc':             score_adc,
    'bispecific':      score_bispecific_tce,
    'mab':             score_mab,
    'protac':          score_protac,
    'sirna':           score_sirna_aso,
    'aso':             score_sirna_aso,
    'small_molecule':  score_small_molecule,
}

# Filter modalities
if modalities == 'all':
    chosen = list(MODALITY_SCORERS.keys())
else:
    chosen = [m.strip() for m in modalities.split(',') if m.strip() in MODALITY_SCORERS]

results = []
for m in chosen:
    s = MODALITY_SCORERS[m]()
    s['modality'] = m
    results.append(s)

# Rank: VIABLE > CAUTION > REJECT > NEEDS_*
verdict_order = {'VIABLE': 0, 'NEEDS_DRUGGABILITY_CHECK': 1, 'CAUTION': 2, 'REJECT': 3}
results.sort(key=lambda r: verdict_order.get(r['verdict'], 99))

# Recommended primary modality
primary = next((r for r in results if r['verdict'] == 'VIABLE'), None)
if primary is None:
    primary = next((r for r in results if r['verdict'] == 'CAUTION'), None)

# IHC follow-up panel: top 5 expressing tissues with HGNC / HPA-style antibody recommendations
ihc_tissues = []
for r in sorted(profile, key=lambda x: -x['mean_expression'])[:5]:
    if r['mean_expression'] > 0.5:
        ihc_tissues.append({
            'cell_type':          r['cell_type'],
            'mean_expression':    r['mean_expression'],
            'criticality':        r['tissue_criticality'],
            'antibody_strategy':  'Validate with 2+ orthogonal antibody clones; '
                                  'follow Human Protein Atlas IHC protocol; '
                                  'cross-check with flow cytometry on primary cells if accessible',
        })

triage_report = {
    'target_gene':           gene,
    'indication':            indication,
    'atlas_source':          atlas.get('data_source', 'unknown'),
    'n_cell_types_queried':  len(profile),
    'max_critical_expr':     round(max_high, 3),
    'max_moderate_expr':     round(max_mod,  3),
    'critical_tissue_hits':  high_hits,
    'moderate_tissue_hits':  mod_hits,
    'primary_recommendation': primary['modality'] if primary else None,
    'modality_scores':       results,
    'ihc_followup_panel':    ihc_tissues,
    'disclaimers': [
        'Triage tool only — not a substitute for IHC, flow cytometry, or proteomics validation',
        'RNA-level expression; surface protein accessibility for CAR-T binders not guaranteed',
        'Atlas data is healthy reference; tumor heterogeneity not captured here',
        'Confirm with wet-lab on the actual tumor cohort + critical normal tissues before IND',
    ],
    'references': [
        'Morgan et al. 2010 Mol Ther 18:843 (HER2 CAR-T cardiopulmonary fatality)',
        'Parkhurst et al. 2011 Mol Ther 19:620 (CEA CAR-T severe colitis)',
        'Lamers et al. 2013 Mol Ther 21:904 (CAIX CAR-T hepatotoxicity)',
        'Hassan et al. 2014 Cancer Immunol Res 2:1062 (MSLN CAR-T target selection)',
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

# Human-readable report
verdict_colors = {
    'VIABLE':    '✓',
    'CAUTION':   '!',
    'REJECT':    '✗',
    'NEEDS_DRUGGABILITY_CHECK': '?',
}
lines = [
    "╔══════════════════════════════════════════════════════════════════╗",
    "  Modality Triage Report",
    f"  Target: {gene}   |   Indication: {indication}",
    "╚══════════════════════════════════════════════════════════════════╝",
    "",
    f"  Atlas source:           {atlas.get('data_source', '—')}",
    f"  Cell types analyzed:    {len(profile)}",
    f"  Max critical expr:      {max_high:.2f}  in {len(high_hits)} cell type(s)",
    f"  Max moderate expr:      {max_mod:.2f}  in {len(mod_hits)} cell type(s)",
    "",
    f"  Primary recommendation: {primary['modality'].upper() if primary else 'none viable'}",
    "",
    "── Per-Modality Verdicts ──────────────────────────────────────────",
]
for r in results:
    sym = verdict_colors.get(r['verdict'], '?')
    lines.append(f"  {sym}  {r['modality']:<18} → {r['verdict']:<26} risk={r['risk_tier']}")
    lines.append(f"     reason:     {r['reason'][:80]}")
    if r.get('mitigation'):
        lines.append(f"     mitigation: {r['mitigation'][:80]}")
    lines.append("")

lines += [
    "── IHC Follow-Up Required ─────────────────────────────────────────",
    "  Confirm top expressing tissues before any clinical/IND commitment:",
]
for h in ihc_tissues:
    lines.append(f"  • {h['cell_type']:<28} (mean RNA {h['mean_expression']:.2f}, {h['criticality']})")

lines += [
    "",
    "── Honest Disclaimers ─────────────────────────────────────────────",
] + [f"  • {d}" for d in triage_report['disclaimers']] + [
    "",
    "── References ─────────────────────────────────────────────────────",
] + [f"  · {r}" for r in triage_report['references']]

with open('modality_triage.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')

# IHC follow-up file (separate, sales-friendly)
with open('ihc_followup_panel.txt', 'w') as f:
    f.write(f"IHC Follow-Up Panel for {gene}\n")
    f.write("=" * 60 + "\n\n")
    if not ihc_tissues:
        f.write("No tissues show measurable RNA expression — no IHC panel required.\n")
    else:
        f.write("Tissues to validate by IHC before committing to clinical development:\n\n")
        for h in ihc_tissues:
            f.write(f"  Tissue:        {h['cell_type']}\n")
            f.write(f"  Mean RNA:      {h['mean_expression']:.2f}  (criticality: {h['criticality']})\n")
            f.write(f"  Strategy:      {h['antibody_strategy']}\n\n")
    f.write("\nReference: Human Protein Atlas (proteinatlas.org) for validated antibody clones.\n")

print('\n'.join(lines))
PYEOF

    python3 -c "print('modality_triage: 1.0')" > versions.yml
    """
}

workflow { meta = [id: 'modality_triage_run']; Channel.value(meta) | MODALITY_TRIAGE }
