#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survival — cox_proportional_hazards_regression
// Fit a semi-parametric Cox proportional hazards model to evaluate the effect of multiple continuous and categorical covariates on survival.
// Input: patient_clinical_data.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the Cox proportional hazards model using coxph()
//  * 2. [Visualization & Output] Summarize hazard ratios and significance using summary()
//  * 3. [Core Analysis] Test the proportional hazards assumption using cox.zph()

nextflow.enable.dsl = 2

process BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION {
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
        
        # Load required library
        library(survival)
        
        # Read user input file (accept common cold-start aliases of the basename)
        .clin_candidates <- c(
          "patient_clinical_data.csv",
          list.files(".", pattern = "(?i)(clinical|patient|cohort|survival).*\\\\.(csv|tsv|txt)$")
        )
        .clin_path <- .clin_candidates[file.exists(.clin_candidates)][1]
        if (is.na(.clin_path) || !nzchar(.clin_path)) {
          stop("Required input file missing: patient_clinical_data.csv (or a *clinical*/*patient* CSV)")
        }
        clinical_data <- if (grepl("\\\\.tsv$", .clin_path, ignore.case = TRUE)) {
          read.delim(.clin_path, stringsAsFactors = FALSE)
        } else {
          read.csv(.clin_path, stringsAsFactors = FALSE)
        }

        # Standardize columns — same contract as survival/main.nf (KM). Cold-start
        # autoimmune cohort uses time_months + status; Surv(time, status) needs numeric `time`.
        colnames(clinical_data) <- tolower(colnames(clinical_data))
        if (!"time" %in% colnames(clinical_data)) {
          time_col <- grep("time|month|day|year|duration|follow", colnames(clinical_data), value = TRUE)[1]
          if (!is.na(time_col)) colnames(clinical_data)[colnames(clinical_data) == time_col] <- "time"
        }
        if (!"status" %in% colnames(clinical_data)) {
          status_col <- grep("status|event|cens|flare", colnames(clinical_data), value = TRUE)[1]
          if (!is.na(status_col)) colnames(clinical_data)[colnames(clinical_data) == status_col] <- "status"
        }
        if (!all(c("time", "status") %in% colnames(clinical_data))) {
          stop("Clinical table must have time and status columns (or aliases like time_months / event).")
        }
        if (is.character(clinical_data\$status) || is.factor(clinical_data\$status)) {
          num_status <- suppressWarnings(as.numeric(as.character(clinical_data\$status)))
          if (!any(is.na(num_status) & !is.na(clinical_data\$status))) {
            clinical_data\$status <- num_status
          } else {
            status_lower <- tolower(trimws(as.character(clinical_data\$status)))
            new_status <- rep(NA_real_, length(status_lower))
            new_status[status_lower %in% c("alive", "censored", "stable", "disease free", "false", "no", "0")] <- 0
            new_status[status_lower %in% c("dead", "death", "event", "progression", "relapse", "recurrence", "deceased", "true", "yes", "1", "flare")] <- 1
            unmapped <- is.na(new_status) & !is.na(status_lower)
            if (any(unmapped)) new_status[unmapped] <- as.numeric(as.factor(status_lower[unmapped])) - 1
            clinical_data\$status <- new_status
          }
        } else {
          clinical_data\$status <- as.numeric(clinical_data\$status)
        }
        clinical_data\$time <- as.numeric(clinical_data\$time)
        # Drop ID-like columns from the RHS so coxph(~ .) is identifiable
        .drop <- grepl("(?i)^(patient|subject|sample|id|rownames)$|(_id)$", colnames(clinical_data))
        clinical_data <- clinical_data[, (!.drop) | colnames(clinical_data) %in% c("time", "status"), drop = FALSE]
        # Coerce remaining character covariates to factors
        for (.cn in setdiff(colnames(clinical_data), c("time", "status"))) {
          if (is.character(clinical_data[[.cn]])) clinical_data[[.cn]] <- as.factor(clinical_data[[.cn]])
        }
        
        # 1. Fit the Cox proportional hazards model using coxph()
        fit <- coxph(Surv(time, status) ~ ., data = clinical_data)
        
        # 2. Summarize hazard ratios and significance using summary()
        fit_summary <- summary(fit)
        print(fit_summary)
        
        # 3. Test the proportional hazards assumption using cox.zph()
        cz <- cox.zph(fit)
        print(cz)
        
        # Write outputs
        saveRDS(fit, "cox_fit.rds")
        
        # Extract and save coefficients and hazard ratios
        coef_df <- as.data.frame(fit_summary\$coefficients)
        write.csv(coef_df, "cox_coefficients.csv", row.names = TRUE)
        
        confint_df <- as.data.frame(fit_summary\$conf.int)
        write.csv(confint_df, "cox_hazard_ratios.csv", row.names = TRUE)
        
        # Save proportional hazards test results
        cz_df <- as.data.frame(cz\$table)
        write.csv(cz_df, "cox_zph_test.csv", row.names = TRUE)
        
        # Save diagnostic plots
        pdf("cox_zph_plots.pdf")
        plot(cz)
        dev.off()

    writeLines(c(
        '"BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION":',
        paste0('    survival: ', as.character(packageVersion('survival')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cox_proportional_hazards_regression.csv versions.yml
    """
}

workflow BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ patient_clinical_data.csv ] ]

    main:
    BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION(ch_input)

    emit:
    tables   = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.tables
    plots    = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.plots
    objects  = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.objects
    versions = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.versions
}
