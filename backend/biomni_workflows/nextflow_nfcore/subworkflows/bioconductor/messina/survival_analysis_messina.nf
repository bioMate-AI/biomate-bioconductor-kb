#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: messina — survival_analysis_messina
// Identify optimal single-gene threshold classifiers to predict survival outcomes and separate patients into short and long survivors.
// Input: expression_matrix.csv, survival_data.csv
// Container: quay.io/biocontainers/bioconductor-messina:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: messina, survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the expression data and survival times
//  * 2. [Input & Preparation] Create a Surv object representing survival times and censoring status
//  * 3. [Core Analysis] Fit the Messina survival model using the messinaSurv function with a specified objective function and minimum value
//  * 4. [Core Analysis] Inspect the S4 result object to identify features passing performance requirements
//  * 5. [Visualization & Output] Plot the survival curves and separation at the threshold and margins using the plot function

nextflow.enable.dsl = 2

process BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA {
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
    
    # 1. Load libraries
    library(messina)
    library(survival)
    
    # 2. Load the expression data and survival times from user input files
    if (!file.exists("expression_matrix.csv") || !file.exists("survival_data.csv")) {
      stop("Required input files 'expression_matrix.csv' and/or 'survival_data.csv' are missing.")
    }
    
    expression_data <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    kirc.exprs <- as.matrix(expression_data)
    
    survival_data <- read.csv("survival_data.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and survival data
    common_samples <- intersect(colnames(kirc.exprs), rownames(survival_data))
    if (length(common_samples) == 0) {
      # Fallback if row names of survival_data don't match colnames of expression matrix
      # Try using the first column of survival_data as sample IDs
      if (any(survival_data[[1]] %in% colnames(kirc.exprs))) {
        rownames(survival_data) <- survival_data[[1]]
        common_samples <- intersect(colnames(kirc.exprs), rownames(survival_data))
      }
    }
    
    if (length(common_samples) == 0) {
      stop("No matching sample IDs found between expression_matrix.csv and survival_data.csv.")
    }
    
    kirc.exprs <- kirc.exprs[, common_samples, drop = FALSE]
    survival_data <- survival_data[common_samples, , drop = FALSE]
    
    # Identify time and status columns in survival_data
    time_col <- grep("time", colnames(survival_data), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(time_col)) {
      time_col <- colnames(survival_data)[1]
    }
    
    status_col <- grep("status|event|cens", colnames(survival_data), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(status_col)) {
      status_col <- colnames(survival_data)[2]
    }
    
    # Create a Surv object representing survival times and censoring status
    kirc.surv <- Surv(time = as.numeric(survival_data[[time_col]]), 
                      event = as.numeric(survival_data[[status_col]]))
    
    # 3. Fit the Messina survival model using the messinaSurv function
    fit.surv = messinaSurv(kirc.exprs, kirc.surv, obj_func = "tau", obj_min = 0.6, parallel = FALSE, silent = TRUE)
    
    # 4. Inspect the S4 result object to identify features passing performance requirements
    print(fit.surv)
    
    # Save S4 object
    saveRDS(fit.surv, file = "messina_survival_fit.rds")
    
    # Save text summary
    sink("messina_survival_summary.txt")
    print(fit.surv)
    sink()
    
    # Extract and save top results table if possible
    tryCatch({
      top_results <- messinaTopResults(fit.surv)
      write.csv(top_results, "messina_top_survival_results.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not extract top results table using messinaTopResults: ", e\$message)
    })
    
    # 5. Plot the survival curves and separation at the threshold and margins using the plot function
    pdf("messina_survival_plots.pdf", width = 10, height = 8)
    plot(fit.surv, bootstrap_type = "ci")
    dev.off()

    writeLines(c(
        '"BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA":',
        paste0('    messina: ', as.character(packageVersion('messina')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_analysis_messina.csv versions.yml
    """
}

workflow BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, survival_data.csv ] ]

    main:
    BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA(ch_input)

    emit:
    tables   = BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA.out.tables
    plots    = BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA.out.plots
    objects  = BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA.out.objects
    versions = BIOC_MESSINA_SURVIVAL_ANALYSIS_MESSINA.out.versions
}
