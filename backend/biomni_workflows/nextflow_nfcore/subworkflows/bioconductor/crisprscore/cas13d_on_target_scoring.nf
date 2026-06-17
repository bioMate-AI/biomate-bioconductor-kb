#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprScore — cas13d_on_target_scoring
// Predict on-target efficiency for RNA-targeting RfxCas13d (CasRx) gRNAs.
// Input: transcripts.fasta
// Container: quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0
// R packages: Biostrings, crisprScore
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, crisprScore
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read mRNA sequences from a FASTA file using Biostrings::readDNAStringSet
//  * 2. [Core Analysis] Run getCasRxRFScores to predict on-target efficiency

nextflow.enable.dsl = 2

process BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING {
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
    .bm_deps <- c("Biostrings", "crisprScore")
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
    library(crisprScore)
    library(Biostrings)
    
    # Define the input file path as specified by the user
    fasta_file <- "transcripts.fasta"
    
    # Verify that the input file exists
    if (!file.exists(fasta_file)) {
      stop(paste("Error: Required input file", fasta_file, "not found in the working directory."))
    }
    
    # 1. Read mRNA sequences from the user-provided FASTA file using Biostrings::readDNAStringSet
    # Keeping the exact argument names and structure from the documented code
    mrnaSequence <- Biostrings::readDNAStringSet(filepath=fasta_file,
                                                 format="fasta",
                                                 use.names=TRUE)
    
    # 2. Run getCasRxRFScores to predict on-target efficiency
    # Keeping the exact function call and argument names from the documented code
    results <- getCasRxRFScores(mrnaSequence)
    
    # 3. Save the meaningful results to a CSV file
    # Convert results to a data frame to ensure compatibility with write.csv
    results_df <- as.data.frame(results)
    write.csv(results_df, file="cas13d_on_target_scores.csv", row.names=FALSE)
    
    # Also save the raw results object as an RDS file for downstream R analysis
    saveRDS(results, file="cas13d_on_target_scores.rds")
    
    cat("Workflow completed successfully. Results saved to 'cas13d_on_target_scores.csv' and 'cas13d_on_target_scores.rds'.\n")

    writeLines(c(
        '"BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING":',
        paste0('    crisprScore: ', as.character(packageVersion('crisprScore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cas13d_on_target_scoring.csv versions.yml
    """
}

workflow BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transcripts.fasta ] ]

    main:
    BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING(ch_input)

    emit:
    tables   = BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING.out.tables
    plots    = BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING.out.plots
    objects  = BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING.out.objects
    versions = BIOC_CRISPRSCORE_CAS13D_ON_TARGET_SCORING.out.versions
}
