#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rawrr
// This package wraps the functionality of the RawFileReader .NET assembly. Within the R environment, s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rawrr/inst/doc/rawrr.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("rawrr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAWRR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rawrr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rawrr:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rawrr:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rawrr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rawrr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rawrr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(jsonlite)

    # --- Access ExperimentHub data [] ---
    # Key functions: ExperimentHub, normalizePath
    library(ExperimentHub)
    eh <- ExperimentHub::ExperimentHub()
    EH4547 <- normalizePath(eh[["EH4547"]])
    # --- InstallRawFileReaderDLLs analysis [] ---
    # Key functions: include_graphics, installRawFileReaderDLLs, installRawrrExe, readFileHeader, readSpectrum, makeAccessor, maxIonTime, readChromatogram


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rawrr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rawrr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rawrr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAWRR:", paste0("    rawrr: ", packageVersion("rawrr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rawrr_results.csv
    touch ${prefix}_rawrr_output.rds
    echo "BIOC_RAWRR:" > versions.yml
    echo "    rawrr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAWRR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAWRR(ch_input)

    emit:
    results  = BIOC_RAWRR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAWRR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAWRR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAWRR.out.versions  // channel: path(versions.yml)
}
