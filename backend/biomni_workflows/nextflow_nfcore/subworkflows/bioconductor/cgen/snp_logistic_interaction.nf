#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CGEN — snp_logistic_interaction
// Fit logistic regression models (UML, CML, and EB) to evaluate gene-environment interactions on a case-control dataset.
// Input: Xdata
// Container: quay.io/biocontainers/bioconductor-cgen:3.46.0--r45h63f16b7_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CGEN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create dummy variables for categorical covariates
//  * 2. [Core Analysis] Fit the interaction model using snp.logistic
//  * 3. [Visualization & Output] Extract model summaries using getSummary
//  * 4. [Core Analysis] Perform Wald tests for the SNP and interaction terms using getWaldTest

nextflow.enable.dsl = 2

process BIOC_CGEN_SNP_LOGISTIC_INTERACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("CGEN")
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
    library(CGEN)
    
    # Read the user input file from the working directory
    # The user input is expected to be a CSV file named "Xdata.csv"
    Xdata <- read.csv("Xdata.csv", header = TRUE, stringsAsFactors = FALSE)
    
    # 1. Create dummy variables for categorical covariates
    age_groups <- sort(unique(Xdata[, "age.group"]))
    dummy_vars <- character()
    
    for (a in age_groups) {
      dummyVar <- paste("age.group_", a, sep="")
      dummy_vars <- c(dummy_vars, dummyVar)
      Xdata[, dummyVar] <- 0
      temp <- Xdata[, "age.group"] == a
      if (any(temp)) Xdata[temp, dummyVar] <- 1
    }
    
    # Define main effects variables
    # Use all but the first age group as dummy variables to avoid multicollinearity
    mainVars <- c("oral.years", "n.children", dummy_vars[-1])
    
    # 2. Fit the interaction model using snp.logistic
    fit <- snp.logistic(Xdata, "case.control", "BRCA.status",
                         main.vars=mainVars, 
                         int.vars=c("oral.years", "n.children"), 
                         strata.var="ethnic.group")
    
    # 3. Extract model summaries using getSummary
    summary_list <- getSummary(fit)
    
    # 4. Perform Wald tests for the SNP and interaction terms using getWaldTest
    wald_results <- getWaldTest(fit, c("BRCA.status", "BRCA.status:oral.years", "BRCA.status:n.children"))
    
    # Save the meaningful results to output files
    saveRDS(fit, "fit_object.rds")
    saveRDS(summary_list, "fit_summary.rds")
    saveRDS(wald_results, "wald_test.rds")
    
    # Write summary tables to CSV files
    for (model_name in names(summary_list)) {
      write.csv(summary_list[[model_name]], paste0("summary_", model_name, ".csv"), row.names = TRUE)
    }
    
    # Write a text report of the results
    sink("analysis_report.txt")
    cat("====================================================\n")
    cat("CGEN snp_logistic_interaction Workflow Results\n")
    cat("====================================================\n\n")
    cat("--- MODEL SUMMARIES ---\n")
    print(summary_list)
    cat("\n--- WALD TEST RESULTS ---\n")
    print(wald_results)
    sink()

    writeLines(c(
        '"BIOC_CGEN_SNP_LOGISTIC_INTERACTION":',
        paste0('    CGEN: ', as.character(packageVersion('CGEN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_logistic_interaction.csv versions.yml
    """
}

workflow BIOC_CGEN_SNP_LOGISTIC_INTERACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Xdata ] ]

    main:
    BIOC_CGEN_SNP_LOGISTIC_INTERACTION(ch_input)

    emit:
    tables   = BIOC_CGEN_SNP_LOGISTIC_INTERACTION.out.tables
    plots    = BIOC_CGEN_SNP_LOGISTIC_INTERACTION.out.plots
    objects  = BIOC_CGEN_SNP_LOGISTIC_INTERACTION.out.objects
    versions = BIOC_CGEN_SNP_LOGISTIC_INTERACTION.out.versions
}
