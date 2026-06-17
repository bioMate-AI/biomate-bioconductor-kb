#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cancerclass — multiple_random_validation
// Evaluate classification accuracy and estimate misclassification rates across different numbers of genes or training set sizes using a multiple random validation
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-cancerclass:1.54.0--r45h01b2380_0
// R packages: Biobase, cancerclass, cancerdata
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, cancerclass
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run multiple random validation across different gene counts using nvalidate
//  * 2. [Visualization & Output] Plot misclassification rates using plot
//  * 3. [Core Analysis] Run validation across different training set sizes using validate
//  * 4. [Visualization & Output] Plot training size validation results using plot

nextflow.enable.dsl = 2

process BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION {
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
    .bm_deps <- c("Biobase", "cancerclass", "cancerdata")
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
        library(cancerclass)
        library(Biobase)
        
        # 1. Read the user input ExpressionSet from the working directory
        input_file <- "ExpressionSet.rds"
        if (!file.exists(input_file)) {
          stop(paste("Error: Input file", input_file, "not found in the working directory."))
        }
        
        # Load the ExpressionSet object
        eset <- readRDS(input_file)
        
        # Ensure the object is indeed an ExpressionSet
        if (!inherits(eset, "ExpressionSet")) {
          stop("Error: The input file does not contain an ExpressionSet object.")
        }
        
        # Ensure there are at least 200 features for the evaluated gene counts
        if (nrow(eset) < 200) {
          stop("Error: The input ExpressionSet must have at least 200 features (rows) to run the documented workflow.")
        }
        
        # 2. Run multiple random validation across different gene counts using nvalidate
        message("Running multiple random validation (nvalidate)...")
        nval <- nvalidate(eset, ngenes=c(5, 10, 20, 50, 100, 200))
        
        # Save the nval object
        saveRDS(nval, "nval_results.rds")
        
        # 3. Plot misclassification rates using plot
        message("Plotting nvalidate results...")
        pdf("nvalidate_plot.pdf", width = 7, height = 7)
        plot(nval)
        dev.off()
        
        # 4. Run validation across different training set sizes using validate
        message("Running validation across training set sizes (validate)...")
        val <- validate(eset, ngenes=10, ntrain="balanced")
        
        # Save the val object
        saveRDS(val, "val_results.rds")
        
        # 5. Plot training size validation results using plot
        message("Plotting validate results...")
        pdf("validate_plot.pdf", width = 7, height = 7)
        plot(val)
        dev.off()
        
        # Save text summaries of the validation runs
        sink("validation_summary.txt")
        cat("=== Multiple Random Validation (nvalidate) ===\n")
        print(summary(nval))
        cat("\n=== Validation across Training Set Sizes (validate) ===\n")
        print(summary(val))
        sink()
        
        message("Workflow completed successfully. Outputs saved: nval_results.rds, val_results.rds, nvalidate_plot.pdf, validate_plot.pdf, validation_summary.txt")

    writeLines(c(
        '"BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION":',
        paste0('    cancerclass: ', as.character(packageVersion('cancerclass')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_random_validation.csv versions.yml
    """
}

workflow BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION(ch_input)

    emit:
    tables   = BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION.out.tables
    plots    = BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION.out.plots
    objects  = BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION.out.objects
    versions = BIOC_CANCERCLASS_MULTIPLE_RANDOM_VALIDATION.out.versions
}
