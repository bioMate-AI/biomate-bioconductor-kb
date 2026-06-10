#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicTuples
// GenomicTuples defines general purpose containers for storing genomic tuples. It aims to provide func
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicTuples/inst/doc/GenomicTuplesIntroduction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GenomicTuples")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_GENOMICTUPLES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomictuples"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomictuples_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomictuples_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomictuples_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicTuples)
    library(GTuples)
    library(GTuplesList)
    library(Seqinfo)
    library(jsonlite)

    # --- Genomic Tuples Creation [] ---
    # Key functions: GTuples, Seqinfo, Rle, strand
    seqinfo <- Seqinfo(paste0("chr", 1:3), c(1000, 2000, 1500), NA, "mock1")
    gt3 <- GTuples(
        seqnames = Rle(c("chr1", "chr2", "chr1", "chr3"), c(1, 3, 2, 4)),
        tuples = matrix(c(1:10, 2:11, 3:12), ncol = 3),
        strand = Rle(
            strand(c("-", "+", "*", "+", "-")),
            c(1, 2, 2, 3, 2)
        ),
        score = 1:10,
        GC = seq(1, 0, length = 10),
        seqinfo = seqinfo
    )
    names(gt3) <- letters[1:10]

    # --- Tuple Property Extraction [] ---
    # Key functions: tuples, size, IPD, shift
    gt_tuples <- tuples(gt3)
    gt_size <- size(gt3)
    gt_ipd <- IPD(gt3)
    gt_seqnames <- seqnames(gt3)
    gt_mcols <- mcols(gt3)
    gt_subset <- gt3[2:3, "GC"]
    gt_shifted <- shift(gt3, 500)

    # --- Genomic Tuples List Operations [] ---
    # Key functions: GTuplesList, size, IPD, shift, isEmpty
    gtl3 <- GTuplesList(A = gt3[1:5], B = gt3[6:10])
    gtl_size <- size(gtl3)
    gtl_ipd <- IPD(gtl3)
    gtl_shifted <- shift(gtl3, IntegerList(A = 300L, B = 500L))
    gtl_empty <- isEmpty(gtl3)
    gtl_gr <- as(gtl3, "GRangesList")

    # --- Overlap and Intersection Analysis [] ---
    # Key functions: GTuples, findOverlaps, as
    gt1 <- GTuples(
        seqnames = c('chr1', 'chr1', 'chr1', 'chr2'),
        tuples = matrix(c(10L, 10L, 10L, 10L), ncol = 1),
        strand = c('+', '-', '*', '+')
    )
    overlaps_any <- findOverlaps(gt1, gt1, type = 'any')
    overlaps_start <- findOverlaps(gt1, gt1, type = 'start')
    overlaps_end <- findOverlaps(gt1, gt1, type = 'end')
    gr1 <- as(gt1, "GRanges")


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_genomictuples_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_genomictuples_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_genomictuples_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICTUPLES:", paste0("    genomictuples: ", as.character(packageVersion("GenomicTuples")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomictuples_results.csv
    touch ${prefix}_genomictuples_output.rds
    echo "BIOC_GENOMICTUPLES:" > versions.yml
    echo "    genomictuples: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICTUPLES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICTUPLES(ch_input)

    emit:
    results  = BIOC_GENOMICTUPLES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICTUPLES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICTUPLES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICTUPLES.out.versions  // channel: path(versions.yml)
}
