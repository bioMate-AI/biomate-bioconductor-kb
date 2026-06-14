#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprscore — on_target_efficiency_prediction
// Predict on-target cutting efficiency for Cas9, Cas12a, or Cas13d gRNAs using sequence-based algorithms.
// Input: sequences.txt, test.fa
// Container: quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0
// R packages: Biostrings, crisprScore
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0"

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
    
    # Read user input sequences from sequences.txt
    # We assume line 1 is a 20bp spacer and line 2 is a 23bp spacer for Cas12a.
    # If only one line is present, we use it for both (or fallback to default lengths).
    seq_lines <- readLines("sequences.txt", warn = FALSE)
    spacer20 <- trimws(seq_lines[1])
    spacer23 <- if (length(seq_lines) > 1) trimws(seq_lines[2]) else "AATCGATGCTGATGCTAGATATT"
    
    # --- Run RuleSet1 scoring using getRuleSet1Scores ---
    flank5 <- "ACCT" #4bp
    spacer <- spacer20 #20bp
    pam    <- "AGG" #3bp 
    flank3 <- "TTG" #3bp
    input  <- paste0(flank5, spacer, pam, flank3) 
    results <- getRuleSet1Scores(input)
    write.csv(as.data.frame(results), "results_ruleset1.csv", row.names = FALSE)
    
    # --- Run RuleSet3 scoring using getRuleSet3Scores with a ---
    condaEnv <- "/Users/fortin946/miniforge3/envs/rs3-env"
    tryCatch({
        results <- getRuleSet3Scores(input, tracrRNA = "Hsu2013", condaEnv = condaEnv)
        write.csv(as.data.frame(results), "results_ruleset3.csv", row.names = FALSE)
    }, error = function(e) {
        message("RuleSet3 scoring skipped or failed: ", e\$message)
    })
    
    # --- Run DeepHF scoring using getDeepHFScores with a specified ---
    spacer  <- spacer20 #20bp
    pam     <- "AGG" #3bp
    input   <- paste0(spacer, pam)
    condaEnv <- "/Users/fortin946/miniforge3/envs/deephf-env"
    tryCatch({
        results <- getDeepHFScores(input, condaEnv = condaEnv)
        write.csv(as.data.frame(results), "results_deephf.csv", row.names = FALSE)
    }, error = function(e) {
        message("DeepHF scoring skipped or failed: ", e\$message)
    })
    
    # --- Run CRISPRscan scoring using getCRISPRscanScores ---
    flank5 <- "ACCTAA" #6bp
    spacer <- spacer20 #20bp
    pam    <- "AGG" #3bp 
    flank3 <- "TTGAAT" #6bp
    input  <- paste0(flank5, spacer, pam, flank3) 
    results <- getCRISPRscanScores(input)
    write.csv(as.data.frame(results), "results_crisprscan.csv", row.names = FALSE)
    
    # --- Run CRISPRater scoring using getCRISPRaterScores ---
    spacer <- spacer20 #20bp
    results <- getCRISPRaterScores(spacer)
    write.csv(as.data.frame(results), "results_crisprater.csv", row.names = FALSE)
    
    # --- Run enPAM+GB scoring for Cas12a using getEnPAMGBScores ---
    flank5 <- "ACCG" #4bp
    pam    <- "TTTT" #4bp
    spacer <- spacer23 #23bp
    flank3 <- "AAG" #3bp
    input  <- paste0(flank5, pam, spacer, flank3)
    condaEnv <- "/Users/fortin946/miniforge3/envs/enpamgb-env"
    tryCatch({
        results <- getEnPAMGBScores(input, condaEnv = condaEnv)
        write.csv(as.data.frame(results), "results_enpamgb.csv", row.names = FALSE)
    }, error = function(e) {
        message("enPAM+GB scoring skipped or failed: ", e\$message)
    })
    
    # --- Run CasRxRF scoring for Cas13d using getCasRxRFScores on ---
    mrnaSequence <- Biostrings::readDNAStringSet(filepath = "test.fa",
                                                 format = "fasta",
                                                 use.names = TRUE)
    tryCatch({
        results <- getCasRxRFScores(mrnaSequence)
        write.csv(as.data.frame(results), "results_casrxrf.csv", row.names = FALSE)
    }, error = function(e) {
        message("CasRxRF scoring skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION":',
        paste0('        crisprscore: ', as.character(packageVersion("crisprscore")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_on_target_efficiency_prediction.csv versions.yml
    """
}

workflow BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.txt, test.fa ] ]

    main:
    BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION(ch_input)

    emit:
    tables   = BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION.out.tables
    plots    = BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION.out.plots
    objects  = BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION.out.objects
    versions = BIOC_CRISPRSCORE_ON_TARGET_EFFICIENCY_PREDICTION.out.versions
}
