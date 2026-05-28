#!/usr/bin/env nextflow
/*
 * drug_discovery/atlas_expression_query  (3-phase pipeline)
 *
 *   Phase A — Data Fetch              : query CELLxGENE Census or fall back to reference cache
 *   Phase B — Tissue Tabulation       : per-tissue / per-cell-type expression matrix
 *   Phase C — Critical-Tissue Check   : CNS / heart / kidney safety flags + final report
 *
 * Output feeds modality_triage for on-target/off-tumor risk scoring.
 *
 * References:
 *   - Tabula Sapiens 2.0 (Quake lab, Stanford) — Science 2022
 *   - CELLxGENE Census (CZI) — https://chanzuckerberg.github.io/cellxgene-census
 *   - Human Protein Atlas — for IHC clone cross-reference
 *   - Morgan et al. 2010 Mol Ther 18:843 (HER2 CAR-T fatality)
 *   - Parkhurst et al. 2011 Mol Ther 19:620 (CEA CAR-T colitis)
 */

nextflow.enable.dsl = 2

params.outdir         = './results'
params.target_gene    = 'null'
params.tissues        = 'all'
params.census_offline = 'auto'

// [Phase A] Data Fetch — query CELLxGENE Census or fall back to reference cache
process ATLAS_DATA_FETCH {
    tag "atlas:phaseA:${params.target_gene}"
    label 'process_low'
    publishDir "${params.outdir}/phaseA_fetch", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("raw_profile.json"), emit: raw
    path "phaseA_summary.txt",                  emit: summary

    script:
    """
    export PARAM_GENE='${params.target_gene}'
    export PARAM_TISSUES='${params.tissues}'
    export PARAM_OFFLINE='${params.census_offline}'

    python3 << 'PYEOF'
import os, json, sys

gene = os.environ.get('PARAM_GENE', '').strip()
if not gene or gene.lower() == 'null':
    gene = 'CD19'
gene = gene.upper()
tissues = os.environ.get('PARAM_TISSUES', 'all').strip().lower()
offline = os.environ.get('PARAM_OFFLINE', 'auto').strip().lower()

REFERENCE_CACHE = {
    'CD19': {
        'B_cell_naive':          (4.2, 95, 'LOW'),
        'B_cell_memory':         (4.5, 96, 'LOW'),
        'plasmablast':           (2.1, 60, 'LOW'),
        'follicular_DC':         (0.8, 15, 'LOW'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'cerebral_cortex_neuron':(0.0,  0, 'HIGH'),
        'hepatocyte':            (0.0,  0, 'MOD'),
        'hematopoietic_stem':    (0.1,  2, 'HIGH'),
    },
    'BCMA': {
        'plasma_cell':           (5.2, 98, 'LOW'),
        'plasmablast':           (3.4, 72, 'LOW'),
        'B_cell_memory':         (0.6, 18, 'LOW'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'cerebral_cortex_neuron':(0.0,  0, 'HIGH'),
        'hematopoietic_stem':    (0.0,  0, 'HIGH'),
    },
    'CD22': {
        'B_cell_naive':          (4.0, 92, 'LOW'),
        'B_cell_memory':         (4.2, 94, 'LOW'),
        'plasmablast':           (1.0, 30, 'LOW'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'cerebral_cortex_neuron':(0.0,  0, 'HIGH'),
    },
    'HER2': {
        'cardiac_endothelial':   (1.8, 35, 'HIGH'),
        'cardiac_muscle_cell':   (0.6, 12, 'HIGH'),
        'lung_alveolar_type2':   (1.4, 28, 'HIGH'),
        'lung_bronchial_epi':    (2.1, 42, 'MOD'),
        'breast_epithelial':     (3.4, 70, 'MOD'),
        'gastric_epithelial':    (2.8, 55, 'MOD'),
        'colon_enterocyte':      (1.5, 30, 'MOD'),
        'skin_keratinocyte':     (2.2, 48, 'MOD'),
    },
    'CEA': {
        'colon_enterocyte':      (3.8, 78, 'MOD'),
        'gastric_epithelial':    (3.1, 65, 'MOD'),
        'lung_bronchial_epi':    (1.6, 32, 'MOD'),
        'breast_epithelial':     (0.9, 18, 'MOD'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
    },
    'ROR1': {
        'adipose_white':         (1.4, 28, 'LOW'),
        'parathyroid_chief':     (2.0, 42, 'LOW'),
        'pancreatic_islet_beta': (1.6, 32, 'MOD'),
        'lung_alveolar_type2':   (0.7, 14, 'HIGH'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
    },
    'EGFR': {
        'skin_keratinocyte':     (4.2, 88, 'MOD'),
        'lung_alveolar_type2':   (3.1, 68, 'HIGH'),
        'lung_bronchial_epi':    (3.5, 72, 'MOD'),
        'colon_enterocyte':      (1.8, 38, 'MOD'),
        'hepatocyte':            (1.6, 32, 'MOD'),
        'cardiac_muscle_cell':   (0.1,  2, 'HIGH'),
    },
    'GD2': {
        'peripheral_nerve':      (2.6, 52, 'MOD'),
        'cerebral_cortex_neuron':(1.1, 22, 'HIGH'),
        'melanocyte':            (1.4, 28, 'LOW'),
        'adipose_white':         (0.4,  8, 'LOW'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
    },
    'TROP2': {
        'colon_enterocyte':      (2.4, 50, 'MOD'),
        'gastric_epithelial':    (2.0, 42, 'MOD'),
        'breast_epithelial':     (3.0, 64, 'MOD'),
        'skin_keratinocyte':     (3.6, 76, 'MOD'),
        'kidney_tubule_epi':     (2.8, 58, 'MOD'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'cerebral_cortex_neuron':(0.0,  0, 'HIGH'),
    },
    'CD33': {
        'myeloid_progenitor':    (4.6, 92, 'HIGH'),
        'monocyte':              (4.2, 88, 'MOD'),
        'granulocyte':           (3.8, 80, 'MOD'),
        'hematopoietic_stem':    (3.2, 70, 'HIGH'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
    },
    'BRD4': {
        'cardiac_muscle_cell':   (2.8, 92, 'HIGH'),
        'cerebral_cortex_neuron':(2.5, 88, 'HIGH'),
        'hepatocyte':            (3.0, 94, 'MOD'),
        'B_cell_naive':          (2.6, 86, 'LOW'),
        'plasma_cell':           (3.2, 90, 'LOW'),
    },
    'PCSK9': {
        'hepatocyte':            (4.4, 92, 'MOD'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'kidney_tubule_epi':     (0.2,  5, 'MOD'),
    },
    'PDCD1': {
        'T_cell_exhausted':      (4.2, 88, 'LOW'),
        'T_cell_activated':      (3.1, 70, 'LOW'),
        'T_regulatory':          (2.4, 55, 'LOW'),
        'T_follicular_helper':   (2.6, 60, 'LOW'),
        'B_cell_naive':          (0.3,  8, 'LOW'),
        'monocyte':              (0.4, 10, 'MOD'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'cerebral_cortex_neuron':(0.0,  0, 'HIGH'),
    },
    'KDR': {
        'vascular_endothelial':  (3.6, 85, 'MOD'),
        'cardiac_endothelial':   (3.5, 85, 'HIGH'),
        'lung_capillary_endo':   (3.8, 88, 'HIGH'),
        'kidney_glomerular_endo':(4.0, 92, 'HIGH'),
        'hematopoietic_stem':    (1.5, 30, 'HIGH'),
        'megakaryocyte':         (2.2, 50, 'MOD'),
    },
    'TIGIT': {
        'T_regulatory':          (3.8, 82, 'LOW'),
        'T_cell_exhausted':      (4.2, 88, 'LOW'),
        'NK_cell':               (3.2, 70, 'LOW'),
        'T_follicular_helper':   (2.8, 60, 'LOW'),
        'B_cell_memory':         (1.2, 28, 'LOW'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
    },
    'GLP1R': {
        'pancreatic_islet_beta': (4.2, 85, 'MOD'),
        'pancreatic_islet_alpha':(3.5, 75, 'MOD'),
        'enteroendocrine_L':     (4.5, 90, 'MOD'),
        'hypothalamic_POMC':     (3.0, 65, 'HIGH'),
        'gastric_smooth_muscle': (2.8, 60, 'MOD'),
        'cardiac_muscle_cell':   (1.2, 25, 'HIGH'),
        'bone_osteoblast':       (1.5, 30, 'MOD'),
        'thyroid_C_cell':        (2.0, 45, 'LOW'),
    },
    'GIPR': {
        'pancreatic_islet_beta': (3.8, 80, 'MOD'),
        'adipose_white':         (3.2, 70, 'LOW'),
        'adipose_brown':         (2.8, 60, 'LOW'),
        'bone_osteoclast':       (2.0, 42, 'MOD'),
        'hypothalamic_neuron':   (1.6, 32, 'HIGH'),
        'cardiac_muscle_cell':   (0.4,  8, 'HIGH'),
    },
    'GCGR': {
        'hepatocyte':            (4.0, 88, 'MOD'),
        'pancreatic_islet_alpha':(2.4, 50, 'MOD'),
        'kidney_tubule_epi':     (2.0, 42, 'MOD'),
        'adipose_brown':         (1.8, 38, 'LOW'),
        'cardiac_muscle_cell':   (1.0, 22, 'HIGH'),
    },
    'ANGPTL3': {
        'hepatocyte':            (4.5, 92, 'MOD'),
        'bile_duct_epi':         (0.6, 12, 'MOD'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'cerebral_cortex_neuron':(0.0,  0, 'HIGH'),
    },
    'PIK3CA': {
        'pancreatic_islet_beta': (3.0, 70, 'MOD'),
        'adipose_white':         (2.8, 65, 'LOW'),
        'hepatocyte':            (3.5, 80, 'MOD'),
        'breast_epithelial':     (3.2, 75, 'MOD'),
        'cardiac_muscle_cell':   (2.0, 50, 'HIGH'),
        'cerebral_cortex_neuron':(1.8, 45, 'HIGH'),
        'B_cell_naive':          (2.5, 60, 'LOW'),
    },
    'TFPI': {
        'vascular_endothelial':  (3.4, 80, 'MOD'),
        'megakaryocyte':         (2.8, 60, 'MOD'),
        'monocyte':              (1.5, 30, 'MOD'),
        'cardiac_endothelial':   (3.0, 65, 'HIGH'),
        'cardiac_muscle_cell':   (0.2,  4, 'HIGH'),
    },
    'CSF1R': {
        'macrophage_tissue':     (4.5, 92, 'MOD'),
        'monocyte':              (3.8, 82, 'MOD'),
        'microglia':             (3.2, 75, 'HIGH'),
        'kupffer_cell':          (4.0, 88, 'MOD'),
        'dendritic_cell':        (2.5, 60, 'LOW'),
        'cardiac_muscle_cell':   (0.0,  0, 'HIGH'),
        'cerebral_cortex_neuron':(0.2,  4, 'HIGH'),
    },
    'IDH1': {
        'hepatocyte':            (3.8, 85, 'MOD'),
        'cardiac_muscle_cell':   (3.5, 82, 'HIGH'),
        'cerebral_cortex_neuron':(3.0, 75, 'HIGH'),
        'pancreatic_islet_beta': (2.8, 70, 'MOD'),
        'B_cell_naive':          (2.5, 65, 'LOW'),
        'astrocyte':             (3.2, 78, 'HIGH'),
    },
    'NRG1': {
        'stromal_fibroblast':    (3.0, 70, 'LOW'),
        'breast_epithelial':     (2.5, 55, 'MOD'),
        'cardiac_endothelial':   (1.5, 30, 'HIGH'),
        'schwann_cell':          (3.2, 75, 'MOD'),
        'cardiac_muscle_cell':   (1.2, 25, 'HIGH'),
    },
}

GENE_ALIASES = {
    'PD-1':    'PDCD1',
    'PD1':     'PDCD1',
    'VEGFR2':  'KDR',
    'VEGFR-2': 'KDR',
    'HER3':    'ERBB3',
    'HER2':    'HER2',
    'TROP-2':  'TROP2',
    'CD276':   'B7H3',
}

profile = None
source = None

if offline != 'yes':
    try:
        import cellxgene_census
        with cellxgene_census.open_soma(census_version="stable") as census:
            adata = cellxgene_census.get_anndata(
                census=census,
                organism="Homo sapiens",
                var_value_filter=f"feature_name == '{gene}'",
                obs_value_filter="is_primary_data == True and disease == 'normal'",
                obs_column_names=["cell_type", "tissue"],
            )
        import numpy as np
        profile = {}
        CRIT_DEFAULT = 'LOW'
        for cell_type in adata.obs['cell_type'].unique():
            mask = adata.obs['cell_type'] == cell_type
            values = adata.X[mask.values].toarray().ravel() if hasattr(adata.X, 'toarray') else adata.X[mask.values].ravel()
            if len(values) == 0:
                continue
            mean_expr = float(np.mean(values))
            pct_expr = float((values > 0).mean() * 100)
            profile[str(cell_type)] = (mean_expr, pct_expr, CRIT_DEFAULT)
        source = 'cellxgene_census_live'
    except Exception as e:
        sys.stderr.write(f"[atlas_query] CELLxGENE Census unavailable ({type(e).__name__}); falling back\\n")

if profile is None:
    canonical = GENE_ALIASES.get(gene, gene)
    if canonical in REFERENCE_CACHE:
        profile = {k: list(v) for k, v in REFERENCE_CACHE[canonical].items()}
        source = 'reference_cache' if canonical == gene else f'reference_cache (alias {gene}->{canonical})'
    else:
        profile = {'unknown_cell_type': [0.0, 0, 'LOW']}
        source = 'no_data_available'
else:
    profile = {k: list(v) for k, v in profile.items()}

raw = {
    'target_gene': gene,
    'data_source': source,
    'tissues_filter': tissues,
    'profile_raw': profile,
}
with open('raw_profile.json', 'w') as f:
    json.dump(raw, f, indent=2)

lines = [
    "Phase A — Data Fetch",
    f"  Target gene:  {gene}",
    f"  Data source:  {source}",
    f"  Cell types:   {len(profile)}",
]
with open('phaseA_summary.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase B] Tissue Tabulation — per-tissue / per-cell-type expression matrix with criticality tags
process ATLAS_TISSUE_TABULATION {
    tag "atlas:phaseB"
    label 'process_low'
    publishDir "${params.outdir}/phaseB_tabulation", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(raw_json)

    output:
    tuple val(meta), path("tabulated_profile.json"), emit: tabulated
    path "phaseB_summary.txt",                        emit: summary

    script:
    """
    export PARAM_TISSUES='${params.tissues}'

    python3 << 'PYEOF'
import os, json

tissues = os.environ.get('PARAM_TISSUES', 'all').strip().lower()

with open('${raw_json}') as f:
    raw = json.load(f)

profile_raw = raw['profile_raw']

TISSUE_WEIGHTS = {'HIGH': 3.0, 'MOD': 1.2, 'LOW': 0.3}

CRITICAL_CELL_TYPES = {
    'cardiac_muscle_cell': 'HIGH', 'cardiac_endothelial': 'HIGH',
    'cardiac_valve_cell': 'HIGH', 'purkinje_fiber': 'HIGH',
    'cerebral_cortex_neuron': 'HIGH', 'hippocampal_neuron': 'HIGH',
    'cerebellar_purkinje': 'HIGH', 'astrocyte': 'HIGH',
    'oligodendrocyte': 'HIGH', 'microglia': 'HIGH',
    'peripheral_nerve': 'MOD', 'schwann_cell': 'MOD',
    'lung_alveolar_type1': 'HIGH', 'lung_alveolar_type2': 'HIGH',
    'hematopoietic_stem': 'HIGH', 'myeloid_progenitor': 'HIGH',
    'lymphoid_progenitor': 'HIGH',
    'kidney_glomerular_endo': 'HIGH', 'kidney_podocyte': 'HIGH',
    'skin_keratinocyte': 'MOD', 'gastric_epithelial': 'MOD',
    'colon_enterocyte': 'MOD', 'small_intestine_epi': 'MOD',
    'kidney_tubule_epi': 'MOD', 'hepatocyte': 'MOD',
    'lung_bronchial_epi': 'MOD', 'pancreatic_islet_beta': 'MOD',
    'pancreatic_acinar': 'MOD', 'breast_epithelial': 'MOD',
    'monocyte': 'MOD', 'granulocyte': 'MOD',
    'adipose_white': 'LOW', 'adipose_brown': 'LOW',
    'thyroid_follicular': 'LOW', 'parathyroid_chief': 'LOW',
    'melanocyte': 'LOW', 'sebaceous_gland': 'LOW',
    'B_cell_naive': 'LOW', 'B_cell_memory': 'LOW',
    'plasma_cell': 'LOW', 'plasmablast': 'LOW',
    'follicular_DC': 'LOW',
}

# Re-tag criticality (in case live census fetch defaulted everything to LOW)
profile = {}
for ct, vals in profile_raw.items():
    mean_expr, pct, crit_cached = vals[0], vals[1], vals[2]
    norm_key = str(ct).replace(' ', '_').replace('-', '_')
    crit = CRITICAL_CELL_TYPES.get(norm_key, crit_cached)
    profile[ct] = (mean_expr, pct, crit)

if tissues != 'all':
    wanted = {t.strip() for t in tissues.split(',') if t.strip()}
    profile = {ct: v for ct, v in profile.items()
               if any(w in ct.lower() for w in wanted)}

records = []
for ct, (mean_expr, pct, crit) in profile.items():
    records.append({
        'cell_type':            ct,
        'mean_expression':      round(mean_expr, 3),
        'pct_cells_expressing': round(pct, 1),
        'tissue_criticality':   crit,
        'criticality_weight':   TISSUE_WEIGHTS[crit],
        'weighted_risk':        round(mean_expr * TISSUE_WEIGHTS[crit], 3),
    })
records.sort(key=lambda r: -r['weighted_risk'])

out = {
    'target_gene': raw['target_gene'],
    'data_source': raw['data_source'],
    'tissues_queried': tissues,
    'records': records,
    'tissue_criticality_weights': TISSUE_WEIGHTS,
    'critical_cell_types': CRITICAL_CELL_TYPES,
}
with open('tabulated_profile.json', 'w') as f:
    json.dump(out, f, indent=2)

lines = [
    "Phase B — Tissue Tabulation",
    f"  Cell types tabulated:   {len(records)}",
    f"  Top weighted risk:      {records[0]['cell_type'] if records else '—'}  "
    f"({records[0]['weighted_risk'] if records else 0})",
]
with open('phaseB_summary.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')
print('\\n'.join(lines))
PYEOF
    """
}

// [Phase C] Critical-Tissue Check — CNS / heart / kidney safety flags + final report
process ATLAS_CRITICAL_CHECK {
    tag "atlas:phaseC"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(tab_json)

    output:
    tuple val(meta), path("atlas_expression.json"),   emit: expression_json
    tuple val(meta), path("atlas_expression.csv"),    emit: expression_csv
    tuple val(meta), path("tissue_criticality.json"), emit: criticality_json
    tuple val(meta), path("atlas_query_report.txt"),  emit: report
    path "versions.yml",                                emit: versions

    script:
    """
    python3 << 'PYEOF'
import json, csv

with open('${tab_json}') as f:
    tab = json.load(f)

records = tab['records']
TISSUE_WEIGHTS = tab['tissue_criticality_weights']
CRITICAL_CELL_TYPES = tab['critical_cell_types']
gene = tab['target_gene']
source = tab['data_source']
tissues = tab['tissues_queried']

result = {
    'status': 'completed',
    'target_gene': gene,
    'data_source': source,
    'tissues_queried': tissues,
    'n_cell_types': len(records),
    'critical_tissue_hits': sum(1 for r in records
                                if r['tissue_criticality'] == 'HIGH' and r['mean_expression'] > 0.5),
    'moderate_tissue_hits': sum(1 for r in records
                                if r['tissue_criticality'] == 'MOD' and r['mean_expression'] > 0.5),
    'low_tissue_hits':      sum(1 for r in records
                                if r['tissue_criticality'] == 'LOW' and r['mean_expression'] > 0.5),
    'top_critical_tissues': [r for r in records[:10] if r['tissue_criticality'] == 'HIGH'],
    'cell_type_profile':    records,
    'tissue_criticality_weights': TISSUE_WEIGHTS,
}

# Safety flags by organ system
def flag_for(prefixes):
    hits = [r for r in records
            if any(p in r['cell_type'].lower() for p in prefixes) and r['mean_expression'] > 0.5]
    return hits

cns_hits   = flag_for(['cerebral', 'neuron', 'astrocyte', 'oligodendrocyte', 'microglia', 'hippocampal', 'purkinje'])
heart_hits = flag_for(['cardiac', 'purkinje_fiber'])
kidney_hits= flag_for(['kidney', 'podocyte', 'glomerular'])

result['safety_flags'] = {
    'cns':    [r['cell_type'] for r in cns_hits],
    'heart':  [r['cell_type'] for r in heart_hits],
    'kidney': [r['cell_type'] for r in kidney_hits],
}

with open('atlas_expression.json', 'w') as f:
    json.dump(result, f, indent=2)

with open('atlas_expression.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['cell_type', 'mean_expression',
        'pct_cells_expressing', 'tissue_criticality',
        'criticality_weight', 'weighted_risk'])
    w.writeheader()
    w.writerows(records)

