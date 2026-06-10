#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qvalue — fdr_estimation_from_pvalues
// Estimate q-values, pi0, and local FDR directly from a vector of user-provided p-values, and visualize the results.
// Input: hedenfalk$p
// Container: quay.io/biocontainers/bioconductor-qvalue:2.42.0--r45hdfd78af_0
// R packages: qvalue
// Bioconductor: 3.20 | R: 4.4
// Requires: qvalue
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input p-values
//  * 2. [Core Analysis] Run the qvalue function to perform FDR estimation
//  * 3. [Core Analysis] Extract estimated q-values, pi0, and local FDR
//  * 4. [Visualization & Output] Summarize and visualize the results using diagnostic plots and histograms

nextflow.enable.dsl = 2

process BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("qvalue")
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
    
    # 1. Load the package and input p-values
    library(qvalue)
    
    # Read the user-provided input file representing hedenfalk\$p
    if (file.exists("hedenfalk.csv")) {
      input_data <- read.csv("hedenfalk.csv")
      if ("p" %in% colnames(input_data)) {
        pvalues <- input_data\$p
      } else {
        pvalues <- input_data[[1]]
      }
    } else if (file.exists("hedenfalk_p.txt")) {
      pvalues <- scan("hedenfalk_p.txt", quiet = TRUE)
    } else if (file.exists("hedenfalk_p.csv")) {
      pvalues <- read.csv("hedenfalk_p.csv", header = FALSE)[[1]]
    } else if (file.exists("hedenfalk.rds")) {
      obj <- readRDS("hedenfalk.rds")
      if (is.list(obj) && "p" %in% names(obj)) {
        pvalues <- obj\$p
      } else {
        pvalues <- obj
      }
    } else {
      stop("Error: Input file representing 'hedenfalk\$p' not found in the working directory. Please provide 'hedenfalk.csv' with a column 'p' or 'hedenfalk_p.txt'.")
    }
    
    # 2. Run the qvalue function to perform FDR estimation
    qobj <- qvalue(p = pvalues)
    
    # 3. Extract estimated q-values, pi0, and local FDR
    qvalues <- qobj\$qvalues
    pi0 <- qobj\$pi0
    lfdr <- qobj\$lfdr
    
    # 4. Summarize and visualize the results using diagnostic plots and histograms
    # Capture and save summary text
    summary_text <- capture.output(summary(qobj))
    writeLines(summary_text, "qvalue_summary.txt")
    
    # Save diagnostic plots to PDF
    pdf("qvalue_plots.pdf", width = 10, height = 8)
    plot(qobj)
    hist(qobj)
    dev.off()
    
    # Save results to CSV
    results_df <- data.frame(
      pvalue = qobj\$pvalues,
      qvalue = qvalues,
      localFDR = lfdr
    )
    write.csv(results_df, "qvalue_results.csv", row.names = FALSE)
    
    # Save the qvalue object as RDS
    saveRDS(qobj, "qvalue_object.rds")

    writeLines(c(
        '"BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES":',
        paste0('    qvalue: ', as.character(packageVersion('qvalue')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fdr_estimation_from_pvalues.csv versions.yml
    """
}

workflow BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hedenfalk$p ] ]

    main:
    BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES(ch_input)

    emit:
    tables   = BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES.out.tables
    plots    = BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES.out.plots
    objects  = BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES.out.objects
    versions = BIOC_QVALUE_FDR_ESTIMATION_FROM_PVALUES.out.versions
}
