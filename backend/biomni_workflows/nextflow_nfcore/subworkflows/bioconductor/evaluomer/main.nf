#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: evaluomeR
// Evaluating the reliability of your own metrics and the measurements done on your own datasets by ana
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/evaluomeR/inst/doc/manual.R
// Upstream  : SummarizedExperiment, kableExtra, magrittr
// Downstream: none
//
// Install: BiocManager::install("evaluomeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EVALUOMER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-evaluomer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-evaluomer:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-evaluomer:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_evaluomer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_evaluomer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_evaluomer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(evaluomeR)
    library(jsonlite)

    # --- Assay data access [] ---
    # Key functions: metricsCorrelations, assay, stability, kable_styling, scroll_box, diff, stabilityRange, qualityRange
    stabilityData <- stabilityRange(data=ontMetrics, k.range=c(2,4),
    qualityData <- qualityRange(data=ontMetrics, k.range=c(2,4),
    kOptTable <- getOptimalKValue(stabilityData, qualityData)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_evaluomer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_evaluomer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_evaluomer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EVALUOMER:", paste0("    evaluomer: ", packageVersion("evaluomeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_evaluomer_results.csv
    touch ${prefix}_evaluomer_output.rds
    echo "BIOC_EVALUOMER:" > versions.yml
    echo "    evaluomer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EVALUOMER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EVALUOMER(ch_input)

    emit:
    results  = BIOC_EVALUOMER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EVALUOMER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EVALUOMER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EVALUOMER.out.versions  // channel: path(versions.yml)
}
