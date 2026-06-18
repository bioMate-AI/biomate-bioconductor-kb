#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: peakPantheR — real_time_annotation
// Detect and integrate multiple targeted features in a single MS file in real-time (e.g., immediately after acquisition).
// Input: input_spectraPath, input_targetFeatTable
// Container: quay.io/biocontainers/bioconductor-peakpanther:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: peakPantheR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define targeted features in a data frame
//  * 2. [Core Analysis] Run single file search using peakPantheR_singleFileSearch
//  * 3. [Core Analysis] Extract TIC, acquisition time, peak table, curve fit parameters, and raw data points from the returned list

nextflow.enable.dsl = 2

process BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("peakPantheR")
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
    library(peakPantheR)
    
    # 1. Read User Inputs from the working directory
    # Detect the single raw MS spectra file (NetCDF/mzML/mzXML/mzData format)
    spectra_extensions <- c("mzML", "CDF", "cdf", "mzXML", "mzData")
    all_files <- list.files(pattern = paste0("\\\\.(", paste(spectra_extensions, collapse="|"), ")\$"))
    input_spectra_file <- all_files[grep("^input_spectra", all_files)]
    if (length(input_spectra_file) == 0 && length(all_files) > 0) {
      input_spectra_file <- all_files[1]
    }
    if (length(input_spectra_file) == 0) {
      stop("No raw MS spectra file (NetCDF/mzML/mzXML/mzData) found in the working directory.")
    }
    input_spectraPath <- input_spectra_file
    
    # Read the targeted features table
    if (file.exists("input_targetFeatTable.csv")) {
      input_targetFeatTable <- read.csv("input_targetFeatTable.csv", stringsAsFactors = FALSE)
    } else {
      stop("Required input file 'input_targetFeatTable.csv' not found in the working directory.")
    }
    
    # Ensure correct column types as in the documented code
    input_targetFeatTable[, c(3:8)] <- sapply(input_targetFeatTable[, c(3:8)], as.numeric)
    
    # 2. Run single file search using peakPantheR_singleFileSearch
    annotation <- peakPantheR_singleFileSearch(
      singleSpectraDataPath = input_spectraPath,
      targetFeatTable = input_targetFeatTable,
      peakStatistic = TRUE,
      curveModel = 'skewedGaussian',
      verbose = TRUE
    )
    
    # 3. Extract TIC, acquisition time, peak table, curve fit parameters, and raw data points
    tic_val <- annotation\$TIC
    acqu_time <- annotation\$acquTime
    peak_table <- annotation\$peakTable
    curve_fit <- annotation\$curveFit
    rois_datapoint <- annotation\$ROIsDataPoint
    
    # 4. Write outputs to disk
    # Save the full annotation object
    saveRDS(annotation, file = "annotation_results.rds")
    
    # Save peak table
    if (!is.null(peak_table)) {
      write.csv(peak_table, file = "peakTable.csv", row.names = FALSE)
    }
    
    # Save metadata (TIC and Acquisition Time)
    metadata <- list(
      spectraPath = input_spectraPath,
      TIC = tic_val,
      acquTime = acqu_time
    )
    saveRDS(metadata, file = "metadata.rds")
    
    # Save complex list objects as RDS
    saveRDS(curve_fit, file = "curveFit.rds")
    saveRDS(rois_datapoint, file = "ROIsDataPoint.rds")
    
    cat("Real-time annotation pipeline completed successfully.\n")

    writeLines(c(
        '"BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION":',
        paste0('    peakPantheR: ', as.character(packageVersion('peakPantheR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_real_time_annotation.csv versions.yml
    """
}

workflow BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_spectraPath, input_targetFeatTable ] ]

    main:
    BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION.out.tables
    plots    = BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION.out.plots
    objects  = BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION.out.objects
    versions = BIOC_PEAKPANTHER_REAL_TIME_ANNOTATION.out.versions
}
