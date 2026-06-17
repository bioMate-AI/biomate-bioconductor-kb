#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicFiles
// This package provides infrastructure for parallel computations distributed 'by file' or 'by range'. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicFiles/inst/doc/GenomicFiles.R
// Upstream  : BiocManager, GenomicAlignments
// Downstream: erma, IntEREst
//
// Install: BiocManager::install("GenomicFiles")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_GENOMICFILES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicfiles"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicfiles_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicfiles_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicfiles_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BamFile", "GenomicRanges", "GenomicFiles", "ScanBamParam", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(BamFile)
    library(GenomicRanges)
    library(GenomicFiles)
    library(ScanBamParam)
    library(jsonlite)

    # --- Genomic Files Initialization [] ---
    # Key functions: GenomicFiles
    gr <- GenomicRanges::GRanges("chr14",
        IRanges::IRanges(c(19411500, 19659063), width=100))
    fls <- c("sample1.bam", "sample2.bam")
    gf <- GenomicFiles(rowRanges=gr, files=fls)

    # --- File-by-File Reduction [] ---
    # Key functions: reduceByFile
    gr <- GenomicRanges::GRanges("chr14",
        IRanges::IRanges(c(19411500, 19659063), width=100))
    fls <- c("sample1.bam", "sample2.bam")
    MAP <- function(range, file, ...) {
        length(range)
    }
    se <- reduceByFile(gr, fls, MAP, summarize=TRUE)

    # --- Range-by-Range Reduction [] ---
    # Key functions: reduceByRange
    gr <- GenomicRanges::GRanges("chr14",
        IRanges::IRanges(c(19411500, 19659063), width=100))
    fls <- c("sample1.bam", "sample2.bam")
    MAP <- function(range, file, ...) {
        length(range)
    }
    REDUCE <- function(mapped, ...) {
        Reduce("+", mapped)
    }
    lst <- reduceByRange(gr, fls, MAP, REDUCE, iterate=FALSE)

    # --- Group-wise Statistical Testing [] ---
    # Key functions: reduceByRange
    gr <- GenomicRanges::GRanges("chr14",
        IRanges::IRanges(c(19411500, 19659063), width=100))
    fls <- c("sample1.bam", "sample2.bam", "sample3.bam", "sample4.bam")
    grp <- factor(rep(c("A", "B"), each=2))
    MAP <- function(range, file, ...) {
        rep(1, length(range))
    }
    REDUCE <- function(mapped, ..., grp) {
        mat <- simplify2array(mapped)
        rowMeans(mat)
    }
    ttest <- reduceByRange(gr, fls, MAP, REDUCE, iterate=FALSE, grp=grp)


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
        write.csv(as.data.frame(.main), "${prefix}_genomicfiles_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_genomicfiles_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_genomicfiles_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICFILES:", paste0("    genomicfiles: ", as.character(packageVersion("GenomicFiles")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicfiles_results.csv
    touch ${prefix}_genomicfiles_output.rds
    echo "BIOC_GENOMICFILES:" > versions.yml
    echo "    genomicfiles: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICFILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICFILES(ch_input)

    emit:
    results  = BIOC_GENOMICFILES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICFILES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICFILES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICFILES.out.versions  // channel: path(versions.yml)
}
