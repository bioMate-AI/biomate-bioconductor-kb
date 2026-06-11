#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MassSpecWavelet — cwt_peak_detection
// Detect, identify, and refine peak parameters in mass spectrometry intensity profiles using Continuous Wavelet Transform (CWT) and ridge-line tracking.
// Input: exampleMS
// Container: quay.io/biocontainers/bioconductor-massspecwavelet:1.76.0--r45h01b2380_0
// R packages: MassSpecWavelet
// Bioconductor: 3.20 | R: 4.4
// Requires: MassSpecWavelet
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform Continuous Wavelet Transform (CWT) using the Mexican Hat wavelet
//  * 2. [Core Analysis] Identify local maxima of CWT coefficients across scales
//  * 3. [Core Analysis] Connect local maxima into ridge lines
//  * 4. [Core Analysis] Identify major peaks based on SNR thresholds
//  * 5. [Core Analysis] Refine peak parameter estimations (center, width, strength)

nextflow.enable.dsl = 2

process BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("MassSpecWavelet")
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
    
    # Load required library
    library(MassSpecWavelet)
    
    # ==========================================
    # 1. Read User Input
    # ==========================================
    # The pipeline expects 'exampleMS' in the working directory.
    # We support RDS, CSV, TXT, or a raw scan file.
    if (file.exists("exampleMS.rds")) {
      exampleMS <- readRDS("exampleMS.rds")
    } else if (file.exists("exampleMS.csv")) {
      exampleMS <- as.numeric(read.csv("exampleMS.csv", header = FALSE)[[1]])
    } else if (file.exists("exampleMS.txt")) {
      exampleMS <- as.numeric(readLines("exampleMS.txt"))
    } else if (file.exists("exampleMS")) {
      exampleMS <- as.numeric(scan("exampleMS", quiet = TRUE))
    } else {
      stop("Required input file 'exampleMS' (RDS, CSV, TXT, or binary/scan) not found in the working directory.")
    }
    
    # Ensure exampleMS is a numeric vector
    exampleMS <- as.vector(as.numeric(exampleMS))
    
    # ==========================================
    # 2. Perform Continuous Wavelet Transform (CWT)
    # ==========================================
    scales <- seq(1, 64, 2)
    wCoefs <- cwt(exampleMS, scales = scales, wavelet = "mexh")
    wCoefs <- cbind(as.vector(exampleMS), wCoefs)
    colnames(wCoefs) <- c(0, scales)
    
    # ==========================================
    # 3. Identify Local Maxima of CWT Coefficients
    # ==========================================
    localMax <- getLocalMaximumCWT(wCoefs)
    
    # ==========================================
    # 4. Connect Local Maxima into Ridge Lines
    # ==========================================
    ridgeList <- getRidge(localMax)
    
    # ==========================================
    # 5. Identify Major Peaks based on SNR Thresholds
    # ==========================================
    SNR.Th <- 3
    nearbyPeak <- TRUE
    majorPeakInfo <- identifyMajorPeaks(
      exampleMS,
      ridgeList,
      wCoefs,
      SNR.Th = SNR.Th,
      nearbyPeak = nearbyPeak
    )
    
    # ==========================================
    # 6. Refine Peak Parameter Estimations
    # ==========================================
    betterPeakInfo <- tuneInPeakInfo(exampleMS, majorPeakInfo)
    
    # ==========================================
    # 7. Save Outputs (RDS and CSV)
    # ==========================================
    saveRDS(wCoefs, "wCoefs.rds")
    saveRDS(localMax, "localMax.rds")
    saveRDS(ridgeList, "ridgeList.rds")
    saveRDS(majorPeakInfo, "majorPeakInfo.rds")
    saveRDS(betterPeakInfo, "betterPeakInfo.rds")
    
    # Construct and save a refined peaks table
    tryCatch({
      peaks_df <- data.frame(
        Peak_Name = names(majorPeakInfo\$peakIndex),
        Initial_Index = majorPeakInfo\$peakIndex,
        Refined_Center_Index = betterPeakInfo\$peakCenterIndex
      )
      
      if (!is.null(majorPeakInfo\$peakSNR)) {
        peaks_df\$SNR <- majorPeakInfo\$peakSNR[peaks_df\$Peak_Name]
      }
      if (!is.null(majorPeakInfo\$peakScale)) {
        peaks_df\$Scale <- majorPeakInfo\$peakScale[peaks_df\$Peak_Name]
      }
      
      write.csv(peaks_df, "peaks_refined.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not create peaks_refined.csv: ", e\$message)
    })
    
    # ==========================================
    # 8. Generate Diagnostic Plots (PDF)
    # ==========================================
    tryCatch({
      pdf("peak_detection_plots.pdf", width = 10, height = 8)
      
      # Define a robust plotting range based on input length
      plotRange <- c(1, length(exampleMS))
      if (length(exampleMS) >= 11000) {
        plotRange <- c(5000, 11000)
      }
      
      # Plot 1: Raw Spectrum
      plot(exampleMS, xlim = plotRange, type = "l", main = "Raw MS Spectrum", xlab = "m/z Index", ylab = "Intensity")
      
      # Plot 2: Local Maxima
      plotLocalMax(localMax, wCoefs, range = plotRange)
      title(main = "Identified Local Maxima of CWT Coefficients")
      
      # Plot 3: Ridge Lines
      plotRidgeList(ridgeList, wCoefs, range = plotRange)
      title(main = "Identified Ridge Lines")
      
      # Plot 4: Identified Peaks
      peakIndex <- majorPeakInfo\$peakIndex
      plotPeak(
        exampleMS,
        peakIndex,
        range = plotRange,
        main = paste('Identified Peaks with SNR >', SNR.Th)
      )
      
      # Plot 5: Refined Peak Centers
      plot(
        plotRange[1]:plotRange[2],
        exampleMS[plotRange[1]:plotRange[2]],
        type = 'l',
        xlab = 'm/z Index',
        ylab = 'Intensity',
        main = "Refined Peak Center Positions"
      )
      abline(v = betterPeakInfo\$peakCenterIndex, col = 'red', lty = 2)
      
      dev.off()
    }, error = function(e) {
      warning("Could not generate PDF plots: ", e\$message)
      if (!is.null(dev.list())) dev.off()
    })

    writeLines(c(
        '"BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION":',
        paste0('    MassSpecWavelet: ', as.character(packageVersion('MassSpecWavelet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cwt_peak_detection.csv versions.yml
    """
}

workflow BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleMS ] ]

    main:
    BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION(ch_input)

    emit:
    tables   = BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION.out.tables
    plots    = BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION.out.plots
    objects  = BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION.out.objects
    versions = BIOC_MASSSPECWAVELET_CWT_PEAK_DETECTION.out.versions
}
