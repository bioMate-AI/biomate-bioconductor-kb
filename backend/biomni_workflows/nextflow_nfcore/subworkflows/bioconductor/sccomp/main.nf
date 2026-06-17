#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sccomp — differential_composition_analysis
// Estimate and test differences in cell type composition across groups from single-cell count data, with optional outlier removal and visualization.
// Input: user_counts_df.rds
// Container: quay.io/biocontainers/bioconductor-sccomp:2.2.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, forcats, ggplot2, sccomp, tidyr
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate composition coefficients using sccomp_estimate()
//  * 2. [Core Analysis] Probabilistically identify and remove outliers using sccomp_remove_outliers()
//  * 3. [Core Analysis] Test for significant differences using sccomp_test()
//  * 4. [Visualization & Output] Visualize results using sccomp_boxplot() and other plotting functions

nextflow.enable.dsl = 2

process BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS {
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
    .bm_deps <- c("dplyr", "sccomp", "ggplot2", "forcats", "tidyr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(dplyr)
    library(sccomp)
    library(ggplot2)
    library(forcats)
    library(tidyr)
    
    # 1. Read the user input file
    # The input file must be a data frame containing cell group counts, sample IDs, and metadata covariates.
    # Expected columns: "sample", "cell_group", "count", and "type" (or covariates matching the formula).
    counts_obj <- readRDS("user_counts_df.rds")
    
    # 2. Run the sccomp pipeline: Estimate, Remove Outliers, and Test
    sccomp_result =
      counts_obj |>
      sccomp_estimate(
        formula_composition = ~ type,
        sample = "sample",
        cell_group = "cell_group",
        abundance = "count",
        cores = 1, verbose = FALSE
      ) |>
    
      # max_sampling_iterations is used here to not exceed the maximum file size for GitHub action of 100Mb
      sccomp_remove_outliers(cores = 1, verbose = FALSE, max_sampling_iterations = 2000) |> # Optional
      sccomp_test()
    
    # 3. Save the results to disk
    saveRDS(sccomp_result, "sccomp_result.rds")
    
    # Remove the nested list column 'count_data' before writing to CSV to avoid 'unimplemented type list' error
    sccomp_result |> 
      select(-count_data) |> 
      write.csv("sccomp_result.csv", row.names = FALSE)
    
    # 4. Generate and save the documented visualizations
    pdf("sccomp_boxplot.pdf", width = 8, height = 6)
    p1 <- sccomp_result |> sccomp_boxplot(factor = "type")
    print(p1)
    dev.off()
    
    pdf("sccomp_boxplot_adjusted.pdf", width = 8, height = 6)
    p2 <- sccomp_result |> sccomp_boxplot(factor = "type", remove_unwanted_effects = TRUE)
    print(p2)
    dev.off()
    
    pdf("plot_1D_intervals.pdf", width = 8, height = 6)
    p3 <- sccomp_result |> plot_1D_intervals()
    print(p3)
    dev.off()
    
    pdf("plot_2D_intervals.pdf", width = 8, height = 6)
    p4 <- sccomp_result |> plot_2D_intervals()
    print(p4)
    dev.off()
    
    pdf("plot_all.pdf", width = 10, height = 8)
    p5 <- sccomp_result |> plot()
    # plot() returns a list of ggplot objects; iterate over them to print each to the PDF
    lapply(p5, print)
    dev.off()

    writeLines(c(
        '"BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS":',
        paste0('    sccomp: ', as.character(packageVersion('sccomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_composition_analysis.csv versions.yml
    """
}

workflow BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_counts_df.rds ] ]

    main:
    BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.tables
    plots    = BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.plots
    objects  = BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.objects
    versions = BIOC_SCCOMP_DIFFERENTIAL_COMPOSITION_ANALYSIS.out.versions
}
