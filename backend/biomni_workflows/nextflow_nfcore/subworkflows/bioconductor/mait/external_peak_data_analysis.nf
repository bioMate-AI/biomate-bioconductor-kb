#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAIT — external_peak_data_analysis
// Import pre-processed peak tables (masses, retention times, and intensities) using MAITbuilder to perform annotation and metabolite identification.
// Input: peaks, masses, rt
// Container: quay.io/biocontainers/bioconductor-mait:1.44.0--r45ha27e39d_0
// R packages: MAIT
// Bioconductor: 3.20 | R: 4.4
// Requires: MAIT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build MAIT object from external data
//  * 2. [Core Analysis] Biotransformations and adduct annotation
//  * 3. [Core Analysis] Metabolite identification

nextflow.enable.dsl = 2

process BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("MAIT")
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
    library(MAIT)
    
    # Helper function to robustly read a vector from a CSV file
    read_vector <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file missing:", filepath))
      }
      # Test if the first row contains headers (non-numeric values)
      df_test <- read.csv(filepath, nrows = 1, header = FALSE, stringsAsFactors = FALSE)
      has_header <- any(is.na(suppressWarnings(as.numeric(df_test[1, ]))))
      
      df <- read.csv(filepath, header = has_header, stringsAsFactors = FALSE)
      val <- as.numeric(unlist(df))
      val <- val[!is.na(val)]
      return(val)
    }
    
    # Helper function to robustly read a matrix from a CSV file
    read_matrix <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Required input file missing:", filepath))
      }
      # Test if the first column contains row names (non-numeric values)
      df_test <- read.csv(filepath, nrows = 5, header = TRUE, stringsAsFactors = FALSE)
      if (ncol(df_test) > 1 && any(is.na(suppressWarnings(as.numeric(df_test[[1]]))))) {
        df <- read.csv(filepath, row.names = 1, check.names = FALSE)
      } else {
        df <- read.csv(filepath, check.names = FALSE)
      }
      return(as.matrix(df))
    }
    
    # -------------------------------------------------------------------------
    # 1. Read User Input Files from Working Directory
    # -------------------------------------------------------------------------
    
    message("Reading input files from the working directory...")
    
    # Read peaks (matrix of peak intensities/scores)
    if (file.exists("peaks.rds")) {
      peaks <- readRDS("peaks.rds")
    } else {
      peaks <- read_matrix("peaks.csv")
    }
    
    # Read masses (vector of peak mz values)
    if (file.exists("masses.rds")) {
      masses <- readRDS("masses.rds")
    } else {
      masses <- read_vector("masses.csv")
    }
    
    # Read rt (vector of peak retention times in minutes)
    if (file.exists("rt.rds")) {
      rt <- readRDS("rt.rds")
    } else {
      rt <- read_vector("rt.csv")
    }
    
    # Validate input dimensions
    if (nrow(peaks) != length(masses) || nrow(peaks) != length(rt)) {
      stop(sprintf("Dimension mismatch: peaks has %d rows, but masses has length %d and rt has length %d.", 
                   nrow(peaks), length(masses), length(rt)))
    }
    
    # -------------------------------------------------------------------------
    # 2. Build MAIT Object from External Data
    # -------------------------------------------------------------------------
    
    message("Building MAIT object using MAITbuilder...")
    importMAIT <- MAITbuilder(data = peaks, masses = masses, 
                  rt = rt,significantFeatures = TRUE, 
                  spectraEstimation = TRUE,rtRange=0.2,
                  corThresh=0.7)
    
    # -------------------------------------------------------------------------
    # 3. Biotransformations and Adduct Annotation
    # -------------------------------------------------------------------------
    
    message("Performing biotransformations and adduct annotation...")
    importMAIT <- Biotransformations(MAIT.object = importMAIT, 
                  adductAnnotation = TRUE, 
                  peakPrecision = 0.005, adductTable = NULL)
    
    # -------------------------------------------------------------------------
    # 4. Metabolite Identification
    # -------------------------------------------------------------------------
    
    message("Identifying metabolites...")
    importMAIT <- identifyMetabolites(MAIT.object = importMAIT, 
                  peakTolerance=0.005,polarity="positive")
    
    # -------------------------------------------------------------------------
    # 5. Export Results
    # -------------------------------------------------------------------------
    
    message("Exporting pipeline results...")
    
    # Save the complete processed MAIT object
    saveRDS(importMAIT, file = "importMAIT_processed.rds")
    
    # Extract and save the metabolite identification table
    tryCatch({
      metTable <- metaboliteTable(importMAIT)
      write.csv(metTable, "metabolites_identified.csv", row.names = FALSE)
      message("Saved metabolite identification table to 'metabolites_identified.csv'")
    }, error = function(e) {
      warning("Could not extract metabolite table: ", e\$message)
    })
    
    # Extract and save the significant peaks table
    tryCatch({
      sigTable <- sigPeaksTable(MAIT.object = importMAIT, printCSVfile = FALSE)
      write.csv(sigTable, "significant_peaks.csv", row.names = FALSE)
      message("Saved significant peaks table to 'significant_peaks.csv'")
    }, error = function(e) {
      warning("Could not extract significant peaks table: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS":',
        paste0('    MAIT: ', as.character(packageVersion('MAIT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_external_peak_data_analysis.csv versions.yml
    """
}

workflow BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks, masses, rt ] ]

    main:
    BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS.out.tables
    plots    = BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS.out.plots
    objects  = BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS.out.objects
    versions = BIOC_MAIT_EXTERNAL_PEAK_DATA_ANALYSIS.out.versions
}
