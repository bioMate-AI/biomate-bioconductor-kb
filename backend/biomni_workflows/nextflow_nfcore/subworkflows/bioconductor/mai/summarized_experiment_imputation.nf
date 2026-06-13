#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAI — summarized_experiment_imputation
// Perform mechanism-aware imputation on a SummarizedExperiment object containing missing metabolomics values.
// Input: se
// Container: quay.io/biocontainers/bioconductor-mai:1.16.0--r45hdfd78af_0
// R packages: MAI, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: MAI, SummarizedExperiment
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the SummarizedExperiment and MAI packages
//  * 2. [Visualization & Output] Convert the data to a SummarizedExperiment object
//  * 3. [Core Analysis] Set a random seed for reproducibility
//  * 4. [Visualization & Output] Run the MAI function on the SummarizedExperiment object
//  * 5. [Visualization & Output] Extract the imputed assay and estimated missingness parameters from the metadata of the returned SummarizedExperiment

nextflow.enable.dsl = 2

process BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    
    # 1. Load the SummarizedExperiment and MAI packages
    suppressMessages({
      library(MAI)
      library(SummarizedExperiment)
    })
    
    # 2. Read the SummarizedExperiment object from the working directory
    # The pipeline reads the user input file 'se' (or 'se.rds')
    if (file.exists("se")) {
      se <- readRDS("se")
    } else if (file.exists("se.rds")) {
      se <- readRDS("se.rds")
    } else {
      stop("Error: Input file 'se' or 'se.rds' containing the SummarizedExperiment object was not found in the working directory.")
    }
    
    # 3. Set a random seed for reproducibility
    set.seed(137690)
    
    # 4. Run the MAI function on the SummarizedExperiment object
    Results = MAI(se, # The data with missing values
              MCAR_algorithm = "BPCA", # The MCAR algorithm to use
              MNAR_algorithm= "Single", # The MNAR algorithm to use
              assay_ix = 1, # If SE, designates the assay to impute
              forest_list_args = list( # random forest arguments for training
                ntree = 300,
                proximity = FALSE
            ),
              verbose = TRUE # allows console message output
            )
    
    # 5. Extract the imputed assay and estimated missingness parameters
    imputed_assay <- assay(Results)
    est_params <- metadata(Results)[["meta_assay_1"]][["Estimated_Params"]]
    
    # Print preview to console
    cat("Imputed assay (first 5x5):\n")
    print(imputed_assay[1:min(5, nrow(imputed_assay)), 1:min(5, ncol(imputed_assay))])
    cat("\nEstimated Parameters:\n")
    print(est_params)
    
    # 6. Write named output files
    # Save the complete imputed SummarizedExperiment object
    saveRDS(Results, file = "imputed_se.rds")
    
    # Save the imputed assay matrix as a CSV
    write.csv(as.data.frame(imputed_assay), file = "imputed_assay.csv", row.names = TRUE)
    
    # Save the estimated parameters as a CSV
    if (!is.null(est_params)) {
      est_params_df <- data.frame(
        Parameter = names(est_params),
        Value = unlist(est_params),
        row.names = NULL
      )
      write.csv(est_params_df, file = "estimated_params.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION":',
        paste0('    MAI: ', as.character(packageVersion('MAI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarized_experiment_imputation.csv versions.yml
    """
}

workflow BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se ] ]

    main:
    BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION.out.tables
    plots    = BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION.out.plots
    objects  = BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION.out.objects
    versions = BIOC_MAI_SUMMARIZED_EXPERIMENT_IMPUTATION.out.versions
}
