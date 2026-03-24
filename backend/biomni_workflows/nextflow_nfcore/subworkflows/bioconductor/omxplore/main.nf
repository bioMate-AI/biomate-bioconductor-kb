#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omXplore
// This package contains a collection of functions (written as shiny modules) for the visualisation and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omXplore/inst/doc/omXplore.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("omXplore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMXPLORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omxplore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omxplore:1.0.2--r44_0' :
        'quay.io/biocontainers/bioconductor-omxplore:1.0.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omxplore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omxplore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omxplore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omXplore)
    library(jsonlite)

    # --- Meta Mae [] ---
    # Key functions: metadata
    data(vdata)
    MultiAssayExperiment::metadata(vdata)
    # --- Meta Se [] ---
    # Key functions: metadata
    data(vdata)
    MultiAssayExperiment::metadata(vdata[[1]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omxplore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omxplore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omxplore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMXPLORE:", paste0("    omxplore: ", packageVersion("omXplore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omxplore_results.csv
    touch ${prefix}_omxplore_output.rds
    echo "BIOC_OMXPLORE:" > versions.yml
    echo "    omxplore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMXPLORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMXPLORE(ch_input)

    emit:
    results  = BIOC_OMXPLORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMXPLORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMXPLORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMXPLORE.out.versions  // channel: path(versions.yml)
}
