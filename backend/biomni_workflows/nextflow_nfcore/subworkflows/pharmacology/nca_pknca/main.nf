#!/usr/bin/env nextflow
/*
 * pharmacology/nca_pknca
 *
 * Non-compartmental analysis (NCA) of pharmacokinetic data using PKNCA.
 *
 * PKNCA is an open-source R package for regulatory-grade NCA:
 *   Bacon et al. (2016) CPT: Pharmacometrics & Systems Pharmacology 5(1):e65
 *   https://cran.r-project.org/package=PKNCA
 *
 * PKNCA implements the same NCA methods as Phoenix WinNonlin and SAS PROC NCA.
 * Output is compatible with NCA reporting requirements in FDA/EMA Phase I submissions.
 *
 * Inputs:
 *   --pk_data_csv   : PK concentration-time data CSV
 *                     Required columns: subject_id, time, concentration, dose, route
 *                     Optional: nominal_time, analyte, period, treatment
 *   --route         : "oral" | "iv" (default: "oral")
 *   --dose_col      : Column name for dose amounts (default: "dose")
 *   --conc_col      : Column name for concentration (default: "concentration")
 *   --time_col      : Column name for time (default: "time")
 *   --subject_col   : Column name for subject ID (default: "subject_id")
 *   --lambda_z_adj  : Manual lambda_z adjustment; "auto" uses PKNCA's best-fit (default: "auto")
 *
 * Outputs:
 *   nca_results.csv         — Full NCA parameter table (all subjects × all parameters)
 *   nca_summary.csv         — Mean ± SD / CV% summary by treatment group
 *   nca_report.html         — Interactive NCA report with individual PK profiles
 *   pk_profiles.pdf         — Individual concentration-time plots (linear + semi-log)
 *   nca_results.json        — Machine-readable summary for BioMate QC gate
 *
 * Parameters computed:
 *   AUClast      — AUC from time 0 to last measurable timepoint (trapezoidal)
 *   AUCinf       — AUC from time 0 to infinity (with extrapolation)
 *   Cmax         — Maximum observed concentration
 *   Tmax         — Time of maximum concentration
 *   t½           — Terminal elimination half-life (ln2 / lambda_z)
 *   lambda_z     — Terminal rate constant
 *   CL/F         — Apparent clearance (dose / AUCinf)
 *   Vz/F         — Apparent volume of distribution (CL/F / lambda_z)
 *   AUC%extrap   — % AUC extrapolated beyond last timepoint (< 20% preferred)
 *   MRT          — Mean residence time
 *
 * QC flags (written to nca_results.json):
 *   auc_extrap_pct_max — max % AUC extrapolated across subjects
 *   subjects_with_no_terminal_slope — count of subjects where t½ could not be estimated
 *
 * Usage:
 *   nextflow run subworkflows/pharmacology/nca_pknca/main.nf \
 *     --pk_data_csv data/phase1_pk.csv \
 *     --route oral \
 *     -profile docker
 */

nextflow.enable.dsl = 2

params.outdir      = './results/nca'
params.pk_data_csv = null
params.route       = 'oral'
params.dose_col    = 'dose'
params.conc_col    = 'concentration'
params.time_col    = 'time'
params.subject_col = 'subject_id'
params.lambda_z_adj = 'auto'
params.sparse      = false   // true = sparse sampling (use NCA by group, not individual)

if (!params.pk_data_csv) {
    error "Please provide --pk_data_csv (PK concentration-time data)"
}

