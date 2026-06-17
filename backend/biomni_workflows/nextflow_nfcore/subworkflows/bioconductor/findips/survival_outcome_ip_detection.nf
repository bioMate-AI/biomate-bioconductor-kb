#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: findIPs — survival_outcome_ip_detection
// Detect influential points affecting feature rankings for survival outcomes using a univariate Cox proportional hazards model.
// Input: expression_matrix.csv, survival_data.csv
// Container: quay.io/biocontainers/bioconductor-findips:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: findIPs, survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the one-step findIPs() function with fun = "cox"
//  * 2. [Visualization & Output] Visualize the influence scores of each sample using plotIPs()

nextflow.enable.dsl = 2

process BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("findIPs", "survival")
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
    library(findIPs)
    library(survival)
    
    # Read user input files
    # expression_matrix.csv: samples as rows, genes as columns
    X_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    X <- as.matrix(X_df)
    
    # survival_data.csv: survival response object containing time and event status
    surv_df <- read.csv("survival_data.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and survival data
    common_samples <- intersect(rownames(X), rownames(surv_df))
    if (length(common_samples) == 0) {
      stop("No common samples found between expression_matrix.csv and survival_data.csv")
    }
    X <- X[common_samples, , drop = FALSE]
    surv_df <- surv_df[common_samples, , drop = FALSE]
    
    # Identify time and status columns
    time_col <- grep("time", colnames(surv_df), ignore.case = TRUE, value = TRUE)[1]
    status_col <- grep("status|event", colnames(surv_df), ignore.case = TRUE, value = TRUE)[1]
    
    if (is.na(time_col) || is.na(status_col)) {
      # Fallback to first two columns if names don't match
      time_col <- colnames(surv_df)[1]
      status_col <- colnames(surv_df)[2]
    }
    
    # Construct the survival response object
    surv <- Surv(time = as.numeric(surv_df[[time_col]]), event = as.numeric(surv_df[[status_col]]))
    
    # Run the documented findIPs workflow
    par(mar = c(4, 4, 2, 2))
    results.cox <- findIPs(X, surv, 
                           fun = "cox",
                           decreasing = FALSE,
                           method = "adaptive")
    
    # Save the plot to a PDF file
    pdf("ips_survival_plot.pdf", width = 8, height = 6)
    par(mar = c(4, 4, 2, 2))
    plotIPs(results.cox)
    dev.off()
    
    # Save the results object
    saveRDS(results.cox, "results_cox.rds")
    
    # Save the influence scores to a CSV file
    scores_df <- data.frame(
      Sample = names(results.cox\$score),
      InfluenceScore = results.cox\$score,
      row.names = NULL
    )
    write.csv(scores_df, "influence_scores.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION":',
        paste0('    findIPs: ', as.character(packageVersion('findIPs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_outcome_ip_detection.csv versions.yml
    """
}

workflow BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, survival_data.csv ] ]

    main:
    BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION(ch_input)

    emit:
    tables   = BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION.out.tables
    plots    = BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION.out.plots
    objects  = BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION.out.objects
    versions = BIOC_FINDIPS_SURVIVAL_OUTCOME_IP_DETECTION.out.versions
}
