#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpotSweeper — spot_level_local_outlier_detection
// Identify and visualize spatially-aware local outliers based on library size, unique genes, and mitochondrial percentage.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-spotsweeper:1.6.0--r45hdfd78af_0
// R packages: SpatialExperiment, devtools, escheR, ggplot2, ggpubr, scuttle, SpotSweeper
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, SpotSweeper, escheR, ggplot2, scuttle
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out-of-tissue spots
//  * 2. [Core Analysis] Calculate standard QC metrics (sum, detected, mitochondrial percentage)
//  * 3. [Core Analysis] Run localOutliers for library size, unique genes, and mitochondrial percentage
//  * 4. [Core Analysis] Combine individual outlier metrics into a single logical column
//  * 5. [Visualization & Output] Visualize the local outliers using plotQCmetrics

nextflow.enable.dsl = 2

process BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION {
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
    .bm_deps <- c("SpatialExperiment", "devtools", "escheR", "ggplot2", "ggpubr", "scuttle", "SpotSweeper", "SummarizedExperiment")
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
    library(SpatialExperiment)
    library(SummarizedExperiment)
    library(SpotSweeper)
    library(scuttle)
    library(escheR)
    library(ggplot2)
    
    # 1. Load the SpatialExperiment object from the working directory
    if (!file.exists("spe.rds")) {
      stop("Error: 'spe.rds' not found in the working directory.")
    }
    spe <- readRDS("spe.rds")
    
    # Show column data before SpotSweeper
    print("ColData columns before SpotSweeper:")
    print(colnames(colData(spe)))
    
    # Drop out-of-tissue spots
    spe <- spe[, spe\$in_tissue == 1]
    
    # Change from gene id to gene names
    rownames(spe) <- rowData(spe)\$gene_name
    
    # Identifying the mitochondrial transcripts
    is.mito <- rownames(spe)[grepl("^MT-", rownames(spe))]
    
    # Calculating QC metrics for each spot using scuttle
    spe <- scuttle::addPerCellQCMetrics(spe, subsets = list(Mito = is.mito))
    print("ColData columns after scuttle QC:")
    print(colnames(colData(spe)))
    
    # 2. Run localOutliers for library size, unique genes, and mitochondrial percentage
    # Library size
    spe <- localOutliers(spe,
        metric = "sum",
        direction = "lower",
        log = TRUE
    )
    
    # Unique genes
    spe <- localOutliers(spe,
        metric = "detected",
        direction = "lower",
        log = TRUE
    )
    
    # Mitochondrial percent
    spe <- localOutliers(spe,
        metric = "subsets_Mito_percent",
        direction = "higher",
        log = FALSE
    )
    
    # 3. Combine all outliers into "local_outliers" column
    spe\$local_outliers <- as.logical(spe\$sum_outliers) |
        as.logical(spe\$detected_outliers) |
        as.logical(spe\$subsets_Mito_percent_outliers)
    
    # 4. Visualize the local outliers and save the plot
    p <- plotQCmetrics(spe, metric = "sum_log", outliers = "local_outliers", point_size = 1.1, 
           stroke = 0.75) +
          ggtitle("All Local Outliers")
    
    # Save the plot to a PDF file
    ggsave("local_outliers_plot.pdf", plot = p, width = 7, height = 6)
    
    # 5. Save the updated SpatialExperiment object and its colData
    saveRDS(spe, "spe_outliers.rds")
    
    # Export colData as a CSV table for downstream analysis
    write.csv(as.data.frame(colData(spe)), "colData_outliers.csv", row.names = TRUE)
    
    print("Pipeline completed successfully. Outputs saved: 'local_outliers_plot.pdf', 'spe_outliers.rds', and 'colData_outliers.csv'.")

    writeLines(c(
        '"BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION":',
        paste0('    SpotSweeper: ', as.character(packageVersion('SpotSweeper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spot_level_local_outlier_detection.csv versions.yml
    """
}

workflow BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION.out.tables
    plots    = BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION.out.plots
    objects  = BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION.out.objects
    versions = BIOC_SPOTSWEEPER_SPOT_LEVEL_LOCAL_OUTLIER_DETECTION.out.versions
}
