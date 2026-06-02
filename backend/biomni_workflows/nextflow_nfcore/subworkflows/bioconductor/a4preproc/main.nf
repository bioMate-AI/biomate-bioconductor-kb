#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: a4Preproc
// Utility functions to pre-process data for the Automated Affymetrix Array Analysis set of packages.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/a4Preproc/inst/doc/a4Preproc-vignette.R
// Upstream  : ALL
// Downstream: a4, a4Base, a4Classif
//
// Install: BiocManager::install("a4Preproc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_A4PREPROC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-a4preproc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-a4preproc:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-a4preproc:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_a4preproc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_a4preproc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_a4preproc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(a4Preproc)
    library(jsonlite)

    # --- add Gene Info [] ---
    # Key functions: addGeneInfo
    library(ALL)
    data(ALL)
    a4ALL <- addGeneInfo(eset = ALL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_a4preproc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_a4preproc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_a4preproc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_A4PREPROC:", paste0("    a4preproc: ", packageVersion("a4Preproc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_a4preproc_results.csv
    touch ${prefix}_a4preproc_output.rds
    echo "BIOC_A4PREPROC:" > versions.yml
    echo "    a4preproc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_A4PREPROC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_A4PREPROC(ch_input)

    emit:
    results  = BIOC_A4PREPROC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_A4PREPROC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_A4PREPROC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_A4PREPROC.out.versions  // channel: path(versions.yml)
}
