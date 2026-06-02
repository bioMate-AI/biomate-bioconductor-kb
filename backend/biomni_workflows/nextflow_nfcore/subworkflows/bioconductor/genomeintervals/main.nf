#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genomeIntervals
// This package defines classes for representing genomic intervals and provides functions and methods f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genomeIntervals/inst/doc/genomeIntervals.R
// Upstream  : none
// Downstream: girafe
//
// Install: BiocManager::install("genomeIntervals")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMEINTERVALS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomeintervals"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomeintervals:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomeintervals:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomeintervals_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomeintervals_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomeintervals_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(genomeIntervals)
    library(jsonlite)

    # --- Annotation Management [] ---
    # Key functions: annotation, annotation<-
    intervals <- new(
        "Genome_intervals_stranded",
        matrix(c(1, 100, 200, 500), ncol = 2),
        closed = TRUE,
        annotation = data.frame(
            seq_name = factor(c("chr01", "chr02")),
            inter_base = FALSE,
            strand = factor(c("+", "-"), levels = c("+", "-"))
        )
    )
    annotation(intervals)$myannot <- rep(
        c("my", "annot"),
        length = nrow(intervals)
    )
    subset_annot <- annotation(intervals[1, ])
    val <- intervals$myannot


    # --- Interval Overlap and Set Operations [] ---
    # Key functions: interval_overlap, interval_intersection, interval_complement
    i <- new(
        "Genome_intervals_stranded",
        matrix(c(1, 100, 200, 500), ncol = 2),
        closed = TRUE,
        annotation = data.frame(
            seq_name = factor(c("chr01", "chr01")),
            inter_base = FALSE,
            strand = factor(c("+", "+"), levels = c("+", "-"))
        )
    )
    j <- i
    overlap_result <- interval_overlap(from = i, to = j)
    intersect_result <- interval_intersection(i, j)
    complement_result <- interval_complement(j[1, ])


    # --- Distance Calculation [] ---
    # Key functions: distance_to_nearest
    i <- new(
        "Genome_intervals_stranded",
        matrix(c(1, 100, 200, 500), ncol = 2),
        closed = TRUE,
        annotation = data.frame(
            seq_name = factor(c("chr01", "chr01")),
            inter_base = FALSE,
            strand = factor(c("+", "+"), levels = c("+", "-"))
        )
    )
    j <- i
    dist_result <- distance_to_nearest(i, j)


    # --- GFF File Parsing [] ---
    # Key functions: readGff3, getGffAttribute
    gff_file <- system.file(
        "example_files",
        "sgd_simple.gff",
        package = "genomeIntervals"
    )
    gff <- readGff3(gff_file, isRightOpen = FALSE, quiet = TRUE)
    idpa <- getGffAttribute(gff, c("ID", "Parent"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomeintervals_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomeintervals_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomeintervals_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMEINTERVALS:", paste0("    genomeintervals: ", packageVersion("genomeIntervals"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomeintervals_results.csv
    touch ${prefix}_genomeintervals_output.rds
    echo "BIOC_GENOMEINTERVALS:" > versions.yml
    echo "    genomeintervals: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMEINTERVALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMEINTERVALS(ch_input)

    emit:
    results  = BIOC_GENOMEINTERVALS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMEINTERVALS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMEINTERVALS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMEINTERVALS.out.versions  // channel: path(versions.yml)
}