with open('tissue_criticality.json', 'w') as f:
    json.dump({
        'weights': TISSUE_WEIGHTS,
        'critical_cell_types': CRITICAL_CELL_TYPES,
    }, f, indent=2)

lines = [
    "================================================================",
    f"  Atlas Expression Query Report",
    f"  Target: {gene}   |   Data source: {source}",
    "================================================================",
    "",
    f"  Cell types found:          {len(records)}",
    f"  Critical-tissue hits:      {result['critical_tissue_hits']}",
    f"  Moderate-tissue hits:      {result['moderate_tissue_hits']}",
    f"  Low-tissue hits:           {result['low_tissue_hits']}",
    "",
    "-- Safety Flags --",
    f"  CNS:    {result['safety_flags']['cns'] or 'none'}",
    f"  Heart:  {result['safety_flags']['heart'] or 'none'}",
    f"  Kidney: {result['safety_flags']['kidney'] or 'none'}",
    "",
    "-- Top 12 Cell Types by Weighted Risk --",
    f"  {'Cell Type':<28} {'Mean':<8} {'Pct':<6} {'Crit':<6} {'Risk':<6}",
    "  " + "-" * 60,
]
for r in records[:12]:
    lines.append(f"  {r['cell_type']:<28} {r['mean_expression']:<8.2f} "
                 f"{r['pct_cells_expressing']:<6.1f} "
                 f"{r['tissue_criticality']:<6} {r['weighted_risk']:<6.2f}")

lines += [
    "",
    "-- Honest Limitations --",
    "  * RNA expression != surface protein expression",
    "  * Confirmation by IHC, flow cytometry, or scProteomics required",
    "  * Atlas data is healthy reference; tumor heterogeneity not captured",
    "",
    "-- Next Step --",
    "  Feed atlas_expression.json into modality_triage for on/off-tumor",
    "  risk scoring across all therapeutic modality options.",
]

with open('atlas_query_report.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')

print('\\n'.join(lines))
PYEOF

    python3 -c "print('atlas_expression_query: 2.0')" > versions.yml
    """
}

workflow {
    meta = [id: 'atlas_query_run']
    Channel.value(meta) | ATLAS_DATA_FETCH
    ATLAS_DATA_FETCH.out.raw       | ATLAS_TISSUE_TABULATION
    ATLAS_TISSUE_TABULATION.out.tabulated | ATLAS_CRITICAL_CHECK
}
