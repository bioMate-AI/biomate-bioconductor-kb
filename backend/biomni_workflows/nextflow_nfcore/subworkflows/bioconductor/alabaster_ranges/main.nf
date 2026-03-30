#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.ranges
// Save GenomicRanges, IRanges and related data structures into file artifacts, and load them back into
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.ranges/inst/doc/userguide.R
// Upstream  : BiocStyle, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("alabaster.ranges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_RANGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_ranges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.ranges:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.ranges:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_ranges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_ranges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_ranges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Granges [] ---
    # Key functions: GRanges, IRanges, sample, mcols, runif, metadata
    ---------------------------------------------------------------------
    library(GenomicRanges)
    gr <- GRanges("chrA", IRanges(sample(100), width=sample(100)))
    mcols(gr)$score <- runif(length(gr))
    metadata(gr)$genome <- "Aaron"
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    roundtrip <- readObject(tmp)
    roundtrip
    # --- Metadata [] ---
    # Key functions: metadata, mcols, seqinfo
    ---------------------------------------------------------------------
    metadata(roundtrip)
    mcols(roundtrip)
    seqinfo(roundtrip)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_ranges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_ranges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_ranges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_RANGES:", paste0("    alabaster_ranges: ", packageVersion("alabaster.ranges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_ranges_results.csv
    touch ${prefix}_alabaster_ranges_output.rds
    echo "BIOC_ALABASTER_RANGES:" > versions.yml
    echo "    alabaster_ranges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_RANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_RANGES(ch_input)

    emit:
    results  = BIOC_ALABASTER_RANGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_RANGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_RANGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_RANGES.out.versions  // channel: path(versions.yml)
}
