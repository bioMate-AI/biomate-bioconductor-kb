#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edgeR — classic_pipeline
// Perform pairwise differential expression analysis using exact tests (qCML method) for single-factor designs.
// Input: x
// Container: quay.io/biocontainers/bioconductor-edger:4.8.2--r45h01b2380_0
// R packages: edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR
// Visualizations: MDS plot, BCV plot
// QC: filter low-expression genes, dispersion QC plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create DGEList object with grouping
//  * 2. [Core Analysis] Estimate common and tagwise dispersions
//  * 3. [Core Analysis] Perform exact test
//  * 4. [Core Analysis] Extract top tags

nextflow.enable.dsl = 2

process BIOC_EDGER_CLASSIC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("edgeR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(edgeR)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a file named 'x.csv', 'x.tsv', or 'x.txt' in the working directory
    # representing the matrix of raw counts.
    if (file.exists("x.csv")) {
      x <- read.csv("x.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("x.tsv")) {
      x <- read.delim("x.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("x.txt")) {
      x <- read.delim("x.txt", row.names = 1, check.names = FALSE)
    } else {
      stop("Error: Input file 'x.csv', 'x.tsv', or 'x.txt' containing raw counts not found in the working directory.")
    }
    
    # Convert to matrix
    x <- as.matrix(x)
    
    # Determine the number of samples (columns)
    n_samples <- ncol(x)
    if (n_samples < 2) {
      stop("Error: At least 2 samples (columns) are required for pairwise differential expression analysis.")
    }
    
    # Define a grouping factor for the single-factor design.
    # Since the user input only provides the count matrix, we assign samples to two groups
    # (alternating or split) to allow pairwise comparison.
    group <- factor(rep(1:2, length.out = n_samples))
    
    # -----------------------------------------------------------------------------
    # 2. Execute Documented edgeR Classic Pipeline
    # -----------------------------------------------------------------------------
    # Create DGEList object with grouping
    y <- DGEList(counts=x, group=group)
    
    # Filter lowly expressed genes
    keep <- filterByExpr(y)
    y <- y[keep, , keep.lib.sizes=FALSE]
    
    # Normalize library sizes (TMM)
    y <- normLibSizes(y)
    
    # Estimate common and tagwise dispersions (qCML method)
    y <- estimateCommonDisp(y)
    y <- estimateTagwiseDisp(y)
    
    # Perform exact test
    et <- exactTest(y)
    
    # Extract and print top tags (reproducing the documented call)
    topTags(et)
    
    # -----------------------------------------------------------------------------
    # 3. Write Outputs
    # -----------------------------------------------------------------------------
    # Save the complete differential expression results table
    de_results <- as.data.frame(topTags(et, n = Inf))
    write.csv(de_results, "differential_expression_results.csv", row.names = TRUE)
    
    # Save RDS objects for downstream analysis
    saveRDS(y, "edgeR_dgelist.rds")
    saveRDS(et, "edgeR_exact_test.rds")
    
    # Generate diagnostic plots
    pdf("edgeR_classic_plots.pdf", width = 7, height = 7)
    tryCatch({
      plotMDS(y, main = "MDS Plot")
    }, error = function(e) {
      warning("Could not generate MDS plot: ", e\$message)
    })
    
    tryCatch({
      plotBCV(y, main = "BCV Plot")
    }, error = function(e) {
      warning("Could not generate BCV plot: ", e\$message)
    })
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'differential_expression_results.csv', 'edgeR_dgelist.rds', 'edgeR_exact_test.rds', and 'edgeR_classic_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_EDGER_CLASSIC_PIPELINE":',
        paste0('    edgeR: ', as.character(packageVersion('edgeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_classic_pipeline.csv versions.yml
    """
}

workflow BIOC_EDGER_CLASSIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x ] ]

    main:
    BIOC_EDGER_CLASSIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EDGER_CLASSIC_PIPELINE.out.tables
    plots    = BIOC_EDGER_CLASSIC_PIPELINE.out.plots
    objects  = BIOC_EDGER_CLASSIC_PIPELINE.out.objects
    versions = BIOC_EDGER_CLASSIC_PIPELINE.out.versions
}
