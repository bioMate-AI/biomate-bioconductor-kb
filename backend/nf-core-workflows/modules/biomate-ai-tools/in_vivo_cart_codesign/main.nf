#!/usr/bin/env nextflow
/*
 * drug_discovery/in_vivo_cart_codesign  (4-phase pipeline)
 *
 *   Phase A — Atlas Safety Check        : CAR target expression profile; critical-tissue scan
 *   Phase B — LNP Tropism Selection     : anti-CD5/CD8/CD3 LNP options; transfection compatibility
 *   Phase C — Fratricide Check          : CAR target vs T-cell-restricted LNP — no overlap = safe
 *   Phase D — CAR Construct Assembly    : final FASTA (scFv + CD8α + CD28/4-1BB + CD3ζ); Kymriah arch if CD19
 *
 * Marketing context:
 *   - Capstan Therapeutics CPTX-2309 (anti-CD8 LNP, CD19 CAR mRNA)
 *   - Umoja Biopharma; Kelonia Therapeutics
 *   Eliminates ex vivo manufacturing ($400-500K/patient → potentially $5-50K)
 *
 * References:
 *   - Rurik et al. 2022 Science (in vivo CAR-T for cardiac fibrosis)
 *   - Capstan CPTX-2309 (CD8-targeted LNP)
 *   - Kheirolomoom et al. 2022 (in vivo CAR engineering)
 *   - Akinc et al. 2019 Nat Nanotechnol (LNP-mediated mRNA delivery)
 */

nextflow.enable.dsl = 2

params.outdir         = './results'
params.car_target     = 'null'
params.indication     = 'undefined'
params.delivery_cell  = 'T_cell'        // T_cell | NK_cell | macrophage
params.lnp_targeting  = 'auto'           // spleen_C12-200 | anti_CD8 | anti_CD5 | anti_CD3 | untargeted_MC3 | auto
params.persistence    = 'transient'      // transient | persistent

