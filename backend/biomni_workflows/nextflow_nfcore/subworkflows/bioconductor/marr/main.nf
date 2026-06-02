#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: marr
// marr (Maximum Rank Reproducibility) is a nonparametric approach that detects reproducible signals us
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/marr/inst/doc/MarrVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("marr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MARR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-marr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-marr:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-marr:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_marr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_marr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_marr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(marr)
    library(Marr)
    library(MarrFeaturesfiltered)
    library(MarrFilterData)
    library(MarrSamplepairsfiltered)
    library(jsonlite)

    # --- Filtering and Diagnostics [] ---
    # Key functions: MarrFeaturesfiltered, MarrSamplepairsfiltered
    filtered_features <- MarrFeaturesfiltered(Marr_output)
    filtered_samples <- MarrSamplepairsfiltered(Marr_output)


    # --- Visualisation [] ---
    # Key functions: MarrPlotSamplepairs, MarrPlotFeatures
    MarrPlotSamplepairs(Marr_output)
    MarrPlotFeatures(Marr_output)


    # --- Data Filtering [] ---
    # Key functions: MarrFilterData
    filtered_by_features <- MarrFilterData(Marr_output, by = "features")
    filtered_by_samples <- MarrFilterData(Marr_output, by = "samplePairs")
    filtered_by_both <- MarrFilterData(Marr_output, by = "both")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_marr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_marr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_marr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MARR:", paste0("    marr: ", packageVersion("marr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_marr_results.csv
    touch ${prefix}_marr_output.rds
    echo "BIOC_MARR:" > versions.yml
    echo "    marr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MARR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MARR(ch_input)

    emit:
    results  = BIOC_MARR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MARR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MARR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MARR.out.versions  // channel: path(versions.yml)
}
