#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: orfhunter — train_orf_classifier
// Train a custom Random Forest classifier to distinguish true ORFs from pseudo-ORFs using known lncRNA and mRNA sequences.
// Input: fileORFLncRNAs.fasta.gz, fileORFmRNAs.fasta.gz
// Container: quay.io/biocontainers/bioconductor-orfhunter:1.18.0--r45ha27e39d_0
// R packages: ORFhunteR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-orfhunter:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("ORFhunteR")
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
    library(ORFhunteR)
    
    # Define input files as specified by the user
    fileORFLncRNAs <- "fileORFLncRNAs.fasta.gz"
    fileORFmRNAs <- "fileORFmRNAs.fasta.gz"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(fileORFLncRNAs)) {
      stop(paste("Error: Required input file missing:", fileORFLncRNAs))
    }
    if (!file.exists(fileORFmRNAs)) {
      stop(paste("Error: Required input file missing:", fileORFmRNAs))
    }
    
    # Load transcript/ORF sequences using loadTrExper
    ORFLncRNAs <- loadTrExper(tr = fileORFLncRNAs)
    ORFmRNAs <- loadTrExper(tr = fileORFmRNAs)
    
    # Define the number of sequences to use for training
    N <- 1000
    
    # Robust check to prevent out-of-bounds subscripting if input files have fewer than 1000 sequences
    N <- min(N, length(ORFLncRNAs), length(ORFmRNAs))
    
    ORFLncRNAs <- ORFLncRNAs[1:N]
    ORFmRNAs <- ORFmRNAs[1:N]
    
    # Train the Random Forest classifier using classifyORFsCandidates
    clt <- classifyORFsCandidates(
      ORFLncRNAs = ORFLncRNAs,
      ORFmRNAs = ORFmRNAs,
      pLearn = 0.75,
      nTrees = 500,
      modelRF = NULL,
      workDir = NULL,
      showAccuracy = TRUE
    )
    
    # Save the trained Random Forest model object
    saveRDS(clt, "trained_orf_classifier.rds")
    
    # Export meaningful classification metrics if available
    if (!is.null(clt)) {
      if (!is.null(clt\$confusion)) {
        write.csv(clt\$confusion, "classifier_confusion_matrix.csv", row.names = TRUE)
      }
      if (!is.null(clt\$importance)) {
        write.csv(clt\$importance, "classifier_variable_importance.csv", row.names = TRUE)
      }
    }

    writeLines(c(
        '"BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER":',
        paste0('        orfhunter: ', as.character(packageVersion("orfhunter")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_train_orf_classifier.csv versions.yml
    """
}

workflow BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fileORFLncRNAs.fasta.gz, fileORFmRNAs.fasta.gz ] ]

    main:
    BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER(ch_input)

    emit:
    tables   = BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER.out.tables
    plots    = BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER.out.plots
    objects  = BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER.out.objects
    versions = BIOC_ORFHUNTER_TRAIN_ORF_CLASSIFIER.out.versions
}