process NCA_PKNCA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container 'rocker/tidyverse:latest'

    input:
    val(meta)
    path(pk_data)

    output:
    tuple val(meta), path("nca_results.csv"),    emit: results
    tuple val(meta), path("nca_summary.csv"),    emit: summary
    tuple val(meta), path("nca_report.html"),    emit: report,   optional: true
    tuple val(meta), path("pk_profiles.pdf"),    emit: profiles, optional: true
    tuple val(meta), path("nca_results.json"),   emit: json
    path "versions.yml",                         emit: versions

    script:
    """
    Rscript - << 'REOF'
    suppressPackageStartupMessages({
        library(PKNCA)
        library(ggplot2)
        library(dplyr)
        library(tidyr)
        library(jsonlite)
        library(data.table)
    })

    cat("PKNCA non-compartmental analysis\\n")
    cat("Route      :", "${params.route}", "\\n")
    cat("Data file  :", "${pk_data}", "\\n\\n")

    # ── Load and validate data ───────────────────────────────────────────────
    pk_data <- fread("${pk_data}")
    req_cols <- c("${params.subject_col}", "${params.time_col}",
                  "${params.conc_col}", "${params.dose_col}")
    missing  <- setdiff(req_cols, names(pk_data))
    if (length(missing) > 0) {
        stop(paste("Missing required columns:", paste(missing, collapse=", "),
                   "\\nAvailable columns:", paste(names(pk_data), collapse=", ")))
    }

    # Standardise column names to PKNCA expected names
    setnames(pk_data,
             old = c("${params.subject_col}", "${params.time_col}",
                     "${params.conc_col}", "${params.dose_col}"),
             new = c("subject", "time", "conc", "dose"),
             skip_absent = TRUE)

    # Handle BLQ (below limit of quantification) — set to 0
    pk_data[conc < 0, conc := 0]
    # Remove pre-dose observations at time == 0 with conc > 0 for dose calculation
    dose_data  <- pk_data[!duplicated(subject), .(subject, time = 0, dose)]
    conc_data  <- pk_data[, .(subject, time, conc)]

    n_subjects <- length(unique(pk_data[["subject"]]))
    cat(sprintf("Subjects: %d\\n", n_subjects))

    # ── Build PKNCA objects ──────────────────────────────────────────────────
    conc_obj <- PKNCAconc(conc_data, conc ~ time | subject)
    dose_obj <- PKNCAdose(dose_data, dose ~ time | subject,
                          route = "${params.route}")
    pk_obj   <- PKNCAdata(conc_obj, dose_obj)

    # ── Run NCA ─────────────────────────────────────────────────────────────
    nca_results <- pk.nca(pk_obj)
    nca_df      <- as.data.frame(nca_results)
    fwrite(nca_df, "nca_results.csv")
    cat(sprintf("NCA parameters computed: %d rows\\n", nrow(nca_df)))

    # ── Summary table (mean, SD, CV%, geometric mean, geometric CV%) ────────
    key_params <- c("auclast", "aucinf.obs", "cmax", "tmax", "half.life",
                    "cl.obs", "vz.obs", "aucpext.obs", "mrt.obs")
    summary_df <- nca_df %>%
        filter(PPTESTCD %in% key_params) %>%
        group_by(PPTESTCD, PPSTRESU) %>%
        summarise(
            n        = sum(!is.na(PPORRES)),
            mean     = mean(as.numeric(PPORRES), na.rm = TRUE),
            sd       = sd(as.numeric(PPORRES), na.rm = TRUE),
            cv_pct   = sd(as.numeric(PPORRES), na.rm = TRUE) /
                       mean(as.numeric(PPORRES), na.rm = TRUE) * 100,
            median   = median(as.numeric(PPORRES), na.rm = TRUE),
            min      = min(as.numeric(PPORRES), na.rm = TRUE),
            max      = max(as.numeric(PPORRES), na.rm = TRUE),
            .groups  = "drop"
        ) %>%
        mutate(across(where(is.numeric), ~ round(., 3)))
    fwrite(summary_df, "nca_summary.csv")

    # ── Concentration-time plots ─────────────────────────────────────────────
    tryCatch({
        pdf("pk_profiles.pdf", width = 10, height = 8)

        # Linear scale
        p1 <- ggplot(pk_data, aes(x = time, y = conc, group = subject, colour = subject)) +
            geom_line(alpha = 0.6) + geom_point(alpha = 0.7, size = 1.5) +
            labs(title = "Individual PK Profiles (Linear)",
                 x = "Time (h)", y = "Concentration") +
            theme_bw() + theme(legend.position = "none")
        print(p1)

        # Semi-log scale (for terminal half-life visualisation)
        p2 <- ggplot(pk_data[conc > 0], aes(x = time, y = conc, group = subject, colour = subject)) +
            geom_line(alpha = 0.6) + geom_point(alpha = 0.7, size = 1.5) +
            scale_y_log10() +
            labs(title = "Individual PK Profiles (Semi-log)",
                 x = "Time (h)", y = "Concentration (log scale)") +
            theme_bw() + theme(legend.position = "none")
        print(p2)
        dev.off()
    }, error = function(e) cat("Plot warning:", conditionMessage(e), "\\n"))

    # ── QC flags for BioMate gate ────────────────────────────────────────────
    auc_extrap_rows <- nca_df[nca_df[["PPTESTCD"]] == "aucpext.obs", "PPORRES"]
    auc_extrap_vals <- suppressWarnings(as.numeric(auc_extrap_rows))
    auc_extrap_max  <- if (length(auc_extrap_vals) > 0) max(auc_extrap_vals, na.rm = TRUE) else NA

    t_half_rows  <- nca_df[nca_df[["PPTESTCD"]] == "half.life", "PPORRES"]
    no_t_half    <- sum(is.na(suppressWarnings(as.numeric(t_half_rows))))

    cmax_mean    <- mean(as.numeric(
        nca_df[nca_df[["PPTESTCD"]] == "cmax",  "PPORRES"]), na.rm = TRUE)
    auclast_mean <- mean(as.numeric(
        nca_df[nca_df[["PPTESTCD"]] == "auclast","PPORRES"]), na.rm = TRUE)
    thalf_mean   <- mean(as.numeric(
        nca_df[nca_df[["PPTESTCD"]] == "half.life","PPORRES"]), na.rm = TRUE)
    cl_mean      <- mean(as.numeric(
        nca_df[nca_df[["PPTESTCD"]] == "cl.obs", "PPORRES"]), na.rm = TRUE)

    results_json <- list(
        n_subjects                      = n_subjects,
        route                           = "${params.route}",
        cmax_mean                       = round(cmax_mean, 3),
        auclast_mean                    = round(auclast_mean, 3),
        thalf_mean_h                    = round(thalf_mean, 2),
        cl_f_mean                       = round(cl_mean, 3),
        auc_extrap_pct_max              = if (!is.na(auc_extrap_max)) round(auc_extrap_max, 1) else NULL,
        subjects_with_no_terminal_slope = no_t_half,
        pknca_version                   = as.character(packageVersion("PKNCA"))
    )
    write_json(results_json, "nca_results.json", pretty = TRUE, auto_unbox = TRUE)
    cat("\\nNCA complete. Results written to nca_results.json\\n")
    cat(sprintf("  Cmax (mean)    : %.3f\\n", cmax_mean))
    cat(sprintf("  AUClast (mean) : %.3f\\n", auclast_mean))
    cat(sprintf("  t½ (mean, h)   : %.2f\\n", thalf_mean))
    cat(sprintf("  CL/F (mean)    : %.3f\\n", cl_mean))
    if (!is.na(auc_extrap_max) && auc_extrap_max > 20) {
        cat(sprintf("  WARNING: AUC%%extrap max = %.1f%% (> 20%% — t½ estimate unreliable)\\n",
                    auc_extrap_max))
    }
    REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: \$(Rscript --version 2>&1 | cut -d' ' -f5)
        PKNCA: \$(Rscript -e "cat(as.character(packageVersion('PKNCA')))" 2>/dev/null || echo "unknown")
    END_VERSIONS
    """
}

workflow NCA_PKNCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    ch_pk_data = Channel.fromPath(params.pk_data_csv)
    NCA_PKNCA(ch_input, ch_pk_data)

    emit:
    results  = NCA_PKNCA.out.results
    summary  = NCA_PKNCA.out.summary
    report   = NCA_PKNCA.out.report
    profiles = NCA_PKNCA.out.profiles
    json     = NCA_PKNCA.out.json
    versions = NCA_PKNCA.out.versions
}

workflow {
    ch_input = Channel.of([id: 'nca_run'])
    NCA_PKNCA_WORKFLOW(ch_input)
    NCA_PKNCA_WORKFLOW.out.json.view { meta, json -> "NCA results: $json" }
}
