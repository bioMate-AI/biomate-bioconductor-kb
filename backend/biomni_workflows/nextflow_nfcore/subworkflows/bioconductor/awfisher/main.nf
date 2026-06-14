#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AWFisher — aw_fisher_meta_analysis
// Combine p-values from multiple independent studies to perform adaptively weighted Fisher's meta-analysis.
// Input: pmatrix
// Container: quay.io/biocontainers/bioconductor-awfisher:1.24.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AWFisher
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform differential expression analysis in each study to generate a p-value matrix
//  * 2. [Core Analysis] Run AWFisher_pvalue to perform the meta-analysis
//  * 3. [Core Analysis] Adjust the resulting p-values for multiple testing

nextflow.enable.dsl = 2

process BIOC_AWFISHER_AW_FISHER_META_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("AWFisher")
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
    
    # Load required libraries
    library(AWFisher)
    
    # Stage 1: Load the p-value matrix (representing the differential expression analysis results from each study)
    if (file.exists("pmatrix.csv")) {
      pmatrix <- as.matrix(read.csv("pmatrix.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("pmatrix.tsv")) {
      pmatrix <- as.matrix(read.delim("pmatrix.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("pmatrix.rds")) {
      pmatrix <- readRDS("pmatrix.rds")
      if (!is.matrix(pmatrix)) pmatrix <- as.matrix(pmatrix)
    } else if (file.exists("pmatrix")) {
      pmatrix <- as.matrix(read.table("pmatrix", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Required input file 'pmatrix' (CSV, TSV, or RDS format) not found in the working directory.")
    }
    
    # Stage 2: Run AWFisher_pvalue to perform the meta-analysis
    res <- AWFisher_pvalue(pmatrix)
    
    # Stage 3: Adjust the resulting p-values for multiple testing
    qvalue <- p.adjust(res\$pvalue, "BH")
    sum(qvalue < 0.05)
    head(res\$weights)
    
    # Save outputs
    results_df <- data.frame(
      Gene = rownames(pmatrix),
      pvalue = res\$pvalue,
      qvalue = qvalue
    )
    
    weights_df <- as.data.frame(res\$weights)
    if (!is.null(colnames(pmatrix))) {
      colnames(weights_df) <- paste0("Weight_", colnames(pmatrix))
    } else {
      colnames(weights_df) <- paste0("Weight_Study_", 1:ncol(weights_df))
    }
    
    results_df <- cbind(results_df, weights_df)
    
    write.csv(results_df, "awfisher_results.csv", row.names = FALSE)
    saveRDS(res, "awfisher_results.rds")

    writeLines(c(
        '"BIOC_AWFISHER_AW_FISHER_META_ANALYSIS":',
        paste0('    AWFisher: ', as.character(packageVersion('AWFisher')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aw_fisher_meta_analysis.csv versions.yml
    """
}

workflow BIOC_AWFISHER_AW_FISHER_META_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pmatrix ] ]

    main:
    BIOC_AWFISHER_AW_FISHER_META_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_AWFISHER_AW_FISHER_META_ANALYSIS.out.tables
    plots    = BIOC_AWFISHER_AW_FISHER_META_ANALYSIS.out.plots
    objects  = BIOC_AWFISHER_AW_FISHER_META_ANALYSIS.out.objects
    versions = BIOC_AWFISHER_AW_FISHER_META_ANALYSIS.out.versions
}
