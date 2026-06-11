#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: process — mean_spectrum_peak_detection
// Detect peaks using the average spectrum of all samples and quantify them in individual pre-processed spectra for a faster alternative workflow.
// Input: fs, rtM
// Container: quay.io/biocontainers/bioconductor-process:1.86.0--r45hdfd78af_0
// R packages: PROcess
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-process:1.86.0--r45hdfd78af_0"

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
    .bm_deps <- c("PROcess")
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
    library(PROcess)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read rtM (matrix of normalized, baseline-subtracted spectra)
    if (file.exists("rtM.rds")) {
      rtM <- readRDS("rtM.rds")
    } else if (file.exists("rtM.csv")) {
      rtM_df <- read.csv("rtM.csv", row.names = 1, check.names = FALSE)
      rtM <- as.matrix(rtM_df)
    } else {
      stop("Error: rtM matrix file ('rtM.rds' or 'rtM.csv') not found in the working directory.")
    }
    
    # Identify raw mass spectrometry CSV files for fs
    # We exclude 'rtM.csv' if it exists in the same directory to avoid treating it as a raw spectrum
    fs <- list.files(pattern = "\\\\.csv\$", full.names = TRUE)
    fs <- fs[basename(fs) != "rtM.csv" & basename(fs) != "grandBmk.csv" & basename(fs) != "grandpvec.csv"]
    
    if (length(fs) == 0) {
      stop("Error: No raw mass spectrometry CSV files found in the working directory for 'fs'.")
    }
    
    # ==========================================
    # 2. Execute Workflow
    # ==========================================
    
    # Open PDF device to capture diagnostic plots from bslnoff and isPeak
    pdf("mean_spectrum_diagnostic_plots.pdf", width = 8, height = 6)
    
    # Step 1: Compute the grand average spectrum using aveSpec
    grandAve <- aveSpec(fs)
    mzs <- grandAve[, 1]
    
    # Step 2: Subtract baseline from the average spectrum using bslnoff
    grandOff <- bslnoff(grandAve[mzs > 0, ], method = "loess", plot = TRUE, bw = 0.1)
    
    # Step 3: Detect peaks on the average spectrum using isPeak
    grandPkg <- isPeak(grandOff[grandOff[, 1] > 1500, ], zerothrsh = 1, plot = TRUE, ratio = 0.1)
    grandpvec <- round(grandPkg[grandPkg\$peak, "mz"])
    
    # Print detected peak m/z values to standard output
    print(as.vector(grandpvec))
    
    # Close the plotting device
    dev.off()
    
    # Step 4: Quantify the detected peaks in individual spectra using getPeaks2
    grandBmk <- getPeaks2(rtM, grandpvec)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save the quantified peak biomarker matrix
    write.csv(as.data.frame(grandBmk), "grandBmk.csv", row.names = TRUE)
    saveRDS(grandBmk, "grandBmk.rds")
    
    # Save the detected peak m/z vector
    write.csv(data.frame(mz = grandpvec), "grandpvec.csv", row.names = FALSE)
    saveRDS(grandpvec, "grandpvec.rds")
    
    cat("Workflow completed successfully. Outputs saved to 'grandBmk.csv', 'grandBmk.rds', 'grandpvec.csv', 'grandpvec.rds', and 'mean_spectrum_diagnostic_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION":',
        paste0('        process: ', as.character(packageVersion("process")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mean_spectrum_peak_detection.csv versions.yml
    """
}

workflow BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fs, rtM ] ]

    main:
    BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION(ch_input)

    emit:
    tables   = BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION.out.tables
    plots    = BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION.out.plots
    objects  = BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION.out.objects
    versions = BIOC_PROCESS_MEAN_SPECTRUM_PEAK_DETECTION.out.versions
}
