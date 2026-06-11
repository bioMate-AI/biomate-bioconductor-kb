#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mait — external_peak_table_analysis
// Import pre-processed external peak tables, masses, and retention times to perform annotation and metabolite identification.
// Input: peaks_matrix, masses_vector, rt_vector
// Container: quay.io/biocontainers/bioconductor-mait:1.44.0--r45ha27e39d_0
// R packages: faahKO, MAIT
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mait:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("faahKO", "MAIT")
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
    
    # Helper function to load peaks matrix from RDS or CSV
    load_peaks <- function(file_base) {
      if (file.exists(paste0(file_base, ".rds"))) {
        return(as.matrix(readRDS(paste0(file_base, ".rds"))))
      } else if (file.exists(paste0(file_base, ".csv"))) {
        df <- read.csv(paste0(file_base, ".csv"), header = TRUE, check.names = FALSE)
        if (is.character(df[[1]]) || is.factor(df[[1]])) {
          rownames(df) <- df[[1]]
          df <- df[-1]
        }
        return(as.matrix(df))
      } else {
        stop(paste("Error: Input file", file_base, "not found in RDS or CSV format."))
      }
    }
    
    # Helper function to load numeric vectors from RDS or CSV
    load_vector <- function(file_base) {
      if (file.exists(paste0(file_base, ".rds"))) {
        return(as.numeric(readRDS(paste0(file_base, ".rds"))))
      } else if (file.exists(paste0(file_base, ".csv"))) {
        df <- read.csv(paste0(file_base, ".csv"), header = TRUE, check.names = FALSE)
        numeric_cols <- sapply(df, is.numeric)
        if (any(numeric_cols)) {
          return(as.numeric(df[[which(numeric_cols)[1]]]))
        } else {
          return(as.numeric(df[[1]]))
        }
      } else {
        stop(paste("Error: Input file", file_base, "not found in RDS or CSV format."))
      }
    }
    
    # Read user inputs from the working directory
    peaks <- load_peaks("peaks_matrix")
    masses <- load_vector("masses_vector")
    rt <- load_vector("rt_vector")
    
    # 1. Build MAIT object from external data
    importMAIT <- MAITbuilder(data = peaks, masses = masses, 
                  rt = rt,significantFeatures = TRUE, 
                  spectraEstimation = TRUE,rtRange=0.2,
                  corThresh=0.7)
    
    # 2. Perform biotransformation and adduct annotation
    importMAIT <- Biotransformations(MAIT.object = importMAIT, 
                  adductAnnotation = TRUE, 
                  peakPrecision = 0.005, adductTable = NULL)
    
    # 3. Identify metabolites against the database
    importMAIT <- identifyMetabolites(MAIT.object = importMAIT, 
                  peakTolerance=0.005,polarity="positive")
    
    # Save the final MAIT object
    saveRDS(importMAIT, "importMAIT_results.rds")
    
    # Extract and save metabolite table
    tryCatch({
      metTable <- metaboliteTable(importMAIT)
      write.csv(metTable, "identified_metabolites.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not extract metabolite table: ", e\$message)
    })
    
    # Extract and save significant peaks table if available
    tryCatch({
      sigTable <- sigPeaksTable(importMAIT, printCSVfile = FALSE)
      write.csv(sigTable, "significant_peaks.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not extract significant peaks table: ", e\$message)
    })
    
    # Save summary of the analysis
    tryCatch({
      sink("mait_summary.txt")
      summary(importMAIT)
      sink()
    }, error = function(e) {
      if (sink.number() > 0) sink()
      warning("Could not write summary: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS":',
        paste0('        mait: ', as.character(packageVersion("mait")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_external_peak_table_analysis.csv versions.yml
    """
}

workflow BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_matrix, masses_vector, rt_vector ] ]

    main:
    BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS.out.tables
    plots    = BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS.out.plots
    objects  = BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS.out.objects
    versions = BIOC_MAIT_EXTERNAL_PEAK_TABLE_ANALYSIS.out.versions
}
