#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEAT — meat_epigenetic_age
// Estimate epigenetic age and age acceleration in skeletal muscle DNA methylation data using the MEAT package.
// Input: matrix.csv, coldata.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MEAT, SummarizedExperiment
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEAT_MEAT_EPIGENETIC_AGE {
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
    .bm_deps <- c("MEAT", "SummarizedExperiment")
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
    
    # Load required libraries    library(SummarizedExperiment)

    library(MEAT)
    
    # --- Read and align input data ---
    message("Stage 1: Loading and aligning input data...")
    if (!file.exists("matrix.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'matrix.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read methylation beta matrix
    beta_df <- read.csv("matrix.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"feature_id" %in% colnames(beta_df)) {
      stop("matrix.csv must contain a 'feature_id' column for CpG/probe names.")
    }
    rownames(beta_df) <- beta_df\$feature_id
    beta_df\$feature_id <- NULL
    beta_matrix <- as.matrix(beta_df)
    
    # Read sample metadata
    coldata_df <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"sample" %in% colnames(coldata_df)) {
      stop("coldata.csv must contain a 'sample' column matching the matrix columns.")
    }
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align samples between beta matrix and coldata
    common_samples <- intersect(colnames(beta_matrix), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No matching samples found between matrix.csv and coldata.csv.")
    }
    message(paste("Aligned", length(common_samples), "samples for analysis."))
    beta_matrix <- beta_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # --- Format data into a SummarizedExperiment object ---
    message("Stage 2: Formatting data into SummarizedExperiment...")
    # MEAT requires the assay containing beta values to be named "beta"
    SE <- SummarizedExperiment(
      assays = list(beta = beta_matrix),
      colData = coldata_df
    )
    
    # --- Data cleaning (subsetting to clock CpGs and imputing ---
    message("Stage 3: Cleaning beta values...")
    version_param <- "MEAT2.0" # Default version
    SE_clean <- clean_beta(SE = SE, version = version_param)
    
    # --- Data calibration (re-scaling to the gold standard dataset) ---
    message("Stage 4: Calibrating beta values using BMIQcalibration...")
    SE_calibrated <- BMIQcalibration(SE = SE_clean, version = version_param)
    
    # Save calibrated beta values
    calibrated_beta <- assays(SE_calibrated)\$beta
    write.csv(calibrated_beta, "calibrated_beta.csv", row.names = TRUE)
    message("Calibrated beta matrix saved to 'calibrated_beta.csv'.")
    
    # --- Epigenetic age estimation ---
    message("Stage 5: Estimating epigenetic age...")
    # Check if chronological age is provided in coldata (case-insensitive search)
    age_col <- grep("^age\$", colnames(colData(SE_calibrated)), ignore.case = TRUE, value = TRUE)
    
    if (length(age_col) > 0) {
      age_col_name <- age_col[1]
      message(paste("Chronological age column detected:", age_col_name))
      # Ensure age is numeric
      colData(SE_calibrated)[[age_col_name]] <- as.numeric(colData(SE_calibrated)[[age_col_name]])
      
      # Run estimation with age acceleration calculation
      SE_epiage <- epiage_estimation(
        SE = SE_calibrated,
        age_col_name = age_col_name,
        version = version_param
      )
    } else {
      message("No chronological age column detected. Estimating DNAmage only.")
      # Run estimation without age acceleration
      SE_epiage <- epiage_estimation(
        SE = SE_calibrated,
        version = version_param
      )
    }
    
    # --- Export results ---
    message("Stage 6: Exporting final results...")
    results_df <- as.data.frame(colData(SE_epiage))
    write.csv(results_df, "epigenetic_age_results.csv", row.names = TRUE)
    message("Epigenetic age estimation completed successfully. Results saved to 'epigenetic_age_results.csv'.")

    writeLines(c(
        '"BIOC_MEAT_MEAT_EPIGENETIC_AGE":',
        paste0('    MEAT: ', as.character(packageVersion('MEAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meat_epigenetic_age.csv versions.yml
    """
}

workflow BIOC_MEAT_MEAT_EPIGENETIC_AGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MEAT_MEAT_EPIGENETIC_AGE(ch_input)

    emit:
    tables   = BIOC_MEAT_MEAT_EPIGENETIC_AGE.out.tables
    plots    = BIOC_MEAT_MEAT_EPIGENETIC_AGE.out.plots
    objects  = BIOC_MEAT_MEAT_EPIGENETIC_AGE.out.objects
    versions = BIOC_MEAT_MEAT_EPIGENETIC_AGE.out.versions
}
