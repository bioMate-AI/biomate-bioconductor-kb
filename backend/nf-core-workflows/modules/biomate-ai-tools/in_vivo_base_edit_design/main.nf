#!/usr/bin/env nextflow
/*
 * drug_discovery/in_vivo_base_edit_design
 *
 * Workflow for designing in vivo CRISPR base editing therapeutics.
 * Recovers the Verve VERVE-101/102 (PCSK9), VERVE-201 (ANGPTL3), and
 * Beam BEAM-101 (HBG1/2 sickle cell) clinical designs from inputs.
 *
 * Algorithm:
 *   1. Atlas tissue restriction check on target gene
 *   2. Editor class selection (CBE / ABE / prime editing) based on edit goal
 *   3. Delivery vehicle decision matrix (LNP IV, ex vivo HSC, AAV9, intrathecal)
 *   4. Guide RNA + off-target check recommendation (routes to crisprScore)
 *   5. IND-readiness checklist
 *
 * References:
 *   - Verve VERVE-101 / VERVE-102 (PCSK9 CBE, hepatocyte LNP, IV)
 *   - Verve VERVE-201 (ANGPTL3)
 *   - Beam BEAM-101 (HBG1/2 ABE, ex vivo HSC)
 *   - Intellia NTLA-2001 (TTR, LNP-CRISPR, IV)
 *   - Editas EDIT-301 (HbF via BCL11A enhancer)
 *   - Komor et al. 2016 Nature (CBE)
 *   - Gaudelli et al. 2017 Nature (ABE)
 *   - Anzalone et al. 2019 Nature (Prime editing)
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.target_gene       = 'null'
params.edit_goal         = 'loss_of_function'   // loss_of_function | gain_of_function | gene_correction | regulatory_modification
params.indication        = 'undefined'
params.delivery          = 'auto'                // lnp_iv_hepatocyte | lnp_intrathecal | aav9_muscle | aav9_cns | ex_vivo_hsc | auto
params.editor_preference = 'auto'                // cbe | abe | prime | auto

process IN_VIVO_BASE_EDIT_DESIGN {
    tag "base_edit:${params.target_gene}"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("base_edit_design.json"),       emit: design_json
    tuple val(meta), path("editor_choice.txt"),           emit: editor_choice
    tuple val(meta), path("delivery_plan.txt"),           emit: delivery_plan
    tuple val(meta), path("ind_readiness_checklist.txt"), emit: ind_checklist
    tuple val(meta), path("base_edit_design.txt"),        emit: report
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_GENE='${params.target_gene}'
    export PARAM_GOAL='${params.edit_goal}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_DELIVERY='${params.delivery}'
    export PARAM_EDITOR='${params.editor_preference}'

    python3 << 'PYEOF'
import os, json

gene       = os.environ.get('PARAM_GENE', '').strip().upper() or 'PCSK9'
goal       = os.environ.get('PARAM_GOAL', 'loss_of_function').strip().lower()
indication = os.environ.get('PARAM_INDICATION', 'undefined').strip().lower()
delivery   = os.environ.get('PARAM_DELIVERY', 'auto').strip().lower()
editor_pref= os.environ.get('PARAM_EDITOR', 'auto').strip().lower()

# ─── Atlas tissue restriction lookup (mirror of atlas_expression_query cache) ─
# Only fields needed for delivery decision (max-expressing tissue + tier)
ATLAS_TISSUE = {
    'PCSK9':   {'primary_tissue': 'hepatocyte',     'tier': 'MOD', 'note': 'Liver-restricted; ideal LNP IV target'},
    'ANGPTL3': {'primary_tissue': 'hepatocyte',     'tier': 'MOD', 'note': 'Liver-restricted; VERVE-201 precedent'},
    'APOC3':   {'primary_tissue': 'hepatocyte',     'tier': 'MOD', 'note': 'Liver-restricted; olezarsen ASO precedent'},
    'LPA':     {'primary_tissue': 'hepatocyte',     'tier': 'MOD', 'note': 'Liver-restricted (Lp(a) lowering)'},
    'TTR':     {'primary_tissue': 'hepatocyte',     'tier': 'MOD', 'note': 'Liver-restricted; Intellia NTLA-2001 precedent'},
    'HBG1':    {'primary_tissue': 'erythroid_progenitor', 'tier': 'MOD', 'note': 'Hematopoietic; ex vivo HSC required'},
    'HBG2':    {'primary_tissue': 'erythroid_progenitor', 'tier': 'MOD', 'note': 'Hematopoietic; ex vivo HSC required'},
    'BCL11A':  {'primary_tissue': 'erythroid_progenitor', 'tier': 'MOD', 'note': 'Erythroid enhancer target; Casgevy/CTX001 precedent'},
    'HBB':     {'primary_tissue': 'erythroid_progenitor', 'tier': 'MOD', 'note': 'Beta-globin; ex vivo HSC; Beam BEAM-201'},
    'CFTR':    {'primary_tissue': 'lung_bronchial_epi', 'tier': 'MOD', 'note': 'Cystic fibrosis target; lung delivery hard'},
    'DMD':     {'primary_tissue': 'cardiac_muscle_cell','tier': 'HIGH','note': 'Duchenne; AAV-rh74 muscle precedent'},
    'SMN1':    {'primary_tissue': 'motor_neuron',   'tier': 'HIGH','note': 'SMA; AAV9 IV / IT precedent (Zolgensma analogue)'},
    'TARDBP':  {'primary_tissue': 'cerebral_cortex_neuron','tier':'HIGH','note': 'ALS target; CNS delivery required'},
    'HTT':     {'primary_tissue': 'cerebral_cortex_neuron','tier':'HIGH','note': 'Huntington target; intrathecal AAV9 or LNP'},
    'SOD1':    {'primary_tissue': 'motor_neuron',   'tier': 'HIGH','note': 'ALS target; intrathecal'},
}

atlas = ATLAS_TISSUE.get(gene, {'primary_tissue':'unknown','tier':'LOW',
                                'note':'No atlas cache entry; assume broad expression'})

# ─── Editor class selection ──────────────────────────────────────────────────

EDITOR_RULES = {
    'loss_of_function': {
        # LoF via stop codon → CBE (C→T) is preferred. Alternative: splice disruption.
        'editor':     'cbe',
        'mechanism':  'Premature stop codon: CAA→TAA, CAG→TAG, or CGA→TGA via C→T transition on coding strand. '
                      'Alternative: splice donor disruption (GT→AT) for exon skipping.',
        'pam':        'SpCas9 NGG (canonical); SpRY for relaxed PAM if needed',
        'efficiency': '40-60% editing typical in hepatocyte; 20-40% in HSC ex vivo',
        'precedent':  'Verve VERVE-101/102 PCSK9 (CBE W8X stop), VERVE-201 ANGPTL3 (CBE)',
    },
    'gain_of_function': {
        # GoF via correction or enhancer activation
        'editor':     'abe',
        'mechanism':  'A→G correction of pathogenic G→A variant. Or enhancer activation via base-edit'
                      ' regulatory site.',
        'pam':        'SpCas9 NGG; ABE8e variant for higher activity',
        'efficiency': '30-50% in hepatocyte; 15-30% in HSC',
        'precedent':  'Disease correction via ABE — multiple academic Phase 1',
    },
    'gene_correction': {
        'editor':     'abe',
        'mechanism':  'Most pathogenic SNVs are G→A or C→T transitions. ABE corrects G→A (A→G to restore). '
                      'CBE corrects C→T (G→A on antisense).',
        'pam':        'SpCas9 NGG; consider Cas12-derived editors for AT-rich windows',
        'efficiency': '20-50% depending on context',
        'precedent':  'Multiple research-stage corrections',
    },
    'regulatory_modification': {
        # HbF reactivation via BCL11A or HBG enhancer — Beam BEAM-101 precedent
        'editor':     'abe',
        'mechanism':  'Modify regulatory SNVs (e.g., HBG1/2 -175 GATA enhancer; BCL11A +58 erythroid enhancer). '
                      'Disrupts transcription factor binding to derepress target gene.',
        'pam':        'SpCas9 NGG; pick SNV based on TF footprint mapping',
        'efficiency': '60-80% editing in HSC ex vivo (BEAM-101 reported)',
        'precedent':  'Beam BEAM-101 (HBG1/2 ABE for sickle cell), Editas EDIT-301 (BCL11A erythroid enhancer)',
    },
}

rule = EDITOR_RULES.get(goal, EDITOR_RULES['loss_of_function'])

# Override if user specified
if editor_pref in ('cbe', 'abe', 'prime'):
    rule = dict(rule)
    rule['editor'] = editor_pref
    if editor_pref == 'prime':
        rule['mechanism'] = 'Prime editing — search-and-replace, can install any base-to-base change ' \
                            'plus small insertions/deletions. Lower efficiency (15-30%) than CBE/ABE.'
        rule['efficiency'] = '10-25% in hepatocyte; lower in HSC. Use only when CBE/ABE cannot.'

# ─── Delivery vehicle decision ───────────────────────────────────────────────

DELIVERY_MATRIX = {
    'hepatocyte': {
        'recommended': 'lnp_iv_hepatocyte',
        'lnp_chemistry': 'MC3-class or biodegradable ionizable lipid (VERVE-102 reformulation); '
                         'Onpattro/Spikevax-class LNPs reach hepatocytes via ApoE-LDLR uptake',
        'route':         'Intravenous infusion',
        'cmc_flag':      'VERVE-101 LFT elevation (Nov 2023) → optimize LNP for lower hepatotoxicity '
                         '(reduced PEG, alternative ionizable lipid). VERVE-102 addressed this.',
        'precedent':     'VERVE-101/102 (PCSK9), VERVE-201 (ANGPTL3), Intellia NTLA-2001 (TTR), '
                         'Intellia NTLA-2002 (KLKB1)',
    },
    'erythroid_progenitor': {
        'recommended': 'ex_vivo_hsc',
        'lnp_chemistry': 'N/A — electroporation of mRNA + gRNA into autologous CD34+ HSCs',
        'route':         'Ex vivo edit + autologous transplant',
        'cmc_flag':      'Requires myeloablative conditioning. Manufacturing: leukapheresis → CD34 selection → '
                         'electroporation → release testing → reinfusion. Capital-intensive.',
        'precedent':     'Casgevy (exa-cel CRISPR), BEAM-101 (HBG1/2 ABE), EDIT-301 (BCL11A)',
    },
    'cardiac_muscle_cell': {
        'recommended': 'aav9_iv',
        'lnp_chemistry': 'N/A — AAV9 capsid; consider engineered AAV-MYO',
        'route':         'IV (cardiac tropism); titer 1e13-1e14 vg/kg',
        'cmc_flag':      'AAV manufacturing scale; cardiac dose-limited; anti-AAV9 NAbs in ~30% of patients',
        'precedent':     'Elevidys AAVrh74 muscle (DMD); cardiac Duchenne pipelines',
    },
    'motor_neuron': {
        'recommended': 'aav9_intrathecal',
        'lnp_chemistry': 'N/A — AAV9; emerging intrathecal LNP (e.g., Verve VERVE-302)',
        'route':         'Intrathecal infusion; lower dose vs IV cardiac',
        'cmc_flag':      'CSF distribution validation required; intrathecal AAV established for SMA',
        'precedent':     'Zolgensma AAV9 (SMA IV in infants → IT in older patients)',
    },
    'cerebral_cortex_neuron': {
        'recommended': 'aav9_intrathecal',
        'lnp_chemistry': 'N/A; intrathecal LNP under development',
        'route':         'Intrathecal infusion or convection-enhanced delivery',
        'cmc_flag':      'CNS distribution heterogeneity; partial coverage typical',
        'precedent':     'AAV9 intrathecal for SOD1 ALS (Wave Life Sciences ASO precedent for delivery route)',
    },
    'lung_bronchial_epi': {
        'recommended': 'aerosol_lnp',
        'lnp_chemistry': 'Inhaled LNP — under development (Translate Bio / Sanofi for CF)',
        'route':         'Inhalation; lung-specific lipid composition',
        'cmc_flag':      'Aerosol manufacturing; deposition heterogeneity; mucus barrier',
        'precedent':     'Inhaled mRNA CFTR programs (Phase 1/2)',
    },
    'unknown': {
        'recommended': 'tbd',
        'lnp_chemistry': 'Atlas tissue context required',
        'route':         'TBD',
        'cmc_flag':      'No atlas precedent for this target',
        'precedent':     '—',
    },
}

delivery_choice = DELIVERY_MATRIX.get(atlas['primary_tissue'], DELIVERY_MATRIX['unknown'])

# User override
if delivery != 'auto':
    delivery_choice = dict(delivery_choice)
    delivery_choice['recommended'] = delivery
    delivery_choice['note'] = 'User override applied; verify atlas tissue match'

# ─── Guide RNA + off-target recommendation ──────────────────────────────────

grna_rec = {
    'recommendation': f"Design gRNA spacer at editor activity window (positions 4-8 from PAM-distal end). "
                      f"For {gene} {goal}: target the codon at the edit site. "
                      f"Run BioMate `crisprScore` workflow for on-target (Azimuth/DeepHF) and off-target "
                      f"(CFD / MIT) scoring before locking the lead guide.",
    'off_target_check':'Atlas-driven off-target scan: query atlas_expression_query for any gene with '
                       f"similar sequence (homology >85% in seed region) AND expression in critical tissue. "
                       'Flag for IND submission.',
    'pam_strategy':   rule['pam'],
}

# ─── IND-readiness checklist ────────────────────────────────────────────────

ind_checklist = [
    '── Preclinical Pharmacology ──',
    '  ☐ In vitro editing efficiency (HepG2 or primary hepatocytes for liver target)',
    '  ☐ Off-target genome-wide profiling (GUIDE-seq, CIRCLE-seq, or DISCOVER-seq)',
    '  ☐ Long-read sequencing for large structural variants at on-target site',
    '  ☐ Editing durability in primary cells (≥3 months in vitro)',
    '  ☐ Functional readout for therapeutic effect (e.g., serum LDL for PCSK9)',
    '',
    '── Toxicology ──',
    '  ☐ GLP single-dose tox in 2 species (typically NHP + rodent)',
    '  ☐ Liver enzyme monitoring (LFT) — VERVE-101 lesson',
    '  ☐ Immunogenicity to LNP components (anti-PEG antibodies)',
    '  ☐ p53 activation assay (DSB-induced; usually low for base editors)',
    '',
    '── CMC ──',
    '  ☐ mRNA cap structure (CleanCap AG / Cap1)',
    '  ☐ Pseudouridine modification (m1Ψ) per Karikó',
    '  ☐ LNP characterization (size, PDI, encapsulation efficiency)',
    '  ☐ gRNA chemical modification (2′-OMe, PS at termini)',
    '  ☐ Bioanalytical method for editing quantification',
    '',
    '── Regulatory ──',
    '  ☐ FDA pre-IND meeting (recommended for novel chemistry)',
    '  ☐ CBER division for cell/gene therapy',
    '  ☐ Genotoxicity follow-up plan (CRISPR risk assessment)',
    '  ☐ Long-term follow-up commitment (15 years for gene therapy)',
]

# ─── Assemble outputs ────────────────────────────────────────────────────────

design = {
    'target_gene':        gene,
    'edit_goal':          goal,
    'indication':         indication,
    'atlas_tissue':       atlas,
    'editor_recommendation': rule,
    'delivery_plan':      delivery_choice,
    'grna_strategy':      grna_rec,
    'modality_class':     f"In vivo base editing ({rule['editor'].upper()}) via {delivery_choice['recommended']}",
    'precedents_recovered': [
        rule.get('precedent', ''),
        delivery_choice.get('precedent', ''),
    ],
    'disclaimers': [
        'In vivo base editing is permanent — no opportunity for dose reduction after administration',
        'LNP chemistry critical; VERVE-101 LFT signal informed VERVE-102 reformulation',
        'Long-term follow-up (15 years FDA requirement) needed for any gene therapy',
        'Off-target editing in critical tissue requires comprehensive whole-genome profiling',
    ],
    'references': [
        'Komor 2016 Nature (CBE)',
        'Gaudelli 2017 Nature (ABE)',
        'Anzalone 2019 Nature (Prime editing)',
        'Musunuru 2021 Nature (VERVE-101 PCSK9 NHP)',
        'Frangoul 2021 NEJM (exa-cel sickle cell)',
    ],
}

with open('base_edit_design.json', 'w') as f:
    json.dump(design, f, indent=2)

# Editor choice text
with open('editor_choice.txt', 'w') as f:
    f.write(f"Editor Class Recommendation — {gene} / {goal}\n")
    f.write("=" * 60 + "\n\n")
    f.write(f"Recommended editor: {rule['editor'].upper()}\n\n")
    f.write(f"Mechanism: {rule['mechanism']}\n\n")
    f.write(f"PAM strategy: {rule['pam']}\n\n")
    f.write(f"Expected efficiency: {rule['efficiency']}\n\n")
    f.write(f"Clinical precedent: {rule['precedent']}\n")

# Delivery plan
with open('delivery_plan.txt', 'w') as f:
    f.write(f"Delivery Plan — {gene} / target tissue: {atlas['primary_tissue']}\n")
    f.write("=" * 60 + "\n\n")
    f.write(f"Recommended vehicle: {delivery_choice['recommended']}\n\n")
    f.write(f"Chemistry: {delivery_choice.get('lnp_chemistry', '—')}\n")
    f.write(f"Route: {delivery_choice.get('route', '—')}\n\n")
    f.write(f"CMC consideration: {delivery_choice.get('cmc_flag', '—')}\n\n")
    f.write(f"Clinical precedent: {delivery_choice.get('precedent', '—')}\n")

# IND checklist
with open('ind_readiness_checklist.txt', 'w') as f:
    f.write(f"IND-Readiness Checklist — {gene} in vivo base editing\n")
    f.write("=" * 60 + "\n\n")
    f.write('\n'.join(ind_checklist) + '\n')

# Human-readable report
lines = [
    "╔══════════════════════════════════════════════════════════════════╗",
    "  In Vivo Base Editing Design Report",
    f"  Target: {gene}   |   Goal: {goal}   |   Indication: {indication}",
    "╚══════════════════════════════════════════════════════════════════╝",
    "",
    "── Atlas Tissue Context ───────────────────────────────────────────",
    f"  Primary tissue: {atlas['primary_tissue']}",
    f"  Criticality:    {atlas['tier']}",
    f"  Note:           {atlas['note']}",
    "",
    "── Editor Recommendation ──────────────────────────────────────────",
    f"  Editor:         {rule['editor'].upper()}",
    f"  Mechanism:      {rule['mechanism'][:80]}",
    f"  Efficiency:     {rule['efficiency']}",
    f"  Precedent:      {rule['precedent'][:80]}",
    "",
    "── Delivery Plan ──────────────────────────────────────────────────",
    f"  Vehicle:        {delivery_choice['recommended']}",
    f"  Route:          {delivery_choice.get('route', '—')}",
    f"  CMC flag:       {delivery_choice.get('cmc_flag', '—')[:80]}",
    f"  Precedent:      {delivery_choice.get('precedent', '—')[:80]}",
    "",
    "── Guide RNA ──────────────────────────────────────────────────────",
    f"  Strategy: {grna_rec['recommendation'][:80]}",
    f"  Next step: Run crisprScore workflow for guide ranking + off-target",
    "",
    "── Modality Class ─────────────────────────────────────────────────",
    f"  {design['modality_class']}",
    "",
    "── Honest Disclaimers ─────────────────────────────────────────────",
] + [f"  • {d}" for d in design['disclaimers']]

with open('base_edit_design.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')

print('\n'.join(lines))
PYEOF

    python3 -c "print('in_vivo_base_edit_design: 1.0')" > versions.yml
    """
}

workflow { meta = [id: 'base_edit_run']; Channel.value(meta) | IN_VIVO_BASE_EDIT_DESIGN }
