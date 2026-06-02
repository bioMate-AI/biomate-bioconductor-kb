#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: easylift
// The easylift package provides a convenient tool for genomic liftover operations between different ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/easylift/inst/doc/easylift.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("easylift")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EASYLIFT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-easylift"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-easylift:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-easylift:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_easylift_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_easylift_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_easylift_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(GRanges)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, genome, package

    # --- easylift [] ---
    # Key functions: easylift
    easylift(gr, "hg38", chain)
    # --- Bioc File Cache [] ---
    # Key functions: BiocFileCache, bfcadd
    bfc <- BiocFileCache()
    if (nrow(bfcquery(bfc, basename(chain_file))) == 0)
    bfcadd(bfc, chain_file)
    # --- easylift [] ---
    # Key functions: easylift
    easylift(gr, "hg38")
    gr |> easylift("hg38")
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_easylift_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_easylift_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_easylift_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EASYLIFT:", paste0("    easylift: ", packageVersion("easylift"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_easylift_results.csv
    touch ${prefix}_easylift_output.rds
    echo "BIOC_EASYLIFT:" > versions.yml
    echo "    easylift: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EASYLIFT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EASYLIFT(ch_input)

    emit:
    results  = BIOC_EASYLIFT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EASYLIFT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EASYLIFT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EASYLIFT.out.versions  // channel: path(versions.yml)
}
