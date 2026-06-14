#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: stJoincount — spatial_join_count_analysis
// Quantify and visualize spatial correlation between clusters in spatial transcriptomics data using join count statistics.
// Input: seuratBC, SpeObjBC, humanBC
// Container: quay.io/biocontainers/bioconductor-stjoincount:1.12.0--r45hdfd78af_0
// R packages: ggplot2, pheatmap, stJoincount
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, pheatmap, stJoincount
// Visualizations: mosaic plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare data from Seurat or SpatialExperiment objects
//  * 2. [Core Analysis] Calculate optimal raster resolution
//  * 3. [Core Analysis] Rasterize each cluster
//  * 4. [Visualization & Output] Visualize the rasterized mosaic
//  * 5. [Core Analysis] Perform join count analysis
//  * 6. [Core Analysis] Generate a z-score matrix
//  * 7. [Visualization & Output] Plot the z-score heatmap

nextflow.enable.dsl = 2

process BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS {
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
    .bm_deps <- c("ggplot2", "pheatmap", "stJoincount")
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
        library(stJoincount)
        library(pheatmap)
        library(ggplot2)
        
        # Helper function to load inputs robustly from the working directory
        load_input <- function(name) {
          possible_files <- c(
            name, 
            paste0(name, ".rds"), 
            paste0(name, ".RDS"), 
            paste0(name, ".rda"), 
            paste0(name, ".RData")
          )
          for (f in possible_files) {
            if (file.exists(f)) {
              if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
                return(readRDS(f))
              } else {
                env <- new.env()
                load(f, envir = env)
                if (name %in% names(env)) {
                  return(env[[name]])
                } else {
                  return(env[[names(env)[1]]])
                }
              }
            }
          }
          stop(paste("Error: Could not find input file for", name))
        }
        
        # 1. Load user inputs
        seuratBC <- load_input("seuratBC")
        SpeObjBC <- load_input("SpeObjBC")
        humanBC <- load_input("humanBC")
        
        # 2. Prepare data from Seurat or SpatialExperiment objects
        df <- dataPrepFromSeurat(seuratBC, "label")
        df2 <- dataPrepFromSpE(SpeObjBC, "label")
        
        # Save prepared data frames
        write.csv(df, "df_seurat.csv", row.names = TRUE)
        write.csv(df2, "df_spe.csv", row.names = TRUE)
        
        # 3. Calculate optimal raster resolution
        resolutionList <- resolutionCalc(humanBC)
        saveRDS(resolutionList, "resolutionList.rds")
        
        # 4. Rasterize each cluster
        mosaicIntegration <- rasterizeEachCluster(humanBC)
        saveRDS(mosaicIntegration, "mosaicIntegration.rds")
        
        # 5. Visualize the rasterized mosaic
        pdf("mosaic_integration_plot.pdf", width = 7, height = 7)
        print(mosaicIntPlot(humanBC, mosaicIntegration))
        dev.off()
        
        # 6. Perform join count analysis
        joincount.result <- joincountAnalysis(mosaicIntegration)
        saveRDS(joincount.result, "joincount_result.rds")
        
        # 7. Generate a z-score matrix
        zscore_mat <- zscoreMatrix(humanBC, joincount.result)
        write.csv(zscore_mat, "zscore_matrix.csv", row.names = TRUE)
        saveRDS(zscore_mat, "zscore_matrix.rds")
        
        # 8. Plot the z-score heatmap
        pdf("zscore_heatmap.pdf", width = 7, height = 7)
        print(zscorePlot(zscore_mat))
        dev.off()

    writeLines(c(
        '"BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS":',
        paste0('    stJoincount: ', as.character(packageVersion('stJoincount')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_join_count_analysis.csv versions.yml
    """
}

workflow BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seuratBC, SpeObjBC, humanBC ] ]

    main:
    BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS.out.tables
    plots    = BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS.out.plots
    objects  = BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS.out.objects
    versions = BIOC_STJOINCOUNT_SPATIAL_JOIN_COUNT_ANALYSIS.out.versions
}
