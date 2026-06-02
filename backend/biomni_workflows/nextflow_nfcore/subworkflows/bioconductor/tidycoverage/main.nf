#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidyCoverage
// `tidyCoverage` framework enables tidy manipulation of collections of genomic tracks and features usi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidyCoverage/inst/doc/tidyCoverage.R
// Upstream  : AnnotationHub, ggplot2, plyranges, purrr, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("tidyCoverage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYCOVERAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidycoverage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidycoverage:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidycoverage:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidycoverage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidycoverage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidycoverage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidyCoverage)
    library(AnnotationHub)
    library(BigWigFileList)
    library(CoverageExperiment)
    library(GRanges)
    library(jsonlite)

    # --- Resolution Coarsening and Expansion [] ---
    # Key functions: coarsen, expand
    cov_coarse <- coarsen(cov_exp, window = 20)
    cov_expanded <- expand(cov_coarse)


    # --- Coverage Aggregation [] ---
    # Key functions: aggregate, as_tibble
    cov_aggregated <- aggregate(cov_exp, bin = 20)
    cov_tibble <- as_tibble(cov_aggregated)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidycoverage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidycoverage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidycoverage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYCOVERAGE:", paste0("    tidycoverage: ", packageVersion("tidyCoverage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidycoverage_results.csv
    touch ${prefix}_tidycoverage_output.rds
    echo "BIOC_TIDYCOVERAGE:" > versions.yml
    echo "    tidycoverage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYCOVERAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYCOVERAGE(ch_input)

    emit:
    results  = BIOC_TIDYCOVERAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYCOVERAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYCOVERAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYCOVERAGE.out.versions  // channel: path(versions.yml)
}
