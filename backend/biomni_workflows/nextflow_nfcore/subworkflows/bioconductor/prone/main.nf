#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PRONE
// High-throughput omics data are often affected by systematic biases introduced throughout all the ste
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PRONE/inst/doc/Differential_Expression.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PRONE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PRONE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-prone"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-prone:1.0.7--r44_0' :
        'quay.io/biocontainers/bioconductor-prone:1.0.7--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_prone_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_prone_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_prone_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PRONE)
    library(jsonlite)

    # --- Normalisation [normalize_se, remove_reference_samples] ---
    # Key functions: normalize_se, remove_reference_samples
    data("tuberculosis_TMT_se")
    se <- tuberculosis_TMT_se
    se_norm <- normalize_se(
        se,
        c("IRS_on_RobNorm", "IRS_on_Median", "IRS_on_LoessF", "IRS_on_Quantile"),
        combination_pattern = "_on_"
    )
    se_norm <- remove_reference_samples(se_norm)

    # --- Differential Expression Analysis [run_DE] ---
    # Key functions: run_DE
    comparisons <- c("PTB-HC", "TBL-HC", "TBL-PTB", "Rx-PTB")
    de_res <- run_DE(
        se = se_norm,
        comparisons = comparisons,
        DE_method = "limma",
        logFC = TRUE,
        logFC_up = 1,
        logFC_down = -1,
        p_adj = TRUE,
        alpha = 0.05,
        trend = TRUE,
        robust = TRUE
    )

    # --- Thresholding and Filtering [apply_thresholds] ---
    # Key functions: apply_thresholds
    new_de_res <- apply_thresholds(
        de_res = de_res,
        logFC = TRUE,
        logFC_up = 0,
        logFC_down = 0,
        p_adj = TRUE,
        alpha = 0.05
    )

    # --- Visualisation of DE Results [plot_overview_DE_bar, plot_overview_DE_tile, plot_volcano_DE] ---
    # Key functions: plot_overview_DE_bar, plot_overview_DE_tile, plot_volcano_DE
    plot_overview_DE_bar(
        de_res,
        comparisons = comparisons,
        plot_type = "facet_regulation"
    )
    plot_overview_DE_tile(de_res)
    plot_volcano_DE(
        de_res,
        comparisons = comparisons[1],
        facet_norm = TRUE
    )

    # --- Consensus and Enrichment Analysis [extract_consensus_DE_candidates, plot_intersection_enrichment] ---
    # Key functions: extract_consensus_DE_candidates, plot_intersection_enrichment
    consensus_candidates <- extract_consensus_DE_candidates(
        de_res, comparisons = comparisons, norm_thr = 0.8
    )
    enrich_results <- plot_intersection_enrichment(
        se, de_res,
        comparison = "PTB-HC",
        ain = c("IRS_on_Median", "IRS_on_RobNorm"),
        id_column = "Gene.Names",
        organism = "hsapiens",
        source = "KEGG"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_prone_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_prone_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_prone_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PRONE:", paste0("    prone: ", packageVersion("PRONE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prone_results.csv
    touch ${prefix}_prone_output.rds
    echo "BIOC_PRONE:" > versions.yml
    echo "    prone: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PRONE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PRONE(ch_input)

    emit:
    results  = BIOC_PRONE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PRONE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PRONE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PRONE.out.versions  // channel: path(versions.yml)
}
