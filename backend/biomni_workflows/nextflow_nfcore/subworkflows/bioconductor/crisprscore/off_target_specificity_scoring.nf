#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprScore — off_target_specificity_scoring
// Predict off-target specificity scores for CRISPR/Cas9 systems using MIT and CFD algorithms.
// Input: gRNAs_and_targets.csv
// Container: quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0
// Requires: crisprScore
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define spacer, protospacers, and PAMs
//  * 2. [Core Analysis] Run getMITScores to calculate MIT specificity scores
//  * 3. [Core Analysis] Run getCFDScores to calculate CFD specificity scores

nextflow.enable.dsl = 2

process BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING {
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
    .bm_deps <- c("crisprScore")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required library
    library(crisprScore)
    
    # 1. Read user input file
    input_file <- "gRNAs_and_targets.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    data <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Ensure required columns exist
    required_cols <- c("spacer", "protospacer", "pam")
    missing_cols <- setdiff(required_cols, colnames(data))
    if (length(missing_cols) > 0) {
      stop(paste("Input CSV is missing required columns:", paste(missing_cols, collapse = ", ")))
    }
    
    # Extract inputs
    spacers <- data\$spacer
    protospacers <- data\$protospacer
    pams <- data\$pam
    
    # 2. Run getMITScores to calculate MIT specificity scores
    message("Calculating MIT specificity scores...")
    mit_scores <- getMITScores(spacers = spacers,
                               protospacers = protospacers,
                               pams = pams)
    
    # 3. Run getCFDScores to calculate CFD specificity scores
    message("Calculating CFD specificity scores...")
    cfd_scores <- getCFDScores(spacers = spacers,
                               protospacers = protospacers,
                               pams = pams)
    
    # 4. Save results to output files
    write.csv(mit_scores, "mit_scores.csv", row.names = FALSE)
    write.csv(cfd_scores, "cfd_scores.csv", row.names = FALSE)
    
    # Combine and save a unified output
    combined_results <- data.frame(
      spacer = spacers,
      protospacer = protospacers,
      pam = pams,
      mit_score = mit_scores\$score,
      cfd_score = cfd_scores\$score,
      stringsAsFactors = FALSE
    )
    write.csv(combined_results, "off_target_specificity_scores.csv", row.names = FALSE)
    
    message("Workflow complete. Outputs saved to 'mit_scores.csv', 'cfd_scores.csv', and 'off_target_specificity_scores.csv'.")

    writeLines(c(
        '"BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING":',
        paste0('    crisprScore: ', as.character(packageVersion('crisprScore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_off_target_specificity_scoring.csv versions.yml
    """
}

workflow BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gRNAs_and_targets.csv ] ]

    main:
    BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING(ch_input)

    emit:
    tables   = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING.out.tables
    plots    = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING.out.plots
    objects  = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING.out.objects
    versions = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_SCORING.out.versions
}
