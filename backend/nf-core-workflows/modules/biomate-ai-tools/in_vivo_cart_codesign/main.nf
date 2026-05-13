#!/usr/bin/env nextflow
/*
 * drug_discovery/in_vivo_cart_codesign
 *
 * Multi-modality co-design workflow for in vivo CAR-T therapies.
 * The headline demo: chains atlas safety + LNP tropism + CAR architecture
 * + fratricide analysis in one query. No single-modality competitor has
 * all four components.
 *
 * Marketing context:
 *   - Capstan Therapeutics CPTX-2309 (anti-CD8-targeted LNP, CD19 CAR mRNA)
 *   - Umoja Biopharma (in vivo CAR-T platform)
 *   - Kelonia Therapeutics (LNP CAR delivery)
 *   Eliminates ex vivo manufacturing ($400-500K/patient → potentially $5-50K)
 *
 * Algorithm:
 *   1. Atlas CAR target safety check (atlas-driven; mirrors modality_triage CAR-T scorer)
 *   2. LNP tropism analysis (which cells get transfected)
 *   3. Fratricide check (LNP-target cell type vs CAR-target cell type)
 *   4. CAR construct architecture recommendation
 *   5. Integrated design output
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

process IN_VIVO_CART_CODESIGN {
    tag "in_vivo_cart:${params.car_target}"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("in_vivo_cart_design.json"), emit: design_json
    tuple val(meta), path("cart_construct.fasta"),     emit: cart_fasta
    tuple val(meta), path("fratricide_check.json"),    emit: fratricide_json
    tuple val(meta), path("design_report.txt"),        emit: report
    path "versions.yml",                                emit: versions

    script:
    """
    export PARAM_TARGET='${params.car_target}'
    export PARAM_INDICATION='${params.indication}'
    export PARAM_CELL='${params.delivery_cell}'
    export PARAM_LNP='${params.lnp_targeting}'
    export PARAM_PERSIST='${params.persistence}'

    python3 << 'PYEOF'
import os, json

car_target = os.environ.get('PARAM_TARGET', '').strip().upper() or 'CD19'
indication = os.environ.get('PARAM_INDICATION', 'undefined').strip().lower()
deliv_cell = os.environ.get('PARAM_CELL', 'T_cell').strip()
lnp_pref   = os.environ.get('PARAM_LNP', 'auto').strip()        # case-sensitive (anti_CD5 ≠ anti_cd5)
if lnp_pref.lower() in ('auto', '', 'null'):
    lnp_pref = 'auto'
persist    = os.environ.get('PARAM_PERSIST', 'transient').strip().lower()

# ─── PHASE 1: Atlas CAR target safety (slim cache mirror) ────────────────────
# Cell types where CAR target is expressed (mean expression in cell type, tier)
ATLAS = {
    'CD19':  [('B_cell_naive', 4.2, 'LOW'), ('B_cell_memory', 4.5, 'LOW'),
              ('plasmablast', 2.1, 'LOW')],
    'BCMA':  [('plasma_cell', 5.2, 'LOW'), ('plasmablast', 3.4, 'LOW'),
              ('B_cell_memory', 0.6, 'LOW')],
    'CD22':  [('B_cell_naive', 4.0, 'LOW'), ('B_cell_memory', 4.2, 'LOW')],
    'CD7':   [('T_cell_naive', 4.8, 'LOW'), ('T_cell_memory', 4.5, 'LOW'),
              ('NK_cell', 4.0, 'LOW')],
    'CD5':   [('T_cell_naive', 4.6, 'LOW'), ('T_cell_memory', 4.4, 'LOW'),
              ('B_cell_naive', 1.0, 'LOW')],   # B1 subset
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

# Score CAR target (same logic as modality_triage CAR-T rule)
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

# ─── PHASE 2: LNP tropism analysis ───────────────────────────────────────────
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

# Auto-select LNP based on delivery cell
if lnp_pref == 'auto':
    if deliv_cell == 'T_cell':
        lnp_choice = 'anti_CD8'   # Capstan default
    elif deliv_cell == 'NK_cell':
        lnp_choice = 'anti_CD7'   # NK + T (limited NK-selective LNPs in development)
    elif deliv_cell == 'macrophage':
        lnp_choice = 'untargeted_MC3'   # macrophage uptake from broad LNP
    else:
        lnp_choice = 'C12-200'
else:
    lnp_choice = lnp_pref

lnp_info = LNP_LIBRARY.get(lnp_choice, LNP_LIBRARY['anti_CD8'])

# Build the set of cell types the LNP will transfect
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

# ─── PHASE 3: Fratricide check ───────────────────────────────────────────────
# If LNP transfects a cell type that also EXPRESSES the CAR target → those cells become CAR-T
# AND get killed by other CAR-T → fratricide
def is_T_cell(cell_type):
    return 'T_cell' in cell_type or cell_type.startswith('T_cell')

def is_B_cell(cell_type):
    return 'B_cell' in cell_type or cell_type == 'plasma_cell' or cell_type == 'plasmablast'

# Map: does the LNP target T cells?
lnp_hits_t = any(is_T_cell(c) for c in lnp_target_cells)
# Direct overlap check: is CAR target expressed in any cell type the LNP transfects?
car_expressing_cells = {ct for ct, m, tier in car_atlas if m > 0.5}
fratricide_cells = car_expressing_cells & set(lnp_target_cells)

# Special case: T-cell-targeted LNP + T-cell-expressed CAR target = fratricide
if lnp_hits_t and car_target in ('CD7', 'CD5', 'CD3'):
    fratricide = True
    frat_reason = (f"LNP {lnp_choice} transfects T cells. CAR target {car_target} "
                   f"is expressed on T cells. The newly-generated CAR-T cells will kill "
                   f"each other AND the LNP-target T-cell population.")
    mitigation = (f"Engineer CAR-T to be {car_target}-KO before transduction (electroporation "
                  f"of CRISPR for ex vivo, or co-delivery of guide RNA for in vivo). "
                  f"Capstan/Allogene pattern: B2M-KO + {car_target}-KO. Alternatively, "
                  f"switch LNP to {('anti_CD8' if car_target != 'CD8' else 'C12-200')} "
                  f"or change CAR target to a non-T-cell antigen.")
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

# ─── PHASE 4: CAR construct architecture ─────────────────────────────────────
# In vivo CAR-T persistence considerations
if persist == 'transient':
    costim_choice = 'CD28'   # faster, shorter persistence — matches transient mRNA
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

# scFv source (from cart_construct_design library)
SCFV_LIBRARY = {
    'CD19': 'FMC63', 'BCMA': 'bb2121', 'CD22': 'm971', 'CD7': 'TH69',
    'CD5':  'H65',   'CD33': 'gemtuzumab-derived', 'MSLN': 'SS1', 'CD20': '2F2',
    'HER2': 'trastuzumab-derived',
}
scfv = SCFV_LIBRARY.get(car_target, 'novel_scFv_design_required')

# Full domain assembly
GMCSFR_SIGNAL = "MLLLVTSLLLCELPHPAFLLIP"
G4S3_LINKER   = "GGGGSGGGGSGGGGS"
CD8A_HINGE_TM = "TTTPAPRPPTPAPTIASQPLSLRPEACRPAAGGAVHTRGLDFACDIYIWAPLAGTCGVLLLSLVITLYC"
CD28_INTRA    = "RSKRSRLLHSDYMNMTPRRPGPTRKHYQPYAPPRDFAAYRS"
TNFRSF9_INTRA = "KRGRKKLLYIFKQGRDQALSFLSQTPKNFLNLRPRDQFRHSQAFLERNLKQLSGN"   # 4-1BB intracellular
CD3Z          = ("RVKFSRSAEPPASVQFHIPDREKTLAQETSQGSETMFPENLPNAFESQGPLHESPREATPQQLELPG"
                 "GDVDFCLKTEAQIPSIQLVNMFHFLAQERPTINIQIESSEDPEHEFEIIRSGNLQGAPNPAAPDQLQ"
                 "GLAPKEETQRK")

# Placeholder scFv sequences (not the real ones — clinical sequences are IP-protected)
SCFV_SEQS = {
    'FMC63': 'DIQMTQTTSSLSASLGDRVTISCRASQDISKYLNWYQQKPDGTVKLLIYHTSRLHSGVPSRFSGSGSGTDYSLTISNLEQEDIATYFCQQGNTLPYTFGGGTKLEITGGGGSGGGGSGGGGSEVKLQESGPGLVAPSQSLSVTCTVSGVSLPDYGVSWIRQPPRKGLEWLGVIWGSETTYYNSALKSRLTIIKDNSKSQVFLKMNSLQTDDTAIYYCAKHYYYGGSYAMDYWGQGTSVTVSS',
    'bb2121': 'QVQLVQSGAEVKKPGSSVKVSCKASGYTFTDYSINWVRQAPGQGLEWMGWINTETREPAYAYDFRGRFVFSLDTSVSTAYLQISSLKAEDTAVYYCALDYSYAMDYWGQGTLVTVSSGGGGSGGGGSGGGGSEIVLTQSPATLSLSPGERATLSCRASQSVSSYLAWYQQKPGQAPRLLIYDASNRATGIPARFSGSGSGTDFTLTISSLEPEDFAVYYCQQRSNWPPLTFGGGTKVEIK',
}
scfv_seq = SCFV_SEQS.get(scfv, 'SCFV_PLACEHOLDER_DESIGN_REQUIRED')

costim_seq = CD28_INTRA if costim_choice == 'CD28' else TNFRSF9_INTRA

full_car = (GMCSFR_SIGNAL + scfv_seq + CD8A_HINGE_TM + costim_seq + CD3Z) if scfv_seq != 'SCFV_PLACEHOLDER_DESIGN_REQUIRED' else None

# ─── PHASE 5: Output ─────────────────────────────────────────────────────────
design = {
    'car_target':            car_target,
    'indication':            indication,
    'delivery_cell':         deliv_cell,
    'persistence':           persist,
    'atlas_check': {
        'verdict':           car_verdict,
        'rationale':         car_rationale,
        'high_tissue_hits':  high_hits,
        'mod_tissue_hits':   mod_hits,
    },
    'lnp_choice': {
        'lnp':               lnp_choice,
        'tropism':           lnp_info['tropism'],
        'in_vivo_cart_use':  lnp_info['in_vivo_cart_use'],
        'notes':             lnp_info['notes'],
        'target_cells':      lnp_target_cells,
    },
    'fratricide_check': {
        'fratricide_risk':   fratricide,
        'rationale':         frat_reason,
        'mitigation':        mitigation,
    },
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

# CAR construct FASTA
with open('cart_construct.fasta', 'w') as f:
    if full_car:
        f.write(f">CAR_{car_target}_{costim_choice}_invivo\\n")
        # 60-char wrap
        for i in range(0, len(full_car), 60):
            f.write(full_car[i:i+60] + '\\n')
    else:
        f.write(f">CAR_{car_target}_designREQUIRED\\n# Novel target — scFv design needed via scfv_antibody_design workflow\\n")

with open('fratricide_check.json', 'w') as f:
    json.dump(design['fratricide_check'], f, indent=2)

# Human-readable
lines = [
    "╔══════════════════════════════════════════════════════════════════╗",
    "  In Vivo CAR-T Co-Design Report",
    f"  Target: {car_target}   |   Indication: {indication}",
    f"  Delivery cell: {deliv_cell}   |   Persistence: {persist}",
    "╚══════════════════════════════════════════════════════════════════╝",
    "",
    f"── PHASE 1: Atlas Safety Check ────────────────────────────────────",
    f"  Verdict:   {car_verdict}",
    f"  Rationale: {car_rationale}",
    "",
    f"── PHASE 2: LNP Tropism ───────────────────────────────────────────",
    f"  LNP:               {lnp_choice}",
    f"  Tropism:           {lnp_info['tropism']}",
    f"  In vivo CAR-T use: {lnp_info['in_vivo_cart_use']}",
    f"  Notes:             {lnp_info['notes']}",
    "",
    f"── PHASE 3: Fratricide Check ──────────────────────────────────────",
    f"  Risk:        {'YES' if fratricide else 'NO'}",
    f"  Rationale:   {frat_reason}",
]
if mitigation:
    lines.append(f"  Mitigation:  {mitigation}")
lines += [
    "",
    f"── PHASE 4: CAR Construct ─────────────────────────────────────────",
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
    f"── Overall Verdict: {design['overall_verdict']} ─────────────────────────",
    "",
    "── Clinical Precedents ────────────────────────────────────────────",
] + [f"  • {p}" for p in design['precedents']] + [
    "",
    "── Disclaimers ────────────────────────────────────────────────────",
] + [f"  • {d}" for d in design['disclaimers']]

with open('design_report.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')

print('\\n'.join(lines))
PYEOF

    python3 -c "print('in_vivo_cart_codesign: 1.0')" > versions.yml
    """
}

workflow { meta = [id: 'invivo_cart_run']; Channel.value(meta) | IN_VIVO_CART_CODESIGN }
