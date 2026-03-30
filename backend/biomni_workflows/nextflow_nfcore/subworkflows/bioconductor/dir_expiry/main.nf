#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dir.expiry
// Implements an expiration system for access to versioned directories. Directories that have not been 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dir.expiry/inst/doc/userguide.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("dir.expiry")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIR_EXPIRY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dir_expiry"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dir.expiry:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dir.expiry:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dir_expiry_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dir_expiry_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dir_expiry_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dir.expiry)
    library(jsonlite)

    # --- Touchdirectory [] ---
    # Key functions: touchDirectory
    ---------------------------------------------------------------------
    library(dir.expiry)
    touchDirectory(version.dir)
    # --- Files [] ---
    # Key functions: files, path
    ---------------------------------------------------------------------
    list.files(cache.path)
    cat(readLines(file.path(cache.path, "1.0.0_dir.expiry")), sep="\n")
    # --- Unlockdirectory [] ---
    # Key functions: unlockDirectory
    ---------------------------------------------------------------------
    unlockDirectory(lock)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dir_expiry_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dir_expiry_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dir_expiry_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIR_EXPIRY:", paste0("    dir_expiry: ", packageVersion("dir.expiry"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dir_expiry_results.csv
    touch ${prefix}_dir_expiry_output.rds
    echo "BIOC_DIR_EXPIRY:" > versions.yml
    echo "    dir_expiry: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIR_EXPIRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIR_EXPIRY(ch_input)

    emit:
    results  = BIOC_DIR_EXPIRY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIR_EXPIRY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIR_EXPIRY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIR_EXPIRY.out.versions  // channel: path(versions.yml)
}
