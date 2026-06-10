#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprscore — indel_frameshift_prediction
// Predict the probability of a Cas9 gRNA to produce indels inducing a frameshift mutation using the Lindel algorithm.
// Input: sequences.txt
// Container: quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0
// R packages: crisprScore
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION {
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
    .bm_deps <- c("crisprScore")
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
    library(crisprScore)
    
    # 1. Read the 65bp sequence context around the protospacer from the user input file
    input_file <- "sequences.txt"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    # Read sequences (one per line) and clean up whitespace
    input <- readLines(input_file)
    input <- trimws(input)
    input <- input[input != ""]
    
    if (length(input) == 0) {
      stop("Error: 'sequences.txt' is empty.")
    }
    
    # Validate sequence lengths (Lindel requires exactly 65bp)
    invalid_seqs <- input[nchar(input) != 65]
    if (length(invalid_seqs) > 0) {
      warning(paste("The following sequences do not have the required 65bp length for Lindel:", 
                    paste(head(invalid_seqs, 5), collapse = ", "), "..."))
    }
    
    # 2. Define the conda environment path
    # We default to the documented path, but allow overriding via an environment variable for portability
    condaEnv <- Sys.getenv("LINDEL_CONDA_ENV", unset = "/Users/fortin946/miniforge3/envs/lindel-env")
    
    # 3. Run Lindel scoring using getLindelScores
    message("Running Lindel scoring...")
    results <- tryCatch({
      getLindelScores(input, condaEnv=condaEnv)
    }, error = function(e) {
      message("Error running getLindelScores: ", e\$message)
      message("Please ensure that the conda environment at '", condaEnv, "' is correctly configured with Python and Lindel dependencies.")
      stop(e)
    })
    
    # 4. Format and write the output results
    if (is.vector(results) || is.numeric(results)) {
      output_df <- data.frame(
        sequence = input,
        lindel_score = results,
        stringsAsFactors = FALSE
      )
    } else {
      output_df <- as.data.frame(results)
    }
    
    output_file <- "lindel_scores.csv"
    write.csv(output_df, file = output_file, row.names = FALSE)
    message(paste("Successfully wrote Lindel scores to", output_file))

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION":
        crisprscore: \$(Rscript -e 'cat(as.character(packageVersion("crisprscore")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_indel_frameshift_prediction.csv versions.yml
    """
}

workflow BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.txt ] ]

    main:
    BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION(ch_input)

    emit:
    tables   = BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION.out.tables
    plots    = BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION.out.plots
    objects  = BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION.out.objects
    versions = BIOC_CRISPRSCORE_INDEL_FRAMESHIFT_PREDICTION.out.versions
}
