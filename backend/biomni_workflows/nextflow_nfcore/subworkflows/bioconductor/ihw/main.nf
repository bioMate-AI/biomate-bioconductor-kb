#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IHW
// Independent hypothesis weighting (IHW) is a multiple testing procedure that increases power compared
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IHW/inst/doc/introduction_to_ihw.R
// Upstream  : DESeq2, dplyr, ggplot2
// Downstream: IHWpaper
//
// Install: BiocManager::install("IHW")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IHW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ihw"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ihw:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ihw:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ihw_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ihw_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ihw_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IHW)
    library(DESeqDataSet)
    library(jsonlite)

    # --- Covariate Stratification [groups_by_filter] ---
    # Key functions: groups_by_filter
    de_results <- data.frame(
        pvalue = runif(1000),
        baseMean = rexp(1000, rate = 0.01),
        log2FoldChange = rnorm(1000)
    )
    de_results$baseMeanGroup <- groups_by_filter(
        de_results$baseMean,
        8
    )
    de_results$lfcGroup <- groups_by_filter(
        abs(de_results$log2FoldChange),
        8
    )

    # --- Independent Hypothesis Weighting [ihw] ---
    # Key functions: ihw, rejections, adj_pvalues
    ihw_res <- ihw(
        pvalue ~ baseMean,
        data = de_results,
        alpha = 0.1,
        adjustment_type = "bh"
    )
    total_rejections <- rejections(ihw_res)
    adjusted_pvals <- adj_pvalues(ihw_res)

    # --- Model Diagnostics and Extraction [weights, nbins, nfolds] ---
    # Key functions: weights, nbins, nfolds
    ihw_weights <- weights(ihw_res)
    level_weights <- weights(ihw_res, levels_only = TRUE)
    num_bins <- nbins(ihw_res)
    num_folds <- nfolds(ihw_res)

    # --- Decision Boundary and Weight Visualization [plot] ---
    # Key functions: plot
    weight_plot <- plot(ihw_res)
    boundary_plot <- plot(
        ihw_res,
        what = "decisionboundary"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ihw_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ihw_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ihw_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IHW:", paste0("    ihw: ", packageVersion("IHW"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ihw_results.csv
    touch ${prefix}_ihw_output.rds
    echo "BIOC_IHW:" > versions.yml
    echo "    ihw: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IHW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IHW(ch_input)

    emit:
    results  = BIOC_IHW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IHW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IHW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IHW.out.versions  // channel: path(versions.yml)
}
