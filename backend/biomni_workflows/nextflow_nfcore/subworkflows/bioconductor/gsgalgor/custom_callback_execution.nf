#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSgalgoR — custom_callback_execution
// Monitor and save intermediate population states during the Galgo evolution process using custom callback functions.
// Input: expression_matrix.csv, survival_data.csv
// Container: quay.io/biocontainers/bioconductor-gsgalgor:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSgalgoR, survival
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define a custom callback function accepting the six required arguments (userdir, generation, pop_pool, pareto, prob_matrix, curren

nextflow.enable.dsl = 2

process BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GSgalgoR)
    library(survival)
    
    # Read user input files
    if (!file.exists("expression_matrix.csv") || !file.exists("survival_data.csv")) {
        stop("Required input files 'expression_matrix.csv' and/or 'survival_data.csv' are missing.")
    }
    
    expr_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    surv_df <- read.csv("survival_data.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and survival data
    common_samples <- intersect(colnames(expr_df), rownames(surv_df))
    if (length(common_samples) == 0) {
        # Fallback: check if there is a sample ID column in survival data
        sample_cols <- grep("sample|id", colnames(surv_df), ignore.case = TRUE, value = TRUE)
        if (length(sample_cols) > 0) {
            rownames(surv_df) <- surv_df[[sample_cols[1]]]
            common_samples <- intersect(colnames(expr_df), rownames(surv_df))
        }
    }
    
    if (length(common_samples) == 0) {
        stop("No matching samples found between expression matrix columns and survival data rows.")
    }
    
    expr_df <- expr_df[, common_samples, drop = FALSE]
    surv_df <- surv_df[common_samples, , drop = FALSE]
    
    # Scale the expression matrix (features are rows, samples are columns)
    expression <- as.matrix(expr_df)
    expression <- t(scale(t(expression)))
    
    # Identify survival time and event columns
    time_col <- grep("time|t.rfs|OS_time|survival", colnames(surv_df), ignore.case = TRUE, value = TRUE)[1]
    event_col <- grep("event|status|e.rfs|OS_event|dead", colnames(surv_df), ignore.case = TRUE, value = TRUE)[1]
    
    if (is.na(time_col)) time_col <- colnames(surv_df)[1]
    if (is.na(event_col)) event_col <- colnames(surv_df)[2]
    
    # Create survival object
    OS <- survival::Surv(time = as.numeric(surv_df[[time_col]]), event = as.numeric(surv_df[[event_col]]))
    
    # Define a simple reporting callback
    my_callback <-
        function(userdir = "",
            generation,
                pop_pool,
                pareto,
                prob_matrix,
                current_time) {
        # code starts  here
        if (generation%%2 == 0)
            message(paste0("generation: ",generation,
                        " current_time: ",current_time))
        }
    
    # Define a callback to save intermediate populations
    my_save_pop_callback <-
        function(userdir = "",
                generation,
                pop_pool,
                pareto,
                prob_matrix,
                current_time) {
            directory <- paste0(tempdir(), "/")
            if (!dir.exists(directory)) {
                dir.create(directory, recursive = TRUE)
            }
            filename <- paste0(directory, generation, ".rda")
            if (generation%%2 == 0){
                save(file = filename, pop_pool)
            }
            message(paste("solution file saved in",filename))
        }
    
    # Run galgo with custom callbacks
    GSgalgoR::galgo(
        generations = 6, 
        population = 15, 
        prob_matrix = expression, 
        OS = OS,
        start_galgo_callback = GSgalgoR::callback_default, 
        end_galgo_callback = GSgalgoR::callback_default,   
        report_callback = my_callback,
        start_gen_callback = GSgalgoR::callback_default,
        end_gen_callback = my_save_pop_callback
        ) 
    
    # Copy saved intermediate populations to the working directory as output files
    for (gen in c(2, 4, 6)) {
        temp_file <- file.path(tempdir(), paste0(gen, ".rda"))
        if (file.exists(temp_file)) {
            dest_file <- paste0("galgo_population_gen_", gen, ".rda")
            file.copy(temp_file, dest_file, overwrite = TRUE)
            message(paste("Saved intermediate population to:", dest_file))
        }
    }

    writeLines(c(
        '"BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION":',
        paste0('    GSgalgoR: ', as.character(packageVersion('GSgalgoR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_callback_execution.csv versions.yml
    """
}

workflow BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, survival_data.csv ] ]

    main:
    BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION(ch_input)

    emit:
    tables   = BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION.out.tables
    plots    = BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION.out.plots
    objects  = BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION.out.objects
    versions = BIOC_GSGALGOR_CUSTOM_CALLBACK_EXECUTION.out.versions
}
