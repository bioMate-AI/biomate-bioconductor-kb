#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCASPAR — survival_prediction_with_split_sets
// Train a survival prediction model on a training dataset and predict survival times on an independent validation dataset using high-dimensional covariates.
// Input: geDataT, survDataT, geDataS, survDataS
// Container: quay.io/biocontainers/bioconductor-rcaspar:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RCASPAR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize the prior distribution for weights
//  * 2. [Visualization & Output] Visualize the gamma prior distribution for baseline hazards
//  * 3. [Core Analysis] Train the model and predict survival times on the validation set
//  * 4. [Visualization & Output] Plot Kaplan-Meier survival curves for predicted long and short survivors
//  * 5. [Visualization & Output] Calculate and plot the Area Under the ROC Curve (AURC)
//  * 6. [Core Analysis] Perform a log-rank test to compare the predicted survivor groups

nextflow.enable.dsl = 2

process BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS {
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
    
    # Load required library
    library(RCASPAR)
    
    # Helper function to robustly read input files
    read_input <- function(base_name) {
      # Check for exact filename first
      if (file.exists(base_name)) {
        res <- tryCatch(readRDS(base_name), error = function(e) NULL)
        if (!is.null(res)) return(res)
        res <- tryCatch(read.csv(base_name, row.names = 1, check.names = FALSE), error = function(e) NULL)
        if (!is.null(res)) return(res)
        res <- tryCatch(read.table(base_name, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE), error = function(e) NULL)
        if (!is.null(res)) return(res)
      }
      
      # Check with common extensions
      for (ext in c(".rds", ".csv", ".tsv", ".txt")) {
        fn <- paste0(base_name, ext)
        if (file.exists(fn)) {
          if (ext == ".rds") {
            return(readRDS(fn))
          } else if (ext == ".csv") {
            return(read.csv(fn, row.names = 1, check.names = FALSE))
          } else {
            return(read.table(fn, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
          }
        }
      }
      stop(paste("Error: Input file for", base_name, "not found in the working directory."))
    }
    
    # 1. Read User Inputs
    geDataT_raw <- read_input("geDataT")
    survDataT_raw <- read_input("survDataT")
    geDataS_raw <- read_input("geDataS")
    survDataS_raw <- read_input("survDataS")
    
    # Format inputs as required by RCASPAR
    geDataT <- as.matrix(geDataT_raw)
    geDataS <- as.matrix(geDataS_raw)
    survDataT <- as.data.frame(survDataT_raw)
    survDataS <- as.data.frame(survDataS_raw)
    
    # Ensure survival data frames have the exact required column names
    required_cols <- c("True_STs", "censored")
    if (!all(required_cols %in% colnames(survDataT))) {
      stop("survDataT must contain 'True_STs' and 'censored' columns.")
    }
    if (!all(required_cols %in% colnames(survDataS))) {
      stop("survDataS must contain 'True_STs' and 'censored' columns.")
    }
    
    # 2. Visualize the prior distribution for weights
    pdf("prior_distribution.pdf")
    pltprior(q=1, s=1)
    dev.off()
    
    # 3. Visualize the gamma prior distribution for baseline hazards
    pdf("gamma_distribution.pdf")
    pltgamma(a=1.558, b=0.179)
    dev.off()
    
    # 4. Train the model and predict survival times on the validation set
    result <- STpredictor_BLH(
      geDataS = geDataS, 
      survDataS = survDataS, 
      geDataT = geDataT, 
      survDataT = survDataT, 
      q = 1, 
      s = 1, 
      a = 1.558, 
      b = 0.179, 
      cut.off = 15, 
      groups = 3, 
      method = "CG", 
      noprior = 1, 
      extras = list(reltol = 1)
    )
    
    # Save the main result object
    saveRDS(result, "rcaspar_result.rds")
    
    # Save predicted survival times and groups
    write.csv(result\$predicted_STs, "predicted_survival_times.csv", row.names = TRUE)
    write.csv(result\$long_survivors, "long_survivors.csv", row.names = TRUE)
    write.csv(result\$short_survivors, "short_survivors.csv", row.names = TRUE)
    
    # 5. Plot Kaplan-Meier survival curves for predicted long and short survivors
    pdf("km_plot_survivors.pdf")
    kmplt_svrl(
      long = result\$long_survivors, 
      short = result\$short_survivors, 
      title = "KM plot of long and short survivors"
    )
    dev.off()
    
    # 6. Calculate and plot the Area Under the ROC Curve (AURC)
    pdf("aurc_plot.pdf")
    aurc_res <- survivAURC(
      Stime = result\$predicted_STs\$True_STs, 
      status = result\$predicted_STs\$censored, 
      marker = result\$predicted_STs\$Predicted_STs, 
      time.max = 20
    )
    dev.off()
    
    # Save AURC metrics
    saveRDS(aurc_res, "aurc_results.rds")
    sink("aurc_summary.txt")
    cat("Area Under the ROC Curve (AUC):\n")
    print(aurc_res\$AUC)
    cat("\nAUC at each time point:\n")
    print(aurc_res\$AUeachROC)
    sink()
    
    # 7. Perform a log-rank test to compare the predicted survivor groups
    logrank_res <- logrnk(
      dataL = result\$long_survivors, 
      dataS = result\$short_survivors
    )
    
    # Save log-rank test results
    saveRDS(logrank_res, "logrank_results.rds")
    sink("logrank_summary.txt")
    cat("Log-rank Test Results:\n")
    cat(paste("Chi-squared statistic (Xsq):", logrank_res\$Xsq, "\n"))
    cat(paste("p-value:", logrank_res\$pValue, "\n"))
    sink()

    writeLines(c(
        '"BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS":',
        paste0('    RCASPAR: ', as.character(packageVersion('RCASPAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_prediction_with_split_sets.csv versions.yml
    """
}

workflow BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geDataT, survDataT, geDataS, survDataS ] ]

    main:
    BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS(ch_input)

    emit:
    tables   = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS.out.tables
    plots    = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS.out.plots
    objects  = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS.out.objects
    versions = BIOC_RCASPAR_SURVIVAL_PREDICTION_WITH_SPLIT_SETS.out.versions
}
