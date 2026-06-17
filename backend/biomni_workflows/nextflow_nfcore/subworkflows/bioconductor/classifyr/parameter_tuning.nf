#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClassifyR — parameter_tuning
// Optimize model hyperparameters (e.g., SVM cost) during cross-validation and extract the tuned parameters.
// Input: measurements, classes
// Container: quay.io/biocontainers/bioconductor-classifyr:3.14.0--r45ha27e39d_0
// R packages: ClassifyR
// Bioconductor: 3.20 | R: 4.4
// Requires: ClassifyR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a tuning grid list
//  * 2. [Input & Preparation] Set up CrossValParams with a tuning mode
//  * 3. [Input & Preparation] Define ModellingParams with TrainParams containing the tuning list
//  * 4. [Core Analysis] Run cross-validation using runTests
//  * 5. [Core Analysis] Extract and inspect tuned parameters using tunedParameters

nextflow.enable.dsl = 2

process BIOC_CLASSIFYR_PARAMETER_TUNING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ClassifyR")
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
    library(ClassifyR)
    
    # Set seed for reproducibility
    set.seed(9500)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    # The pipeline expects 'measurements' and 'classes' files in the working directory.
    # We support both RDS and CSV formats for robustness.
    
    if (file.exists("measurements.rds")) {
      measurements <- readRDS("measurements.rds")
    } else if (file.exists("measurements.csv")) {
      measurements <- as.matrix(read.csv("measurements.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("measurements.txt")) {
      measurements <- as.matrix(read.table("measurements.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: 'measurements' file not found in the working directory (expected measurements.rds, measurements.csv, or measurements.txt).")
    }
    
    if (file.exists("classes.rds")) {
      classes <- readRDS("classes.rds")
    } else if (file.exists("classes.csv")) {
      classes_df <- read.csv("classes.csv", header = TRUE)
      classes <- factor(classes_df[[1]])
    } else if (file.exists("classes.txt")) {
      classes_df <- read.table("classes.txt", header = TRUE)
      classes <- factor(classes_df[[1]])
    } else {
      stop("Error: 'classes' file not found in the working directory (expected classes.rds, classes.csv, or classes.txt).")
    }
    
    # Ensure measurements is a matrix or data.frame and classes is a factor
    if (!is.factor(classes)) {
      classes <- factor(classes)
    }
    
    # ==========================================
    # 2. Parameter Tuning Workflow (Documented Code)
    # ==========================================
    
    # Stage 1: Define a tuning grid list
    tuneList <- list(cost = c(0.01, 0.1, 1, 10))
    
    # Stage 2: Set up CrossValParams with a tuning mode
    crossValParams <- CrossValParams(permutations = 5, tuneMode = "Resubstitution")
    
    # Stage 3: Define ModellingParams with TrainParams containing the tuning list
    SVMparams <- ModellingParams(trainParams = TrainParams("SVM", kernel = "linear", tuneParams = tuneList),
                                 predictParams = PredictParams("SVM"))
    
    # Stage 4: Run cross-validation using runTests
    SVMresults <- runTests(measurements, classes, crossValParams, SVMparams)
    
    # Stage 5: Extract and inspect tuned parameters using tunedParameters
    num_tuned <- length(tunedParameters(SVMresults))
    tuned_sample <- tunedParameters(SVMresults)[1:min(5, num_tuned)]
    
    # Print summary to console
    cat("Number of tuned parameter sets:", num_tuned, "\n")
    print(tuned_sample)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save the full ClassifyResult object
    saveRDS(SVMresults, file = "SVMresults.rds")
    
    # Save the raw tuned parameters list
    saveRDS(tunedParameters(SVMresults), file = "tuned_parameters.rds")
    
    # Extract and format the best parameters for each iteration into a table
    tuned_list <- tunedParameters(SVMresults)
    best_params_list <- lapply(seq_along(tuned_list), function(i) {
      comb <- tuned_list[[i]]\$tuneCombinations
      best_idx <- tuned_list[[i]]\$bestIndex
      best_row <- comb[best_idx, , drop = FALSE]
      best_row\$Iteration <- i
      return(best_row)
    })
    best_params_df <- do.call(rbind, best_params_list)
    write.csv(best_params_df, file = "best_tuned_parameters.csv", row.names = FALSE)
    
    # Calculate and save cross-validation performance
    tryCatch({
      SVMresults <- calcCVperformance(SVMresults)
      perf <- performance(SVMresults)
      saveRDS(perf, file = "performance_metrics.rds")
      
      # Write performance summary to a text file
      sink("performance_summary.txt")
      print(perf)
      sink()
    }, error = function(e) {
      warning("Could not calculate performance metrics: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_CLASSIFYR_PARAMETER_TUNING":',
        paste0('    ClassifyR: ', as.character(packageVersion('ClassifyR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parameter_tuning.csv versions.yml
    """
}

workflow BIOC_CLASSIFYR_PARAMETER_TUNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ measurements, classes ] ]

    main:
    BIOC_CLASSIFYR_PARAMETER_TUNING(ch_input)

    emit:
    tables   = BIOC_CLASSIFYR_PARAMETER_TUNING.out.tables
    plots    = BIOC_CLASSIFYR_PARAMETER_TUNING.out.plots
    objects  = BIOC_CLASSIFYR_PARAMETER_TUNING.out.objects
    versions = BIOC_CLASSIFYR_PARAMETER_TUNING.out.versions
}
