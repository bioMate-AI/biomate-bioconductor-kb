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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20"

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
    .bm_deps <- c("MAI", "SummarizedExperiment")
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
