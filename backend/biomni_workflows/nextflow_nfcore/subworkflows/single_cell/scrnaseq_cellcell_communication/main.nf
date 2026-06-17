#!/usr/bin/env nextflow
/*
 * single_cell/scrnaseq_cellcell_communication
 *
 * Cell-cell communication INFERENCE for annotated scRNA-seq. Wraps LIANA+
 * (consensus across CellChat / CellPhoneDB / NATMI / SingleCellSignalR /
 * Connectome / logFC) to score every (source_celltype, target_celltype,
 * ligand, receptor) tuple, optionally tests condition-specific signaling,
 * and chains downstream to CCPlotR (id 11052) + InterCellar (id 11646)
 * for visualization and interactive exploration.
 *
 * THIS WORKFLOW IS THE INFERENCE LAYER ONLY. Visualization is delegated
 * to existing tested workflows (CCPlotR 11052 ok_warnings, InterCellar
 * 11646 ok_warnings).
 *
 * Pipeline:
 *   1. Validate input (celltype col + min cells per type + raw counts)
 *   2. Load LR resource (bundled cache by default; live OmnipathR if opt-in)
 *   3. Run LIANA+ scoring
 *   4. Aggregate + rank pairs across methods + emit CCPlotR TSV
 *   5. Condition-stratified comparison (optional)
 *   6. decoupler TF-activity follow-up (optional)
 *   7. Methods report; chain to CCPlotR (11052) + InterCellar (11646)
 *
 * References:
 *   - Dimitrov et al. 2022 Nat Commun (LIANA+)
 *   - Türei et al. 2021 Mol Syst Biol (OmniPath)
 *   - Browaeys et al. 2020 Nat Methods (NicheNet/baseline)
 *   - Badia-i-Mompel et al. 2022 Bioinform Adv (decoupler)
 *
 * Spec doc: docs/20260616_SC_WORKFLOW_IMPLEMENTATION_REQUIREMENT_3_WORKFLOWS.md
 *           § Spec 3
 */

nextflow.enable.dsl = 2

params.outdir                       = './results'
params.annotated_h5ad               = 'null'         // required input
params.omnipath_resource            = 'false'        // true → live fetch; false → bundled cache
params.celltype_key                 = 'celltype'
params.condition_key                = 'null'         // optional, e.g. 'lesion_type'
params.methods                      = 'consensus'    // comma list
params.min_cells_per_celltype       = '10'
params.resource_name                = 'consensus'
params.top_n_pairs                  = '50'
params.run_decoupler_followup       = 'true'
params.assume_raw_counts            = 'true'

process SCRNASEQ_CELLCELL_COMMUNICATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/liana-plus:v1' \
        : 'biomate/liana-plus:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("liana_results.csv"),       emit: liana
    tuple val(meta), path("top_lr_pairs.csv"),        emit: top_pairs
    tuple val(meta), path("liana_for_ccplotr.tsv"),   emit: ccplotr_input
    tuple val(meta), path("methods_report.html"),     emit: report
    tuple val(meta), path("liana_results.tar.gz"),    emit: archive
    tuple val(meta), path("condition_diff_lr.csv"),   emit: condition_diff,  optional: true
    tuple val(meta), path("tf_activity_per_target.csv"), emit: tf_activity,  optional: true
    path "versions.yml",                              emit: versions

    script:
    """
    # ---------------------------------------------------------------
    # STAGE 1 — Validate input
    # Gates: has_celltype_col, n_valid_celltypes>=3, mean_X_modulus_check>=50
    # ---------------------------------------------------------------
    python /opt/biomate/cellcomm/validate_input.py \\
        --h5ad ${params.annotated_h5ad} \\
        --celltype_key ${params.celltype_key} \\
        --min_cells ${params.min_cells_per_celltype} \\
        --assume_raw_counts ${params.assume_raw_counts}

    # ---------------------------------------------------------------
    # STAGE 2 — Load LR resource
    # ---------------------------------------------------------------
    if [ "${params.omnipath_resource}" = "true" ]; then
        Rscript /opt/biomate/cellcomm/load_omnipath_live.R --out resource.csv
    else
        cp /opt/biomate/cellcomm/cache/${params.resource_name}.parquet resource.parquet
        python /opt/biomate/cellcomm/parquet_to_csv.py resource.parquet resource.csv
    fi

    # ---------------------------------------------------------------
    # STAGE 3 — Run LIANA+ scoring
    # ---------------------------------------------------------------
    python /opt/biomate/cellcomm/run_liana.py \\
        --h5ad ${params.annotated_h5ad} \\
        --celltype_key ${params.celltype_key} \\
        --resource resource.csv \\
        --methods ${params.methods} \\
        --out_results liana_results.csv \\
        --out_parquet liana_consensus.parquet

    # ---------------------------------------------------------------
    # STAGE 4 — Aggregate + rank + emit CCPlotR TSV
    # ---------------------------------------------------------------
    python /opt/biomate/cellcomm/aggregate_rank.py \\
        --liana liana_results.csv \\
        --top_n ${params.top_n_pairs} \\
        --out_top top_lr_pairs.csv \\
        --out_ccplotr liana_for_ccplotr.tsv

    # ---------------------------------------------------------------
    # STAGE 5 — Condition-stratified comparison (optional)
    # ---------------------------------------------------------------
    if [ "${params.condition_key}" != "null" ]; then
        python /opt/biomate/cellcomm/condition_diff.py \\
            --h5ad ${params.annotated_h5ad} \\
            --liana liana_results.csv \\
            --condition_key ${params.condition_key} \\
            --out condition_diff_lr.csv \\
            --plot condition_diff_volcano.png
    fi

    # ---------------------------------------------------------------
    # STAGE 6 — decoupler TF activity (optional)
    # ---------------------------------------------------------------
    if [ "${params.run_decoupler_followup}" = "true" ]; then
        python /opt/biomate/cellcomm/decoupler_followup.py \\
            --h5ad ${params.annotated_h5ad} \\
            --liana liana_results.csv \\
            --out tf_activity_per_target.csv \\
            --plot tf_activity_heatmap.png
    fi

    # ---------------------------------------------------------------
    # STAGE 7 — Methods report
    # Chained downstream (CCPlotR id 11052 + InterCellar id 11646)
    # handled by the orchestrator once liana_for_ccplotr.tsv emits.
    # ---------------------------------------------------------------
    python /opt/biomate/cellcomm/render_report.py \\
        --liana liana_results.csv \\
        --top top_lr_pairs.csv \\
        --params params.json \\
        --out methods_report.html

    tar -czf liana_results.tar.gz \\
        liana_results.csv top_lr_pairs.csv liana_for_ccplotr.tsv \\
        methods_report.html \\
        \$([ -f condition_diff_lr.csv ] && echo "condition_diff_lr.csv condition_diff_volcano.png") \\
        \$([ -f tf_activity_per_target.csv ] && echo "tf_activity_per_target.csv tf_activity_heatmap.png")

    cat <<EOF > versions.yml
    "${task.process}":
        liana: \$(python -c "import liana; print(liana.__version__)")
        decoupler: \$(python -c "import decoupler; print(decoupler.__version__)")
        omnipath: \$(python -c "import omnipath; print(omnipath.__version__)")
        resource_version: ${params.resource_name}@2026.06
    EOF
    """
}
