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
    tuple val(meta), path("survival_qc.json"), emit: qc_metrics, optional: true
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
        
        # Read user input file
        clinical_data <- read.csv("patient_clinical_data.csv")
        
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

        # 4. Emit survival_qc.json for the survival QC gate / auto-loop.
        #    The first covariate column (after time/status) is the primary biomarker.
        #    We report: the naive biomarker-only HR vs the adjusted HR, the Schoenfeld
        #    global PH p-value, and every other covariate as a candidate confounder
        #    (name/HR/p). The survival_autoloop evaluator reads these: a significant
        #    omitted covariate -> confounding gate -> re-fit adjusted; a Schoenfeld
        #    global p < 0.05 -> PH gate -> stratify.
        tryCatch({
          if (!requireNamespace("jsonlite", quietly=TRUE))
            install.packages("jsonlite", repos="https://packagemanager.posit.co/cran/__linux__/jammy/latest")
          covs    <- setdiff(colnames(clinical_data), c("time", "status"))
          primary <- covs[1]
          coefs <- as.data.frame(fit_summary\$coefficients)   # cols: coef, exp(coef), se, z, Pr(>|z|)
          ci    <- as.data.frame(fit_summary\$conf.int)
          hr_of <- function(v) if (!is.null(v) && v %in% rownames(ci))    unname(ci[v, "exp(coef)"]) else NA
          p_of  <- function(v) if (!is.null(v) && v %in% rownames(coefs)) unname(coefs[v, ncol(coefs)]) else NA
          naive_hr <- tryCatch({
            nf <- coxph(as.formula(paste0("Surv(time, status) ~ ", primary)), data = clinical_data)
            unname(summary(nf)\$conf.int[primary, "exp(coef)"])
          }, error = function(e) NA)
          omitted <- list()
          for (v in setdiff(covs, primary)) {
            pv <- p_of(v)
            if (!is.na(pv)) omitted[[length(omitted) + 1]] <- list(name = v, hr = round(hr_of(v), 4), p = pv)
          }
          cz_tab <- as.data.frame(cz\$table)
          gp   <- if ("GLOBAL" %in% rownames(cz_tab)) unname(cz_tab["GLOBAL", "p"]) else NA
          viol <- rownames(cz_tab)[!is.na(cz_tab\$p) & cz_tab\$p < 0.05 & rownames(cz_tab) != "GLOBAL"]
          qc <- list(
            process                 = "BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION",
            domain                  = "survival",
            primary_covariate       = primary,
            naive_primary_hr        = if (is.na(naive_hr))        NULL else round(naive_hr, 4),
            adjusted_primary_hr     = if (is.na(hr_of(primary)))  NULL else round(hr_of(primary), 4),
            schoenfeld_global_p     = if (is.na(gp))              NULL else gp,
            ph_violating_covariates = as.list(viol),
            omitted_confounders     = omitted,
            # Explicit design block so the Phase-0 run contract (design.json) carries a
            # real formula/covariates/exposure instead of nulls — the design-aware
            # critics read this. 'exposure_of_interest' = the primary biomarker; the
            # modeled covariates are the full adjusted set.
            design                  = list(
              formula              = paste0("Surv(time, status) ~ ", paste(covs, collapse = " + ")),
              covariates           = as.list(covs),
              candidate_covariates = as.list(setdiff(covs, primary)),
              exposure_of_interest = primary,
              model_type           = "cox",
              # events / n_samples power the EPV (events-per-variable) critic; group_sizes
              # (event vs censored, or exposure-arm Ns) powers the low-replicate critic.
              events               = tryCatch(as.integer(sum(clinical_data\$status == 1, na.rm = TRUE)), error = function(e) NULL),
              n_samples            = nrow(clinical_data),
              n_covariates         = length(covs),
              group_sizes          = tryCatch({
                                       if (!is.null(primary) && length(unique(clinical_data[[primary]])) <= 10)
                                         as.list(table(clinical_data[[primary]]))
                                       else
                                         as.list(c(event = sum(clinical_data\$status == 1, na.rm = TRUE),
                                                   censored = sum(clinical_data\$status == 0, na.rm = TRUE)))
                                     }, error = function(e) NULL),
              design_source        = "workflow"
            )
          )
          cat(jsonlite::toJSON(qc, auto_unbox = TRUE, null = "null", pretty = TRUE), file = "survival_qc.json")
        }, error = function(e) message("survival_qc emit failed: ", conditionMessage(e)))

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
    tables     = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.tables
    plots      = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.plots
    objects    = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.objects
    qc_metrics = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.qc_metrics
    versions   = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.versions
}
