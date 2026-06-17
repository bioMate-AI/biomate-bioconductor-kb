#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survival — kaplan_meier_survival_curves
// Estimate and plot non-parametric survival curves using the Kaplan-Meier method to compare survival times between groups.
// Input: patient_clinical_data.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the survival outcome using Surv()
//  * 2. [Core Analysis] Fit the Kaplan-Meier survival curve using survfit()
//  * 3. [Visualization & Output] Summarize survival probabilities and median survival times using summary()
//  * 4. [Visualization & Output] Plot the survival curves using plot()

nextflow.enable.dsl = 2

process BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("survival")
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
    library(survival)
    
    # 1. Read the user input file
    lung <- read.csv("patient_clinical_data.csv", stringsAsFactors = FALSE)
    
    # Standardize column names to match the documented code's variables: time, status, sex
    colnames(lung) <- tolower(colnames(lung))
    
    # Map 'time' column
    if (!"time" %in% colnames(lung)) {
      time_col <- grep("time|month|day|year|duration", colnames(lung), value = TRUE)[1]
      if (!is.na(time_col)) {
        colnames(lung)[colnames(lung) == time_col] <- "time"
      }
    }
    
    # Map 'status' column
    if (!"status" %in% colnames(lung)) {
      status_col <- grep("status|event|cens", colnames(lung), value = TRUE)[1]
      if (!is.na(status_col)) {
        colnames(lung)[colnames(lung) == status_col] <- "status"
      }
    }
    
    # Map 'sex' column
    if (!"sex" %in% colnames(lung)) {
      sex_col <- grep("sex|gender|group|tx|treatment", colnames(lung), value = TRUE)[1]
      if (!is.na(sex_col)) {
        colnames(lung)[colnames(lung) == sex_col] <- "sex"
      } else {
        lung\$sex <- "All"
      }
    }
    
    # Ensure status and time are numeric
    if (is.character(lung\$status) || is.factor(lung\$status)) {
      num_status <- suppressWarnings(as.numeric(as.character(lung\$status)))
      if (!any(is.na(num_status) & !is.na(lung\$status))) {
        lung\$status <- num_status
      } else {
        status_lower <- tolower(trimws(as.character(lung\$status)))
        new_status <- rep(NA, length(status_lower))
        
        # Explicitly map known terms to 0 (censored) and 1 (event)
        new_status[status_lower %in% c("alive", "censored", "stable", "disease free", "false", "no", "0")] <- 0
        new_status[status_lower %in% c("dead", "death", "event", "progression", "relapse", "recurrence", "deceased", "true", "yes", "1")] <- 1
        
        unmapped <- is.na(new_status) & !is.na(status_lower)
        if (any(unmapped)) {
          new_status[unmapped] <- as.numeric(as.factor(status_lower[unmapped])) - 1
        }
        lung\$status <- new_status
      }
    } else {
      lung\$status <- as.numeric(lung\$status)
    }
    lung\$time <- as.numeric(lung\$time)
    
    # 2. Fit the Kaplan-Meier survival curve using survfit()
    # Exact documented call: fit <- survfit(Surv(time, status) ~ sex, data = lung)
    fit <- survfit(Surv(time, status) ~ sex, data = lung)
    
    # 3. Summarize survival probabilities and median survival times using summary()
    # Exact documented call: summary(fit)
    # Capture the console output to a text file
    sink("survival_summary.txt")
    print(summary(fit))
    sink()
    
    # Also save a structured CSV of the summary for downstream analysis
    fit_summary <- summary(fit)
    summary_df <- data.frame(
      time = fit_summary\$time,
      n.risk = fit_summary\$n.risk,
      n.event = fit_summary\$n.event,
      survival = fit_summary\$surv,
      std.err = fit_summary\$std.err,
      lower = fit_summary\$lower,
      upper = fit_summary\$upper
    )
    
    if (!is.null(fit_summary\$strata)) {
      summary_df\$strata <- fit_summary\$strata
      summary_df <- summary_df[, c("strata", "time", "n.risk", "n.event", "survival", "std.err", "lower", "upper")]
    }
    
    write.csv(summary_df, "survival_summary_table.csv", row.names = FALSE)
    
    # 4. Plot the survival curves using plot()
    # Exact documented call: plot(fit)
    # Wrap in a pdf device to save the plot
    pdf("kaplan_meier_curves.pdf", width = 8, height = 6)
    plot(fit)
    dev.off()
    
    # Save the fit object as RDS
    saveRDS(fit, "kaplan_meier_fit.rds")

    writeLines(c(
        '"BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES":',
        paste0('    survival: ', as.character(packageVersion('survival')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kaplan_meier_survival_curves.csv versions.yml
    """
}

workflow BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ patient_clinical_data.csv ] ]

    main:
    BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES(ch_input)

    emit:
    tables   = BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES.out.tables
    plots    = BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES.out.plots
    objects  = BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES.out.objects
    versions = BIOC_SURVIVAL_KAPLAN_MEIER_SURVIVAL_CURVES.out.versions
}
