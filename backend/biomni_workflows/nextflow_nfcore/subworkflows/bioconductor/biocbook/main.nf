#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiocBook
// A BiocBook can be created by authors (e.g. R developers, but also scientists, teachers, communicator
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiocBook/inst/doc/BiocBook.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BiocBook")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCBOOK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocbook"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocbook:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocbook:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocbook_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocbook_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocbook_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocBook)
    library(jsonlite)

    # --- Init [] ---
    # Key functions: init
    ---------------------------------------------------------------------
    library(BiocBook)
    ## Note that `.local = TRUE` is only set here for demonstration.
    init("myNewBook", .local = TRUE)
    # --- Biocbook [] ---
    # Key functions: BiocBook
    ---------------------------------------------------------------------
    bb <- BiocBook("myNewBook")
    bb
    # --- Add Preamble [] ---
    # Key functions: add_preamble, add_chapter
    ---------------------------------------------------------------------
    add_preamble(bb, open = FALSE)
    add_chapter(bb, title = 'Chapter 1', open = FALSE)
    bb

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocbook_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocbook_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocbook_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCBOOK:", paste0("    biocbook: ", packageVersion("BiocBook"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocbook_results.csv
    touch ${prefix}_biocbook_output.rds
    echo "BIOC_BIOCBOOK:" > versions.yml
    echo "    biocbook: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCBOOK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCBOOK(ch_input)

    emit:
    results  = BIOC_BIOCBOOK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCBOOK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCBOOK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCBOOK.out.versions  // channel: path(versions.yml)
}
