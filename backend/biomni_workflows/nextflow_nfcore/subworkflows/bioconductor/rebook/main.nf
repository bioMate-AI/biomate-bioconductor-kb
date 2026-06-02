#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rebook
// Provides utilities to re-use content across chapters of a Bioconductor book. This is mostly based on
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rebook/inst/doc/userguide.R
// Upstream  : none
// Downstream: csawBook, OSCA, OSCA.advanced, OSCA.basic, OSCA.intro
//
// Install: BiocManager::install("rebook")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REBOOK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rebook"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rebook:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rebook:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rebook_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rebook_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rebook_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rebook)
    library(jsonlite)


    # --- Results="asis" [] ---
    # Key functions: extractCached, godzilla
    extractCached(example, chunk="godzilla-1954", object="godzilla")

    ## -----------------------------------------------------------------------------
    godzilla

    # --- Results="asis" [] ---
    # Key functions: extractCached, godzilla, ghidorah
    extractCached(example, chunk="ghidorah-1964", object=c("godzilla", "ghidorah"))

    ## -----------------------------------------------------------------------------
    godzilla
    ghidorah

    # --- Results="asis" [] ---
    # Key functions: extractCached, godzilla
    extractCached(example, chunk="godzilla-2014", object="godzilla")

    ## -----------------------------------------------------------------------------
    godzilla

    # --- Results="asis" [] ---
    # Key functions: extractCached, link, mechagodzilla, godzilla, installation
    extractCached(example, chunk="godzilla-2014", object=c("mechagodzilla", "godzilla"))

    ## -----------------------------------------------------------------------------
    godzilla
    mechagodzilla

    ## -----------------------------------------------------------------------------
    link("installation", "OSCA.intro")
    link("some-comments-on-experimental-design", "OSCA.intro")
    link("fig:sce-structure", "OSCA.intro")

    # --- Results="asis" [] ---
    # Key functions: extractFromPackage, clustering
    extractFromPackage("lun-416b.Rmd", chunk="clustering", 
        objects='sce.416b', package="OSCA.workflows")

    ## -----------------------------------------------------------------------------
    sce.416b

    # --- Results="asis" [] ---
    # Key functions: prettySessionInfo
    prettySessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rebook_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rebook_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rebook_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REBOOK:", paste0("    rebook: ", packageVersion("rebook"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rebook_results.csv
    touch ${prefix}_rebook_output.rds
    echo "BIOC_REBOOK:" > versions.yml
    echo "    rebook: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REBOOK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REBOOK(ch_input)

    emit:
    results  = BIOC_REBOOK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REBOOK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REBOOK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REBOOK.out.versions  // channel: path(versions.yml)
}
