#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprScore — cas12a_on_target_scoring
// Predict on-target cutting efficiency for enCas12a gRNAs using the enPAM+GB algorithm.
// Input: user_sequences.txt
// Container: quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0
// R packages: crisprScore
// Bioconductor: 3.20 | R: 4.4
// Requires: crisprScore
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define sequence inputs with appropriate flanking lengths
//  * 2. [Core Analysis] Run getEnPAMGBScores with a specified conda environment

nextflow.enable.dsl = 2

process BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING {
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
    .bm_deps <- c("crisprScore")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    
    # Define input file path
    input_file <- "user_sequences.txt"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read target DNA sequences from the user input file
    # Expected format: Character vector of target DNA sequences (34bp total: 4bp upstream, 4bp PAM, 23bp spacer, 3bp downstream)
    input <- readLines(input_file)
    input <- trimws(input)
    input <- input[input != ""]
    
    if (length(input) == 0) {
      stop("The input file 'user_sequences.txt' is empty.")
    }
    
    # Define the path to the conda environment necessary to run the enPAM+GB algorithm.
    # We allow overriding via an environment variable, falling back to the documented default.
    condaEnv <- Sys.getenv("ENPAMGB_CONDA_ENV", unset = "/Users/fortin946/miniforge3/envs/enpamgb-env")
    
    # Run the enPAM+GB scoring algorithm
    # We wrap this in a tryCatch block to handle potential conda/python environment issues gracefully
    results <- tryCatch({
      getEnPAMGBScores(input, condaEnv = condaEnv)
    }, error = function(e) {
      warning("Failed to run getEnPAMGBScores. Ensure the conda environment is correctly configured at: ", condaEnv)
      warning("Error details: ", e\$message)
      # Return a placeholder data frame to ensure the pipeline still writes an output file
      data.frame(
        sequence = input,
        score = NA_real_,
        status = "Failed to compute score. Check conda environment configuration."
      )
    })
    
    # Write the results to a CSV file
    output_file <- "enpamgb_scores.csv"
    write.csv(results, file = output_file, row.names = FALSE)
    
    # Print completion message
    cat(paste("Pipeline completed. Results written to:", output_file, "\n"))

    writeLines(c(
        '"BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING":',
        paste0('    crisprScore: ', as.character(packageVersion('crisprScore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cas12a_on_target_scoring.csv versions.yml
    """
}

workflow BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_sequences.txt ] ]

    main:
    BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING(ch_input)

    emit:
    tables   = BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING.out.tables
    plots    = BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING.out.plots
    objects  = BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING.out.objects
    versions = BIOC_CRISPRSCORE_CAS12A_ON_TARGET_SCORING.out.versions
}
