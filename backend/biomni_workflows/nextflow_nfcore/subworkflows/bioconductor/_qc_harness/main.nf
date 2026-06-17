#!/usr/bin/env nextflow
/*
 * Bioconductor QC Harness (Track 3 Phase 3b, 2026-06-16)
 *
 * Standalone process that any Bioconductor subworkflow can `include` after
 * its core analysis step. The harness reads the workflow's qc_steps
 * declaration (a JSON list of labels from the 25-label taxonomy stored in
 * the workflows.qc_steps DB column) and emits a qc_metrics.json keyed by
 * label, mapping each declared QC step to a measurable diagnostic.
 *
 * Schema lives in backend/config/qc_evidence.yaml under bioconductor_qc.*
 * (added in commit 1ab27c2f9). Process keyword BIOC_QC_HARNESS is
 * registered in backend/lib/galaxy/jobs/qc_trace_monitor.py _S3_REPORT_PATHS
 * so the QC monitor reads the published artifact.
 *
 * Adoption pattern (Phase 3c, rolling):
 *   include { BIOC_QC_HARNESS } from '../_qc_harness/main.nf'
 *   workflow {
 *     CORE_ANALYSIS(input_ch)
 *     BIOC_QC_HARNESS(
 *       CORE_ANALYSIS.out.artifact,
 *       params.qc_steps_json     // e.g. '["count normalization","cell QC metrics"]'
 *     )
 *   }
 *
 * Current MVP: harness skeleton with status='not_computed (harness MVP;
 * metric impl pending)' per label. This unblocks adoption (the gate row
 * lands in audit ledger immediately) while individual metric R impls
 * land in follow-up commits without blocking the rollout.
 *
 * Per-label impl mapping (Phase 3c follow-on):
 *   missing-value handling             → na_fraction_remaining
 *   count normalization                → lib_size_cv ratio
 *   cell QC metrics                    → pct_mito_max, n_features_min
 *   low-count filtering                → genes_kept_fraction
 *   ...                                (see docs/20260615_QC_GATE_INVENTORY_AND_PLAN.md
 *                                       "Label → canonical metric → threshold mapping")
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.publish_dir_mode  = 'copy'

process BIOC_QC_HARNESS {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}/qc_harness" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(artifact)
    val(qc_steps_json)

    output:
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml", emit: versions

    script:
    def safe_steps = (qc_steps_json ?: '[]')
        .toString()
        .replace('"', '\\"')
    """
    export PARAM_QC_STEPS='${safe_steps}'
    export PARAM_ARTIFACT='${artifact}'

    python3 << 'PYEOF'
import json, os

# ── Load workflow's qc_steps declaration ─────────────────────────────────────
try:
    qc_steps = json.loads(os.environ.get('PARAM_QC_STEPS', '[]'))
    if not isinstance(qc_steps, list):
        qc_steps = []
except Exception:
    qc_steps = []

# ── 25-label taxonomy → canonical metric name + YAML row key ─────────────────
# Keys match labels in workflows.qc_steps; values point to the canonical
# bioconductor_qc.* gate row in qc_evidence.yaml + the metric name the
# qc_gate_reader expects to find in qc_metrics.json.
LABEL_TO_GATE = {
    'missing-value handling':            ('bioc_missing_value_handling',         'na_fraction_remaining'),
    'count normalization':               ('bioc_count_normalization',            'lib_size_cv_ratio'),
    'cell QC metrics':                   ('bioc_cell_qc_metrics',                'pct_mito_max'),
    'low-count filtering':               ('bioc_low_count_filtering',            'genes_kept_fraction'),
    'diagnostic MA/PCA QC':              ('bioc_diagnostic_ma_pca_qc',           'pc1_var_explained'),
    'dispersion/size-factor estimation': ('bioc_dispersion_size_factor',         'disp_outlier_fraction'),
    'batch-effect correction':           ('bioc_batch_effect_correction',        'kbet_acceptance_rate'),
    'highly-variable feature selection': ('bioc_hvg_selection',                  'hvg_count'),
    'TMM normalization':                 ('bioc_tmm_normalization',              'tmm_factor_in_range_fraction'),
    'variance-stabilizing normalization':('bioc_vsn_normalization',              'mean_sd_slope_after_vsn'),
    'doublet detection QC':              ('bioc_doublet_detection',              'doublet_rate_estimated'),
    'clustering QC':                     ('bioc_clustering_qc',                  'silhouette_mean'),
    'voom mean-variance modelling':      ('bioc_voom_fit',                       'voom_fit_smooth_residual'),
    'input validation':                  ('bioc_input_validation',               'input_validation_passes'),
    'filter low-expression genes':       ('bioc_low_count_filtering',            'genes_kept_fraction'),
    'per-cell QC metrics':               ('bioc_per_cell_qc_outliers',           'cells_flagged_outlier_fraction'),
    'dispersion QC plot':                ('bioc_dispersion_qc_plot',             'dispersion_plot_exists'),
    'prevalence/abundance filtering':    ('bioc_taxa_prevalence_filter',         'taxa_kept_fraction'),
    'array detection QC':                ('bioc_array_detection_qc',             'detection_call_rate'),
    'alignment/mapping QC':              ('bioc_alignment_mapping_qc',           'uniquely_mapped_pct'),
    'between-array normalization':       ('bioc_between_array_normalization',    'max_pairwise_quantile_ks'),
    'outlier detection':                 ('bioc_outlier_detection',              'flagged_sample_count'),
    'expression-level QC':               ('bioc_expression_level_qc',            'expression_dynamic_range_log2'),
    'outlier diagnostics':               ('bioc_outlier_detection',              'flagged_sample_count'),
    'normalization diagnostic plot':     ('bioc_normalization_diagnostic_plot',  'normalization_plot_exists'),
}

# ── Emit qc_metrics.json ─────────────────────────────────────────────────────
# Track 3 Phase 3b MVP: emit the schema for every declared qc_step. Each
# metric reports status='not_computed (harness MVP; metric impl pending)' —
# Phase 3c lands the per-metric R implementations rolling.
emitted = {
    'success':  True,
    'process':  'BIOC_QC_HARNESS',
    'domain':   'bioconductor',
    'declared_qc_steps': qc_steps,
    'gates_by_label':   {},
    'evidence_tier':    'mixed (per bioconductor_qc.* in qc_evidence.yaml)',
    'citation':         'see qc_evidence.yaml bioconductor_qc section per-label',
    'harness_version':  '0.1.0-mvp',
}

for label in qc_steps:
    gate_row, metric_name = LABEL_TO_GATE.get(label, (None, None))
    if gate_row is None:
        emitted['gates_by_label'][label] = {
            'gate_row': None,
            'status':   f'unknown_label (not in BIOC_QC_HARNESS LABEL_TO_GATE)',
        }
        continue
    emitted['gates_by_label'][label] = {
        'gate_row':     gate_row,
        'metric_name':  metric_name,
        'metric_value': None,
        'passes':       None,
        'status':       'not_computed (harness MVP; metric impl pending — see Phase 3c)',
    }

with open('qc_metrics.json', 'w') as f:
    json.dump(emitted, f, indent=2)

print(f'BIOC_QC_HARNESS emitted gates for {len(qc_steps)} declared labels')
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bioc_qc_harness: "0.1.0-mvp"
    END_VERSIONS
    """
}
