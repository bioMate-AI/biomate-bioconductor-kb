#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: speckle — propeller_direct_object_analysis
// Test for differences in cell type proportions directly from a SingleCellExperiment or Seurat object.
// Input: sce_all
// Container: quay.io/biocontainers/bioconductor-speckle:1.10.0--r45hdfd78af_0
// R packages: SingleCellExperiment, ggplot2, speckle
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, speckle
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run propeller with default logit transformation. 2. Run propeller with arcsin square root transformation. 3. Run propeller by expl

nextflow.enable.dsl = 2

process BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("SingleCellExperiment", "ggplot2", "speckle")
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
    library(speckle)
    library(ggplot2)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Load User Input
    # -----------------------------------------------------------------------------
    # Read the SingleCellExperiment or Seurat object from the working directory
    if (file.exists("sce_all")) {
      sce_all <- readRDS("sce_all")
    } else if (file.exists("sce_all.rds")) {
      sce_all <- readRDS("sce_all.rds")
    } else {
      stop("Error: Input file 'sce_all' or 'sce_all.rds' not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run propeller with default logit transformation
    # -----------------------------------------------------------------------------
    message("Running propeller with default logit transformation...")
    results_logit <- propeller(sce_all)
    write.csv(results_logit, "propeller_logit_results.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run propeller with arcsin square root transformation
    # -----------------------------------------------------------------------------
    message("Running propeller with arcsin square root transformation...")
    results_asin <- propeller(sce_all, transform="asin")
    write.csv(results_asin, "propeller_asin_results.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run propeller by explicitly passing metadata vectors
    # -----------------------------------------------------------------------------
    message("Running propeller with explicitly passed metadata vectors...")
    results_explicit <- propeller(clusters=sce_all\$cluster, sample=sce_all\$sample, group=sce_all\$group)
    write.csv(results_explicit, "propeller_explicit_results.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Visualise cell type proportions across samples
    # -----------------------------------------------------------------------------
    message("Generating cell type proportion plots...")
    plot_props <- plotCellTypeProps(sce_all)
    
    # Save the plot to a PDF file
    ggsave(
      filename = "cell_type_proportions.pdf",
      plot = plot_props,
      width = 8,
      height = 6,
      device = "pdf"
    )
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS":',
        paste0('    speckle: ', as.character(packageVersion('speckle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_propeller_direct_object_analysis.csv versions.yml
    """
}

workflow BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_all ] ]

    main:
    BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS.out.tables
    plots    = BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS.out.plots
    objects  = BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS.out.objects
    versions = BIOC_SPECKLE_PROPELLER_DIRECT_OBJECT_ANALYSIS.out.versions
}
