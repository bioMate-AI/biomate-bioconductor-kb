#!/usr/bin/env nextflow
/*
 * drug_discovery/in_vivo_base_edit_design  (4-phase pipeline)
 *
 *   Phase A — Atlas Tissue Check     : target gene tissue-restriction profile; LNP feasibility
 *   Phase B — Editor Selection       : CBE vs ABE vs Prime based on edit goal
 *   Phase C — Guide RNA Design       : gRNA design for premature stop (CAA->TAA / W8 etc.)
 *   Phase D — CMC Flag Emission      : LNP hepatotoxicity flags (VERVE-101 LFT precedent), final report
 *
 * Recovers Verve VERVE-101/102 (PCSK9), VERVE-201 (ANGPTL3), Beam BEAM-101 (HBG1/2),
 * Intellia NTLA-2001 (TTR), Editas EDIT-301 (BCL11A) clinical designs from inputs.
 *
 * References:
 *   - Komor 2016 Nature (CBE); Gaudelli 2017 Nature (ABE); Anzalone 2019 Nature (Prime)
 *   - Musunuru 2021 Nature (VERVE-101 PCSK9 NHP); Frangoul 2021 NEJM (exa-cel)
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.target_gene       = 'null'
params.edit_goal         = 'loss_of_function'
params.indication        = 'undefined'
params.delivery          = 'auto'
params.editor_preference = 'auto'

// [Phase A] Atlas Tissue Check — target gene tissue-restriction lookup and LNP feasibility
process BASE_EDIT_ATLAS_TISSUE_CHECK {
    tag "base_edit:phaseA:${params.target_gene}"
    label 'process_low'
    publishDir "${params.outdir}/phaseA_atlas", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("atlas_tissue.json"), emit: atlas
    path "phaseA_summary.txt",                   emit: summary

    script:
    """
    export PARAM_GENE='${params.target_gene}'
    export PARAM_GOAL='${params.edit_goal}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_DELIVERY='${params.delivery}'
    export PARAM_EDITOR='${params.editor_preference}'

    python3 << 'PYEOF'
import os, json

gene = os.environ.get('PARAM_GENE', '').strip()
if not gene or gene.lower() == 'null':
    gene = 'PCSK9'
gene = gene.upper()

goal = os.environ.get('PARAM_GOAL', '').strip()
if not goal or goal.lower() == 'null':
    goal = 'loss_of_function'
goal = goal.lower()

indication = os.environ.get('PARAM_INDICATION', '').strip()
if not indication or indication.lower() == 'null':
    indication = 'undefined'
indication = indication.lower()

delivery = os.environ.get('PARAM_DELIVERY', '').strip()
if not delivery or delivery.lower() == 'null':
    delivery = 'auto'
delivery = delivery.lower()

editor_pref = os.environ.get('PARAM_EDITOR', '').strip()
if not editor_pref or editor_pref.lower() == 'null':
    editor_pref = 'auto'
editor_pref = editor_pref.lower()

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

lnp_feasible = atlas['primary_tissue'] in ('hepatocyte',)

out = {
    'target_gene': gene,
    'edit_goal':   goal,
    'indication':  indication,
    'delivery_pref': delivery,
    'editor_pref': editor_pref,
    'atlas_tissue': atlas,
    'lnp_iv_feasible': lnp_feasible,
}
with open('atlas_tissue.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase A — Atlas Tissue Check",
    f"  Target gene:     {gene}",
    f"  Edit goal:       {goal}",
    f"  Indication:      {indication}",
    f"  Primary tissue:  {atlas['primary_tissue']}  (tier={atlas['tier']})",
    f"  Note:            {atlas['note']}",
    f"  LNP IV feasible: {lnp_feasible}",
]
with open('phaseA_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase B] Editor Selection — CBE vs ABE vs Prime based on edit goal
process BASE_EDIT_EDITOR_SELECTION {
    tag "base_edit:phaseB"
    label 'process_low'
    publishDir "${params.outdir}/phaseB_editor", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(atlas_json)

    output:
    tuple val(meta), path("editor_selection.json"), path(atlas_json), emit: editor
    path "phaseB_summary.txt",                                         emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${atlas_json}') as f:
    ctx = json.load(f)

goal        = ctx['edit_goal']
editor_pref = ctx['editor_pref']

EDITOR_RULES = {
    'loss_of_function': {
        'editor':     'cbe',
        'mechanism':  'Premature stop codon: CAA->TAA, CAG->TAG, or CGA->TGA via C->T transition on coding strand. '
                      'Alternative: splice donor disruption (GT->AT) for exon skipping.',
        'pam':        'SpCas9 NGG (canonical); SpRY for relaxed PAM if needed',
        'efficiency': '40-60% editing typical in hepatocyte; 20-40% in HSC ex vivo',
        'precedent':  'Verve VERVE-101/102 PCSK9 (CBE W8X stop), VERVE-201 ANGPTL3 (CBE)',
    },
    'gain_of_function': {
        'editor':     'abe',
        'mechanism':  'A->G correction of pathogenic G->A variant. Or enhancer activation via base-edit'
                      ' regulatory site.',
        'pam':        'SpCas9 NGG; ABE8e variant for higher activity',
        'efficiency': '30-50% in hepatocyte; 15-30% in HSC',
        'precedent':  'Disease correction via ABE — multiple academic Phase 1',
    },
    'gene_correction': {
        'editor':     'abe',
        'mechanism':  'Most pathogenic SNVs are G->A or C->T transitions. ABE corrects G->A (A->G to restore). '
                      'CBE corrects C->T (G->A on antisense).',
        'pam':        'SpCas9 NGG; consider Cas12-derived editors for AT-rich windows',
        'efficiency': '20-50% depending on context',
        'precedent':  'Multiple research-stage corrections',
    },
    'regulatory_modification': {
        'editor':     'abe',
        'mechanism':  'Modify regulatory SNVs (e.g., HBG1/2 -175 GATA enhancer; BCL11A +58 erythroid enhancer). '
                      'Disrupts transcription factor binding to derepress target gene.',
        'pam':        'SpCas9 NGG; pick SNV based on TF footprint mapping',
        'efficiency': '60-80% editing in HSC ex vivo (BEAM-101 reported)',
        'precedent':  'Beam BEAM-101 (HBG1/2 ABE for sickle cell), Editas EDIT-301 (BCL11A erythroid enhancer)',
    },
}

rule = dict(EDITOR_RULES.get(goal, EDITOR_RULES['loss_of_function']))

if editor_pref in ('cbe', 'abe', 'prime'):
    rule['editor'] = editor_pref
    if editor_pref == 'prime':
        rule['mechanism'] = 'Prime editing — search-and-replace, can install any base-to-base change ' \
                            'plus small insertions/deletions. Lower efficiency (15-30%) than CBE/ABE.'
        rule['efficiency'] = '10-25% in hepatocyte; lower in HSC. Use only when CBE/ABE cannot.'

out = {**ctx, 'editor_recommendation': rule}
with open('editor_selection.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase B — Editor Selection",
    f"  Edit goal:    {goal}",
    f"  Editor:       {rule['editor'].upper()}",
    f"  PAM strategy: {rule['pam']}",
    f"  Efficiency:   {rule['efficiency']}",
    f"  Precedent:    {rule['precedent'][:80]}",
]
with open('phaseB_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase C] Guide RNA Design — gRNA design for premature stop (CAA->TAA / W8 codon etc.)
process BASE_EDIT_GRNA_DESIGN {
    tag "base_edit:phaseC"
    label 'process_low'
    publishDir "${params.outdir}/phaseC_grna", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(editor_json), path(atlas_json)

    output:
    tuple val(meta), path("grna_design.json"), emit: grna
    path "phaseC_summary.txt",                  emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${editor_json}') as f:
    ctx = json.load(f)

gene = ctx['target_gene']
goal = ctx['edit_goal']
rule = ctx['editor_recommendation']

grna_rec = {
    'recommendation': f"Design gRNA spacer at editor activity window (positions 4-8 from PAM-distal end). "
                      f"For {gene} {goal}: target the codon at the edit site "
                      f"(e.g., PCSK9 W8X CAA->TAA via CBE). "
                      f"Run BioMate crisprScore workflow for on-target (Azimuth/DeepHF) and off-target "
                      f"(CFD / MIT) scoring before locking the lead guide.",
    'off_target_check':'Atlas-driven off-target scan: query atlas_expression_query for any gene with '
                       f"similar sequence (homology >85% in seed region) AND expression in critical tissue. "
                       'Flag for IND submission.',
    'pam_strategy':   rule['pam'],
    'activity_window':'positions 4-8 from PAM-distal end (canonical CBE/ABE deaminase window)',
    'next_workflow':  'crisprScore for on-target + off-target ranking',
}

out = {**ctx, 'grna_strategy': grna_rec}
with open('grna_design.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase C — Guide RNA Design",
    f"  Target:           {gene}",
    f"  PAM strategy:     {grna_rec['pam_strategy']}",
    f"  Activity window:  {grna_rec['activity_window']}",
    f"  Next workflow:    {grna_rec['next_workflow']}",
]
with open('phaseC_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase D] CMC Flag Emission — LNP hepatotoxicity flags (VERVE-101 LFT precedent), final report
process BASE_EDIT_CMC_FLAGS {
    tag "base_edit:phaseD"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(grna_json)

    output:
    tuple val(meta), path("base_edit_design.json"),       emit: design_json
    tuple val(meta), path("editor_choice.txt"),           emit: editor_choice
    tuple val(meta), path("delivery_plan.txt"),           emit: delivery_plan
    tuple val(meta), path("ind_readiness_checklist.txt"), emit: ind_checklist
    tuple val(meta), path("base_edit_design.txt"),        emit: report
    path "versions.yml",                                   emit: versions

    script:
    """
    python3 << 'PYEOF'
import json

with open('${grna_json}') as f:
    ctx = json.load(f)

gene       = ctx['target_gene']
goal       = ctx['edit_goal']
indication = ctx['indication']
atlas      = ctx['atlas_tissue']
rule       = ctx['editor_recommendation']
grna_rec   = ctx['grna_strategy']
delivery   = ctx['delivery_pref']

DELIVERY_MATRIX = {
    'hepatocyte': {
        'recommended': 'lnp_iv_hepatocyte',
        'lnp_chemistry': 'MC3-class or biodegradable ionizable lipid (VERVE-102 reformulation); '
                         'Onpattro/Spikevax-class LNPs reach hepatocytes via ApoE-LDLR uptake',
        'route':         'Intravenous infusion',
        'cmc_flag':      'VERVE-101 LFT elevation (Nov 2023) -> optimize LNP for lower hepatotoxicity '
                         '(reduced PEG, alternative ionizable lipid). VERVE-102 addressed this.',
        'precedent':     'VERVE-101/102 (PCSK9), VERVE-201 (ANGPTL3), Intellia NTLA-2001 (TTR), '
                         'Intellia NTLA-2002 (KLKB1)',
    },
    'erythroid_progenitor': {
        'recommended': 'ex_vivo_hsc',
        'lnp_chemistry': 'N/A — electroporation of mRNA + gRNA into autologous CD34+ HSCs',
        'route':         'Ex vivo edit + autologous transplant',
        'cmc_flag':      'Requires myeloablative conditioning. Manufacturing: leukapheresis -> CD34 selection -> '
                         'electroporation -> release testing -> reinfusion. Capital-intensive.',
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
        'precedent':     'Zolgensma AAV9 (SMA IV in infants -> IT in older patients)',
    },
    'cerebral_cortex_neuron': {
        'recommended': 'aav9_intrathecal',
        'lnp_chemistry': 'N/A; intrathecal LNP under development',
        'route':         'Intrathecal infusion or convection-enhanced delivery',
        'cmc_flag':      'CNS distribution heterogeneity; partial coverage typical',
        'precedent':     'AAV9 intrathecal for SOD1 ALS',
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

delivery_choice = dict(DELIVERY_MATRIX.get(atlas['primary_tissue'], DELIVERY_MATRIX['unknown']))

if delivery != 'auto':
    delivery_choice['recommended'] = delivery
    delivery_choice['note'] = 'User override applied; verify atlas tissue match'

# Hepatotoxicity reformulation guidance (VERVE-101 precedent)
cmc_flags = []
if delivery_choice['recommended'] == 'lnp_iv_hepatocyte':
    cmc_flags.append('VERVE-101 LFT elevation precedent (Nov 2023): reformulate LNP with reduced PEG and '
                     'alternative ionizable lipid (VERVE-102 path) to lower hepatotoxicity.')
    cmc_flags.append('Monitor ALT/AST through Day 28 minimum; pre-IND meeting recommended for novel chemistry.')
cmc_flags.append('Long-term follow-up commitment (15 years) per FDA gene therapy guidance.')

ind_checklist = [
    '── Preclinical Pharmacology ──',
    '  [ ] In vitro editing efficiency (HepG2 or primary hepatocytes for liver target)',
    '  [ ] Off-target genome-wide profiling (GUIDE-seq, CIRCLE-seq, or DISCOVER-seq)',
    '  [ ] Long-read sequencing for large structural variants at on-target site',
    '  [ ] Editing durability in primary cells (>=3 months in vitro)',
    '  [ ] Functional readout for therapeutic effect (e.g., serum LDL for PCSK9)',
    '',
    '── Toxicology ──',
    '  [ ] GLP single-dose tox in 2 species (typically NHP + rodent)',
    '  [ ] Liver enzyme monitoring (LFT) — VERVE-101 lesson',
    '  [ ] Immunogenicity to LNP components (anti-PEG antibodies)',
    '  [ ] p53 activation assay (DSB-induced; usually low for base editors)',
    '',
    '── CMC ──',
    '  [ ] mRNA cap structure (CleanCap AG / Cap1)',
    '  [ ] Pseudouridine modification (m1Psi) per Kariko',
    '  [ ] LNP characterization (size, PDI, encapsulation efficiency)',
    '  [ ] gRNA chemical modification (2-OMe, PS at termini)',
    '  [ ] Bioanalytical method for editing quantification',
    '',
    '── Regulatory ──',
    '  [ ] FDA pre-IND meeting (recommended for novel chemistry)',
    '  [ ] CBER division for cell/gene therapy',
    '  [ ] Genotoxicity follow-up plan (CRISPR risk assessment)',
    '  [ ] Long-term follow-up commitment (15 years for gene therapy)',
]

design = {
    'target_gene':        gene,
    'edit_goal':          goal,
    'indication':         indication,
    'atlas_tissue':       atlas,
    'editor_recommendation': rule,
    'delivery_plan':      delivery_choice,
    'grna_strategy':      grna_rec,
    'cmc_flags':          cmc_flags,
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

with open('editor_choice.txt', 'w') as f:
    f.write(f"Editor Class Recommendation — {gene} / {goal}\\n")
    f.write("=" * 60 + "\\n\\n")
    f.write(f"Recommended editor: {rule['editor'].upper()}\\n\\n")
    f.write(f"Mechanism: {rule['mechanism']}\\n\\n")
    f.write(f"PAM strategy: {rule['pam']}\\n\\n")
    f.write(f"Expected efficiency: {rule['efficiency']}\\n\\n")
    f.write(f"Clinical precedent: {rule['precedent']}\\n")

with open('delivery_plan.txt', 'w') as f:
    f.write(f"Delivery Plan — {gene} / target tissue: {atlas['primary_tissue']}\\n")
    f.write("=" * 60 + "\\n\\n")
    f.write(f"Recommended vehicle: {delivery_choice['recommended']}\\n\\n")
    f.write(f"Chemistry: {delivery_choice.get('lnp_chemistry', '-')}\\n")
    f.write(f"Route: {delivery_choice.get('route', '-')}\\n\\n")
    f.write(f"CMC consideration: {delivery_choice.get('cmc_flag', '-')}\\n\\n")
    f.write(f"Clinical precedent: {delivery_choice.get('precedent', '-')}\\n\\n")
    f.write("-- CMC Flags --\\n")
    for fl in cmc_flags:
        f.write(f"  * {fl}\\n")

with open('ind_readiness_checklist.txt', 'w') as f:
    f.write(f"IND-Readiness Checklist — {gene} in vivo base editing\\n")
    f.write("=" * 60 + "\\n\\n")
    f.write('\\n'.join(ind_checklist) + '\\n')

lines = [
    "===================================================================",
    "  In Vivo Base Editing Design Report",
    f"  Target: {gene}   |   Goal: {goal}   |   Indication: {indication}",
    "===================================================================",
    "",
    "-- Atlas Tissue Context --",
    f"  Primary tissue: {atlas['primary_tissue']}",
    f"  Criticality:    {atlas['tier']}",
    f"  Note:           {atlas['note']}",
    "",
    "-- Editor Recommendation --",
    f"  Editor:         {rule['editor'].upper()}",
    f"  Mechanism:      {rule['mechanism'][:80]}",
    f"  Efficiency:     {rule['efficiency']}",
    f"  Precedent:      {rule['precedent'][:80]}",
    "",
    "-- Delivery Plan --",
    f"  Vehicle:        {delivery_choice['recommended']}",
    f"  Route:          {delivery_choice.get('route', '-')}",
    f"  CMC flag:       {delivery_choice.get('cmc_flag', '-')[:80]}",
    f"  Precedent:      {delivery_choice.get('precedent', '-')[:80]}",
    "",
    "-- Guide RNA --",
    f"  Strategy: {grna_rec['recommendation'][:80]}",
    f"  Next step: Run crisprScore workflow for guide ranking + off-target",
    "",
    "-- CMC Flags --",
] + [f"  * {fl}" for fl in cmc_flags] + [
    "",
    "-- Modality Class --",
    f"  {design['modality_class']}",
    "",
    "-- Honest Disclaimers --",
] + [f"  * {d}" for d in design['disclaimers']]

with open('base_edit_design.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')

print('\\n'.join(lines))
PYEOF

    python3 -c "print('in_vivo_base_edit_design: 2.0')" > versions.yml
    """
}

workflow {
    meta = [id: 'base_edit_run']
    Channel.value(meta) | BASE_EDIT_ATLAS_TISSUE_CHECK
    BASE_EDIT_ATLAS_TISSUE_CHECK.out.atlas   | BASE_EDIT_EDITOR_SELECTION
    BASE_EDIT_EDITOR_SELECTION.out.editor    | BASE_EDIT_GRNA_DESIGN
    BASE_EDIT_GRNA_DESIGN.out.grna           | BASE_EDIT_CMC_FLAGS
}
