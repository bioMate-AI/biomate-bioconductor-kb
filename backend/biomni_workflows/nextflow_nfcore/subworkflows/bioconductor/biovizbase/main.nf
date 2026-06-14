#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biovizBase
// The biovizBase package is designed to provide a set of utilities, color schemes and conventions for
//
// Input: genes.csv  (user-provided gene/feature coordinate table; columns: seqnames, start, end[, symbol/name])
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biovizBase/inst/doc/intro.R
// Upstream  : GenomicRanges, Rsamtools, dichromat, rtracklayer, scales
// Downstream: CAFE
//
// Install: BiocManager::install("biovizBase")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BIOVIZBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biovizbase"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biovizbase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biovizbase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biovizbase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("biovizBase", "GCcontent", "GenomicRanges", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(biovizBase)
    library(GCcontent)
    library(GenomicRanges)
    library(jsonlite)

    # --- Gap Calculation [] ---
    # Key functions: maxGap
    gr_temp <- GenomicRanges::GRanges(
        seqnames = "chr1",
        ranges = IRanges::IRanges(start = c(100, 250), end = c(200, 300))
    )
    temp_gaps <- BiocGenerics::gaps(
        gr_temp,
        start = min(BiocGenerics::start(gr_temp))
    )
    gap_val <- maxGap(temp_gaps)
    gap_val_ratio <- maxGap(temp_gaps, ratio = 0.5)


    # --- Coordinate Shrinkage [] ---
    # Key functions: shrinkageFun, maxGap
    gr1 <- GenomicRanges::GRanges(
        "chr1",
        IRanges::IRanges(start = c(10, 300, 800), end = c(150, 400, 850))
    )
    gr2 <- GenomicRanges::GRanges(
        "chr1",
        IRanges::IRanges(start = c(100, 350, 550), end = c(220, 500, 900))
    )
    gaps_gr <- BiocGenerics::intersect(
        BiocGenerics::gaps(gr1, start = min(BiocGenerics::start(gr1))),
        BiocGenerics::gaps(gr2, start = min(BiocGenerics::start(gr2)))
    )
    shrink_fun <- shrinkageFun(gaps_gr, max.gap = maxGap(gaps_gr))
    shrunk_gr1 <- shrink_fun(gr1)
    shrunk_gr2 <- shrink_fun(gr2)


    # --- Gene/Feature Annotation from USER INPUT [] ---
    # Read a user-provided coordinate table and build a named GRanges of features.
    .gene_file <- if (file.exists("genes.csv")) "genes.csv" else if (file.exists("genes.tsv")) "genes.tsv" else NA_character_
    if (is.na(.gene_file)) {
        stop("Required input file 'genes.csv' (columns: seqnames, start, end[, symbol/name]) not found in the working directory.")
    }
    genes_df <- if (grepl("\\\\.tsv\$", .gene_file)) {
        read.delim(.gene_file, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)
    } else {
        read.csv(.gene_file, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)
    }
    .seqcol   <- intersect(c("seqnames", "chrom", "chr"), tolower(colnames(genes_df)))
    .startcol <- intersect(c("start"), tolower(colnames(genes_df)))
    .endcol   <- intersect(c("end", "stop"), tolower(colnames(genes_df)))
    .namecol  <- intersect(c("symbol", "name", "gene", "gene_name"), tolower(colnames(genes_df)))
    colnames(genes_df) <- tolower(colnames(genes_df))
    if (length(.seqcol) == 0 || length(.startcol) == 0 || length(.endcol) == 0) {
        stop("Input table must contain at least 'seqnames', 'start', and 'end' columns.")
    }
    user_features <- GenomicRanges::GRanges(
        seqnames = as.character(genes_df[[.seqcol[1]]]),
        ranges   = IRanges::IRanges(start = as.integer(genes_df[[.startcol[1]]]),
                                    end   = as.integer(genes_df[[.endcol[1]]]))
    )
    if (length(.namecol) > 0) {
        names(user_features) <- as.character(genes_df[[.namecol[1]]])
    }
    # Key biovizBase/GenomicRanges accessors applied to the user features
    first_feature   <- if (!is.null(names(user_features)) && length(user_features) > 0) user_features[1] else user_features
    all_symbols     <- names(user_features)
    subset_features <- user_features[seq_len(min(10, length(user_features)))]
    chromosomes     <- GenomeInfoDb::seqnames(user_features)

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
        write.csv(as.data.frame(.main), "${prefix}_biovizbase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_biovizbase_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_biovizbase_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOVIZBASE:", paste0("    biovizbase: ", as.character(packageVersion("biovizBase")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biovizbase_results.csv
    touch ${prefix}_biovizbase_output.rds
    echo "BIOC_BIOVIZBASE:" > versions.yml
    echo "    biovizbase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOVIZBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(genes_csv) ]

    main:
    BIOC_BIOVIZBASE(ch_input)

    emit:
    results  = BIOC_BIOVIZBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOVIZBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOVIZBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOVIZBASE.out.versions  // channel: path(versions.yml)
}
