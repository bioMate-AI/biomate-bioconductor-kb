#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggspavis
// Visualization functions for spatial transcriptomics data. Includes functions to generate several typ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggspavis/inst/doc/ggspavis_overview.R
// Upstream  : STexampleData, patchwork, scater
// Downstream: none
//
// Install: BiocManager::install("ggspavis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGSPAVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggspavis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggspavis:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggspavis:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_ggspavis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggspavis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggspavis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggspavis)
    library(jsonlite)


    # --- Out Width="60%" [] ---
    # Key functions: plotSpotQC, scatter, subsets_mito_percent
    plotSpotQC(spe, plot_type = "scatter", 
               x_metric = "subsets_mito_percent", y_metric = "sum", 
               x_threshold = 30, y_threshold = 400)

    # --- Warning=false [] ---
    # Key functions: rowData, rowSums, counts, plotFeatureQC, sessionInfo, histogram, feature_sum, low_abundance
    rowData(spe)$feature_sum <- rowSums(counts(spe))
    rowData(spe)$low_abundance <- rowSums(counts(spe) > 0) < 20

    p1 <- plotFeatureQC(spe, plot_type = "histogram", 
                        x_metric = "feature_sum", annotate = "low_abundance")
    p2 <- plotFeatureQC(spe, plot_type = "violin", 
                        x_metric = "feature_sum", annotate = "low_abundance")

    # display panels using patchwork
    p1 | p2

    ## -----------------------------------------------------------------------------
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggspavis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggspavis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggspavis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGSPAVIS:", paste0("    ggspavis: ", packageVersion("ggspavis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggspavis_results.csv
    touch ${prefix}_ggspavis_output.rds
    echo "BIOC_GGSPAVIS:" > versions.yml
    echo "    ggspavis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGSPAVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_GGSPAVIS(ch_input)

    emit:
    results  = BIOC_GGSPAVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGSPAVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGSPAVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGSPAVIS.out.versions  // channel: path(versions.yml)
}
