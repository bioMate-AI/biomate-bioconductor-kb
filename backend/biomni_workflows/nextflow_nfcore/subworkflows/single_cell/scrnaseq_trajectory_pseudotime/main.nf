#!/usr/bin/env nextflow
/*
 * single_cell/scrnaseq_trajectory_pseudotime
 *
 * Trajectory inference + pseudotime + trajectory-DE for clustered + annotated
 * scRNA-seq data. Takes the output of scrnaseq_standard_endtoend (or any
 * h5ad with clusters + UMAP) and identifies lineages with Slingshot, fits
 * gene-expression GAMs along each lineage with tradeSeq, and optionally
 * tests trajectory differences across conditions via condiments.
 *
 * Compute tier: T2 CPU 16 vCPU / 64 GB Balanced (locked).
 * Rationale: mgcv::gam has no CUDA path; tradeSeq is CPU-bound + memory-bound.
 * BiocParallel workers each copy the matrix (#245) → workers=4 locked.
 *
 * Pipeline:
 *   1. Load + validate h5ad (must have cluster + embedding)
 *   2. HVG subset + build SingleCellExperiment
 *   3. Slingshot lineage fit
 *   4. tradeSeq GAM fit (lineage-split if cells > lineage_split_threshold)
 *   5. Association + startVsEnd + earlyDE gene tests
 *   6. Optional condiments comparison
 *   7. Methods report + per-lineage gene-trend gallery
 *
 * References:
 *   - Street et al. 2018 BMC Genomics (Slingshot)
 *   - Van den Berge et al. 2020 Nat Commun (tradeSeq)
 *   - Roux de Bézieux et al. 2024 Nat Commun (condiments)
 *
 * Spec doc: docs/20260616_SC_WORKFLOW_IMPLEMENTATION_REQUIREMENT_3_WORKFLOWS.md
 *           § Spec 2
 */

nextflow.enable.dsl = 2

params.outdir                       = './results'
params.annotated_h5ad               = 'null'        // input h5ad with clusters (required)
params.condition_labels             = 'null'        // optional 2-col CSV cell_id,condition
params.start_cluster                = 'null'        // EITHER start_cluster
params.start_celltype               = 'null'        // OR start_celltype (required if no start_cluster)
params.embedding                    = 'X_umap'      // X_umap | X_pca | X_diffmap
params.n_top_hvgs_for_trajectory    = '2000'
params.extend_curves                = 'y'           // y | n
params.n_knots_gam                  = '6'
params.fdr_threshold                = '0.05'
params.condiments_test              = 'none'        // none | topology | progression | differentialFateSelection
params.bpparam_workers              = '4'           // LOCKED at 4 per tradeSeq #245
params.lineage_split_threshold      = '20000'       // cells > this → split per lineage

