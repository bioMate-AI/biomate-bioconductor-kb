#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metabolomicsWorkbenchR
// This package provides functions for interfacing with the Metabolomics Workbench RESTful API. Study, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metabolomicsWorkbenchR/inst/doc/Introduction_to_metabolomicsWorkbenchR.R
// Upstream  : grid, httptest, structToolbox
// Downstream: none
//
// Install: BiocManager::install("metabolomicsWorkbenchR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METABOLOMICSWORKBENCHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metabolomicsworkbenchr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metabolomicsworkbenchr:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metabolomicsworkbenchr:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metabolomicsworkbenchr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metabolomicsworkbenchr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metabolomicsworkbenchr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metabolomicsWorkbenchR)
    library(jsonlite)

    # --- Do Query [] ---
    # Key functions: do_query
    ---------------------------------------------------------------------
    # search for all studies with "Diabetes" in the title and return a summary
    # --- Context Inputs [] ---
    # Key functions: context_inputs
    ---------------------------------------------------------------------
    # valid inputs for "study" context
    context_inputs('study')
    # --- Do Query [] ---
    # Key functions: do_query
    ---------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metabolomicsworkbenchr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metabolomicsworkbenchr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metabolomicsworkbenchr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METABOLOMICSWORKBENCHR:", paste0("    metabolomicsworkbenchr: ", packageVersion("metabolomicsWorkbenchR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolomicsworkbenchr_results.csv
    touch ${prefix}_metabolomicsworkbenchr_output.rds
    echo "BIOC_METABOLOMICSWORKBENCHR:" > versions.yml
    echo "    metabolomicsworkbenchr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METABOLOMICSWORKBENCHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METABOLOMICSWORKBENCHR(ch_input)

    emit:
    results  = BIOC_METABOLOMICSWORKBENCHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METABOLOMICSWORKBENCHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METABOLOMICSWORKBENCHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METABOLOMICSWORKBENCHR.out.versions  // channel: path(versions.yml)
}
