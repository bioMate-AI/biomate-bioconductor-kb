#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BREW3R.r
// This R package provide functions that are used in the BREW3R workflow. This mainly contains a functi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BREW3R.r/inst/doc/BREW3R.r.R
// Upstream  : GenomicRanges, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("BREW3R.r")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BREW3R_R {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-brew3r_r"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_brew3r_r_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_brew3r_r_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_brew3r_r_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BREW3R.r", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(BREW3R.r)
    library(jsonlite)

    # --- Data Loading and Preparation [import, subset] ---
    # Key functions: import, subset
    input_gtf_to_extend <- system.file(
        "extdata/chr19.gencode.vM25.annotation.gtf.gz",
        package = "BREW3R.r",
        mustWork = TRUE
    )
    input_gtf_template <- system.file(
        "extdata/chr19.mm10.ncbiRefSeq.gtf.gz",
        package = "BREW3R.r",
        mustWork = TRUE
    )
    input_gr_to_extend <- rtracklayer::import(input_gtf_to_extend)
    input_gr_template <- rtracklayer::import(input_gtf_template)
    input_gr_CDS <- subset(input_gr_to_extend, type == "CDS")

    # --- Transcript Extension [extend_granges] ---
    # Key functions: extend_granges
    new_gr_exons <- extend_granges(
        input_gr_to_extend = input_gr_to_extend,
        input_gr_to_overlap = input_gr_template
    )

    # --- Visualization [subset, start, end, strand] ---
    # Key functions: subset, start, end, strand
    my_gene_name <- "Btrc"
    gene_before <- subset(
        input_gr_to_extend,
        type == "exon" & gene_name == my_gene_name
    )
    gene_to_overlap <- subset(
        input_gr_template,
        type == "exon" & gene_name == my_gene_name
    )
    gene_after <- subset(
        new_gr_exons,
        type == "exon" & gene_name == my_gene_name
    )
    code <- (runValue(strand(gene_after[1])) == "+") + 1
    plot(
        1, type = "n", xlab = "", ylab = "", axes = FALSE,
        xlim = c(min(start(gene_after)) - 1, max(end(gene_after))),
        ylim = c(0, 4)
    )
    axis(2, at = 1:3, labels = c("new gtf", "template", "original"))
    arrows(
        x0 = start(gene_before) - 1, x1 = end(gene_before),
        y0 = 3, col = "blue", code = code
    )


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
        write.csv(as.data.frame(.main), "${prefix}_brew3r_r_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_brew3r_r_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_brew3r_r_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BREW3R_R:", paste0("    brew3r_r: ", as.character(packageVersion("BREW3R.r")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_brew3r_r_results.csv
    touch ${prefix}_brew3r_r_output.rds
    echo "BIOC_BREW3R_R:" > versions.yml
    echo "    brew3r_r: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BREW3R_R_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BREW3R_R(ch_input)

    emit:
    results  = BIOC_BREW3R_R.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BREW3R_R.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BREW3R_R.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BREW3R_R.out.versions  // channel: path(versions.yml)
}
