#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MassSpecWavelet — one_step_peak_detection
// Run the entire CWT-based peak detection and parameter refinement pipeline in a single encapsulated step.
// Input: exampleMS
// Container: quay.io/biocontainers/bioconductor-massspecwavelet:1.76.0--r45h01b2380_0
// R packages: MassSpecWavelet
// Bioconductor: 3.20 | R: 4.4
// Requires: MassSpecWavelet
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the encapsulated peak detection pipeline
//  * 2. [Core Analysis] Extract major peak information
//  * 3. [Core Analysis] Refine peak parameter estimations (center, width, strength)

nextflow.enable.dsl = 2

process BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects 'exampleMS' as a numeric vector from the working directory.
    # We support RDS, CSV, or TXT formats.
    if (file.exists("exampleMS.rds")) {
      exampleMS <- readRDS("exampleMS.rds")
    } else if (file.exists("exampleMS.csv")) {
      exampleMS <- as.numeric(read.csv("exampleMS.csv", header = FALSE)[[1]])
    } else if (file.exists("exampleMS.txt")) {
      exampleMS <- scan("exampleMS.txt", quiet = TRUE)
    } else if (file.exists("exampleMS")) {
      exampleMS <- scan("exampleMS", quiet = TRUE)
    } else {
      stop("Error: Required input file 'exampleMS' (RDS, CSV, or TXT) not found in the working directory.")
    }
    
    # Ensure exampleMS is a numeric vector
    exampleMS <- as.numeric(exampleMS)
    
    # -----------------------------------------------------------------------------
    # 2. Run Documented Peak Detection Pipeline
    # -----------------------------------------------------------------------------
    SNR.Th <- 3
    nearbyPeak <- TRUE
    peakInfo <- peakDetectionCWT(exampleMS, SNR.Th=SNR.Th, nearbyPeak=nearbyPeak)
    majorPeakInfo = peakInfo\$majorPeakInfo
    betterPeakInfo <- tuneInPeakInfo(exampleMS, majorPeakInfo)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    # Save the full peakInfo and betterPeakInfo objects as RDS
    saveRDS(peakInfo, "peak_info_results.rds")
    saveRDS(betterPeakInfo, "better_peak_info.rds")
    
    # Create a structured data frame of the refined peak information
    list_elements <- list(
      peakCenterIndex = betterPeakInfo\$peakCenterIndex
    )
    
    # Add other elements if they exist and match the length of peakCenterIndex
    expected_len <- length(betterPeakInfo\$peakCenterIndex)
    for (name in names(betterPeakInfo)) {
      if (name != "peakCenterIndex" && length(betterPeakInfo[[name]]) == expected_len) {
        list_elements[[name]] <- betterPeakInfo[[name]]
      }
    }
    
    peaks_df <- as.data.frame(list_elements)
    write.csv(peaks_df, "refined_peaks_summary.csv", row.names = FALSE)
    
    # Generate PDF visualization of the identified and refined peaks
    pdf("peak_detection_visualization.pdf", width = 11, height = 8.5)
    
    # Plot the entire spectrum with refined peak centers
    plotRange <- c(1, length(exampleMS))
    plotPeak(
      exampleMS, 
      betterPeakInfo\$peakCenterIndex, 
      range = plotRange, 
      main = paste("Refined Peaks (SNR >", SNR.Th, ")")
    )
    
    # If the spectrum is long, also plot a zoomed-in region for clarity
    if (length(exampleMS) > 5000) {
      zoomRange <- c(floor(length(exampleMS)/4), floor(length(exampleMS)/2))
      plotPeak(
        exampleMS, 
        betterPeakInfo\$peakCenterIndex, 
        range = zoomRange, 
        main = paste("Refined Peaks (Zoomed Region:", zoomRange[1], "-", zoomRange[2], ")")
      )
    }
    
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'peak_info_results.rds', 'better_peak_info.rds', 'refined_peaks_summary.csv', and 'peak_detection_visualization.pdf'.\n")

    writeLines(c(
        '"BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION":',
        paste0('    MassSpecWavelet: ', as.character(packageVersion('MassSpecWavelet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_peak_detection.csv versions.yml
    """
}

workflow BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleMS ] ]

    main:
    BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION(ch_input)

    emit:
    tables   = BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION.out.tables
    plots    = BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION.out.plots
    objects  = BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION.out.objects
    versions = BIOC_MASSSPECWAVELET_ONE_STEP_PEAK_DETECTION.out.versions
}
