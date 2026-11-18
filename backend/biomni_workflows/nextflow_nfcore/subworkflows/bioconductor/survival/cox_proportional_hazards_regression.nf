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
    tuple val(meta), path("*.csv"),  emit: tables, optional: true
    tuple val(meta), path("*.pdf"),  emit: plots,  optional: true
    tuple val(meta), path("*.rds"),  emit: objects, optional: true
    tuple val(meta), path("*.json"), emit: reports, optional: true
    tuple val(meta), path("survival_qc.json"), emit: qc_metrics, optional: true
    path "versions.yml",             emit: versions

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
          list.files(".", pattern = "(?i)(clinical|patient|cohort|survival).*\\\\.(csv|tsv|txt)\$")
        )
        .clin_path <- .clin_candidates[file.exists(.clin_candidates)][1]
        if (is.na(.clin_path) || !nzchar(.clin_path)) {
          stop("Required input file missing: patient_clinical_data.csv (or a *clinical*/*patient* CSV)")
        }
        clinical_data <- if (grepl("\\\\.tsv\$", .clin_path, ignore.case = TRUE)) {
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
        .drop <- grepl("(?i)^(patient|subject|sample|id|rownames)\$|(_id)\$", colnames(clinical_data))
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
        
        # Write NAIVE (unadjusted) outputs
        saveRDS(fit, "cox_fit.rds")

        # Extract and save coefficients and hazard ratios (NAIVE fit)
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

        # ============================================================
        # EXECUTED SELF-CORRECTION: PH-violation -> auto-remediate
        # ============================================================
        # cox.zph() above is diagnostic only. A single constant hazard ratio is
        # trustworthy ONLY if the proportional-hazards (PH) assumption holds. When
        # cox.zph flags a violation (any per-covariate OR the GLOBAL test with
        # p < 0.05), the reported HR is over-claimed: the covariate's effect
        # actually changes over follow-up. This block makes the workflow re-fit an
        # ADJUSTED model automatically (no human in the loop):
        #   * low-cardinality violators  -> stratify() : each stratum gets its own
        #     baseline hazard, so a non-proportional nuisance covariate no longer
        #     distorts the other HRs;
        #   * continuous violators       -> tt() time-transform (effect x log(t+1)),
        #     so the time-varying effect is modelled instead of averaged into one HR.
        # It then writes BOTH the naive and the remediated HRs + a flip table, so the
        # over-claimed HR and the honest adjusted HR are both visible in the outputs.
        ph_alpha <- 0.05
        zt <- as.data.frame(cz\$table)
        zt_p <- suppressWarnings(as.numeric(zt[["p"]]))
        names(zt_p) <- rownames(zt)
        global_p_naive <- if ("GLOBAL" %in% names(zt_p)) as.numeric(zt_p[["GLOBAL"]]) else NA_real_
        term_rows <- setdiff(names(zt_p), "GLOBAL")
        violating_terms <- term_rows[which(zt_p[term_rows] < ph_alpha)]
        any_violation <- (length(violating_terms) > 0) ||
                         (!is.na(global_p_naive) && global_p_naive < ph_alpha)

        # Map a cox.zph term label (which may be a factor-expanded coefficient
        # name like "stagehigh") back to the underlying data column.
        .covs <- setdiff(colnames(clinical_data), c("time", "status"))
        .map_term_to_col <- function(term) {
          if (term %in% .covs) return(term)
          hit <- .covs[vapply(.covs, function(cc) startsWith(term, cc), logical(1))]
          if (length(hit)) hit[which.max(nchar(hit))] else NA_character_
        }
        .is_lowcard <- function(cc) {
          v <- clinical_data[[cc]]
          if (is.factor(v) || is.character(v) || is.logical(v)) return(TRUE)
          length(unique(v[!is.na(v)])) <= 6
        }

        remediation <- list(
          ph_violation_detected = any_violation,
          ph_alpha = ph_alpha,
          global_p_naive = global_p_naive,
          violating_terms = violating_terms
        )

        if (any_violation) {
          viol_cols <- unique(stats::na.omit(vapply(
            if (length(violating_terms)) violating_terms else term_rows,
            .map_term_to_col, character(1))))
          # If only GLOBAL violated (no single term flagged), stratify the strongest
          # single non-proportional term so remediation is well-defined.
          if (length(viol_cols) == 0) {
            worst <- term_rows[which.min(zt_p[term_rows])]
            viol_cols <- stats::na.omit(.map_term_to_col(worst))
          }
          strata_cols <- viol_cols[vapply(viol_cols, .is_lowcard, logical(1))]
          tt_cols     <- setdiff(viol_cols, strata_cols)
          plain_cols  <- setdiff(.covs, viol_cols)

          # Pre-compute a median-split stratifier column for each continuous
          # violator, used as the no-tt fallback (keeps the formula simple/robust).
          for (.tc in tt_cols) {
            .med <- stats::median(clinical_data[[.tc]], na.rm = TRUE)
            clinical_data[[paste0(.tc, "_phsplit")]] <- factor(ifelse(clinical_data[[.tc]] > .med, "hi", "lo"))
          }
          .build_rhs <- function(use_tt) {
            terms <- plain_cols
            if (length(strata_cols)) terms <- c(terms, sprintf("strata(%s)", strata_cols))
            if (length(tt_cols)) {
              # tt() needs BOTH the main term and the time-interaction so the
              # model carries a baseline coefficient AND its change over time.
              if (use_tt) terms <- c(terms, tt_cols, sprintf("tt(%s)", tt_cols))
              else        terms <- c(terms, sprintf("strata(%s_phsplit)", tt_cols))
            }
            if (!length(terms)) terms <- "1"
            stats::as.formula(paste("Surv(time, status) ~", paste(terms, collapse = " + ")))
          }

          fit_rem <- tryCatch(
            coxph(.build_rhs(TRUE), data = clinical_data,
                  tt = function(x, t, ...) x * log(t + 1)),
            error = function(e) tryCatch(coxph(.build_rhs(FALSE), data = clinical_data),
                                         error = function(e2) NULL))

          if (!is.null(fit_rem)) {
            sum_rem <- summary(fit_rem)
            saveRDS(fit_rem, "cox_fit_remediated.rds")
            write.csv(as.data.frame(sum_rem\$coefficients), "cox_coefficients_remediated.csv", row.names = TRUE)
            write.csv(as.data.frame(sum_rem\$conf.int), "cox_hazard_ratios_remediated.csv", row.names = TRUE)
            cz_rem <- tryCatch(cox.zph(fit_rem), error = function(e) NULL)
            global_p_rem <- NA_real_
            if (!is.null(cz_rem)) {
              write.csv(as.data.frame(cz_rem\$table), "cox_zph_test_remediated.csv", row.names = TRUE)
              zr <- as.data.frame(cz_rem\$table)
              if ("GLOBAL" %in% rownames(zr)) global_p_rem <- suppressWarnings(as.numeric(zr["GLOBAL", "p"]))
            }

            # Flip table: covariates present in BOTH fits, naive vs remediated.
            nco <- as.data.frame(fit_summary\$coefficients)
            nci <- as.data.frame(fit_summary\$conf.int)
            rco <- as.data.frame(sum_rem\$coefficients)
            rci <- as.data.frame(sum_rem\$conf.int)
            shared <- intersect(rownames(nco), rownames(rco))
            cmp <- data.frame(
              covariate       = shared,
              naive_HR        = nci[shared, "exp(coef)"],
              naive_p         = nco[shared, "Pr(>|z|)"],
              remediated_HR   = rci[shared, "exp(coef)"],
              remediated_p    = rco[shared, "Pr(>|z|)"],
              stringsAsFactors = FALSE
            )
            cmp\$significance_flip <- (cmp\$naive_p < 0.05) != (cmp\$remediated_p < 0.05)
            write.csv(cmp, "cox_naive_vs_remediated.csv", row.names = FALSE)

            # For time-transformed (continuous) violators, a single HR is NOT the
            # honest answer — the effect changes over time. Report the per-unit HR
            # at an EARLY and a LATE follow-up time so the over-claimed constant HR
            # is visibly corrected: e.g. strongly protective early, null by late.
            tv_rows <- list()
            if (length(tt_cols)) {
              t_early <- 6; t_late <- 48
              rc <- stats::coef(fit_rem)
              nco_hr <- as.data.frame(fit_summary\$conf.int)
              for (.tc in tt_cols) {
                b_main <- unname(rc[.tc])
                b_tt   <- unname(rc[paste0("tt(", .tc, ")")])
                if (length(b_main) == 0 || length(b_tt) == 0 || is.na(b_main) || is.na(b_tt)) next
                hr_e <- exp(b_main + b_tt * log(t_early + 1))
                hr_l <- exp(b_main + b_tt * log(t_late + 1))
                tv_rows[[length(tv_rows) + 1]] <- data.frame(
                  covariate = .tc,
                  naive_constant_HR = if (.tc %in% rownames(nco_hr)) nco_hr[.tc, "exp(coef)"] else NA_real_,
                  remediated_HR_early_mo = round(hr_e, 4),
                  remediated_HR_late_mo  = round(hr_l, 4),
                  t_early_months = t_early, t_late_months = t_late,
                  stringsAsFactors = FALSE)
              }
              if (length(tv_rows)) {
                tv_df <- do.call(rbind, tv_rows)
                write.csv(tv_df, "cox_timevarying_hr.csv", row.names = FALSE)
                remediation\$timevarying_hr <- lapply(seq_len(nrow(tv_df)), function(i) {
                  as.list(tv_df[i, c("covariate","naive_constant_HR","remediated_HR_early_mo","remediated_HR_late_mo")])
                })
              }
            }

            remediation\$strategy <- list(
              stratified = as.character(strata_cols),
              time_transformed = as.character(tt_cols)
            )
            remediation\$global_p_remediated <- global_p_rem
            remediation\$n_covariates_flipped <- sum(cmp\$significance_flip, na.rm = TRUE)
            remediation\$status <- "remediated"
          } else {
            remediation\$status <- "remediation_failed"
            remediation\$error  <- "adjusted re-fit could not be computed; naive fit retained"
          }
        } else {
          remediation\$status <- "no_remediation_needed"
          remediation\$note   <- "PH assumption holds (no covariate and GLOBAL p < 0.05); the naive HRs are trustworthy. No second model fabricated."
        }

        # Minimal dependency-free JSON writer for the remediation headline.
        .jesc <- function(s) gsub('"', '\\\\"', as.character(s))
        .jval <- function(v) {
          if (is.null(v) || length(v) == 0) return(if (is.list(v)) "{}" else "[]")
          if (length(v) == 1 && !is.list(v) && is.na(v)) return("null")
          if (is.list(v)) {
            if (is.null(names(v)) || any(!nzchar(names(v)))) {
              # unnamed list -> JSON array of objects/values
              return(paste0("[", paste(vapply(v, .jval, character(1)), collapse = ", "), "]"))
            }
            inner <- paste(sprintf('"%s": %s', names(v), vapply(v, .jval, character(1))), collapse = ", ")
            return(paste0("{", inner, "}"))
          }
          if (is.logical(v) && length(v) == 1) return(tolower(as.character(v)))
          if (is.numeric(v) && length(v) == 1) return(as.character(v))
          if (length(v) > 1) return(paste0("[", paste(sprintf('"%s"', .jesc(v)), collapse = ", "), "]"))
          paste0('"', .jesc(v), '"')
        }
        .jlines <- vapply(names(remediation), function(k) sprintf('  "%s": %s', k, .jval(remediation[[k]])), character(1))
        writeLines(c("{", paste(.jlines, collapse = ",\n"), "}"), "cox_remediation_summary.json")
        cat("\\n[self-correction] PH-violation remediation status: ", remediation\$status, "\\n", sep = "")

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
    reports    = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.reports
    qc_metrics = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.qc_metrics
    versions   = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.versions
}