// [Phase A] Atlas Safety Check — CAR target expression profile across critical tissues
process INVIVO_CART_ATLAS_SAFETY {
    tag "invivo_cart:phaseA:${params.car_target}"
    label 'process_low'
    publishDir "${params.outdir}/phaseA_atlas_safety", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("atlas_safety.json"), emit: atlas
    path "phaseA_summary.txt",                   emit: summary

    script:
    """
    export PARAM_TARGET='${params.car_target}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_CELL='${params.delivery_cell}'
    export PARAM_LNP='${params.lnp_targeting}'
    export PARAM_PERSIST='${params.persistence}'

    python3 << 'PYEOF'
import os, json

car_target = os.environ.get('PARAM_TARGET', '').strip()
if not car_target or car_target.lower() == 'null':
    car_target = 'CD19'
car_target = car_target.upper()

indication = os.environ.get('PARAM_INDICATION', '').strip()
if not indication or indication.lower() == 'null':
    indication = 'undefined'
indication = indication.lower()

deliv_cell = os.environ.get('PARAM_CELL', '').strip()
if not deliv_cell or deliv_cell.lower() == 'null':
    deliv_cell = 'T_cell'

lnp_pref = os.environ.get('PARAM_LNP', '').strip()
if not lnp_pref or lnp_pref.lower() in ('auto', 'null'):
    lnp_pref = 'auto'

persist = os.environ.get('PARAM_PERSIST', '').strip()
if not persist or persist.lower() == 'null':
    persist = 'transient'
persist = persist.lower()

ATLAS = {
    'CD19':  [('B_cell_naive', 4.2, 'LOW'), ('B_cell_memory', 4.5, 'LOW'),
              ('plasmablast', 2.1, 'LOW')],
    'BCMA':  [('plasma_cell', 5.2, 'LOW'), ('plasmablast', 3.4, 'LOW'),
              ('B_cell_memory', 0.6, 'LOW')],
    'CD22':  [('B_cell_naive', 4.0, 'LOW'), ('B_cell_memory', 4.2, 'LOW')],
    'CD7':   [('T_cell_naive', 4.8, 'LOW'), ('T_cell_memory', 4.5, 'LOW'),
              ('NK_cell', 4.0, 'LOW')],
    'CD5':   [('T_cell_naive', 4.6, 'LOW'), ('T_cell_memory', 4.4, 'LOW'),
              ('B_cell_naive', 1.0, 'LOW')],
    'CD33':  [('myeloid_progenitor', 4.6, 'HIGH'), ('monocyte', 4.2, 'MOD'),
              ('hematopoietic_stem', 3.2, 'HIGH')],
    'MSLN':  [('mesothelial_pleural', 3.5, 'MOD'),
              ('mesothelial_peritoneal', 3.2, 'MOD')],
    'CD20':  [('B_cell_naive', 4.4, 'LOW'), ('B_cell_memory', 4.6, 'LOW')],
    'HER2':  [('cardiac_endothelial', 1.8, 'HIGH'),
              ('lung_alveolar_type2', 1.4, 'HIGH'),
              ('breast_epithelial', 3.4, 'MOD')],
}
car_atlas = ATLAS.get(car_target, [('unknown', 0.0, 'LOW')])

max_high = max([m for ct, m, t in car_atlas if t == 'HIGH'], default=0.0)
max_mod  = max([m for ct, m, t in car_atlas if t == 'MOD'],  default=0.0)
high_hits= [ct for ct, m, t in car_atlas if t == 'HIGH' and m > 0.5]
mod_hits = [ct for ct, m, t in car_atlas if t == 'MOD' and m > 0.5]

if max_high > 0.5:
    car_verdict = 'REJECT'
    car_rationale = f"CAR target expressed > 0.5 in critical tissue: {high_hits}"
elif max_mod > 3.0:
    car_verdict = 'REJECT'
    car_rationale = f"CAR target expressed > 3.0 in continuous-lining tissue: {mod_hits}"
elif max_mod > 1.0:
    car_verdict = 'CAUTION'
    car_rationale = f"CAR target moderately expressed in: {mod_hits}; logic-gated CAR recommended"
else:
    car_verdict = 'VIABLE'
    car_rationale = "CAR target safely restricted to LOW-criticality cell types"

out = {
    'car_target':   car_target,
    'indication':   indication,
    'delivery_cell':deliv_cell,
    'lnp_pref':     lnp_pref,
    'persistence':  persist,
    'atlas':        [[ct, m, t] for ct, m, t in car_atlas],
    'atlas_check': {
        'verdict':   car_verdict,
        'rationale': car_rationale,
        'high_tissue_hits': high_hits,
        'mod_tissue_hits':  mod_hits,
    },
}
with open('atlas_safety.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase A — Atlas Safety Check",
    f"  CAR target: {car_target}   Indication: {indication}",
    f"  Verdict:    {car_verdict}",
    f"  Rationale:  {car_rationale}",
]
with open('phaseA_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase B] LNP Tropism Selection — pick anti-CD5/CD8/CD3/etc; characterize transfected cell set
process INVIVO_CART_LNP_TROPISM {
    tag "invivo_cart:phaseB"
    label 'process_low'
    publishDir "${params.outdir}/phaseB_lnp_tropism", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(atlas_json)

    output:
    tuple val(meta), path("lnp_tropism.json"), emit: lnp
    path "phaseB_summary.txt",                  emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${atlas_json}') as f:
    ctx = json.load(f)

deliv_cell = ctx['delivery_cell']
lnp_pref   = ctx['lnp_pref']

LNP_LIBRARY = {
    'MC3':            {'tropism': 'hepatocyte',       'in_vivo_cart_use': 'NOT_USEFUL',
                       'notes': 'Onpattro standard; hepatocyte-dominant via ApoE-LDLR; not T-cell-selective'},
    'SM-102':         {'tropism': 'muscle_lymph',     'in_vivo_cart_use': 'WEAK',
                       'notes': 'Moderna IM standard; lymph node draining; some T-cell contact post-IM'},
    'C12-200':        {'tropism': 'spleen',           'in_vivo_cart_use': 'OK',
                       'notes': 'Spleen-tropic with lipid optimization; accesses splenic T cell pool (Anderson lab pattern)'},
    'anti_CD8':       {'tropism': 'CD8_T_cell',       'in_vivo_cart_use': 'PREFERRED',
                       'notes': 'CD8-restricted antibody conjugation; Capstan CPTX-2309 precedent; CD4 T cells excluded'},
    'anti_CD5':       {'tropism': 'pan_T_cell',       'in_vivo_cart_use': 'PREFERRED',
                       'notes': 'Pan-T-cell (CD4 + CD8); broader than anti-CD8; check fratricide vs CAR target'},
    'anti_CD3':       {'tropism': 'pan_T_cell',       'in_vivo_cart_use': 'OK',
                       'notes': 'TCR complex targeting; activates T cells (mixed signal — pro+con)'},
    'anti_CD7':       {'tropism': 'T_NK_cell',        'in_vivo_cart_use': 'CONDITIONAL',
                       'notes': 'T + NK targeting; fratricide risk if CAR target is on T cells'},
    'untargeted_MC3': {'tropism': 'hepatocyte',       'in_vivo_cart_use': 'NOT_USEFUL',
                       'notes': 'Same as MC3'},
}

if lnp_pref == 'auto':
    if deliv_cell == 'T_cell':
        lnp_choice = 'anti_CD8'
    elif deliv_cell == 'NK_cell':
        lnp_choice = 'anti_CD7'
    elif deliv_cell == 'macrophage':
        lnp_choice = 'untargeted_MC3'
    else:
        lnp_choice = 'C12-200'
else:
    lnp_choice = lnp_pref

lnp_info = LNP_LIBRARY.get(lnp_choice, LNP_LIBRARY['anti_CD8'])

LNP_TROPISM_CELLS = {
    'MC3':            ['hepatocyte'],
    'SM-102':         ['muscle_cell', 'lymph_node_DC', 'T_cell_lymph'],
    'C12-200':        ['T_cell_splenic', 'macrophage_splenic', 'B_cell_marginal'],
    'anti_CD8':       ['T_cell_CD8'],
    'anti_CD5':       ['T_cell_CD4', 'T_cell_CD8', 'B_cell_B1'],
    'anti_CD3':       ['T_cell_CD4', 'T_cell_CD8'],
    'anti_CD7':       ['T_cell_CD4', 'T_cell_CD8', 'NK_cell'],
    'untargeted_MC3': ['hepatocyte'],
}
lnp_target_cells = LNP_TROPISM_CELLS.get(lnp_choice, [])

out = {**ctx, 'lnp_choice': {
    'lnp':              lnp_choice,
    'tropism':          lnp_info['tropism'],
    'in_vivo_cart_use': lnp_info['in_vivo_cart_use'],
    'notes':            lnp_info['notes'],
    'target_cells':     lnp_target_cells,
}}
with open('lnp_tropism.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase B — LNP Tropism Selection",
    f"  LNP:               {lnp_choice}",
    f"  Tropism:           {lnp_info['tropism']}",
    f"  In vivo CAR-T use: {lnp_info['in_vivo_cart_use']}",
    f"  Target cells:      {lnp_target_cells}",
]
with open('phaseB_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase C] Fratricide Check — CAR target vs LNP-transfected cell set; flag self-kill risk
process INVIVO_CART_FRATRICIDE_CHECK {
    tag "invivo_cart:phaseC"
    label 'process_low'
    publishDir "${params.outdir}/phaseC_fratricide", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(lnp_json)

    output:
    tuple val(meta), path("fratricide_check.json"), emit: frat
    path "phaseC_summary.txt",                       emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${lnp_json}') as f:
    ctx = json.load(f)

car_target       = ctx['car_target']
lnp_choice       = ctx['lnp_choice']['lnp']
lnp_target_cells = ctx['lnp_choice']['target_cells']
car_atlas        = ctx['atlas']  # list of [ct, m, tier]

def is_T_cell(cell_type):
    return 'T_cell' in cell_type or cell_type.startswith('T_cell')

lnp_hits_t = any(is_T_cell(c) for c in lnp_target_cells)
car_expressing_cells = {ct for ct, m, tier in car_atlas if m > 0.5}
fratricide_cells = car_expressing_cells & set(lnp_target_cells)

if lnp_hits_t and car_target in ('CD7', 'CD5', 'CD3'):
    fratricide = True
    frat_reason = (f"LNP {lnp_choice} transfects T cells. CAR target {car_target} "
                   f"is expressed on T cells. The newly-generated CAR-T cells will kill "
                   f"each other AND the LNP-target T-cell population.")
    alt_lnp = 'anti_CD8' if car_target != 'CD8' else 'C12-200'
    mitigation = (f"Engineer CAR-T to be {car_target}-KO before transduction (electroporation "
                  f"of CRISPR for ex vivo, or co-delivery of guide RNA for in vivo). "
                  f"Capstan/Allogene pattern: B2M-KO + {car_target}-KO. Alternatively, "
                  f"switch LNP to {alt_lnp} or change CAR target to a non-T-cell antigen.")
elif fratricide_cells:
    fratricide = True
    frat_reason = (f"LNP {lnp_choice} transfects cells expressing CAR target {car_target}: "
                   f"{list(fratricide_cells)}. Fratricide risk.")
    mitigation = "Engineer KO or change LNP tropism."
else:
    fratricide = False
    frat_reason = (f"LNP {lnp_choice} transfects {lnp_target_cells}; CAR target "
                   f"{car_target} not expressed in those cells. No fratricide.")
    mitigation = None

frat_block = {
    'fratricide_risk': fratricide,
    'rationale':       frat_reason,
    'mitigation':      mitigation,
}
out = {**ctx, 'fratricide_check': frat_block}
with open('fratricide_check.json','w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase C — Fratricide Check",
    f"  Risk:       {'YES' if fratricide else 'NO'}",
    f"  Rationale:  {frat_reason}",
]
if mitigation:
    lines.append(f"  Mitigation: {mitigation}")
with open('phaseC_summary.txt','w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase D] CAR Construct Assembly — scFv + CD8α + CD28/4-1BB + CD3ζ FASTA; final report
process INVIVO_CART_CONSTRUCT_ASSEMBLY {
    tag "invivo_cart:phaseD"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(frat_json)

    output:
    tuple val(meta), path("in_vivo_cart_design.json"), emit: design_json
    tuple val(meta), path("cart_construct.fasta"),     emit: cart_fasta
    tuple val(meta), path("fratricide_check.json"),    emit: fratricide_json
    tuple val(meta), path("design_report.txt"),        emit: report
    path "versions.yml",                                emit: versions

    script:
    """
    python3 << 'PYEOF'
import json

with open('${frat_json}') as f:
    ctx = json.load(f)

car_target   = ctx['car_target']
indication   = ctx['indication']
deliv_cell   = ctx['delivery_cell']
persist      = ctx['persistence']
atlas_check  = ctx['atlas_check']
lnp_block    = ctx['lnp_choice']
frat_block   = ctx['fratricide_check']
car_verdict  = atlas_check['verdict']
fratricide   = frat_block['fratricide_risk']

if persist == 'transient':
    costim_choice = 'CD28'
    costim_rationale = ('Transient mRNA-encoded CAR. CD28 costimulatory chosen for '
                        'faster effector response. 4-1BB would push memory phenotype '
                        '(less useful for transient).')
else:
    costim_choice = '4-1BB'
    costim_rationale = ('Persistent (integrating) delivery — 4-1BB memory phenotype preferred.')

logic_gate_recommendation = None
if car_verdict == 'CAUTION':
    logic_gate_recommendation = ('Logic-gated CAR recommended (AND-NOT or SynNotch) — '
                                 'use a co-expressed tumor-specific antigen as the gate.')

SCFV_LIBRARY = {
    'CD19': 'FMC63', 'BCMA': 'bb2121', 'CD22': 'm971', 'CD7': 'TH69',
    'CD5':  'H65',   'CD33': 'gemtuzumab-derived', 'MSLN': 'SS1', 'CD20': '2F2',
    'HER2': 'trastuzumab-derived',
}
scfv = SCFV_LIBRARY.get(car_target, 'novel_scFv_design_required')

GMCSFR_SIGNAL = "MLLLVTSLLLCELPHPAFLLIP"
CD8A_HINGE_TM = "TTTPAPRPPTPAPTIASQPLSLRPEACRPAAGGAVHTRGLDFACDIYIWAPLAGTCGVLLLSLVITLYC"
CD28_INTRA    = "RSKRSRLLHSDYMNMTPRRPGPTRKHYQPYAPPRDFAAYRS"
TNFRSF9_INTRA = "KRGRKKLLYIFKQGRDQALSFLSQTPKNFLNLRPRDQFRHSQAFLERNLKQLSGN"
CD3Z          = ("RVKFSRSAEPPASVQFHIPDREKTLAQETSQGSETMFPENLPNAFESQGPLHESPREATPQQLELPG"
                 "GDVDFCLKTEAQIPSIQLVNMFHFLAQERPTINIQIESSEDPEHEFEIIRSGNLQGAPNPAAPDQLQ"
                 "GLAPKEETQRK")

SCFV_SEQS = {
    'FMC63': 'DIQMTQTTSSLSASLGDRVTISCRASQDISKYLNWYQQKPDGTVKLLIYHTSRLHSGVPSRFSGSGSGTDYSLTISNLEQEDIATYFCQQGNTLPYTFGGGTKLEITGGGGSGGGGSGGGGSEVKLQESGPGLVAPSQSLSVTCTVSGVSLPDYGVSWIRQPPRKGLEWLGVIWGSETTYYNSALKSRLTIIKDNSKSQVFLKMNSLQTDDTAIYYCAKHYYYGGSYAMDYWGQGTSVTVSS',
    'bb2121': 'QVQLVQSGAEVKKPGSSVKVSCKASGYTFTDYSINWVRQAPGQGLEWMGWINTETREPAYAYDFRGRFVFSLDTSVSTAYLQISSLKAEDTAVYYCALDYSYAMDYWGQGTLVTVSSGGGGSGGGGSGGGGSEIVLTQSPATLSLSPGERATLSCRASQSVSSYLAWYQQKPGQAPRLLIYDASNRATGIPARFSGSGSGTDFTLTISSLEPEDFAVYYCQQRSNWPPLTFGGGTKVEIK',
}
scfv_seq = SCFV_SEQS.get(scfv, 'SCFV_PLACEHOLDER_DESIGN_REQUIRED')

costim_seq = CD28_INTRA if costim_choice == 'CD28' else TNFRSF9_INTRA

full_car = (GMCSFR_SIGNAL + scfv_seq + CD8A_HINGE_TM + costim_seq + CD3Z) if scfv_seq != 'SCFV_PLACEHOLDER_DESIGN_REQUIRED' else None

design = {
    'car_target':            car_target,
    'indication':            indication,
    'delivery_cell':         deliv_cell,
    'persistence':           persist,
    'atlas_check':           atlas_check,
    'lnp_choice':            lnp_block,
    'fratricide_check':      frat_block,
    'car_construct': {
        'scfv':              scfv,
        'hinge_tm':          'CD8α',
        'costimulatory':     costim_choice,
        'costim_rationale':  costim_rationale,
        'cd3z':              True,
        'total_aa_length':   len(full_car) if full_car else None,
        'logic_gate':        logic_gate_recommendation,
        'sequence_available':full_car is not None,
    },
    'overall_verdict':       'GO' if (car_verdict != 'REJECT' and not fratricide) else 'NO-GO / REWORK',
    'modality_class':        'In vivo CAR-T (LNP-mRNA delivery, transient)',
    'precedents': [
        'Capstan CPTX-2309 (anti-CD8 LNP + CAR mRNA)',
        'Umoja Biopharma in vivo CAR-T platform',
        'Kelonia Therapeutics LNP CAR',
        'Rurik et al. 2022 Science (cardiac fibrosis in vivo CAR-T)',
    ],
    'disclaimers': [
        'In vivo CAR-T is preclinical/Phase 1 frontier — clinical efficacy not yet established',
        'LNP tropism profiles based on published lipid library data; in vivo behavior varies',
        'Fratricide check uses RNA expression; surface protein density determines actual fratricide kinetics',
        'CAR construct sequence is placeholder for design illustration; actual sequences are IP-protected',
    ],
}

with open('in_vivo_cart_design.json', 'w') as f:
    json.dump(design, f, indent=2)

with open('cart_construct.fasta', 'w') as f:
    if full_car:
        f.write(f">CAR_{car_target}_{costim_choice}_invivo\\n")
        for i in range(0, len(full_car), 60):
            f.write(full_car[i:i+60] + '\\n')
    else:
        f.write(f">CAR_{car_target}_designREQUIRED\\n# Novel target — scFv design needed via scfv_antibody_design workflow\\n")

with open('fratricide_check.json', 'w') as f:
    json.dump(frat_block, f, indent=2)

lines = [
    "═══════════════════════════════════════════════════════════════════",
    "  In Vivo CAR-T Co-Design Report",
    f"  Target: {car_target}   |   Indication: {indication}",
    f"  Delivery cell: {deliv_cell}   |   Persistence: {persist}",
    "═══════════════════════════════════════════════════════════════════",
    "",
    "-- Phase A: Atlas Safety Check --",
    f"  Verdict:   {atlas_check['verdict']}",
    f"  Rationale: {atlas_check['rationale']}",
    "",
    "-- Phase B: LNP Tropism --",
    f"  LNP:               {lnp_block['lnp']}",
    f"  Tropism:           {lnp_block['tropism']}",
    f"  In vivo CAR-T use: {lnp_block['in_vivo_cart_use']}",
    f"  Notes:             {lnp_block['notes']}",
    "",
    "-- Phase C: Fratricide Check --",
    f"  Risk:      {'YES' if fratricide else 'NO'}",
    f"  Rationale: {frat_block['rationale']}",
]
if frat_block.get('mitigation'):
    lines.append(f"  Mitigation: {frat_block['mitigation']}")
lines += [
    "",
    "-- Phase D: CAR Construct --",
    f"  scFv:              {scfv}",
    f"  Hinge/TM:          CD8α",
    f"  Costimulatory:     {costim_choice}",
    f"  Rationale:         {costim_rationale}",
]
if logic_gate_recommendation:
    lines.append(f"  Logic gate:        {logic_gate_recommendation}")
if full_car:
    lines.append(f"  Total length:      {len(full_car)} AA")
lines += [
    "",
    f"-- Overall Verdict: {design['overall_verdict']} --",
    "",
    "-- Clinical Precedents --",
] + [f"  * {p}" for p in design['precedents']] + [
    "",
    "-- Disclaimers --",
] + [f"  * {d}" for d in design['disclaimers']]

with open('design_report.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF

    python3 -c "print('in_vivo_cart_codesign: 2.0')" > versions.yml
    """
}

workflow {
    meta = [id: 'invivo_cart_run']
    Channel.value(meta) | INVIVO_CART_ATLAS_SAFETY
    INVIVO_CART_ATLAS_SAFETY.out.atlas       | INVIVO_CART_LNP_TROPISM
    INVIVO_CART_LNP_TROPISM.out.lnp          | INVIVO_CART_FRATRICIDE_CHECK
    INVIVO_CART_FRATRICIDE_CHECK.out.frat    | INVIVO_CART_CONSTRUCT_ASSEMBLY
}
