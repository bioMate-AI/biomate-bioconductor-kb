#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FuseSOM — sce_or_spe_input
// Run FuseSOM clustering, estimate the optimal number of clusters, and visualize results using a SingleCellExperiment or SpatialExperiment object.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-fusesom:1.12.0--r45ha27e39d_0
// R packages: FuseSOM, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: FuseSOM, SingleCellExperiment
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run FuseSOM clustering on the SCE/SPE object using runFuseSOM
//  * 2. [Visualization & Output] Generate a marker expression heatmap using markerHeatmap
//  * 3. [Core Analysis] Estimate the optimal number of clusters on the SCE/SPE object using estimateNumCluster
//  * 4. [Visualization & Output] Plot cluster estimation metrics using optiPlot

nextflow.enable.dsl = 2

process BIOC_FUSESOM_SCE_OR_SPE_INPUT {
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
    .bm_deps <- c("FuseSOM", "SingleCellExperiment", "SummarizedExperiment")
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
            library(FuseSOM)
            library(SummarizedExperiment)
            
            # Read the user input SCE/SPE object from the working directory
            if (file.exists("sce")) {
              sce <- readRDS("sce")
            } else if (file.exists("sce.rds")) {
              sce <- readRDS("sce.rds")
            } else {
              stop("Input file 'sce' or 'sce.rds' not found in the working directory.")
            }
            
            # Define markers and reconstruct the original data matrix from the SCE object
            # We exclude 'CellType' if it is present in the rownames
            if (is.null(assayNames(sce))) {
              assayNames(sce) <- paste0("assay", seq_along(assays(sce)))
            }
            assay_name <- assayNames(sce)[1]
            risomMarkers <- setdiff(rownames(sce), "CellType")
            risom_dat <- as.data.frame(t(as.matrix(assay(sce, assay_name))))
            
            # 1. Run FuseSOM clustering on the SCE/SPE object
            risomRessce <- runFuseSOM(sce, markers = risomMarkers, assay = assay_name, 
                                      numClusters = 23, verbose = FALSE)
            colnames(colData(risomRessce))
            names(metadata(risomRessce))
            
            # 2. Generate a marker expression heatmap
            data <- risom_dat[, risomMarkers] # get the original data used
            clusters <- colData(risomRessce)\$clusters # extract the clusters from the sce object
            risomHeatsce <- markerHeatmap(data = risom_dat, markers = risomMarkers,
                                          clusters = clusters, clusterMarkers = TRUE)
            
            # Save the heatmap to a PDF file
            pdf("marker_heatmap.pdf", width = 10, height = 8)
            print(risomHeatsce)
            dev.off()
            
            # 3. Estimate the optimal number of clusters on the SCE/SPE object
            risomRessce <- estimateNumCluster(data = risomRessce, kSeq = 2:25, 
                                              method = c("Discriminant", "Distance"))
            names(metadata(risomRessce))
            metadata(risomRessce)\$clusterEstimation\$Discriminant 
            
            # Save the cluster estimation results
            saveRDS(metadata(risomRessce)\$clusterEstimation, "cluster_estimation.rds")
            
            # 4. Plot cluster estimation metrics using optiPlot
            pSlope <- optiPlot(risomRessce, method = 'slope')
            pSlope
            pJump <- optiPlot(risomRessce, method = 'jump')
            pJump
            pWcd <- optiPlot(risomRessce, method = 'wcd')
            pWcd
            pGap <- optiPlot(risomRessce, method = 'gap')
            pGap
            pSil <- optiPlot(risomRessce, method = 'silhouette')
            pSil
            
            # Save the optimization plots to a PDF file
            pdf("opti_plots.pdf", width = 8, height = 6)
            print(pSlope)
            print(pJump)
            print(pWcd)
            print(pGap)
            print(pSil)
            dev.off()
            
            # Save the final SCE object containing clustering and estimation metadata
            saveRDS(risomRessce, "risomRessce.rds")

    writeLines(c(
        '"BIOC_FUSESOM_SCE_OR_SPE_INPUT":',
        paste0('    FuseSOM: ', as.character(packageVersion('FuseSOM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sce_or_spe_input.csv versions.yml
    """
}

workflow BIOC_FUSESOM_SCE_OR_SPE_INPUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_FUSESOM_SCE_OR_SPE_INPUT(ch_input)

    emit:
    tables   = BIOC_FUSESOM_SCE_OR_SPE_INPUT.out.tables
    plots    = BIOC_FUSESOM_SCE_OR_SPE_INPUT.out.plots
    objects  = BIOC_FUSESOM_SCE_OR_SPE_INPUT.out.objects
    versions = BIOC_FUSESOM_SCE_OR_SPE_INPUT.out.versions
}
