#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pgca
// Protein Group Code Algorithm (PGCA) is a computationally inexpensive algorithm to merge protein summ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pgca/inst/doc/intro.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pgca")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PGCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pgca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pgca:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pgca:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pgca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pgca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pgca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pgca)
    library(jsonlite)

    # --- Dictionary Application [] ---
    # Key functions: applyDict
    translated <- applyDict(
        BET2007_v339,
        BET2047_v339,
        dict = dict
    )


    # --- Dictionary Saving [] ---
    # Key functions: saveDict
    dictOutFile <- tempfile()
    saveDict(
        dict,
        file = dictOutFile
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pgca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pgca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pgca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PGCA:", paste0("    pgca: ", packageVersion("pgca"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pgca_results.csv
    touch ${prefix}_pgca_output.rds
    echo "BIOC_PGCA:" > versions.yml
    echo "    pgca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PGCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PGCA(ch_input)

    emit:
    results  = BIOC_PGCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PGCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PGCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PGCA.out.versions  // channel: path(versions.yml)
}
