#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plyranges
// A dplyr-like interface for interacting with the common Bioconductor classes Ranges and GenomicRanges
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plyranges/inst/doc/an-introduction.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("plyranges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLYRANGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plyranges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plyranges:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plyranges:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plyranges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plyranges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plyranges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plyranges)
    library(jsonlite)

    # --- Grouping and Filtering [] ---
    # Key functions: as_granges, filter, group_by
    grng <- as_granges(data.frame(
        seqnames = sample(c("chr1", "chr2"), 10, replace = TRUE),
        strand = sample(c("+", "-"), 10, replace = TRUE),
        gc = runif(10),
        start = 1:10,
        width = 10
    ))
    filtered_grng <- filter(grng, gc < 0.3)
    grouped_grng <- group_by(grng, strand)
    max_gc_by_strand <- filter(grouped_grng, gc == max(gc))


    # --- Overlap Filtering and Aggregation [] ---
    # Key functions: as_iranges, filter_by_overlaps, filter_by_non_overlaps, group_by_overlaps, summarise
    ir0 <- as_iranges(data.frame(start = c(5, 10, 15, 20), width = 5))
    ir1 <- as_iranges(data.frame(start = 2:6, width = 3:7))
    ir1 <- mutate(ir1, gc = runif(length(ir1)))
    overlapping_ranges <- filter_by_overlaps(ir0, ir1)
    non_overlapping_ranges <- filter_by_non_overlaps(ir0, ir1)
    aggregated_overlaps <- summarise(
        group_by_overlaps(ir0, ir1),
        mean_gc = mean(gc)
    )


    # --- Overlap Joins [] ---
    # Key functions: join_overlap_intersect, join_overlap_inner, join_overlap_left, find_overlaps
    query <- as_granges(data.frame(
        seqnames = "chr1", strand = c("+", "-"),
        start = c(1, 9), end = c(7, 10), key.a = letters[1:2]
    ))
    subject <- as_granges(data.frame(
        seqnames = "chr1", strand = c("-", "+"),
        start = c(2, 6), end = c(4, 8), key.b = LETTERS[1:2]
    ))
    intersect_ranges <- join_overlap_intersect(query, subject)
    inner_ranges <- join_overlap_inner(query, subject)
    left_ranges <- join_overlap_left(query, subject)
    all_overlaps <- find_overlaps(query, subject)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plyranges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plyranges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plyranges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLYRANGES:", paste0("    plyranges: ", packageVersion("plyranges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plyranges_results.csv
    touch ${prefix}_plyranges_output.rds
    echo "BIOC_PLYRANGES:" > versions.yml
    echo "    plyranges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLYRANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLYRANGES(ch_input)

    emit:
    results  = BIOC_PLYRANGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLYRANGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLYRANGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLYRANGES.out.versions  // channel: path(versions.yml)
}
