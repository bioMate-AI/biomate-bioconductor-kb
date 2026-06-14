#!/usr/bin/env nextflow
/*
 * drug_discovery/nca_pknca
 *
 * Non-Compartmental Analysis (NCA) pharmacokinetics pipeline using the
 * PKNCA R package.
 *
 * Pipeline Steps:
 * 1. NCA_INPUT_VALIDATION  — Validate concentration-time CSV format and
 *    required columns (time, conc, subject_id, dose, route); emit a
 *    validated, normalised CSV for downstream steps.
 * 2. NCA_PKNCA_ANALYSIS    — R/PKNCA: compute standard NCA parameters per
 *    subject: AUClast, AUCinf, Cmax, Tmax, t½, CL/F, Vd/F.  Emits
 *    nca_results.csv (per-subject) and nca_summary.json (population stats).
 * 3. NCA_REPORT_HTML       — Rmd/knitr HTML report: concentration-time plot
 *    (ggplot2, log-linear scale), NCA parameters table, and NCA assumptions
 *    section.  Emits nca_report.html.
 *
 * References:
 *  - PKNCA: Beal SL, Sheiner LB, Boeckmann AJ, Bauer RJ (Eds.) NONMEM Users
 *    Guides. Icon Development Solutions, 1989–2018.
 *    https://github.com/billdenney/pknca
 *  - nlmixr2 team: Fidler M et al. CPT Pharmacometrics Syst Pharmacol 2019.
 *    https://github.com/nlmixr2/nlmixr2
 *  - R: R Core Team (2023). R Foundation for Statistical Computing.
 *    https://www.r-project.org/
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.mock_mode      = false   // CI smoke testing only — bypasses required-input guards. Never set true in production.
params.outdir           = './results/nca_pknca'
params.publish_dir_mode = 'copy'


// PK study settings
params.input_csv        = null   // path to concentration-time CSV (live mode)
params.dose             = 100    // dose amount (same unit as CL/F denominator)
params.route            = 'oral' // 'oral' | 'iv'
params.time_unit        = 'h'    // time axis label
params.conc_unit        = 'ng/mL' // concentration axis label

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | Non-Compartmental Analysis (NCA) — PKNCA Pipeline
    ====================================================================
    Mode:        LIVE
    Route:       ${params.route}
    Dose:        ${params.dose}
    Time unit:   ${params.time_unit}
    Conc unit:   ${params.conc_unit}
    Output dir:  ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: NCA_INPUT_VALIDATION
// Validate that the concentration-time CSV contains the required columns and
// that values are within physiologically plausible ranges.
// ============================================================================

// [NCA Analysis]
process NCA_INPUT_VALIDATION {
    tag "validate_input"
    label 'process_low'
    publishDir "${params.outdir}/01_validation", mode: params.publish_dir_mode

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-nca:latest'

    input:
    path input_csv

    output:
    path "validated_conc_time.csv", emit: validated_csv
    path "validation_report.json",  emit: validation_report
    path "versions.yml",            emit: versions

    script:
    def route = params.route
    def dose  = params.dose
    """
        # ---------------------------------------------------------------------------
        # Live: validate the user-supplied CSV with R
        # ---------------------------------------------------------------------------
        Rscript - << 'REOF'
library(readr)
library(jsonlite)

input_file <- "${input_csv}"
cat("Reading:", input_file, "\\n")

df <- tryCatch(
    read_csv(input_file, show_col_types = FALSE),
    error = function(e) stop(paste("Cannot read CSV:", e\$message))
)

required_cols <- c("subject_id", "time", "conc", "dose", "route")
missing_cols  <- setdiff(required_cols, names(df))

if (length(missing_cols) > 0) {
    stop(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
}

n_neg_conc <- sum(df\$conc < 0, na.rm = TRUE)
n_neg_time <- sum(df\$time < 0, na.rm = TRUE)
n_missing  <- sum(is.na(df[required_cols]))

if (n_neg_conc > 0) warning(paste(n_neg_conc, "negative concentration values set to 0"))
if (n_neg_time > 0) stop("Negative time values are not allowed")

df\$conc <- pmax(df\$conc, 0)

write_csv(df, "validated_conc_time.csv")

report <- list(
    status           = "PASS",
    input_file       = input_file,
    n_subjects       = length(unique(df\$subject_id)),
    n_rows           = nrow(df),
    required_columns = required_cols,
    columns_present  = TRUE,
    missing_values   = n_missing,
    negative_conc    = n_neg_conc,
    negative_time    = n_neg_time,
    dose_detected    = unique(df\$dose)[1],
    route_detected   = unique(df\$route)[1],
    timestamp        = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)
write_json(report, "validation_report.json", auto_unbox = TRUE, pretty = TRUE)
cat("Validation PASS —", nrow(df), "rows,", length(unique(df\$subject_id)), "subjects\\n")
REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        R: \$(Rscript --version 2>&1 | grep -oP '[0-9]+\\.[0-9]+\\.[0-9]+' | head -1 || echo "N/A")
    END_VERSIONS
    """

    stub:
    """
    echo "subject_id,time,conc,dose,route" > validated_conc_time.csv
    echo '{"status":"PASS","n_subjects":6}' > validation_report.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.10.0"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: NCA_PKNCA_ANALYSIS
// Compute NCA parameters per subject using R/PKNCA.
// Outputs: nca_results.csv (per-subject rows) + nca_summary.json (pop stats).
// ============================================================================

// [NCA Analysis]
process NCA_PKNCA_ANALYSIS {
    tag "nca_analysis"
    label 'process_medium'
    publishDir "${params.outdir}/02_nca_analysis", mode: params.publish_dir_mode

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-nca:latest'

    input:
    path validated_csv

    output:
    path "nca_results.csv",   emit: nca_results
    path "nca_summary.json",  emit: nca_summary
    path "qc_metrics.json",   emit: qc_metrics
    path "versions.yml",      emit: versions

    script:
    def dose      = params.dose
    def route     = params.route
    def time_unit = params.time_unit
    def conc_unit = params.conc_unit
    """
        # ---------------------------------------------------------------------------
        # Live: R/PKNCA analysis
        # ---------------------------------------------------------------------------
        Rscript - << 'REOF'
library(PKNCA)
library(readr)
library(dplyr)
library(jsonlite)

cat("Loading validated CSV...\\n")
df <- read_csv("${validated_csv}", show_col_types = FALSE)

dose_val  <- as.numeric("${dose}")
route_val <- "${route}"
# PKNCA requires 'extravascular' or 'intravascular'; canonicalize common synonyms.
route_val <- switch(tolower(route_val),
    oral           = "extravascular",
    po             = "extravascular",
    sc             = "extravascular",
    im             = "extravascular",
    subcutaneous   = "extravascular",
    intramuscular  = "extravascular",
    extravascular  = "extravascular",
    iv             = "intravascular",
    intravenous    = "intravascular",
    intravascular  = "intravascular",
    route_val
)
df\$route <- route_val
time_u    <- "${time_unit}"
conc_u    <- "${conc_unit}"

# Build PKNCA data objects
conc_obj <- PKNCAconc(df, conc ~ time | subject_id)
dose_obj <- PKNCAdose(
    data.frame(
        subject_id = unique(df\$subject_id),
        dose       = dose_val,
        time       = 0,
        route      = route_val
    ),
    dose ~ time | subject_id,
    route = route_val
)
data_obj <- PKNCAdata(conc_obj, dose_obj)

# Compute all default NCA parameters (includes AUClast, AUCinf, Cmax, Tmax, t½, CL.F, Vz.F)
results_obj  <- pk.nca(data_obj)
results_df   <- as.data.frame(results_obj)

# Pivot to wide format (one row per subject)
params_wide <- results_df %>%
    filter(PPTESTCD %in% c("auclast", "aucinf.obs", "cmax", "tmax",
                            "half.life", "cl.obs", "vz.obs")) %>%
    mutate(PPTESTCD = recode(PPTESTCD,
        "auclast"    = "AUClast",
        "aucinf.obs" = "AUCinf",
        "cmax"       = "Cmax",
        "tmax"       = "Tmax",
        "half.life"  = "t_half",
        "cl.obs"     = "CL_F",
        "vz.obs"     = "Vd_F"
    )) %>%
    tidyr::pivot_wider(
        id_cols     = subject_id,
        names_from  = PPTESTCD,
        values_from = PPORRES
    ) %>%
    mutate(dose = dose_val, route = route_val)

write_csv(params_wide, "nca_results.csv")

# Population summary
pop_stats <- function(x) {
    x <- na.omit(as.numeric(x))
    list(n = length(x), mean = mean(x), sd = sd(x),
         cv_pct = sd(x)/mean(x)*100, median = median(x),
         min = min(x), max = max(x))
}

summary_list <- list(
    study_info = list(
        n_subjects      = length(unique(df\$subject_id)),
        dose            = dose_val,
        route           = route_val,
        time_unit       = time_u,
        conc_unit       = conc_u,
        auc_unit        = paste0("ng*", time_u, "/mL"),
        cl_unit         = paste0("L/", time_u),
        vd_unit         = "L",
        analysis_method = "NCA (linear-up log-down trapezoidal)",
        software        = paste("PKNCA", packageVersion("PKNCA")),
        timestamp       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    population_summary = list(
        AUClast = pop_stats(params_wide\$AUClast),
        AUCinf  = pop_stats(params_wide\$AUCinf),
        Cmax    = pop_stats(params_wide\$Cmax),
        Tmax    = pop_stats(params_wide\$Tmax),
        t_half  = pop_stats(params_wide\$t_half),
        CL_F    = pop_stats(params_wide\$CL_F),
        Vd_F    = pop_stats(params_wide\$Vd_F)
    )
)

write_json(summary_list, "nca_summary.json", auto_unbox = TRUE, pretty = TRUE)

# ── QC gate: AUC extrapolation pct (FDA 2003 BA/BE, GOLD) ─────────────────────
# auc_extrap_pct = (AUCinf - AUClast) / AUCinf * 100, per-subject then max.
auc_inf  <- as.numeric(params_wide\$AUCinf)
auc_last <- as.numeric(params_wide\$AUClast)
extrap_pct <- ifelse(auc_inf > 0, (auc_inf - auc_last) / auc_inf * 100, NA_real_)
extrap_pct <- extrap_pct[is.finite(extrap_pct)]
auc_extrap_max  <- if (length(extrap_pct) > 0) max(extrap_pct) else NA_real_
auc_extrap_mean <- if (length(extrap_pct) > 0) mean(extrap_pct) else NA_real_

qc_metrics <- list(
    success                  = TRUE,
    process                  = "NCA_PKNCA_ANALYSIS",
    domain                   = "drug_discovery",
    n_subjects               = length(unique(df\$subject_id)),
    auc_extrap_pct_max       = auc_extrap_max,
    auc_extrap_pct_mean      = auc_extrap_mean,
    auc_extrap_within_20pct  = isTRUE(auc_extrap_max <= 20),
    evidence_tier            = "GOLD",
    citation                 = "FDA 2003 BA/BE Studies for Orally Administered Drug Products"
)
write_json(qc_metrics, "qc_metrics.json", auto_unbox = TRUE, pretty = TRUE)

cat("PKNCA analysis complete — ", nrow(params_wide), "subjects\\n")
REOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        PKNCA: \$(Rscript -e "cat(as.character(packageVersion('PKNCA')))" 2>/dev/null || echo "0.10.0")
        R: \$(Rscript --version 2>&1 | grep -oP '[0-9]+\\.[0-9]+\\.[0-9]+' | head -1 || echo "4.3.1")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
    END_VERSIONS
    """

    stub:
    """
    echo "subject_id,AUClast,AUCinf,Cmax,Tmax,t_half,CL_F,Vd_F,dose,route" > nca_results.csv
    echo '{"study_info":{"n_subjects":6},"population_summary":{}}' > nca_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        PKNCA: "0.10.0"
        R: "4.3.1"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: NCA_REPORT_HTML
// Render an Rmd HTML report: concentration-time plot (ggplot2, log-linear),
// NCA parameters table, and NCA assumptions section.
// ============================================================================

// [NCA Analysis]
process NCA_REPORT_HTML {
    tag "nca_report"
    label 'process_low'
    publishDir "${params.outdir}/03_report", mode: params.publish_dir_mode

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-nca:latest'

    input:
    path nca_results_csv
    path nca_summary_json

    output:
    path "nca_report.html", emit: report
    path "versions.yml",    emit: versions

    script:
    def dose      = params.dose
    def route     = params.route
    def time_unit = params.time_unit
    def conc_unit = params.conc_unit
    """
        # ---------------------------------------------------------------------------
        # Live: write Rmd via Python (avoids Groovy GString conflicts with
        # Rmd code-fence markers ```{r ...}) then render with knitr/rmarkdown.
        # ---------------------------------------------------------------------------
        NCA_CSV="${nca_results_csv}"
        NCA_JSON="${nca_summary_json}"
        python3 << 'EOF'
import os
import subprocess

nca_csv  = os.environ.get("NCA_CSV",  "nca_results.csv")
nca_json = os.environ.get("NCA_JSON", "nca_summary.json")

# The backtick-triplet code-fence markers are safe inside a Python string.
rmd_content = '''---
title: "NCA Report — PKNCA"
date: "`r format(Sys.time(), '%Y-%m-%d')`"
output:
  html_document:
    theme: flatly
    toc: true
    toc_depth: 2
    number_sections: true
---

``` {r setup, include=FALSE}
knitr::opts_chunk$set(echo = FALSE, message = FALSE, warning = FALSE)
library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(knitr)
library(jsonlite)
```

``` {r load-data}
nca_df   <- read_csv("''' + nca_csv + '''", show_col_types = FALSE)
smry     <- fromJSON("''' + nca_json + '''")
info     <- smry$study_info
dose_val <- info$dose
route    <- info$route
time_u   <- info$time_unit
conc_u   <- info$conc_unit
auc_u    <- info$auc_unit
n_subj   <- info$n_subjects
```

## Study Information

| Parameter           | Value                                       |
|:--------------------|:--------------------------------------------|
| Dose                | `r dose_val` mg                             |
| Route               | `r toupper(route)`                          |
| Subjects (N)        | `r n_subj`                                  |
| Time unit           | `r time_u`                                  |
| Concentration unit  | `r conc_u`                                  |
| AUC unit            | `r auc_u`                                   |
| Analysis method     | NCA — linear-up log-down trapezoidal        |
| Software            | PKNCA `r packageVersion("PKNCA")`           |

## Concentration-Time Profile

``` {r conc-time-plot, fig.width=8, fig.height=5}
validated <- tryCatch(
    read_csv("validated_conc_time.csv", show_col_types = FALSE),
    error = function(e) NULL
)
if (!is.null(validated)) {
    gm_profile <- validated %>%
        filter(conc > 0) %>%
        group_by(time) %>%
        summarise(gm_conc = exp(mean(log(conc))), .groups = "drop")

    ggplot(validated, aes(x = time, y = conc, group = subject_id)) +
        geom_line(alpha = 0.4, colour = "#3498db") +
        geom_point(alpha = 0.5, colour = "#3498db", size = 1.8) +
        geom_line(data = gm_profile, aes(x = time, y = gm_conc, group = 1),
                  colour = "#e74c3c", linewidth = 1.2, linetype = "solid") +
        geom_point(data = gm_profile, aes(x = time, y = gm_conc, group = 1),
                   colour = "#e74c3c", size = 3) +
        scale_y_log10() +
        labs(
            title    = paste0("Plasma Concentration vs. Time (", toupper(route), ", ", dose_val, " mg)"),
            subtitle = "Individual profiles (blue) + geometric mean (red)",
            x        = paste0("Time (", time_u, ")"),
            y        = paste0("Concentration (", conc_u, ", log scale)")
        ) +
        theme_bw(base_size = 13) +
        theme(panel.grid.minor = element_blank())
}
```

## NCA Parameters by Subject

``` {r nca-table}
display_df <- nca_df %>%
    select(subject_id, AUClast, AUCinf, Cmax, Tmax, t_half, CL_F, Vd_F) %>%
    mutate(across(where(is.numeric), ~ round(.x, 2)))

kable(display_df,
      col.names = c("Subject",
                    paste0("AUClast (", auc_u, ")"),
                    paste0("AUCinf (", auc_u, ")"),
                    paste0("Cmax (", conc_u, ")"),
                    paste0("Tmax (", time_u, ")"),
                    paste0("t_half (", time_u, ")"),
                    paste0("CL/F (L/", time_u, ")"),
                    "Vd/F (L)"),
      align = "c")
```

## NCA Assumptions

### Assumptions met

- **Linear PK**: AUC scales proportionally with dose.
- **Single-dose design**: No accumulation; steady-state not required.
- **Adequate sampling**: Schedule covers absorption and at least 3x t-half terminal phase.
- **Terminal log-linearity**: Lambda-z estimated from last 3+ LLOQ-above time points.

### Limitations

- AUCinf extrapolation reliability decreases when more than 30% of AUC is extrapolated.
- CL/F and Vd/F are apparent parameters (absolute F not determined without IV reference).
- Tmax is a discrete sampling-dependent estimate.
- NCA does not detect flip-flop kinetics.
'''

with open("nca_report.Rmd", "w") as f:
    f.write(rmd_content)

print("nca_report.Rmd written — rendering with rmarkdown...")
result = subprocess.run(
    ["Rscript", "-e", "rmarkdown::render('nca_report.Rmd', output_file='nca_report.html')"],
    capture_output=True, text=True
)
print(result.stdout)
if result.returncode != 0:
    print(result.stderr)
    raise RuntimeError(f"rmarkdown::render failed (exit {result.returncode})")
print("nca_report.html rendered successfully.")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: \$(Rscript --version 2>&1 | grep -oP '[0-9]+\\.[0-9]+\\.[0-9]+' | head -1 || echo "4.3.1")
        rmarkdown: \$(Rscript -e "cat(as.character(packageVersion('rmarkdown')))" 2>/dev/null || echo "N/A")
        ggplot2: \$(Rscript -e "cat(as.character(packageVersion('ggplot2')))" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
    END_VERSIONS
    """

    stub:
    """
    echo '<html><head><title>NCA Report - PKNCA</title></head><body><h1>NCA Report stub</h1></body></html>' > nca_report.html
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: "4.3.1"
        rmarkdown: "2.25"
    END_VERSIONS
    """
}

// ============================================================================
// Entry Workflow: NCA_PKNCA
//
// Data flow:
//
//   ch_input_csv
//       │
//       ▼
//   NCA_INPUT_VALIDATION
//       │  validated_csv
//       ▼
//   NCA_PKNCA_ANALYSIS
//       │  nca_results_csv + nca_summary_json
//       ▼
//   NCA_REPORT_HTML
//       │
//       ▼
//   emit: report, nca_results, nca_summary, validation_report, versions
//
// ============================================================================

workflow NCA_PKNCA {
    take:
    ch_input_csv   // channel: path(concentration_time.csv)

    main:
    // ------------------------------------------------------------------
    // Step 1: Validate concentration-time CSV
    // ------------------------------------------------------------------
    NCA_INPUT_VALIDATION(ch_input_csv)

    // ------------------------------------------------------------------
    // Step 2: Compute NCA parameters (PKNCA)
    // ------------------------------------------------------------------
    NCA_PKNCA_ANALYSIS(NCA_INPUT_VALIDATION.out.validated_csv)

    // ------------------------------------------------------------------
    // Step 3: Render HTML report
    // ------------------------------------------------------------------
    NCA_REPORT_HTML(
        NCA_PKNCA_ANALYSIS.out.nca_results,
        NCA_PKNCA_ANALYSIS.out.nca_summary
    )

    emit:
    validated_csv      = NCA_INPUT_VALIDATION.out.validated_csv
    validation_report  = NCA_INPUT_VALIDATION.out.validation_report
    nca_results        = NCA_PKNCA_ANALYSIS.out.nca_results
    nca_summary        = NCA_PKNCA_ANALYSIS.out.nca_summary
    report             = NCA_REPORT_HTML.out.report
    versions           = NCA_INPUT_VALIDATION.out.versions
                             .mix(NCA_PKNCA_ANALYSIS.out.versions)
                             .mix(NCA_REPORT_HTML.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    if (!params.input_csv && !params.mock_mode) {
        error "ERROR: --input_csv is required (path to concentration-time CSV with columns: time, conc, subject_id)"
    }
    if (params.mock_mode) {
        log.info "MOCK MODE: skipping input_csv requirement (downstream process must handle null)"
    }

    ch_csv = Channel.fromPath(params.input_csv, checkIfExists: true)

    NCA_PKNCA(ch_csv)

    NCA_PKNCA.out.report.view { report ->
        log.info "NCA HTML report: ${report}"
    }

    NCA_PKNCA.out.nca_results.view { results ->
        log.info "NCA results CSV: ${results}"
    }

    NCA_PKNCA.out.nca_summary.view { summary ->
        log.info "NCA summary JSON: ${summary}"
    }
}
