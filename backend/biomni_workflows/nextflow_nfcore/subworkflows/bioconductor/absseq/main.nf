#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ABSSeq — pairwise_de_analysis
// Perform pairwise differential expression analysis on RNA-Seq count data with replicates using either the standard ABSSeq model or the alternative aFold method.
// Input: counts.tsv, groups.csv
// Container: quay.io/biocontainers/bioconductor-absseq:1.64.0--r45hdfd78af_0
// R packages: ABSSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: ABSSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the ABSDataSet object with counts and group factors
//  * 2. [Core Analysis] Run the differential expression analysis pipeline using the ABSSeq wrapper function (optionally enabling aFold)
//  * 3. [Core Analysis] Extract and view the results including fold-changes, p-values, and adjusted p-values

nextflow.enable.dsl = 2

process BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS {
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
    .bm_deps <- c("ABSSeq")
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
    library(ABSSeq)
    
    # Check for required input files
    if (!file.exists("counts.tsv")) {
      stop("Error: 'counts.tsv' not found in the working directory.")
    }
    if (!file.exists("groups.csv")) {
      stop("Error: 'groups.csv' not found in the working directory.")
    }
    
    # Read raw integer counts
    counts <- as.matrix(read.delim("counts.tsv", row.names = 1, check.names = FALSE))
    storage.mode(counts) <- "integer"
    
    # Read group assignments
    groups_df <- read.csv("groups.csv", stringsAsFactors = FALSE)
    
    # Determine the group column and align with counts matrix columns if possible
    group_col <- if ("group" %in% colnames(groups_df)) {
      "group"
    } else if ("groups" %in% colnames(groups_df)) {
      "groups"
    } else {
      colnames(groups_df)[2]
    }
    
    sample_col <- colnames(groups_df)[1]
    if (all(colnames(counts) %in% groups_df[[sample_col]])) {
      rownames(groups_df) <- groups_df[[sample_col]]
      groups_vector <- groups_df[colnames(counts), group_col]
    } else {
      groups_vector <- groups_df[[group_col]]
    }
    
    # --- Workflow Stage 1: Standard ABSSeq Model ---
    
    # Construct the ABSDataSet object
    obj <- ABSDataSet(counts, factor(groups_vector))
    
    # Run the differential expression analysis pipeline
    obj <- ABSSeq(obj)
    
    # Extract and view the results
    res <- results(obj, c("Amean", "Bmean", "foldChange", "pvalue", "adj.pvalue"))
    head(res)
    
    # Write results to output files
    write.csv(res, "absseq_results_standard.csv", row.names = TRUE)
    
    # Generate diagnostic plot
    pdf("difftobase_plot_standard.pdf")
    tryCatch({
      plotDifftoBase(obj)
    }, error = function(e) {
      warning("Could not generate plotDifftoBase for standard model: ", e\$message)
    })
    dev.off()
    
    
    # --- Workflow Stage 2: Alternative aFold Method ---
    
    # Construct the ABSDataSet object using named arguments
    obj <- ABSDataSet(counts=counts, groups=factor(groups_vector))
    
    # Run the differential expression analysis pipeline with aFold enabled
    obj <- ABSSeq(obj, useaFold=TRUE)
    
    # Extract and view the results
    res <- results(obj, c("Amean", "Bmean", "foldChange", "pvalue", "adj.pvalue"))
    head(res)
    
    # Write results to output files
    write.csv(res, "absseq_results_afold.csv", row.names = TRUE)
    saveRDS(obj, "absseq_object_afold.rds")
    
    # Generate diagnostic plot
    pdf("difftobase_plot_afold.pdf")
    tryCatch({
      plotDifftoBase(obj)
    }, error = function(e) {
      warning("Could not generate plotDifftoBase for aFold model: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS":',
        paste0('    ABSSeq: ', as.character(packageVersion('ABSSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_de_analysis.csv versions.yml
    """
}

workflow BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv, groups.csv ] ]

    main:
    BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.tables
    plots    = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.plots
    objects  = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.objects
    versions = BIOC_ABSSEQ_PAIRWISE_DE_ANALYSIS.out.versions
}
