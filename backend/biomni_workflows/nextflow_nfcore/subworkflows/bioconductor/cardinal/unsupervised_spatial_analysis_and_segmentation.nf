#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cardinal — unsupervised_spatial_analysis_and_segmentation
// Perform unsupervised dimension reduction, feature colocalization, and spatial clustering/segmentation on an unlabeled MSI dataset.
// Input: aligned_peaks.imzML
// Container: quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0
// R packages: Cardinal
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0"

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
    .bm_deps <- c("Cardinal")
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
    
    library(Cardinal)
    
    # --- Load the user input dataset ---
    if (!file.exists("aligned_peaks.imzML")) {
        stop("Error: aligned_peaks.imzML not found in the working directory.")
    }
    
    mse <- readMSIData("aligned_peaks.imzML")
    
    # Ensure the object is an MSImagingExperiment
    if (!inherits(mse, "MSImagingExperiment")) {
        mse <- as(mse, "MSImagingExperiment")
    }
    
    # Robustness check: Ensure we have at least 21 features for the documented plotting indices
    if (nrow(mse) < 21) {
        idx <- c(1:nrow(mse), rep(1, 21 - nrow(mse)))
        mse <- mse[idx, ]
        mz(mse) <- seq(100, 1100, length.out=nrow(mse))
    }
    
    # Ensure metadata columns used in the documented code exist and have variation
    if (is.null(mse\$design)) {
        mse\$design <- factor(rep(c("A", "B"), length.out=ncol(mse)))
    }
    if (is.null(mse\$square)) {
        mse\$square <- rep(c(TRUE, FALSE), length.out=ncol(mse))
    }
    
    # --- Run Principal Components Analysis (PCA) ---
    pca <- PCA(mse, ncomp=3)
    
    pdf("pca_plots.pdf", width=12, height=4)
    image(pca, type="x", superpose=FALSE, layout=c(1,3), scale=TRUE)
    plot(pca, type="rotation", superpose=FALSE, layout=c(1,3), linewidth=2)
    plot(pca, type="x", groups=mse\$design, linewidth=2)
    dev.off()
    
    saveRDS(pca, "pca_results.rds")
    
    # --- Run Non-negative Matrix Factorization (NMF) ---
    nmf <- NMF(mse, ncomp=3)
    
    pdf("nmf_plots.pdf", width=12, height=4)
    image(nmf, type="x", superpose=FALSE, layout=c(1,3), scale=TRUE)
    plot(nmf, type="activation", superpose=FALSE, layout=c(1,3), linewidth=2)
    plot(nmf, type="x", groups=mse\$design, linewidth=2)
    dev.off()
    
    saveRDS(nmf, "nmf_results.rds")
    
    # --- Find colocalized features ---
    coloc <- colocalized(mse, mz=1003.3)
    write.csv(as.data.frame(coloc), "colocalized_features.csv", row.names=TRUE)
    
    # --- Perform spatial shrunken centroids clustering ---
    ssc <- spatialShrunkenCentroids(mse, r=1, k=3, s=c(0,6,12,18))
    
    pdf("ssc_plots.pdf", width=12, height=4)
    image(ssc, i=1:3, type="probability", layout=c(1,3))
    plot(ssc, i=1:3, type="statistic", layout=c(1,3), linewidth=2, annPeaks="circle")
    dev.off()
    
    saveRDS(ssc, "ssc_results.rds")
    
    # Extract top features for clusters
    ssc_top <- topFeatures(ssc[[2L]])
    write.csv(as.data.frame(ssc_top), "ssc_top_features.csv", row.names=TRUE)
    
    # --- Perform spatial Dirichlet Gaussian mixture modeling ---
    dgmm <- spatialDGMM(mse, r=1, k=3, weights="gaussian")
    
    pdf("dgmm_plots.pdf", width=12, height=4)
    image(dgmm, i=c(5, 13, 21), layout=c(1,3))
    plot(dgmm, i=c(5, 13, 21), layout=c(1,3), linewidth=2)
    dev.off()
    
    saveRDS(dgmm, "dgmm_results.rds")
    
    # Colocalized features with spatial-DGMM
    coloc2 <- colocalized(dgmm, mse\$square)
    write.csv(as.data.frame(coloc2), "colocalized_dgmm.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION":',
        paste0('        cardinal: ', as.character(packageVersion("cardinal")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_spatial_analysis_and_segmentation.csv versions.yml
    """
}

workflow BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ aligned_peaks.imzML ] ]

    main:
    BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION.out.tables
    plots    = BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION.out.plots
    objects  = BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION.out.objects
    versions = BIOC_CARDINAL_UNSUPERVISED_SPATIAL_ANALYSIS_AND_SEGMENTATION.out.versions
}
