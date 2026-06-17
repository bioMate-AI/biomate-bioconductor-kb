#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpotSweeper — technical_artifact_detection
// Identify and visualize technical artifacts (such as tissue hangnails) using local variance of mitochondrial metrics across multiple neighborhood sizes.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-spotsweeper:1.6.0--r45hdfd78af_0
// R packages: SpatialExperiment, SpotSweeper, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, SpotSweeper, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize raw mitochondrial percentage to inspect for potential artifacts
//  * 2. [Core Analysis] Run findArtifacts to cluster and identify technical artifacts
//  * 3. [Visualization & Output] Visualize the identified artifacts using plotQCmetrics

nextflow.enable.dsl = 2

process BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION {
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
    .bm_deps <- c("SpatialExperiment", "SpotSweeper", "ggplot2", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(SpotSweeper)
    library(SpatialExperiment)
    library(ggplot2)
    
    # ==========================================
    # 1. Load User Input
    # ==========================================
    # Read the input SpatialExperiment object from the working directory
    if (file.exists("spe")) {
        spe <- readRDS("spe")
    } else if (file.exists("spe.rds")) {
        spe <- readRDS("spe.rds")
    } else {
        stop("Error: Input file 'spe' or 'spe.rds' not found in the working directory.")
    }
    
    # Inspect colData before artifact detection
    cat("ColData columns before artifact detection:\n")
    print(colnames(colData(spe)))
    
    # ==========================================
    # 2. Visualize Raw Mitochondrial Percentage
    # ==========================================
    # Create the initial QC plot to inspect for potential artifacts
    p1 <- plotQCmetrics(spe,
        metric = "expr_chrM_ratio",
        outliers = NULL, point_size = 1.1
    ) +
        ggtitle("Mitochondrial Percent")
    
    # Save the initial plot
    ggsave("mitochondrial_percent_plot.pdf", plot = p1, width = 7, height = 6)
    
    # ==========================================
    # 3. Run findArtifacts to Identify Artifacts
    # ==========================================
    # Find artifacts using SpotSweeper
    spe <- findArtifacts(spe,
        mito_percent = "expr_chrM_ratio",
        mito_sum = "expr_chrM",
        n_order = 5,
        name = "artifact"
    )
    
    # Check that "artifact" is now in colData
    cat("\nColData columns after artifact detection:\n")
    print(colnames(colData(spe)))
    
    # ==========================================
    # 4. Visualize Identified Artifacts
    # ==========================================
    # Create the final QC plot highlighting the identified artifacts
    p2 <- plotQCmetrics(spe,
        metric = "expr_chrM_ratio",
        outliers = "artifact", point_size = 1.1
    ) +
        ggtitle("Hangnail artifact")
    
    # Save the final plot
    ggsave("hangnail_artifact_plot.pdf", plot = p2, width = 7, height = 6)
    
    # ==========================================
    # 5. Save Outputs
    # ==========================================
    # Save the updated SpatialExperiment object
    saveRDS(spe, "spe_artifact_detected.rds")
    
    # Save the colData as a CSV table for downstream analysis
    write.csv(as.data.frame(colData(spe)), "artifact_results.csv", row.names = TRUE)
    
    cat("\nWorkflow completed successfully. Outputs saved:\n")
    cat("- mitochondrial_percent_plot.pdf\n")
    cat("- hangnail_artifact_plot.pdf\n")
    cat("- spe_artifact_detected.rds\n")
    cat("- artifact_results.csv\n")

    writeLines(c(
        '"BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION":',
        paste0('    SpotSweeper: ', as.character(packageVersion('SpotSweeper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_technical_artifact_detection.csv versions.yml
    """
}

workflow BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION(ch_input)

    emit:
    tables   = BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION.out.tables
    plots    = BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION.out.plots
    objects  = BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION.out.objects
    versions = BIOC_SPOTSWEEPER_TECHNICAL_ARTIFACT_DETECTION.out.versions
}
