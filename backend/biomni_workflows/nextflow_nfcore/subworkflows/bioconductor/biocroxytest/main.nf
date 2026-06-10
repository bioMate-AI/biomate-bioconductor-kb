#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biocroxytest — biocroxytest_longtests_pipeline
// Set up, generate, and execute long-running tests for a feature analysis pipeline using biocroxytest.
// Input: input.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: biocroxytest, roxygen2, testthat
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Stage 1: Read input and validate
    if (!file.exists("input.csv")) {
      stop("Required input file 'input.csv' is missing.")
    }
    
    # Read input defensively to understand its structure
    input_data <- read.csv("input.csv", row.names = 1, check.names = FALSE)
    message("Successfully loaded input.csv with ", nrow(input_data), " features and ", ncol(input_data), " samples.")
    
    # Stage 2: Setup mock package structure
    # biocroxytest operates on R package structures, so we initialize a minimal one in the working directory.
    message("Setting up mock package structure...")
    writeLines(c(
      "Package: mockpackage",
      "Type: Package",
      "Title: Mock Package for biocroxytest Pipeline",
      "Version: 0.1.0",
      "Roxygen: list(roclets = c('namespace', 'rd', 'biocroxytest::longtests_roclet'))",
      "Suggests: testthat"
    ), "DESCRIPTION")
    
    # Create R directory
    dir.create("R", showWarnings = FALSE)
    
    # Write an analysis function with @longtests roxygen comments
    # This function processes the input.csv and has associated long tests
    writeLines(c(
      "#' Analyze Feature Matrix",
      "#'",
      "#' @param filepath Path to the input CSV",
      "#' @return A summary data frame",
      "#' @export",
      "#'",
      "#' @longtests",
      "#' # Test that the analysis function works on the input file",
      "#' res <- analyze_features('input.csv')",
      "#' testthat::expect_s3_class(res, 'data.frame')",
      "#' testthat::expect_true(nrow(res) > 0)",
      "#' testthat::expect_true('mean_signal' %in% colnames(res))",
      "analyze_features <- function(filepath) {",
      "  df <- read.csv(filepath, row.names = 1, check.names = FALSE)",
      "  data.frame(",
      "    feature_id = rownames(df),",
      "    mean_signal = rowMeans(df, na.rm = TRUE),",
      "    sd_signal = apply(df, 1, sd, na.rm = TRUE)",
      "  )",
      "}"
    ), "R/analyze.R")
    
    # Stage 3: Initialize biocroxytest
    message("Initializing biocroxytest infrastructure...")
    biocroxytest::use_longtests()
    
    # Stage 4: Generate long tests via roxygenise
    message("Running roxygenise to generate long tests...")
    roxygen2::roxygenise()
    
    # Stage 5: Execute and validate the generated tests
    # Locate the generated test file
    test_files <- list.files("longtests/testthat", pattern = "^test-.*\\\\.R\$", full.names = TRUE)
    
    if (length(test_files) == 0) {
      stop("Failed to generate long test files using biocroxytest.")
    }
    
    generated_test_file <- test_files[1]
    message("Generated test file found: ", generated_test_file)
    
    # Read and save the generated test script as an output
    test_script_content <- readLines(generated_test_file)
    writeLines(test_script_content, "generated_test_script.R")
    
    # Run the generated tests in a controlled environment
    message("Executing the generated long tests...")
    test_env <- new.env(parent = .GlobalEnv)
    
    # Source the analysis function into the test environment
    sys.source("R/analyze.R", envir = test_env)
    
    # Execute the test file and capture output/errors
    log_messages <- c("--- Long Test Execution Log ---")
    tryCatch({
      # Evaluate the test script inside the environment containing our function
      eval(parse(text = test_script_content), envir = test_env)
      log_messages <- c(log_messages, "SUCCESS: All generated long tests passed successfully.")
    }, error = function(e) {
      log_messages <- c(log_messages, paste("FAILURE: Tests failed with error:", e\$message))
    })
    
    # Write execution log
    writeLines(log_messages, "test_execution_log.txt")
    
    # Stage 6: Write BBS options output
    if (file.exists(".BBSoptions")) {
      file.copy(".BBSoptions", "bbs_options.txt", overwrite = TRUE)
    } else {
      writeLines("RunLongTests: TRUE", "bbs_options.txt")
    }
    
    message("Pipeline completed successfully. Outputs written: 'generated_test_script.R', 'test_execution_log.txt', 'bbs_options.txt'.")

    writeLines(c(
        '"BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE":',
        paste0('    biocroxytest: ', as.character(packageVersion('biocroxytest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocroxytest_longtests_pipeline.csv versions.yml
    """
}

workflow BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE.out.tables
    plots    = BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE.out.plots
    objects  = BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE.out.objects
    versions = BIOC_BIOCROXYTEST_BIOCROXYTEST_LONGTESTS_PIPELINE.out.versions
}
