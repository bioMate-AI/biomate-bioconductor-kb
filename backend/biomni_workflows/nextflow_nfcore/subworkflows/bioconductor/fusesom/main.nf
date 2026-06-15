#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FuseSOM — matrix_or_dataframe_input
// Run FuseSOM clustering, estimate the optimal number of clusters, and visualize results using a standard matrix or data frame.
// Input: risom_dat
// Container: quay.io/biocontainers/bioconductor-fusesom:1.12.0--r45ha27e39d_0
// R packages: FuseSOM, knitr, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: FuseSOM
// Visualizations: heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run FuseSOM clustering using runFuseSOM
//  * 2. [Visualization & Output] Generate a marker expression heatmap using markerHeatmap
//  * 3. [Core Analysis] Estimate the optimal number of clusters using estimateNumCluster
//  * 4. [Visualization & Output] Plot cluster estimation metrics using optiPlot

nextflow.enable.dsl = 2

process BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("FuseSOM", "knitr", "SingleCellExperiment")
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
    library(FuseSOM)
    
    # 1. Read User Input
    # The pipeline reads risom_dat from the working directory (supporting RDS or CSV format).
    if (file.exists("risom_dat.rds")) {
      risom_dat <- readRDS("risom_dat.rds")
    } else if (file.exists("risom_dat.csv")) {
      risom_dat <- read.csv("risom_dat.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("risom_dat")) {
      risom_dat <- tryCatch(
        readRDS("risom_dat"),
        error = function(e) read.csv("risom_dat", row.names = 1, check.names = FALSE)
      )
    } else {
      stop("Required input file 'risom_dat' (RDS or CSV) not found in the working directory.")
    }
    
    # Align with vignette preprocessing if the column exists
    if ('manual_gating_phenotype' %in% names(risom_dat)) {
      names(risom_dat)[names(risom_dat) == 'manual_gating_phenotype'] <- 'CellType'
    }
    
    # Define the markers of interest dynamically to support generic user data
    risomMarkers <- setdiff(colnames(risom_dat), 'CellType')
    
    # 2. Run FuseSOM clustering
    risomRes <- runFuseSOM(data = risom_dat, markers = risomMarkers, 
                            numClusters = 23)
    
    # Save clustering results object
    saveRDS(risomRes, "risom_results.rds")
    
    # Calculate and save cluster distribution
    cluster_dist <- table(risomRes\$clusters)/sum(table(risomRes\$clusters))
    write.csv(as.data.frame(cluster_dist), "cluster_distribution.csv", row.names = TRUE)
    
    # 3. Generate marker expression heatmap
    pdf("marker_heatmap.pdf", width = 10, height = 8)
    risomHeat <- FuseSOM::markerHeatmap(data = risom_dat, markers = risomMarkers,
                                clusters = risomRes\$clusters, clusterMarkers = TRUE)
    dev.off()
    
    # 4. Estimate the optimal number of clusters
    risomKest <- estimateNumCluster(data = risomRes\$model, kSeq = 2:25, 
                                      method = c("Discriminant", "Distance"))
    
    # Save cluster estimation results object
    saveRDS(risomKest, "cluster_estimation.rds")
    
    # Write discriminant result to a text file
    writeLines(paste("Optimal clusters (Discriminant):", risomKest\$Discriminant), 
               con = "discriminant_optimal_k.txt")
    
    # 5. Plot cluster estimation metrics using optiPlot
    pSlope <- optiPlot(risomKest, method = 'slope')
    pJump <- optiPlot(risomKest, method = 'jump')
    pWcd <- optiPlot(risomKest, method = 'wcd')
    pGap <- optiPlot(risomKest, method = 'gap')
    pSil <- optiPlot(risomKest, method = 'silhouette')
    
    # Save all diagnostic plots to a single multi-page PDF
    pdf("optimal_clusters_plots.pdf", width = 8, height = 6)
    print(pSlope)
    print(pJump)
    print(pWcd)
    print(pGap)
    print(pSil)
    dev.off()

    writeLines(c(
        '"BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT":',
        paste0('    FuseSOM: ', as.character(packageVersion('FuseSOM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_or_dataframe_input.csv versions.yml
    """
}

workflow BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ risom_dat ] ]

    main:
    BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT(ch_input)

    emit:
    tables   = BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT.out.tables
    plots    = BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT.out.plots
    objects  = BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT.out.objects
    versions = BIOC_FUSESOM_MATRIX_OR_DATAFRAME_INPUT.out.versions
}
