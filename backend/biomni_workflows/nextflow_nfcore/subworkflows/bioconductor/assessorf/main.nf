#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AssessORF
// In order to assess the quality of a set of predicted genes for a genome, evidence must first be mapp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AssessORF/inst/doc/UsingAssessORF.R
// Upstream  : DECIPHER
// Downstream: none
//
// Install: BiocManager::install("AssessORF")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASSESSORF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-assessorf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-assessorf:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-assessorf:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_assessorf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_assessorf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_assessorf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CompareAssessmentResults)
    library(jsonlite)

    # --- Unlink [] ---
    # Key functions: unlink
    ---------------------------------------------------------------------
    ## Remember to use 'unlink' to remove a database once it is no longer needed.
    unlink(databaseFile)
    # --- Readrds [] ---
    # Key functions: CompareAssessmentResults
    ---------------------------------------------------------------------
    resObj2 <- readRDS(system.file("extdata",
                                      "MGAS5005_PreSaved_ResultsObj_GeneMarkS2.rds",
                                      package = "AssessORF"))
    CompareAssessmentResults(currResObj, resObj2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_assessorf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_assessorf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_assessorf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASSESSORF:", paste0("    assessorf: ", packageVersion("AssessORF"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_assessorf_results.csv
    touch ${prefix}_assessorf_output.rds
    echo "BIOC_ASSESSORF:" > versions.yml
    echo "    assessorf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASSESSORF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASSESSORF(ch_input)

    emit:
    results  = BIOC_ASSESSORF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASSESSORF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASSESSORF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASSESSORF.out.versions  // channel: path(versions.yml)
}
