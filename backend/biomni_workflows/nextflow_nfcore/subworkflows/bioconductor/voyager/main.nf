#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Voyager — spatial_exploratory_data_analysis
// Perform exploratory spatial data analysis (ESDA) on spatial transcriptomics data, including univariate, bivariate, and multivariate spatial statistics, and visu
// Input: sfe, tissue_lowres_5a.jpeg
// Container: quay.io/biocontainers/bioconductor-voyager:1.12.0--r45hdfd78af_0
// R packages: ggplot2, pheatmap, scater, scran, SFEData, SpatialExperiment, SpatialFeatureExperiment, Voyager
// Bioconductor: 3.20 | R: 4.4
// Requires: SFEData, SpatialExperiment, SpatialFeatureExperiment, Voyager, ggplot2, pheatmap, scales, scater, scran
// Visualizations: heatmap, elbow plot
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load required libraries and read the SpatialFeatureExperiment dataset
//  * 2. [Core Analysis] Add and mirror the tissue image to align with spatial coordinates
//  * 3. [Core Analysis] Filter spots to keep only those in tissue and normalize counts
//  * 4. [Input & Preparation] Construct a spatial neighborhood graph using findVisiumGraph
//  * 5. [Core Analysis] Run univariate spatial statistics (Moran's I and Getis-Ord Gi*) using runUnivariate
//  * 6. [Core Analysis] Identify highly variable genes and calculate bivariate spatial correlation (Lee's L) using calculateBivariate
//  * 7. [Core Analysis] Perform spatially-informed dimension reduction (MULTISPATI PCA) using runMultivariate
//  * 8. [Visualization & Output] Visualize gene expression, local spatial statistics, eigenvalues, and reduced dimensions in spatial context using plotting functio

nextflow.enable.dsl = 2

process BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS {
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
    .bm_deps <- c("ggplot2", "pheatmap", "scater", "scran", "SFEData", "SpatialExperiment", "SpatialFeatureExperiment", "Voyager", "SummarizedExperiment")
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
            
            # 1. Load required libraries
                 library(SummarizedExperiment)
       library(SFEData)
            library(SpatialFeatureExperiment)
            library(SpatialExperiment)
            library(ggplot2)
            library(Voyager)
            library(scater)
            library(scran)
            library(pheatmap)
            
            # 2. Read the SpatialFeatureExperiment dataset and verify input files
            sfe_path <- if (file.exists("sfe")) "sfe" else "sfe.rds"
            if (!file.exists(sfe_path)) {
                stop("Required input file 'sfe' or 'sfe.rds' not found in the working directory.")
            }
            if (!file.exists("tissue_lowres_5a.jpeg")) {
                stop("Required input file 'tissue_lowres_5a.jpeg' not found in the working directory.")
            }
            
            sfe <- readRDS(sfe_path)
            
            # 3. Add and mirror the tissue image to align with spatial coordinates
            sample_id <- sampleIDs(sfe)[1]
            sfe <- addImg(sfe, imageSource = "tissue_lowres_5a.jpeg", sample_id = sample_id, 
                          image_id = "lowres", scale_fct = 1024/22208)
            
            sfe <- mirrorImg(sfe, sample_id = sample_id, image_id = "lowres")
            
            # 4. Filter spots to keep only those in tissue and normalize counts
            sfe <- sfe[,colData(sfe)\$in_tissue]
            sfe <- logNormCounts(sfe)
            
            # 5. Construct a spatial neighborhood graph using findVisiumGraph
            colGraph(sfe, "visium") <- findVisiumGraph(sfe)
            
            # 6. Run univariate spatial statistics (Moran's I and Getis-Ord Gi*) using runUnivariate
            features_use <- getTopHVGs(modelGeneVar(sfe), n = 2)
            
            sfe <- runUnivariate(sfe, type = "moran", features = features_use, 
                                 colGraphName = "visium")
            
            moran_results <- rowData(sfe)[features_use,]
            write.csv(as.data.frame(moran_results), "moran_results.csv", row.names = TRUE)
            
            sfe <- runUnivariate(sfe, type = "localG", features = features_use,
                                 colGraphName = "visium", include_self = TRUE)
            
            localG_head <- head(localResults(sfe, name = "localG")[[1]])
            write.csv(as.data.frame(localG_head), "localG_head_results.csv", row.names = TRUE)
            
            # 7. Identify highly variable genes and calculate bivariate spatial correlation (Lee's L) using calculateBivariate
            gs <- modelGeneVar(sfe)
            hvgs <- getTopHVGs(gs, fdr.threshold = 0.01)
            
            res <- calculateBivariate(sfe, "lee", hvgs)
            write.csv(as.data.frame(res), "bivariate_lee_results.csv", row.names = TRUE)
            
            pdf("pheatmap_lee.pdf", width = 8, height = 8)
            pheatmap(res, color = scales::viridis_pal()(256), cellwidth = 1, cellheight = 1,
                     show_rownames = FALSE, show_colnames = FALSE)
            dev.off()
            
            # 8. Perform spatially-informed dimension reduction (MULTISPATI PCA) using runMultivariate
            hvgs2 <- getTopHVGs(gs, n = 1000)
            sfe <- runMultivariate(sfe, "multispati", colGraphName = "visium", subset_row = hvgs2,
                                   nfposi = 10, nfnega = 10)
            
            # 9. Visualize gene expression, local spatial statistics, eigenvalues, and reduced dimensions in spatial context
            pdf("spatial_feature_plot.pdf", width = 10, height = 8)
            p1 <- plotSpatialFeature(sfe, features_use, colGeometryName = "spotPoly", 
                                     aes_use = "color", linewidth = 0.5, fill = NA)
            print(p1)
            dev.off()
            
            pdf("local_result_plot.pdf", width = 10, height = 8)
            p2 <- plotLocalResult(sfe, "localG", features = features_use, 
                                  colGeometryName = "spotPoly", divergent = TRUE, 
                                  diverge_center = 0,
                                  image_id = "lowres", maxcell = 5e+4)
            print(p2)
            dev.off()
            
            pdf("elbow_plot.pdf", width = 8, height = 6)
            p3 <- ElbowPlot(sfe, ndims = 10, nfnega = 10, reduction = "multispati") + theme_bw()
            print(p3)
            dev.off()
            
            pdf("spatial_reduced_dim_plot.pdf", width = 10, height = 8)
            p4 <- spatialReducedDim(sfe, "multispati", ncomponents = 2, image_id = "lowres", 
                                    maxcell = 5e+4, divergent = TRUE, diverge_center = 0)
            print(p4)
            dev.off()
            
            # Save the final processed SpatialFeatureExperiment object
            saveRDS(sfe, "sfe_processed.rds")

    writeLines(c(
        '"BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS":',
        paste0('    Voyager: ', as.character(packageVersion('Voyager')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_exploratory_data_analysis.csv versions.yml
    """
}

workflow BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sfe, tissue_lowres_5a.jpeg ] ]

    main:
    BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.tables
    plots    = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.plots
    objects  = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.objects
    versions = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.versions
}
