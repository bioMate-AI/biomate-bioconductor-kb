#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClassifyR — quick_start_cross_validation
// Perform a quick cross-validated classification on a single dataset using a specified classifier and plot the performance.
// Input: measurements, classes
// Container: quay.io/biocontainers/bioconductor-classifyr:3.14.0--r45ha27e39d_0
// R packages: ClassifyR
// Bioconductor: 3.20 | R: 4.4
// Requires: ClassifyR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Set random seed for reproducibility
//  * 2. [Core Analysis] Run cross-validation using crossValidate
//  * 3. [Visualization & Output] Plot performance using performancePlot

nextflow.enable.dsl = 2

process BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION {
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
        
        # Load required libraries
        library(ClassifyR)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files
        # -----------------------------------------------------------------------------
        
        # Load measurements (matrix or data.frame of numeric features)
        if (file.exists("measurements.rds")) {
          measurements <- readRDS("measurements.rds")
        } else if (file.exists("measurements.csv")) {
          measurements <- read.csv("measurements.csv", row.names = 1, check.names = FALSE)
          measurements <- as.matrix(measurements)
        } else if (file.exists("measurements.tsv")) {
          measurements <- read.delim("measurements.tsv", row.names = 1, check.names = FALSE)
          measurements <- as.matrix(measurements)
        } else {
          stop("Error: 'measurements' file not found. Please provide 'measurements.rds', 'measurements.csv', or 'measurements.tsv' in the working directory.")
        }
        
        # Load classes (factor of class labels)
        if (file.exists("classes.rds")) {
          classes <- readRDS("classes.rds")
        } else if (file.exists("classes.csv")) {
          classes_df <- read.csv("classes.csv", row.names = 1)
          classes <- as.factor(classes_df[[1]])
        } else if (file.exists("classes.tsv")) {
          classes_df <- read.delim("classes.tsv", row.names = 1)
          classes <- as.factor(classes_df[[1]])
        } else {
          stop("Error: 'classes' file not found. Please provide 'classes.rds', 'classes.csv', or 'classes.tsv' in the working directory.")
        }
        
        # Ensure classes is a factor
        if (!is.factor(classes)) {
          classes <- as.factor(classes)
        }
        
        # -----------------------------------------------------------------------------
        # 2. Run Cross-Validation Workflow
        # -----------------------------------------------------------------------------
        
        # Set random seed for reproducibility
        set.seed(9500)
        
        # Run cross-validation using crossValidate
        result <- crossValidate(measurements, classes, classifier = "SVM",
                                nFolds = 5, nRepeats = 2, nCores = 1)
        
        # -----------------------------------------------------------------------------
        # 3. Plot Performance and Save Outputs
        # -----------------------------------------------------------------------------
        
        # Save the ClassifyResult object
        saveRDS(result, file = "classify_result.rds")
        
        # Plot performance and save to PDF
        pdf("performance_plot.pdf", width = 7, height = 6)
        print(performancePlot(result))
        dev.off()
        
        # Try to extract and save performance metrics to CSV
        tryCatch({
          perf_list <- performance(result)
          if (is.list(perf_list)) {
            perf_df <- as.data.frame(perf_list)
            write.csv(perf_df, "performance_metrics.csv", row.names = TRUE)
          }
        }, error = function(e) {
          message("Note: Performance metrics could not be written to CSV: ", e\$message)
        })

    writeLines(c(
        '"BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION":',
        paste0('    ClassifyR: ', as.character(packageVersion('ClassifyR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_start_cross_validation.csv versions.yml
    """
}

workflow BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ measurements, classes ] ]

    main:
    BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION.out.tables
    plots    = BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION.out.plots
    objects  = BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION.out.objects
    versions = BIOC_CLASSIFYR_QUICK_START_CROSS_VALIDATION.out.versions
}
