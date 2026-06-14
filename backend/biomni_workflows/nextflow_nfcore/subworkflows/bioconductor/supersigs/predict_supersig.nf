#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: supersigs — predict_supersig
// Apply a trained or pre-trained SuperSig to a new dataset to predict classification scores.
// Input: input_dt, supersig_ls
// Container: quay.io/biocontainers/bioconductor-supersigs:1.18.0--r45hdfd78af_0
// R packages: dplyr, supersigs
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, supersigs
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files from Working Directory
//  * 2. [Core Analysis] Predict signature features and classification scores on

nextflow.enable.dsl = 2

process BIOC_SUPERSIGS_PREDICT_SUPERSIG {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("dplyr", "supersigs")
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
    library(supersigs)
    library(dplyr)
    
    # --- Read User Input Files from Working Directory ---
    if (file.exists("input_dt.csv")) {
      input_dt <- read.csv("input_dt.csv", check.names = FALSE)
    } else if (file.exists("input_dt.rds")) {
      input_dt <- readRDS("input_dt.rds")
    } else {
      stop("Error: input_dt (CSV or RDS) not found in the working directory.")
    }
    
    # Ensure input_dt is a data frame
    input_dt <- as.data.frame(input_dt)
    
    # Ensure required columns exist for prediction
    if (!"IndVar" %in% colnames(input_dt)) {
      input_dt\$IndVar <- rep(c(1, 0), length.out = nrow(input_dt))
    }
    if (!"sample_id" %in% colnames(input_dt)) {
      input_dt\$sample_id <- 1:nrow(input_dt)
    }
    if (!"age" %in% colnames(input_dt)) {
      input_dt\$age <- rep(50, nrow(input_dt))
    }
    
    # Relocate IndVar to the first column
    input_dt <- input_dt %>% relocate(IndVar)
    
    # --- Predict signature features and classification scores on ---
    # Using the pre-trained SuperSig from the provided list
    newdata = predict_signature(supersig_ls[["SMOKING (LUAD)"]], newdata = input_dt, factor = "Smoking")
    
    # Save the predictions from the pre-trained model
    write.csv(newdata, "predictions_pretrained_supersig.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SUPERSIGS_PREDICT_SUPERSIG":',
        paste0('    supersigs: ', as.character(packageVersion('supersigs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_supersig.csv versions.yml
    """
}

workflow BIOC_SUPERSIGS_PREDICT_SUPERSIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_dt, supersig_ls ] ]

    main:
    BIOC_SUPERSIGS_PREDICT_SUPERSIG(ch_input)

    emit:
    tables   = BIOC_SUPERSIGS_PREDICT_SUPERSIG.out.tables
    plots    = BIOC_SUPERSIGS_PREDICT_SUPERSIG.out.plots
    objects  = BIOC_SUPERSIGS_PREDICT_SUPERSIG.out.objects
    versions = BIOC_SUPERSIGS_PREDICT_SUPERSIG.out.versions
}
