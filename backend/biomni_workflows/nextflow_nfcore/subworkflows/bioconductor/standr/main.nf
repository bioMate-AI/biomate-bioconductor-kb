#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: standr — geomx_dsp_qc_norm_batch_correction
// Perform quality control, TMM normalization, and RUV4 batch correction on NanoString GeoMx DSP data.
// Input: countFile, sampleAnnoFile, featureAnnoFile
// Container: quay.io/biocontainers/bioconductor-standr:1.14.0--r45hdfd78af_0
// R packages: ExperimentHub, ggalluvial, ggplot2, limma, SpatialExperiment, standR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-standr:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("ExperimentHub", "ggalluvial", "ggplot2", "limma", "SpatialExperiment", "standR")
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
    
    # Define input file paths in the working directory
    countFile <- "countFile"
    sampleAnnoFile <- "sampleAnnoFile"
    featureAnnoFile <- "featureAnnoFile"
    
    # Validate existence of input files
    if (!file.exists(countFile) || !file.exists(sampleAnnoFile) || !file.exists(featureAnnoFile)) {
      stop("Error: Missing required input files ('countFile', 'sampleAnnoFile', 'featureAnnoFile') in the working directory.")
    }
    
    # Load required libraries
    library(standR)
    library(SpatialExperiment)
    library(limma)
    library(ggalluvial)
    library(ggplot2)
    
    # --- Import raw GeoMx data ---
    spe <- readGeoMx(countFile, sampleAnnoFile, featureAnnoFile = featureAnnoFile, rmNegProbe = TRUE)
    
    # --- Preprocess metadata to avoid collinearity ---
    colData(spe)\$regions <- paste0(colData(spe)\$region,"_",colData(spe)\$SegmentLabel) |> 
      (\(.) gsub("_Geometric Segment","",.))() |>
      paste0("_",colData(spe)\$pathology) |>
      (\(.) gsub("_NA","_ns",.))()
    
    # Set up PDF multi-page plot output
    pdf("standR_workflow_plots.pdf", width = 10, height = 8)
    
    # Visualize sample metadata
    p_sample_info <- plotSampleInfo(spe, column2plot = c("SlideName","disease_status","regions"))
    print(p_sample_info)
    
    # --- Perform gene-level QC ---
    spe <- addPerROIQC(spe, rm_genes = TRUE)
    
    p_gene_qc <- plotGeneQC(spe, ordannots = "regions", col = regions, point_size = 2)
    print(p_gene_qc)
    
    # --- Perform ROI-level QC and filter low-quality ROIs ---
    p_roi_qc <- plotROIQC(spe, y_threshold = 50000, col = SlideName)
    print(p_roi_qc)
    
    spe <- spe[,rownames(colData(spe))[colData(spe)\$lib_size > 50000]]
    
    # --- Inspect variations using RLE and PCA (Pre-normalization) ---
    p_rle_pre <- plotRLExpr(spe, ordannots = "SlideName", assay = 2, col = SlideName)
    print(p_rle_pre)
    
    p_pca_pre <- drawPCA(spe, assay = 2, col = SlideName, shape = regions)
    print(p_pca_pre)
    
    # --- Normalize data using TMM ---
    colData(spe)\$biology <- paste0(colData(spe)\$disease_status, "_", colData(spe)\$regions)
    
    spe_tmm <- geomxNorm(spe, method = "TMM")
    
    # --- Identify Negative Control Genes (NCGs) ---
    spe <- findNCGs(spe, batch_name = "SlideName", top_n = 500)
    
    # Print NCG metadata names to console
    message("Metadata fields after NCG identification:")
    print(names(metadata(spe)))
    
    # --- Perform RUV4 batch correction ---
    spe_ruv <- geomxBatchCorrection(spe, factors = "biology", 
                                    NCGs = metadata(spe)\$NCGs, k = 5)
    
    # --- Visualize corrected data ---
    p_pca_post <- plotPairPCA(spe_ruv, assay = 2, color = disease_status, shape = regions, title = "RUV4")
    print(p_pca_post)
    
    p_rle_post <- plotRLExpr(spe_ruv, assay = 2, color = SlideName) + ggtitle("RUV4")
    print(p_rle_post)
    
    # Close PDF device
    dev.off()
    
    # Save meaningful results to output files
    saveRDS(spe_tmm, "spe_normalized_tmm.rds")
    saveRDS(spe_ruv, "spe_corrected_ruv.rds")
    
    # Export sample metadata and normalized expression data
    write.csv(as.data.frame(colData(spe_ruv)), "spe_corrected_metadata.csv", row.names = TRUE)
    
    message("standR pipeline completed successfully. Outputs saved to 'standR_workflow_plots.pdf', 'spe_normalized_tmm.rds', 'spe_corrected_ruv.rds', and 'spe_corrected_metadata.csv'.")

    writeLines(c(
        '"BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION":',
        paste0('        standr: ', as.character(packageVersion("standr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geomx_dsp_qc_norm_batch_correction.csv versions.yml
    """
}

workflow BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countFile, sampleAnnoFile, featureAnnoFile ] ]

    main:
    BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION.out.tables
    plots    = BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION.out.plots
    objects  = BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION.out.objects
    versions = BIOC_STANDR_GEOMX_DSP_QC_NORM_BATCH_CORRECTION.out.versions
}