process SCRNASEQ_TRAJECTORY_PSEUDOTIME {
    tag "$meta.id"
    label 'process_high_memory'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/sc-trajectory:v1' \
        : 'biomate/sc-trajectory:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("pseudotime_per_cell.csv"),  emit: pseudotime
    tuple val(meta), path("association_genes.csv"),    emit: assoc
    tuple val(meta), path("startvsend_genes.csv"),     emit: startvsend
    tuple val(meta), path("earlyDE_genes.csv"),        emit: early_de
    tuple val(meta), path("umap_slingshot.png"),       emit: viz_slingshot
    tuple val(meta), path("umap_pseudotime.png"),      emit: viz_pseudotime
    tuple val(meta), path("methods_report.html"),      emit: report
    tuple val(meta), path("trajectory_results.tar.gz"),emit: archive
    path "versions.yml",                                emit: versions

    script:
    """
    # ---------------------------------------------------------------
    # STAGE 1 — Load + validate h5ad
    # ---------------------------------------------------------------
    Rscript /opt/biomate/trajectory/validate_input.R \\
        --h5ad ${params.annotated_h5ad} \\
        --start_cluster ${params.start_cluster} \\
        --start_celltype ${params.start_celltype}

    # ---------------------------------------------------------------
    # STAGE 2 — HVG subset + build SingleCellExperiment
    # AnnData → SCE conversion bundled here (do not depend on
    # zellkonverter id 12641 which is exec_error)
    # ---------------------------------------------------------------
    Rscript /opt/biomate/trajectory/h5ad_to_sce.R \\
        --h5ad ${params.annotated_h5ad} \\
        --n_hvgs ${params.n_top_hvgs_for_trajectory} \\
        --out sce_for_traj.rds

    # ---------------------------------------------------------------
    # STAGE 3 — Slingshot lineage fit
    # ---------------------------------------------------------------
    Rscript /opt/biomate/trajectory/slingshot_fit.R \\
        --sce sce_for_traj.rds \\
        --start_cluster ${params.start_cluster} \\
        --start_celltype ${params.start_celltype} \\
        --embedding ${params.embedding} \\
        --extend ${params.extend_curves} \\
        --out_curves slingshot_curves.rds \\
        --out_pseudotime pseudotime_per_cell.csv \\
        --plots umap_slingshot.png,umap_pseudotime.png

    # ---------------------------------------------------------------
    # STAGE 4 — tradeSeq GAM fit (lineage-split if needed)
    # BiocParallel workers=${params.bpparam_workers} locked per #245
    # ---------------------------------------------------------------
    Rscript /opt/biomate/trajectory/tradeseq_fit.R \\
        --sce sce_for_traj.rds \\
        --curves slingshot_curves.rds \\
        --n_knots ${params.n_knots_gam} \\
        --workers ${params.bpparam_workers} \\
        --lineage_split_threshold ${params.lineage_split_threshold} \\
        --out tradeseq_gam.rds \\
        --diag_plot gam_diag.png

    # ---------------------------------------------------------------
    # STAGE 5 — Association + startVsEnd + earlyDE
    # ---------------------------------------------------------------
    Rscript /opt/biomate/trajectory/tradeseq_tests.R \\
        --gam tradeseq_gam.rds \\
        --fdr ${params.fdr_threshold} \\
        --out_assoc association_genes.csv \\
        --out_startvsend startvsend_genes.csv \\
        --out_earlyde earlyDE_genes.csv \\
        --heatmap association_heatmap.png \\
        --trends gene_trends.png

    # ---------------------------------------------------------------
    # STAGE 6 — Optional condiments comparison
    # ---------------------------------------------------------------
    if [ "${params.condiments_test}" != "none" ]; then
        Rscript /opt/biomate/trajectory/condiments_run.R \\
            --sce sce_for_traj.rds \\
            --curves slingshot_curves.rds \\
            --conditions ${params.condition_labels} \\
            --test ${params.condiments_test} \\
            --out condiments_result.csv \\
            --plot condiments_plot.png
    fi

    # ---------------------------------------------------------------
    # STAGE 7 — Methods report
    # ---------------------------------------------------------------
    Rscript /opt/biomate/trajectory/render_report.R \\
        --pseudotime pseudotime_per_cell.csv \\
        --assoc association_genes.csv \\
        --params params.json \\
        --out methods_report.html

    tar -czf trajectory_results.tar.gz \\
        pseudotime_per_cell.csv association_genes.csv startvsend_genes.csv \\
        earlyDE_genes.csv umap_slingshot.png umap_pseudotime.png \\
        association_heatmap.png gene_trends.png methods_report.html

    cat <<EOF > versions.yml
    "${task.process}":
        slingshot: \$(Rscript -e "cat(as.character(packageVersion('slingshot')))")
        tradeSeq: \$(Rscript -e "cat(as.character(packageVersion('tradeSeq')))")
        condiments: \$(Rscript -e "cat(as.character(packageVersion('condiments')))")
        mgcv: \$(Rscript -e "cat(as.character(packageVersion('mgcv')))")
    EOF
    """
}
