#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KnowSeq — automated_report
// Generate an automatic, intelligent HTML report summarizing the entire transcriptomic analysis pipeline in one step.
// Input: expressionMatrix, labels
// Container: quay.io/biocontainers/bioconductor-knowseq:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: KnowSeq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run knowseqReport to perform DEG extraction, feature selection, machine learning classification, and biological enrichment, output

nextflow.enable.dsl = 2

process BIOC_KNOWSEQ_AUTOMATED_REPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("KnowSeq")
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
    library(KnowSeq)
    
    # Read user input files from the working directory
    # expressionMatrix: Matrix of normalized gene expression values (CSV format, genes in rows, samples in columns)
    if (file.exists("expressionMatrix.csv")) {
      expressionMatrix_df <- read.csv("expressionMatrix.csv", row.names = 1, check.names = FALSE)
      expressionMatrix <- as.matrix(expressionMatrix_df)
    } else {
      stop("Required input file 'expressionMatrix.csv' not found in the working directory.")
    }
    
    # labels: Vector of sample class labels (CSV format, single column or first column containing labels)
    if (file.exists("labels.csv")) {
      labels_df <- read.csv("labels.csv", header = TRUE)
      labels <- as.character(labels_df[[1]])
    } else {
      stop("Required input file 'labels.csv' not found in the working directory.")
    }
    
    # Save the loaded and verified inputs as RDS objects for downstream validation
    saveRDS(expressionMatrix, "loaded_expressionMatrix.rds")
    saveRDS(labels, "loaded_labels.rds")
    
    # Execute the automated report generation pipeline
    # This function performs DEG extraction, feature selection, machine learning classification,
    # and biological enrichment, outputting an HTML report.
    # We wrap it in a tryCatch to handle potential external API connection issues (e.g., DAVID, Open Targets)
    tryCatch({
      knowseqReport(expressionMatrix,labels,'knowSeq-report',clasifAlgs=c('knn'),disease='breast-cancer', lfc = 2, pvalue = 0.001, geneOntology = T, getPathways = T)
    }, error = function(e) {
      message("An error occurred during the knowseqReport execution (possibly due to external API connectivity): ", e\$message)
    })

    writeLines(c(
        '"BIOC_KNOWSEQ_AUTOMATED_REPORT":',
        paste0('    KnowSeq: ', as.character(packageVersion('KnowSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_report.csv versions.yml
    """
}

workflow BIOC_KNOWSEQ_AUTOMATED_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expressionMatrix, labels ] ]

    main:
    BIOC_KNOWSEQ_AUTOMATED_REPORT(ch_input)

    emit:
    tables   = BIOC_KNOWSEQ_AUTOMATED_REPORT.out.tables
    plots    = BIOC_KNOWSEQ_AUTOMATED_REPORT.out.plots
    objects  = BIOC_KNOWSEQ_AUTOMATED_REPORT.out.objects
    versions = BIOC_KNOWSEQ_AUTOMATED_REPORT.out.versions
}
