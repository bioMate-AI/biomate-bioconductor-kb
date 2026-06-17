#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PepsNMR — nmr_preprocessing_pipeline
// Pre-process raw 1H-NMR Bruker FID signals into normalized, bucketed, and aligned spectra.
// Input: raw_bruker_directory
// Container: quay.io/biocontainers/bioconductor-pepsnmr:1.28.0--r45hdfd78af_0
// R packages: PepsNMR, pepsnmrdata
// Bioconductor: 3.20 | R: 4.4
// Requires: PepsNMR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw FIDs (ReadFids)
//  * 2. [Core Analysis] Group Delay Correction (GroupDelayCorrection)
//  * 3. [Core Analysis] Solvent Suppression (SolventSuppression)
//  * 4. [Core Analysis] Apodization (Apodization)
//  * 5. [Core Analysis] Zero Filling (ZeroFilling)
//  * 6. [Core Analysis] Fourier Transform (FourierTransform)
//  * 7. [Core Analysis] Zero Order Phase Correction (ZeroOrderPhaseCorrection)
//  * 8. [Core Analysis] Internal Referencing (InternalReferencing)
//  * 9. [Core Analysis] Baseline Correction (BaselineCorrection)
//  * 10. [Core Analysis] Negative Values Zeroing (NegativeValuesZeroing)
//  * 11. [Core Analysis] Warping (Warping)
//  * 12. [Core Analysis] Window Selection (WindowSelection)
//  * 13. [Core Analysis] Bucketing (Bucketing)
//  * 14. [Core Analysis] Region Removal (RegionRemoval)
//  * 15. [Core Analysis] Normalization (Normalization)
//  * 16. [Visualization & Output] Visualization (Draw)

nextflow.enable.dsl = 2

process BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("PepsNMR", "pepsnmrdata")
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
    library(PepsNMR)
    
    # 1. Setup input directory
    raw_input_dir <- "raw_bruker_directory"
    if (!dir.exists(raw_input_dir)) {
      stop("Error: 'raw_bruker_directory' does not exist in the working directory.")
    }
    
    # 2. Read raw FIDs
    fidList <- ReadFids(raw_input_dir)
    Fid_data0 <- fidList[["Fid_data"]]
    Fid_info <- fidList[["Fid_info"]]
    
    # 3. Group Delay Correction
    Fid_data.GDC <- GroupDelayCorrection(Fid_data0, Fid_info)
    
    # 4. Solvent Suppression
    SS.res <- SolventSuppression(Fid_data.GDC, returnSolvent=TRUE)
    Fid_data.SS <- SS.res[["Fid_data"]]
    SolventRe <- SS.res[["SolventRe"]]
    
    # 5. Apodization
    Fid_data.A <- Apodization(Fid_data.SS, Fid_info)
    
    # 6. Zero Filling
    Fid_data.ZF <- ZeroFilling(Fid_data.A, fn = ncol(Fid_data.A))
    
    # 7. Fourier Transform
    RawSpect_data.FT <- FourierTransform(Fid_data.ZF, Fid_info)
    
    # 8. Zero Order Phase Correction
    Spectrum_data.ZOPC <- ZeroOrderPhaseCorrection(RawSpect_data.FT)
    Spectrum_data.ZOPC <- ZeroOrderPhaseCorrection(RawSpect_data.FT, plot_rms = rownames(RawSpect_data.FT)[1])
    
    # 9. Internal Referencing
    target.value <- 0
    IR.res <- InternalReferencing(Spectrum_data.ZOPC, Fid_info, ppm.value = target.value, rowindex_graph = c(1,2))
    Spectrum_data.IR <- IR.res\$Spectrum_data
    
    # 10. Baseline Correction
    BC.res <- BaselineCorrection(Spectrum_data.IR, returnBaseline = TRUE, lambda.bc = 1e8, p.bc = 0.01)
    Spectrum_data.BC <- BC.res[["Spectrum_data"]] 
    Baseline <- BC.res[["Baseline"]]
    
    # 11. Negative Values Zeroing
    Spectrum_data.NVZ <- NegativeValuesZeroing(Spectrum_data.BC)
    
    # 12. Warping
    W.res <- Warping(Spectrum_data.NVZ, returnWarpFunc = TRUE, reference.choice = "fixed")
    Spectrum_data.W <- W.res[["Spectrum_data"]]
    warp_func <- W.res[["Warp.func"]]
    
    # 13. Window Selection
    Spectrum_data.WS <- WindowSelection(Spectrum_data.W, from.ws = 10, to.ws = 0.2)
    
    # 14. Bucketing
    Spectrum_data.B <- Bucketing(Spectrum_data.WS, intmeth = "t")
    
    # 15. Region Removal
    Spectrum_data.RR <- RegionRemoval(Spectrum_data.B)
    
    # 16. Normalization
    Spectrum_data.N <- Normalization(Spectrum_data.RR, type.norm = "mean")
    
    # Define Group_HS for PCA visualization
    if (file.exists("Group_HS.csv")) {
      Group_HS_df <- read.csv("Group_HS.csv", header = FALSE)
      Group_HS <- Group_HS_df[[1]]
    } else if (file.exists(file.path(raw_input_dir, "Group_HS.csv"))) {
      Group_HS_df <- read.csv(file.path(raw_input_dir, "Group_HS.csv"), header = FALSE)
      Group_HS <- Group_HS_df[[1]]
    } else {
      Group_HS <- as.factor(rep(c("Group_A", "Group_B"), length.out = nrow(Spectrum_data.N)))
    }
    
    # 17. Visualization and Output Generation
    pdf("preprocessing_plots.pdf", width = 10, height = 6)
    Draw(Spectrum_data.N[1:min(4, nrow(Spectrum_data.N)), , drop = FALSE], type.draw = c("signal"), subtype= "stacked", output = c("default"))
    Draw(Spectrum_data.N, type.draw = c("pca"), output = c("default"), Class = Group_HS, type.pca = "scores")
    Draw(Spectrum_data.N, type.draw = c("pca"), output = c("default"), Class = Group_HS, type.pca = "loadings")
    dev.off()
    
    # Save final processed data
    saveRDS(Spectrum_data.N, "normalized_spectra.rds")
    write.csv(as.data.frame(Re(Spectrum_data.N)), "normalized_spectra.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE":',
        paste0('    PepsNMR: ', as.character(packageVersion('PepsNMR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nmr_preprocessing_pipeline.csv versions.yml
    """
}

workflow BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_bruker_directory ] ]

    main:
    BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE.out.tables
    plots    = BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE.out.plots
    objects  = BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE.out.objects
    versions = BIOC_PEPSNMR_NMR_PREPROCESSING_PIPELINE.out.versions
}
