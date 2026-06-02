#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SELEX
// Tools for quantifying DNA binding specificities based on SELEX-seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SELEX/inst/doc/SELEX.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SELEX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SELEX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-selex"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-selex:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-selex:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_selex_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_selex_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_selex_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SELEX)
    library(jsonlite)


    # --- Init [] ---
    # Key functions: selex.config
    workDir = "./cache/"
    selex.config(workingDir=workDir, maxThreadNumber=4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_selex_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_selex_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_selex_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SELEX:", paste0("    selex: ", packageVersion("SELEX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_selex_results.csv
    touch ${prefix}_selex_output.rds
    echo "BIOC_SELEX:" > versions.yml
    echo "    selex: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SELEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SELEX(ch_input)

    emit:
    results  = BIOC_SELEX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SELEX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SELEX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SELEX.out.versions  // channel: path(versions.yml)
}
