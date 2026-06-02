#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: doppelgangR
// The main function is doppelgangR(), which takes as minimal input a list of ExpressionSet object, and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/doppelgangR/inst/doc/doppelgangR.R
// Upstream  : Biobase, curatedOvarianData
// Downstream: none
//
// Install: BiocManager::install("doppelgangR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOPPELGANGR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-doppelgangr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-doppelgangr:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-doppelgangr:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_doppelgangr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_doppelgangr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_doppelgangr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExpressionSet)
    library(jsonlite)

    # --- doppelgang R [] ---
    # Key functions: doppelgangR
    results1 <- doppelgangR(testesets, phenoFinder.args=NULL)
    # --- doppelgang R [] ---
    # Key functions: doppelgangR, ExpressionSet


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_doppelgangr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_doppelgangr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_doppelgangr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOPPELGANGR:", paste0("    doppelgangr: ", packageVersion("doppelgangR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_doppelgangr_results.csv
    touch ${prefix}_doppelgangr_output.rds
    echo "BIOC_DOPPELGANGR:" > versions.yml
    echo "    doppelgangr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOPPELGANGR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOPPELGANGR(ch_input)

    emit:
    results  = BIOC_DOPPELGANGR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOPPELGANGR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOPPELGANGR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOPPELGANGR.out.versions  // channel: path(versions.yml)
}
