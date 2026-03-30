#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: frmaTools
// Tools for advanced use of the frma package.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/frmaTools/inst/doc/frmaTools.R
// Upstream  : frmaExampleData
// Downstream: none
//
// Install: BiocManager::install("frmaTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRMATOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-frmatools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-frmatools:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-frmatools:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_frmatools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_frmatools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_frmatools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(frmaTools)
    library(jsonlite)

    # --- Makevectorsaffybatch [] ---
    # Key functions: makeVectorsAffyBatch
    ## vectors <- makeVectorsAffyBatch(files, batch.id)
    # --- Data [] ---
    # Key functions: data
    library(frmaExampleData)
    data(list="AffyBatch133atag")
    # --- Convertplatform [] ---
    # Key functions: convertPlatform
    object <- convertPlatform(AffyBatch133atag, "hgu133a")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_frmatools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_frmatools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_frmatools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FRMATOOLS:", paste0("    frmatools: ", packageVersion("frmaTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_frmatools_results.csv
    touch ${prefix}_frmatools_output.rds
    echo "BIOC_FRMATOOLS:" > versions.yml
    echo "    frmatools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FRMATOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FRMATOOLS(ch_input)

    emit:
    results  = BIOC_FRMATOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FRMATOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FRMATOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FRMATOOLS.out.versions  // channel: path(versions.yml)
}
