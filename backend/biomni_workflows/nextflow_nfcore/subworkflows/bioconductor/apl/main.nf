#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: APL — quick_start_apl
// Quickly compute and plot an Association Plot for a selected cell cluster using the wrapper function runAPL.
// Input: darmanis
// Container: quay.io/biocontainers/bioconductor-apl:1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: APL, SingleCellExperiment, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the user-provided input file
//  * 2. [Core Analysis] Run the documented runAPL workflow exactly as specified
//  * 3. [Core Analysis] Save the resulting plot to a PDF file

nextflow.enable.dsl = 2

process BIOC_APL_QUICK_START_APL {
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
    .bm_deps <- c("APL", "ggplot2")
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
    library(APL)
    library(ggplot2)
    
    # --- Read the user-provided input file ---
    if (file.exists("darmanis")) {
      darmanis <- readRDS("darmanis")
    } else if (file.exists("darmanis.rds")) {
      darmanis <- readRDS("darmanis.rds")
    } else {
      stop("Required input file 'darmanis' or 'darmanis.rds' not found in the working directory.")
    }
    
    # --- Run the documented runAPL workflow exactly as specified ---
    association_plot <- runAPL(
      darmanis,
      assay = "logcounts",
      top = 5000,
      group = which(darmanis\$cell.type == "oligodendrocytes"),
      type = "ggplot"
    )
    
    # --- Save the resulting plot to a PDF file ---
    ggsave(
      filename = "oligodendrocytes_association_plot.pdf",
      plot = association_plot,
      width = 8,
      height = 6
    )
    
    # Save the plot object as an RDS for downstream inspection if needed
    saveRDS(association_plot, file = "oligodendrocytes_association_plot.rds")

    writeLines(c(
        '"BIOC_APL_QUICK_START_APL":',
        paste0('    APL: ', as.character(packageVersion('APL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_start_apl.csv versions.yml
    """
}

workflow BIOC_APL_QUICK_START_APL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ darmanis ] ]

    main:
    BIOC_APL_QUICK_START_APL(ch_input)

    emit:
    tables   = BIOC_APL_QUICK_START_APL.out.tables
    plots    = BIOC_APL_QUICK_START_APL.out.plots
    objects  = BIOC_APL_QUICK_START_APL.out.objects
    versions = BIOC_APL_QUICK_START_APL.out.versions
}
