#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sccomp — differential_variability_analysis
// Model and test differences in cell-group variability across groups.
// Input: user_seurat_obj.rds
// Container: quay.io/biocontainers/bioconductor-sccomp:2.2.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, dplyr, ggplot2, sccomp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate composition and variability coefficients using sccomp_estimate() with formula_variability
//  * 2. [Core Analysis] Test for significant differences in composition and variability using sccomp_test()
//  * 3. [Visualization & Output] Visualize 1D and 2D credible intervals using plot()

nextflow.enable.dsl = 2

process BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS {
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
    .bm_deps <- c("sccomp", "Seurat", "dplyr", "ggplot2")
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
        library(sccomp)
        library(Seurat)
        library(dplyr)
        library(ggplot2)
        
        # 1. Read the user input file
        if (!file.exists("user_seurat_obj.rds")) {
          stop("Error: 'user_seurat_obj.rds' not found in the working directory.")
        }
        
        seurat_obj <- readRDS("user_seurat_obj.rds")
        
        # 2. Estimate composition and variability coefficients
        message("Estimating composition and variability...")
        res =
          seurat_obj |>
          sccomp_estimate(
            formula_composition = ~ type,
            formula_variability = ~ type,
            sample = "sample",
            cell_group = "cell_group",
            cores = 1, verbose = FALSE
          )
        
        # 3. Test for significant differences and generate plots
        message("Testing and plotting...")
        plots = res |> sccomp_test() |> plot()
        
        # Display/evaluate the credible interval plots as in the documented code
        plots\$credible_intervals_1D
        plots\$credible_intervals_2D
        
        # 4. Save outputs to files
        message("Saving results...")
        
        # Save the test results table (extracting the tibble from the sccomp object and removing the nested list column)
        write.csv(as.data.frame(res |> sccomp_test() |> select(-count_data)), "sccomp_test_results.csv", row.names = FALSE)
        saveRDS(res, "sccomp_estimate_results.rds")
        
        # Save the plots to PDF files
        if (!is.null(plots\$credible_intervals_1D)) {
          ggsave("sccomp_credible_intervals_1D.pdf", plot = plots\$credible_intervals_1D, width = 8, height = 6)
        }
        
        if (!is.null(plots\$credible_intervals_2D)) {
          ggsave("sccomp_credible_intervals_2D.pdf", plot = plots\$credible_intervals_2D, width = 8, height = 6)
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS":',
        paste0('    sccomp: ', as.character(packageVersion('sccomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_variability_analysis.csv versions.yml
    """
}

workflow BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_seurat_obj.rds ] ]

    main:
    BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS.out.tables
    plots    = BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS.out.plots
    objects  = BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS.out.objects
    versions = BIOC_SCCOMP_DIFFERENTIAL_VARIABILITY_ANALYSIS.out.versions
}
