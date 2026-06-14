#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcms — direct_injection_ms_preprocessing
// Preprocess direct injection mass spectrometry data (single spectrum per sample, no chromatographic dimension) including peak detection, calibration, and corresp
// Input: mzML_files
// Container: quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0
// R packages: BiocParallel, BiocStyle, MassSpecWavelet, MetaboCoreUtils, MsBackendMgf, MSnbase, xcms
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0"

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
    .bm_deps <- c("BiocParallel", "BiocStyle", "MassSpecWavelet", "MetaboCoreUtils", "MsBackendMgf", "MSnbase", "xcms")
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
    
    library(MSnbase)
    library(xcms)
    library(MassSpecWavelet)
    library(BiocParallel)
    
    # Register serial processing to ensure reproducibility and avoid parallel overhead
    register(SerialParam())
    
    # --- Load data from the working directory ---
    mzML_files <- list.files(
      path = ".",
      pattern = "\\\\.(mzML|mzXML|cdf)\$",
      ignore.case = TRUE,
      full.names = TRUE
    )
    
    if (length(mzML_files) == 0) {
      stop("Error: No mzML, mzXML, or CDF files found in the working directory.")
    }
    
    # Assign samples to groups dynamically (matching the "ham4"/"ham5" naming convention)
    grp <- rep(c("ham4", "ham5"), length.out = length(mzML_files))
    pd <- data.frame(filename = basename(mzML_files), sample_group = grp)
    
    ham_raw <- readMSData(
      files = mzML_files,
      pdata = AnnotatedDataFrame(pd),
      mode = "onDisk"
    )
    
    # --- Detect peaks in the m/z dimension ---
    msw <- MSWParam(
      scales = c(1, 4, 9),
      nearbyPeak = TRUE,
      winSize.noise = 500,
      SNR.method = "data.mean",
      snthresh = 10
    )
    ham_prep <- findChromPeaks(ham_raw, param = msw)
    
    # --- Calibrate peak m/z values ---
    first_file <- filterFile(ham_prep, file = 1)
    peaks_first <- chromPeaks(first_file)
    num_peaks <- nrow(peaks_first)
    
    if (num_peaks >= 7) {
      calib_idx <- c(1, 4, 7)
    } else if (num_peaks >= 3) {
      calib_idx <- c(1, 2, 3)
    } else if (num_peaks > 0) {
      calib_idx <- seq_len(num_peaks)
    } else {
      stop("Error: No peaks detected in the first file to perform calibration.")
    }
    
    calib_mz <- peaks_first[calib_idx, "mz"]
    calib_mz <- calib_mz + 0.00001 * runif(1, 0, 0.4) * calib_mz + 0.0001
    
    prm <- CalibrantMassParam(
      mz = calib_mz,
      method = "edgeshift",
      mzabs = 0.0001,
      mzppm = 5
    )
    first_file_calibrated <- calibrate(first_file, param = prm)
    
    # Save calibration diagnostic plot
    pdf("calibration_difference_plot.pdf")
    diffs <- chromPeaks(first_file_calibrated)[, "mz"] - chromPeaks(first_file)[, "mz"]
    plot(
      x = chromPeaks(first_file)[, "mz"],
      xlab = expression(m/z[raw]),
      y = diffs,
      ylab = expression(m/z[calibrated] - m/z[raw]),
      main = "Calibration Difference"
    )
    dev.off()
    
    # --- Perform correspondence (grouping peaks across samples) ---
    mzc_prm <- MzClustParam(sampleGroups = ham_prep\$sample_group)
    ham_prep <- groupChromPeaks(ham_prep, param = mzc_prm)
    
    # --- Extract feature definitions and values ---
    feat_defs <- featureDefinitions(ham_prep)
    feat_vals <- featureValues(ham_prep, value = "into")
    
    # Write pre-filled feature values and definitions to CSV
    write.csv(as.data.frame(feat_defs), "feature_definitions.csv", row.names = TRUE)
    write.csv(as.data.frame(feat_vals), "feature_values_raw.csv", row.names = TRUE)
    
    # --- Fill missing peaks ---
    ham_prep <- fillChromPeaks(ham_prep, param = FillChromPeaksParam())
    feat_vals_filled <- featureValues(ham_prep, value = "into")
    
    # Write filled feature values to CSV
    write.csv(as.data.frame(feat_vals_filled), "feature_values_filled.csv", row.names = TRUE)
    
    # Save the final preprocessed xcms object
    saveRDS(ham_prep, "xcms_preprocessed_object.rds")

    writeLines(c(
        '"BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING":',
        paste0('        xcms: ', as.character(packageVersion("xcms")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_injection_ms_preprocessing.csv versions.yml
    """
}

workflow BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mzML_files ] ]

    main:
    BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING.out.tables
    plots    = BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING.out.plots
    objects  = BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING.out.objects
    versions = BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING.out.versions
}
