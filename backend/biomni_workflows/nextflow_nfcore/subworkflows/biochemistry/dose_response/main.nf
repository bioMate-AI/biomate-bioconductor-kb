#!/usr/bin/env nextflow
/*
 * biochemistry/dose_response
 *
 * Real dose-response / concentration-response fitter.
 *
 * Fits RAW dose-response data with the R `drc` package using a 4-parameter
 * log-logistic model (drm(response ~ concentration, fct = LL.4())) and reports
 * the fitted IC50/EC50, Hill slope, upper/lower asymptotes, standard errors,
 * a sampled fitted curve, and goodness-of-fit (residual std error, R^2, AIC).
 *
 * Input is a data file (CSV/TSV) with a concentration column and a response
 * column. Column names are auto-detected (concentration|conc|dose|x and
 * response|resp|signal|value|y), with a positional fallback to the first two
 * numeric columns.
 *
 * If no data file is supplied, the module degrades gracefully to a single-point
 * Hill-equation evaluation using the scalar params (x/ic50/hill) so existing
 * callers do not break.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Primary path: raw data file (CSV/TSV with concentration + response columns)
params.data          = null       // path to CSV/TSV; null => scalar fallback
params.concentration_col = null   // optional explicit concentration column name
params.response_col      = null   // optional explicit response column name
params.model         = 'LL.4'     // drc model: 'LL.4' (4PL) or 'LL.5' (5PL, asymmetric)
params.response_type = 'inhibition' // 'inhibition' => IC50, 'activation' => EC50

// Scalar fallback (single-point Hill evaluation when no data file given)
params.x    = null
params.ic50 = null
params.hill = null

process DOSE_RESPONSE {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // R + drc (drc is CRAN; bootstrapped below via Posit PPM binaries if missing)
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim' : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(data_file, stageAs: 'input_data.*')

    output:
    tuple val(meta), path("dose_response_results.json"), emit: results
    tuple val(meta), path("dose_response_output.txt"),   emit: output
    tuple val(meta), path("dose_response_curve.csv"),    emit: curve,  optional: true
    tuple val(meta), path("dose_response_fit.pdf"),      emit: plot,   optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def has_data  = data_file ? 'true' : 'false'
    def conc_col  = params.concentration_col ? "${params.concentration_col}" : ''
    def resp_col  = params.response_col ? "${params.response_col}" : ''
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("drc", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      suppressWarnings(suppressMessages(try(install.packages(.bm_miss), silent=TRUE)))
    }

    has_data      <- ${has_data}
    conc_col_pref <- "${conc_col}"
    resp_col_pref <- "${resp_col}"
    model_name    <- "${params.model}"
    resp_type     <- "${params.response_type}"

    write_fallback <- function(reason) {
      # Scalar single-point Hill evaluation (no raw data available)
      x    <- suppressWarnings(as.numeric("${params.x    ?: ''}"));    if (is.na(x))    x    <- 1.0
      ic50 <- suppressWarnings(as.numeric("${params.ic50 ?: ''}"));    if (is.na(ic50)) ic50 <- 50.0
      hill <- suppressWarnings(as.numeric("${params.hill ?: ''}"));    if (is.na(hill)) hill <- 1.0
      response <- if (ic50 != 0) 1 / (1 + (x / ic50) ^ hill) else 0
      out <- list(success = TRUE, function_ = "dose_response", domain = "biochemistry",
                  mode = "scalar_hill_fallback", note = reason,
                  result = list(x = x, ic50 = ic50, hill = hill, response = response))
      jsonlite::write_json(out, "dose_response_results.json", auto_unbox = TRUE, pretty = TRUE, digits = 8)
      writeLines(c("Biomni: Dose Response (scalar Hill fallback)",
                   paste(rep("=", 60), collapse=""), "",
                   sprintf("reason: %s", reason),
                   sprintf("x: %g", x), sprintf("ic50: %g", ic50),
                   sprintf("hill: %g", hill), sprintf("response: %g", response)),
                 "dose_response_output.txt")
    }

    library(jsonlite)

    if (!has_data) {
      write_fallback("no data file supplied; evaluated single-point Hill equation from scalar params")
    } else if (!requireNamespace("drc", quietly = TRUE)) {
      write_fallback("drc package unavailable in this environment")
    } else {
      library(drc)

      # ---- Load raw data (CSV or TSV, auto-detected) ----
      f <- Sys.glob("input_data.*")[1]
      df <- tryCatch(read.csv(f, stringsAsFactors = FALSE, check.names = FALSE),
                     error = function(e) NULL)
      if (is.null(df) || ncol(df) < 2) {
        df <- tryCatch(read.delim(f, stringsAsFactors = FALSE, check.names = FALSE),
                       error = function(e) NULL)
      }

      pick_col <- function(pref, candidates, numeric_only = TRUE) {
        cn <- colnames(df)
        if (nzchar(pref) && pref %in% cn) return(pref)
        lc <- tolower(cn)
        for (cand in candidates) { hit <- which(lc == cand); if (length(hit)) return(cn[hit[1]]) }
        # positional fallback: first (concentration) / second (response) numeric column
        num <- cn[vapply(df, function(col) is.numeric(suppressWarnings(as.numeric(col))) &&
                                           any(!is.na(suppressWarnings(as.numeric(col)))), logical(1))]
        if (length(num) >= 2) return(num[if (identical(candidates, .conc_cands)) 1 else 2])
        NA_character_
      }
      .conc_cands <- c("concentration", "conc", "dose", "x", "log_conc", "logconc")
      .resp_cands <- c("response", "resp", "signal", "value", "y", "viability", "inhibition", "activity")

      c_col <- pick_col(conc_col_pref, .conc_cands)
      r_col <- pick_col(resp_col_pref, .resp_cands)

      if (is.na(c_col) || is.na(r_col)) {
        write_fallback(sprintf("could not resolve concentration/response columns in %s", basename(f)))
      } else {
        conc <- suppressWarnings(as.numeric(df[[c_col]]))
        resp <- suppressWarnings(as.numeric(df[[r_col]]))
        keep <- is.finite(conc) & is.finite(resp)
        conc <- conc[keep]; resp <- resp[keep]

        fit_ok <- FALSE
        if (length(conc) >= 4) {
          fct <- if (identical(model_name, "LL.5"))
                   LL.5(names = c("Slope","Lower","Upper","ED50","Asym"))
                 else
                   LL.4(names = c("Slope","Lower","Upper","ED50"))
          m <- tryCatch(drm(resp ~ conc, fct = fct), error = function(e) NULL)
          if (!is.null(m)) fit_ok <- TRUE
        }

        if (!fit_ok) {
          write_fallback(sprintf("drc::drm(%s) failed or too few points (n=%d, need >=4)",
                                 model_name, length(conc)))
        } else {
          co   <- coef(m)
          se   <- tryCatch(sqrt(diag(vcov(m))), error = function(e) rep(NA_real_, length(co)))
          slope <- unname(co[grep("Slope", names(co))][1])
          lower <- unname(co[grep("Lower", names(co))][1])
          upper <- unname(co[grep("Upper", names(co))][1])
          ed50  <- unname(co[grep("ED50",  names(co))][1])
          # drc's LL.4 'Slope' is the negative Hill slope for inhibition curves
          hill_slope <- -slope
          potency_label <- if (identical(resp_type, "activation")) "EC50" else "IC50"

          # Goodness of fit
          fitted_vals <- fitted(m)
          resid_vals  <- residuals(m)
          rss <- sum(resid_vals^2)
          tss <- sum((resp - mean(resp))^2)
          r_squared <- if (tss > 0) 1 - rss / tss else NA_real_
          n <- length(resp); p <- length(co)
          resid_se <- if (n > p) sqrt(rss / (n - p)) else NA_real_
          aic_val  <- tryCatch(AIC(m), error = function(e) NA_real_)

          # Sampled fitted curve (log-spaced across observed concentration range)
          pos <- conc[conc > 0]
          if (length(pos) >= 2) {
            grid <- exp(seq(log(min(pos)), log(max(pos)), length.out = 50))
          } else {
            grid <- seq(min(conc), max(conc), length.out = 50)
          }
          pred <- tryCatch(predict(m, newdata = data.frame(conc = grid)),
                           error = function(e) rep(NA_real_, length(grid)))
          curve_df <- data.frame(concentration = grid, response = pred)
          write.csv(curve_df, "dose_response_curve.csv", row.names = FALSE)

          # Diagnostic plot
          ok <- tryCatch({
            pdf("dose_response_fit.pdf", width = 6, height = 5)
            plot(m, type = "all", main = sprintf("Dose-response fit (%s, %s=%.4g)",
                                                 model_name, potency_label, ed50),
                 xlab = "Concentration", ylab = "Response")
            dev.off(); TRUE
          }, error = function(e) { try(dev.off(), silent = TRUE); FALSE })

          res <- list(
            success = TRUE, function_ = "dose_response", domain = "biochemistry",
            mode = "drc_fit", model = model_name,
            fitter = "drc::drm", n_points = n,
            columns = list(concentration = c_col, response = r_col),
            potency = list(metric = potency_label, value = unname(ed50),
                           std_error = unname(se[grep("ED50", names(co))][1])),
            hill_slope = hill_slope,
            asymptotes = list(lower = lower, upper = upper),
            coefficients = as.list(co),
            std_errors = as.list(setNames(se, names(co))),
            goodness_of_fit = list(r_squared = r_squared, residual_std_error = resid_se,
                                   rss = rss, aic = aic_val)
          )
          jsonlite::write_json(res, "dose_response_results.json",
                               auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

          writeLines(c(
            "Biomni: Dose Response (drc fit)",
            paste(rep("=", 60), collapse = ""), "",
            sprintf("model: %s (fitter drc::drm)", model_name),
            sprintf("data points: %d  [conc='%s', resp='%s']", n, c_col, r_col),
            sprintf("%s: %.6g  (SE %.4g)", potency_label, ed50,
                    unname(se[grep("ED50", names(co))][1])),
            sprintf("Hill slope: %.6g", hill_slope),
            sprintf("asymptotes: lower=%.6g  upper=%.6g", lower, upper),
            sprintf("R^2: %.5f   residual SE: %.6g   AIC: %.4g",
                    r_squared, resid_se, aic_val),
            "", "Fitted curve -> dose_response_curve.csv",
            if (ok) "Diagnostic plot -> dose_response_fit.pdf" else "(plot skipped)"
          ), "dose_response_output.txt")
        }
      }
    }

    # versions
    .rv <- paste(R.version\$major, R.version\$minor, sep = ".")
    .dv <- tryCatch(as.character(utils::packageVersion("drc")), error = function(e) "NA")
    writeLines(c(
      "\\"${task.process}\\":",
      paste0("    r-base: ", .rv),
      paste0("    r-drc: ", .dv)
    ), "versions.yml")
    """
}

workflow DOSE_RESPONSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(data) ]  (data may be [] for scalar fallback)

    main:
    DOSE_RESPONSE(ch_input)

    emit:
    results  = DOSE_RESPONSE.out.results
    output   = DOSE_RESPONSE.out.output
    curve    = DOSE_RESPONSE.out.curve
    plot     = DOSE_RESPONSE.out.plot
    versions = DOSE_RESPONSE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Accept a data file via params.data; fall back to scalar Hill evaluation if absent
    ch_input = params.data \
        ? Channel.of([ [id: 'run'], file(params.data) ]) \
        : Channel.of([ [id: 'run'], [] ])

    DOSE_RESPONSE_WORKFLOW(ch_input)

    DOSE_RESPONSE_WORKFLOW.out.output.view { "Output: $it" }
}
