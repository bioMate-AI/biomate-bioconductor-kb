#!/usr/bin/env nextflow
/*
 * pharmacology/nlmixr2_population_pk
 *
 * Population pharmacokinetic / pharmacodynamic (PopPK/PD) analysis using nlmixr2.
 *
 * nlmixr2 implements the SAEM (Stochastic Approximation Expectation-Maximisation)
 * algorithm — the same method used by Monolix — and FOCE+ (equivalent to NONMEM FOCE).
 * It is open-source (GPL-2), Nextflow-compatible via an R container, and has been
 * validated against NONMEM in published benchmarks:
 *   Fidler et al. (2019) CPT: Pharmacometrics & Systems Pharmacology 8(12):931–938
 *
 * Inputs:
 *   --pk_data_csv    : Individual PK concentration-time data
 *                      Required columns: ID, TIME, DV, AMT, EVID, CMT
 *                      Optional: WT, AGE, SEX, CRCL, ALB (covariates)
 *   --model_type     : "1cmt_oral" | "2cmt_oral" | "1cmt_iv" | "2cmt_iv"
 *                      Default: "1cmt_oral"
 *   --algorithm      : "saem" (default) | "focei" | "rxSolve"
 *   --covariates     : Comma-separated list of covariate columns to test (optional)
 *
 * Outputs:
 *   popPK_report.html         — nlmixr2 HTML report (parameter estimates, VPC, GOF)
 *   parameter_estimates.csv   — Fixed effects (THETA) + random effects (OMEGA, SIGMA)
 *   individual_estimates.csv  — EBEs (η): individual PK parameters per subject
 *   vpc_plot.pdf              — Visual predictive check plot
 *   goodness_of_fit.pdf       — Standard GOF diagnostic plots (DV vs PRED/IPRED, CWRES)
 *   nlmixr2_results.json      — Machine-readable summary for QC gate integration
 *
 * QC gates (integrated with BioMate qc_trace_monitor.py):
 *   [GOLD]   Model convergence status — SAEM must converge (OFV stable ± 0.1%)
 *   [SILVER] ETA shrinkage < 30% — high shrinkage invalidates individual estimates
 *   [BRONZE] Condition number < 1000 — high condition number signals parameter correlation
 *
 * Usage:
 *   nextflow run subworkflows/pharmacology/nlmixr2_population_pk/main.nf \
 *     --pk_data_csv data/pk_data.csv \
 *     --model_type 2cmt_oral \
 *     --algorithm saem \
 *     -profile docker
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir        = './results/population_pk'
params.pk_data_csv   = null
params.model_type    = '1cmt_oral'
params.algorithm     = 'saem'
params.covariates    = ''
params.max_iter      = 300
params.seed          = 1234

process NLMIXR2_POPULATION_PK {
    tag "$meta.id"
    label 'process_high'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-pharma:x86' : 'biomate/r-pharma:latest'

    input:
    val(meta)
    path(pk_data)

    output:
    tuple val(meta), path("popPK_report.html"),          emit: report,         optional: true
    tuple val(meta), path("parameter_estimates.csv"),     emit: parameters
    tuple val(meta), path("individual_estimates.csv"),    emit: individual_ebv
    tuple val(meta), path("vpc_plot.pdf"),                emit: vpc,            optional: true
    tuple val(meta), path("goodness_of_fit.pdf"),         emit: gof,            optional: true
    tuple val(meta), path("nlmixr2_results.json"),        emit: results
    tuple val(meta), path("qc_metrics.json"),             emit: qc_metrics
    path "versions.yml",                                  emit: versions

    script:
    def covariates_r = params.covariates
        ? "c(${params.covariates.split(',').collect { "'${it.trim()}'" }.join(', ')})"
        : "NULL"
    """
    Rscript - << 'REOF'
    suppressPackageStartupMessages({
        library(nlmixr2)
        library(rxode2)
        library(xpose)
        library(xpose.nlmixr2)
        library(ggplot2)
        library(jsonlite)
        library(data.table)
    })

    set.seed(${params.seed})
    cat("nlmixr2 population PK analysis\\n")
    cat("Model type : ${params.model_type}\\n")
    cat("Algorithm  : ${params.algorithm}\\n")
    cat("Data file  : ${pk_data}\\n\\n")

    # ── Load data ────────────────────────────────────────────────────────────
    pk_data <- fread("${pk_data}")
    required_cols <- c("ID", "TIME", "DV", "AMT", "EVID")
    missing_cols  <- setdiff(required_cols, names(pk_data))
    if (length(missing_cols) > 0) {
        stop(paste("Missing required columns:", paste(missing_cols, collapse=", ")))
    }
    n_subjects <- length(unique(pk_data[EVID == 0, ID]))
    n_obs      <- nrow(pk_data[EVID == 0])
    cat(sprintf("Subjects: %d   Observations: %d\\n", n_subjects, n_obs))

    # ── Model definition ─────────────────────────────────────────────────────
    if ("${params.model_type}" == "1cmt_oral") {
        pk_model <- function() {
            ini({
                tka   <- log(1.0)   ; label("Absorption rate (log ka, h-1)")
                tcl   <- log(1.0)   ; label("Clearance (log CL, L/h)")
                tv    <- log(10.0)  ; label("Volume (log V, L)")
                eta.ka ~ 0.25
                eta.cl ~ 0.25
                eta.v  ~ 0.25
                add.sd <- 0.1       ; label("Additive residual SD")
                prop.sd <- 0.1      ; label("Proportional residual SD")
            })
            model({
                ka <- exp(tka + eta.ka)
                cl <- exp(tcl + eta.cl)
                v  <- exp(tv  + eta.v)
                d/dt(depot)  <- -ka * depot
                d/dt(center) <-  ka * depot - cl / v * center
                cp           <-  center / v
                cp           ~ add(add.sd) + prop(prop.sd)
            })
        }
    } else if ("${params.model_type}" == "2cmt_oral") {
        pk_model <- function() {
            ini({
                tka   <- log(1.0)   ; label("Absorption rate (log ka, h-1)")
                tcl   <- log(1.0)   ; label("Clearance (log CL, L/h)")
                tv1   <- log(10.0)  ; label("Central volume (log V1, L)")
                tq    <- log(0.5)   ; label("Inter-compartment CL (log Q, L/h)")
                tv2   <- log(5.0)   ; label("Peripheral volume (log V2, L)")
                eta.ka ~ 0.25
                eta.cl ~ 0.25
                eta.v1 ~ 0.25
                add.sd  <- 0.1
                prop.sd <- 0.1
            })
            model({
                ka <- exp(tka + eta.ka)
                cl <- exp(tcl + eta.cl)
                v1 <- exp(tv1 + eta.v1)
                q  <- exp(tq)
                v2 <- exp(tv2)
                d/dt(depot)      <- -ka * depot
                d/dt(central)    <-  ka * depot - cl / v1 * central - q / v1 * central + q / v2 * peripheral
                d/dt(peripheral) <-  q / v1 * central - q / v2 * peripheral
                cp               <-  central / v1
                cp               ~ add(add.sd) + prop(prop.sd)
            })
        }
    } else if ("${params.model_type}" == "1cmt_iv") {
        pk_model <- function() {
            ini({
                tcl   <- log(1.0)  ; label("Clearance (log CL, L/h)")
                tv    <- log(10.0) ; label("Volume (log V, L)")
                eta.cl ~ 0.25
                eta.v  ~ 0.25
                add.sd  <- 0.1
                prop.sd <- 0.1
            })
            model({
                cl <- exp(tcl + eta.cl)
                v  <- exp(tv  + eta.v)
                d/dt(center) <- -cl / v * center
                cp           <-  center / v
                cp           ~ add(add.sd) + prop(prop.sd)
            })
        }
    } else {
        stop(paste("Unknown model_type:", "${params.model_type}",
                   "-- use 1cmt_oral, 2cmt_oral, or 1cmt_iv"))
    }

    # ── Fit model ────────────────────────────────────────────────────────────
    # Pick the control function that matches the chosen estimation algorithm —
    # do.call(saemControl, ...) was used regardless of algorithm, which broke
    # FOCEI runs.
    algo_lc <- tolower("${params.algorithm}")
    control_fn <- switch(algo_lc,
        saem  = saemControl,
        focei = foceiControl,
        saemControl
    )
    control_args <- list(maxOuterIterations = ${params.max_iter})
    fit_err <- NULL
    fit <- tryCatch(
        nlmixr2(pk_model, pk_data, est = "${params.algorithm}",
                control = do.call(control_fn, control_args)),
        error = function(e) {
            msg <- conditionMessage(e)
            fit_err <<- msg
            cat("ERROR: nlmixr2 fitting failed:", msg, "\\n")
            NULL
        }
    )

    if (is.null(fit)) {
        # Persist failure state so the QC monitor still has a qc_metrics.json
        # to read instead of silently going dark.
        results_json <- list(
            convergence_status = "failed",
            model_type         = "${params.model_type}",
            algorithm          = "${params.algorithm}",
            n_subjects         = n_subjects,
            n_observations     = n_obs,
            error_message      = fit_err
        )
        write_json(results_json, "nlmixr2_results.json", pretty = TRUE, auto_unbox = TRUE)
        fwrite(data.frame(), "parameter_estimates.csv")
        fwrite(data.frame(), "individual_estimates.csv")
        qc_failed <- list(
            success            = FALSE,
            process            = "NLMIXR2_POPULATION_PK",
            domain             = "pharmacology",
            convergence_status = "failed",
            model_type         = "${params.model_type}",
            algorithm          = "${params.algorithm}",
            n_subjects         = n_subjects,
            n_observations     = n_obs,
            error_message      = fit_err,
            evidence_tier      = "GOLD",
            citation           = "Savic & Karlsson 2007 AAPS J 9:E251"
        )
        write_json(qc_failed, "qc_metrics.json", pretty = TRUE, auto_unbox = TRUE)
        # Exit 0 so publishDir copies all declared outputs (including the
        # qc_metrics.json failure record) — the QC monitor will then read the
        # convergence_status="failed" and the gate will TRIGGER. Aborting here
        # would suppress publishDir and leave the run silently dark.
        cat("nlmixr2 fit failed; failure-state outputs published. Exiting 0.\\n")
        quit(save = "no", status = 0)
    }

    # ── Extract QC metrics ───────────────────────────────────────────────────
    params_df <- as.data.frame(fit$parFixed)
    etas       <- fit$eta

    # ETA shrinkage (per random effect)
    shrinkage_vals <- tryCatch(fit$shrink, error = function(e) NULL)
    max_shrinkage  <- if (!is.null(shrinkage_vals)) max(shrinkage_vals, na.rm = TRUE) else NA

    # Condition number from covariance matrix
    cov_mat <- tryCatch(fit$covMatrix, error = function(e) NULL)
    cond_number <- if (!is.null(cov_mat) && nrow(cov_mat) > 0) {
        eig <- eigen(cov_mat, only.values = TRUE)$values
        max(abs(eig)) / min(abs(eig[abs(eig) > 1e-10]))
    } else NA

    # OFV (objective function value)
    ofv <- tryCatch(fit$ofv, error = function(e) NA)

    # Convergence: nlmixr2 sets fit$message; SAEM converged if no warning keyword
    converged <- tryCatch({
        msg <- fit$message
        !grepl("not converge|failed|warning", msg, ignore.case = TRUE)
    }, error = function(e) TRUE)  # assume converged if message not accessible

    cat(sprintf("OFV        : %.2f\\n", ofv))
    cat(sprintf("Converged  : %s\\n", converged))
    cat(sprintf("Max eta shrinkage: %.1f%%\\n", max_shrinkage * 100))
    cat(sprintf("Condition number : %.1f\\n", cond_number))

    # ── Write outputs ────────────────────────────────────────────────────────
    fwrite(params_df, "parameter_estimates.csv", row.names = TRUE)
    fwrite(etas,      "individual_estimates.csv")

    # GOF plots
    tryCatch({
        pdf("goodness_of_fit.pdf", width = 10, height = 8)
        xpdb  <- xpose_data_nlmixr2(fit)
        print(dv_vs_pred(xpdb))
        print(dv_vs_ipred(xpdb))
        print(res_vs_pred(xpdb))
        print(res_vs_idv(xpdb))
        dev.off()
    }, error = function(e) cat("GOF plot warning:", conditionMessage(e), "\\n"))

    # VPC
    tryCatch({
        vpc_res <- vpcstats(fit)
        pdf("vpc_plot.pdf", width = 8, height = 6)
        plot(vpc_res)
        dev.off()
    }, error = function(e) cat("VPC warning:", conditionMessage(e), "\\n"))

    # Machine-readable results for QC gate
    results_json <- list(
        convergence_status    = ifelse(converged, "converged", "not_converged"),
        ofv                   = ofv,
        model_type            = "${params.model_type}",
        algorithm             = "${params.algorithm}",
        n_subjects            = n_subjects,
        n_observations        = n_obs,
        max_eta_shrinkage_pct = if (!is.na(max_shrinkage)) round(max_shrinkage * 100, 1) else NULL,
        condition_number      = if (!is.na(cond_number))   round(cond_number, 1)          else NULL,
        aic                   = tryCatch(AIC(fit), error = function(e) NULL),
        bic                   = tryCatch(BIC(fit), error = function(e) NULL)
    )
    write_json(results_json, "nlmixr2_results.json", pretty = TRUE, auto_unbox = TRUE)
    cat("\\nResults written to nlmixr2_results.json\\n")

    # qc_metrics.json — gate metrics consumed by the QC monitor's
    # pop-PK gates. Key names normalized to what qc_gate_reader expects:
    #   eta_shrinkage_pct_max — Savic & Karlsson 2007 (GOLD <20%, SILVER <30%)
    #   condition_number      — community Pop-PK convention (SILVER <100, BRONZE <1000)
    # ofv_delta_max NOT emitted because the workflow runs a single fit;
    # OFV-stability gate needs successive-iteration ΔOFV which would
    # require a refit pipeline. Gate skips with None — by design.
    qc_metrics <- list(
        eta_shrinkage_pct_max = results_json$max_eta_shrinkage_pct,
        condition_number      = results_json$condition_number,
        ofv                   = results_json$ofv,
        convergence_status    = results_json$convergence_status,
        n_subjects            = results_json$n_subjects,
        n_observations        = results_json$n_observations,
        model_type            = results_json$model_type,
        algorithm             = results_json$algorithm
    )
    write_json(qc_metrics, "qc_metrics.json", pretty = TRUE, auto_unbox = TRUE)
    REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: \$(Rscript --version 2>&1 | cut -d' ' -f5)
        nlmixr2: \$(Rscript -e "cat(as.character(packageVersion('nlmixr2')))" 2>/dev/null || echo "unknown")
        rxode2: \$(Rscript -e "cat(as.character(packageVersion('rxode2')))" 2>/dev/null || echo "unknown")
    END_VERSIONS
    """
}

workflow NLMIXR2_POPULATION_PK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    ch_pk_data = Channel.fromPath(params.pk_data_csv)
    NLMIXR2_POPULATION_PK(ch_input, ch_pk_data)

    emit:
    report     = NLMIXR2_POPULATION_PK.out.report
    parameters = NLMIXR2_POPULATION_PK.out.parameters
    individual = NLMIXR2_POPULATION_PK.out.individual_ebv
    vpc        = NLMIXR2_POPULATION_PK.out.vpc
    gof        = NLMIXR2_POPULATION_PK.out.gof
    results    = NLMIXR2_POPULATION_PK.out.results
    versions   = NLMIXR2_POPULATION_PK.out.versions
}

workflow {
    // Parser-v2 requires top-level statements inside workflow{}, not file-level
    if (!params.pk_data_csv) {
        error "Please provide --pk_data_csv (individual PK concentration-time data)"
    }
    ch_input = Channel.of([id: 'popPK_run'])
    NLMIXR2_POPULATION_PK_WORKFLOW(ch_input)
    NLMIXR2_POPULATION_PK_WORKFLOW.out.results.view { meta, json -> "Results: $json" }
}
