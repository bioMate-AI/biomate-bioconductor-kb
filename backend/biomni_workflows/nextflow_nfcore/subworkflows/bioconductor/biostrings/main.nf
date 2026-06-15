#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Biostrings
// Memory efficient string containers, string matching algorithms, and other utilities, for fast manipu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Biostrings/inst/doc/MultipleAlignments.R
// Upstream  : affy, affydata, hgu95av2cdf, hgu95av2probe
// Downstream: alabaster.string, altcdfenvs, amplican, Basic4Cseq, BRAIN
//
// Install: BiocManager::install("Biostrings")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BIOSTRINGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biostrings"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biostrings_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biostrings_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biostrings_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biostrings", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(Biostrings)
    library(jsonlite)

    # --- Hierarchical clustering [] ---
    # Key functions: stringDist, hclust, cutree
    sdist <- stringDist(as(autoMasked,"DNAStringSet"), method="hamming")
    clust <- hclust(sdist, method = "single")
    png(file="goodTree.png")
    # --- Nucleotide frequency QC [] ---
    # Key functions: readDNAMultipleAlignment, readAAMultipleAlignment, rowmask, colmask, maskMotif, maskGaps, alphabetFrequency, consensusMatrix
    rowmask(maskTest) <- IRanges(start=1,end=3)
    rowmask(maskTest,append="intersect") <- IRanges(start=2,end=5)
    rowmask(maskTest,append="replace") <- IRanges(start=5,end=8)

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
        write.csv(as.data.frame(.main), "${prefix}_biostrings_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_biostrings_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_biostrings_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOSTRINGS:", paste0("    biostrings: ", as.character(packageVersion("Biostrings")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biostrings_results.csv
    touch ${prefix}_biostrings_output.rds
    echo "BIOC_BIOSTRINGS:" > versions.yml
    echo "    biostrings: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOSTRINGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOSTRINGS(ch_input)

    emit:
    results  = BIOC_BIOSTRINGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOSTRINGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOSTRINGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOSTRINGS.out.versions  // channel: path(versions.yml)
}
