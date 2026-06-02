#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: blacksheepr
// Blacksheep is a tool designed for outlier analysis in the context of pairwise comparisons in an effo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/blacksheepr/inst/doc/blacksheepr_vignette.R
// Upstream  : SummarizedExperiment, pasilla
// Downstream: none
//
// Install: BiocManager::install("blacksheepr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BLACKSHEEPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-blacksheepr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-blacksheepr:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-blacksheepr:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_blacksheepr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_blacksheepr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_blacksheepr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Create SummarizedExperiment [] ---
    # Key functions: SummarizedExperiment
    suppressPackageStartupMessages(library(SummarizedExperiment))
    blacksheep_SE <- SummarizedExperiment(
    assays=list(counts=as.matrix(phosphotable)),
    # --- Deva analysis [] ---
    # Key functions: deva, deva_results, comparison_groupings, make_outlier_table, count_outliers, outlier_analysis, outlier_heatmap, make_comparison_columns
    plottable <- comptable[do.call(order, c(decreasing = TRUE,
    data.frame(comptable[,1:ncol(comptable)]))),]
    hm1 <- outlier_heatmap(outlier_analysis_out = outlier_analysis_out,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_blacksheepr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_blacksheepr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_blacksheepr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BLACKSHEEPR:", paste0("    blacksheepr: ", packageVersion("blacksheepr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_blacksheepr_results.csv
    touch ${prefix}_blacksheepr_output.rds
    echo "BIOC_BLACKSHEEPR:" > versions.yml
    echo "    blacksheepr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BLACKSHEEPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BLACKSHEEPR(ch_input)

    emit:
    results  = BIOC_BLACKSHEEPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BLACKSHEEPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BLACKSHEEPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BLACKSHEEPR.out.versions  // channel: path(versions.yml)
}
