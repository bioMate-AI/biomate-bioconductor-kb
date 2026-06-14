#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: selectksigs — select_optimal_signatures
// Determine the optimal number of mutational signatures from somatic mutation data using cross-validated perplexity.
// Input: esophageal.mp.txt.gz
// Container: quay.io/biocontainers/bioconductor-selectksigs:1.22.0--r45ha27e39d_0
// R packages: dplyr, ggplot2, HiLDA, selectKSigs, tidyr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-selectksigs:1.22.0--r45ha27e39d_0"

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
    .bm_deps <- c("dplyr", "ggplot2", "HiLDA", "selectKSigs", "tidyr")
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
    library(HiLDA)
    library(tidyr)
    library(ggplot2)
    library(dplyr)
    library(selectKSigs)
    
    # Define input file path (must be in the working directory)
    inputFile <- "esophageal.mp.txt.gz"
    
    if (!file.exists(inputFile)) {
      stop(paste("Required input file missing from working directory:", inputFile))
    }
    
    # --- Read the mutation position file using HiLDA's reader ---
    message("Reading mutation position file...")
    G <- hildaReadMPFile(inputFile, numBases = 5, trDir = TRUE)
    
    # --- Run cross-validation across a range of signature counts ---
    message("Running cross-validation to determine optimal number of signatures...")
    set.seed(5)
    results <- cv_PMSignature(G, Kfold = 3, nRep = 3, Klimit = 7)
    
    # Save the raw cross-validation results
    write.csv(results, "cv_results.csv", row.names = FALSE)
    saveRDS(results, "cv_results.rds")
    
    # --- Format and plot the cross-validation results to identify ---
    message("Formatting results and generating plot...")
    results\$Kvalue <- seq_len(nrow(results)) + 1
    results_df <- gather(results, Method, value, -Kvalue) %>% 
      group_by(Method) %>%
      mutate(xmin = which.min(value) + 1 - 0.1,
             xmax = which.min(value) + 1 + 0.1)
    
    # Save formatted data frame
    write.csv(results_df, "cv_results_formatted.csv", row.names = FALSE)
    
    # Create the plot
    p <- ggplot(results_df) +
      geom_point(aes(x = Kvalue, y = value, color = Method), size = 2) +
      facet_wrap(~ Method, scales = "free") + 
      geom_rect(mapping = aes(xmin = xmin, xmax = xmax, 
                              ymin = -Inf, ymax = Inf),
                fill = 'grey', alpha = 0.05) +
      theme_bw() +
      xlab("Number of signatures")
    
    # Save the plot to a PDF file
    ggsave("optimal_signatures_plot.pdf", plot = p, width = 8, height = 6)
    
    message("Pipeline completed successfully. Outputs saved: 'cv_results.csv', 'cv_results.rds', 'cv_results_formatted.csv', and 'optimal_signatures_plot.pdf'.")

    writeLines(c(
        '"BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES":',
        paste0('        selectksigs: ', as.character(packageVersion("selectksigs")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_select_optimal_signatures.csv versions.yml
    """
}

workflow BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ esophageal.mp.txt.gz ] ]

    main:
    BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES(ch_input)

    emit:
    tables   = BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES.out.tables
    plots    = BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES.out.plots
    objects  = BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES.out.objects
    versions = BIOC_SELECTKSIGS_SELECT_OPTIMAL_SIGNATURES.out.versions
}
