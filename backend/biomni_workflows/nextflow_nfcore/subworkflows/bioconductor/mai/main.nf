#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAI — data_frame_or_matrix_imputation
// Perform mechanism-aware imputation on a standard data.frame or matrix containing missing metabolomics values.
// Input: untargeted_LCMS_data
// Container: quay.io/biocontainers/bioconductor-mai:1.16.0--r45hdfd78af_0
// R packages: MAI, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: MAI
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the MAI package and example dataset
//  * 2. [Core Analysis] Set a random seed for reproducibility
//  * 3. [Core Analysis] Run the MAI function to classify and impute missing values
//  * 4. [Core Analysis] Extract the imputed data matrix and estimated missingness parameters from the results list

nextflow.enable.dsl = 2

process BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MAI", "SummarizedExperiment")
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
    
    # Load the MAI package
    library(MAI)
    
    # Read the user input file from the working directory
    # The pipeline supports CSV, RDS, or a plain text file named 'untargeted_LCMS_data'
    if (file.exists("untargeted_LCMS_data.csv")) {
      untargeted_LCMS_data <- as.matrix(read.csv("untargeted_LCMS_data.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("untargeted_LCMS_data.rds")) {
      untargeted_LCMS_data <- readRDS("untargeted_LCMS_data.rds")
      if (is.data.frame(untargeted_LCMS_data)) {
        untargeted_LCMS_data <- as.matrix(untargeted_LCMS_data)
      }
    } else if (file.exists("untargeted_LCMS_data")) {
      untargeted_LCMS_data <- as.matrix(read.csv("untargeted_LCMS_data", row.names = 1, check.names = FALSE))
    } else {
      stop("Required input file 'untargeted_LCMS_data' (CSV or RDS format) not found in the working directory.")
    }
    
    # Set a seed for reproducibility
    # Estimating pattern of missingness involves imposing MCAR/MAR into the data
    # these are done at random and as such may slightly change the results of the
    # estimated parameters.
    set.seed(137690)
    
    # Impute the data using BPCA for predicted MCAR value imputation and
    # use Single imputation for predicted MNAR value imputation
    Results = MAI(data_miss = untargeted_LCMS_data, # The data with missing values
              MCAR_algorithm = "BPCA", # The MCAR algorithm to use
              MNAR_algorithm = "Single", # The MNAR algorithm to use
              assay_ix = 1, # If SE, designates the assay to impute
              forest_list_args = list( # random forest arguments for training
                ntree = 300,
                proximity = FALSE
            ),
              verbose = TRUE # allows console message output
            )
    
    # Display a preview of the imputed data
    cat("Preview of Imputed Data (5x5):\n")
    print(Results[["Imputed_data"]][1:5, 1:5])
    
    # Display the estimated mixed missingness parameters
    cat("\nEstimated Missingness Parameters:\n")
    print(Results[["Estimated_Params"]])
    
    # Write the imputed data matrix to a CSV file
    write.csv(Results[["Imputed_data"]], "imputed_data.csv", row.names = TRUE)
    
    # Write the estimated parameters to a CSV file
    params <- Results[["Estimated_Params"]]
    params_df <- data.frame(
      Parameter = names(params),
      Value = unlist(params),
      row.names = NULL
    )
    write.csv(params_df, "estimated_params.csv", row.names = FALSE)
    
    # Save the complete Results object as an RDS file
    saveRDS(Results, "MAI_results.rds")
    
    cat("\nPipeline completed successfully. Outputs saved: 'imputed_data.csv', 'estimated_params.csv', 'MAI_results.rds'.\n")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION":',
        paste0('    MAI: ', as.character(packageVersion('MAI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_frame_or_matrix_imputation.csv versions.yml
    """
}

workflow BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ untargeted_LCMS_data ] ]

    main:
    BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION.out.tables
    plots    = BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION.out.plots
    objects  = BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION.out.objects
    versions = BIOC_MAI_DATA_FRAME_OR_MATRIX_IMPUTATION.out.versions
}
