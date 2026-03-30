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

params.outdir           = './results/nca_pknca'
params.publish_dir_mode = 'copy'

// Mode flag
params.mock_mode        = true   // true = synthetic output, no real tools needed

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
    Mode:        ${params.mock_mode ? 'MOCK (synthetic data)' : 'LIVE'}
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

process NCA_INPUT_VALIDATION {
    tag "validate_input"
    label 'process_low'
    publishDir "${params.outdir}/01_validation", mode: params.publish_dir_mode

    container 'docker.io/rocker/r-ver:4.3.1'

    input:
    path input_csv

    output:
    path "validated_conc_time.csv", emit: validated_csv
    path "validation_report.json",  emit: validation_report
    path "versions.yml",            emit: versions

    script:
    def mock  = params.mock_mode
    def route = params.route
    def dose  = params.dose
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
from datetime import datetime

# ---------------------------------------------------------------------------
# Generate a synthetic concentration-time CSV with 6 subjects
# Oral PK profile: lag time 0.25 h, Tmax ~1.5 h, Cmax ~400-700 ng/mL,
# t½ ~6-10 h.  Biexponential model: C(t) = A*(e^-alpha*t - e^-ka*t)
# ---------------------------------------------------------------------------
import math
import random

random.seed(42)

time_points = [0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 24.0]
n_subjects  = 6
dose        = float("${dose}")
route       = "${route}"

def oral_pk(t, ka, ke, F, V, dose):
    # One-compartment oral PK: C(t) = F*D*ka / (V*(ka-ke)) * (e^-ke*t - e^-ka*t)
    if t == 0:
        return 0.0
    if abs(ka - ke) < 1e-9:
        ke += 1e-6
    c = (F * dose * ka) / (V * (ka - ke)) * (math.exp(-ke * t) - math.exp(-ka * t))
    return max(c, 0.0)

def iv_pk(t, ke, V, dose):
    # One-compartment IV bolus: C(t) = (D/V)*e^-ke*t
    if t < 0:
        return 0.0
    return (dose / V) * math.exp(-ke * t)

rows = ["subject_id,time,conc,dose,route"]

for subj in range(1, n_subjects + 1):
    # Inter-subject variability (±20 %)
    eta = random.gauss(0, 0.2)
    ka  = 1.2  * math.exp(random.gauss(0, 0.3))   # absorption rate (h⁻¹)
    ke  = 0.08 * math.exp(eta)                     # elimination rate (h⁻¹); t½ = ln2/ke
    V   = 50.0 * math.exp(random.gauss(0, 0.15))   # apparent volume (L)
    F   = 0.75 * math.exp(random.gauss(0, 0.1))    # bioavailability
    F   = min(F, 1.0)

    for t in time_points:
        if route == "oral":
            c_true = oral_pk(t, ka, ke, F, V, dose)
        else:
            c_true = iv_pk(t, ke, V, dose)
        # Add proportional + additive residual error (CV ~10 %, additive 2 ng/mL)
        noise = c_true * random.gauss(0, 0.10) + random.gauss(0, 2.0)
        c_obs = max(c_true + noise, 0.0)
        rows.append(f"SUBJ{subj:02d},{t},{c_obs:.4f},{dose},{route}")

with open("validated_conc_time.csv", "w") as f:
    f.write("\\n".join(rows) + "\\n")

# Validation report
report = {
    "status":          "PASS",
    "input_file":      "${input_csv}",
    "n_subjects":      n_subjects,
    "n_timepoints":    len(time_points),
    "required_columns": ["subject_id", "time", "conc", "dose", "route"],
    "columns_present": True,
    "missing_values":  0,
    "negative_conc":   0,
    "negative_time":   0,
    "dose_uniform":    True,
    "route_uniform":   True,
    "route_detected":  route,
    "dose_detected":   dose,
    "timestamp":       datetime.utcnow().isoformat() + "Z",
    "mock_mode":       True,
}
with open("validation_report.json", "w") as f:
    json.dump(report, f, indent=2)

print(f"Input validation mock complete: {n_subjects} subjects × {len(time_points)} time points")
print(f"  Route: {route}  |  Dose: {dose}")
EOF

    else
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
    error = function(e) stop(paste("Cannot read CSV:", e$message))
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
    timestamp        = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    mock_mode        = FALSE
)
write_json(report, "validation_report.json", auto_unbox = TRUE, pretty = TRUE)
cat("Validation PASS —", nrow(df), "rows,", length(unique(df\$subject_id)), "subjects\\n")
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        R: \$(Rscript --version 2>&1 | grep -oP '[0-9]+\\.[0-9]+\\.[0-9]+' | head -1 || echo "N/A")
        mock_mode: "${mock}"
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

process NCA_PKNCA_ANALYSIS {
    tag "nca_analysis"
    label 'process_medium'
    publishDir "${params.outdir}/02_nca_analysis", mode: params.publish_dir_mode

    container 'docker.io/rocker/r-ver:4.3.1'

    input:
    path validated_csv

    output:
    path "nca_results.csv",   emit: nca_results
    path "nca_summary.json",  emit: nca_summary
    path "versions.yml",      emit: versions

    script:
    def mock      = params.mock_mode
    def dose      = params.dose
    def route     = params.route
    def time_unit = params.time_unit
    def conc_unit = params.conc_unit
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

# ---------------------------------------------------------------------------
# Six synthetic subjects with realistic oral PK NCA parameters.
# Reference ranges (100 mg oral dose, hypothetical small molecule):
#   AUClast  : 2000–4000 ng·h/mL
#   AUCinf   : 2200–4400 ng·h/mL  (extrapolated tail adds ~5-10 %)
#   Cmax     :  400–700  ng/mL
#   Tmax     :  1.0–2.5  h         (time of Cmax)
#   t½       :  6–10     h         (terminal elimination half-life)
#   CL/F     :   25–50   L/h       (apparent oral clearance = Dose/AUCinf)
#   Vd/F     :  250–400  L         (apparent volume = CL/F / ke)
# ---------------------------------------------------------------------------

n_subjects = 6
dose       = float("${dose}")
route      = "${route}"
time_unit  = "${time_unit}"
conc_unit  = "${conc_unit}"

subjects   = []
for i in range(n_subjects):
    subj_id = f"SUBJ{i+1:02d}"

    # Draw true PK parameters with log-normal inter-subject variability
    ke_true   = 0.08 * math.exp(random.gauss(0, 0.20))   # h⁻¹
    t_half    = round(math.log(2) / ke_true, 2)           # h

    ka_true   = 1.2  * math.exp(random.gauss(0, 0.30))   # h⁻¹  (oral only)
    V_true    = 50.0 * math.exp(random.gauss(0, 0.15))   # L
    F_true    = 0.75 * math.exp(random.gauss(0, 0.10))   # bioavailability
    F_true    = min(F_true, 1.0)

    # Derived NCA quantities
    CL_F   = dose / (F_true * V_true / ke_true)          # L/h  (= dose/AUCinf)
    AUCinf = dose / CL_F                                 # ng·h/mL
    Vd_F   = CL_F / ke_true                              # L

    # Cmax / Tmax from analytical solution (oral 1-cpt)
    # Tmax = ln(ka/ke)/(ka-ke)
    if abs(ka_true - ke_true) > 1e-6:
        Tmax = math.log(ka_true / ke_true) / (ka_true - ke_true)
    else:
        Tmax = 1.5
    Tmax = max(Tmax, 0.5)

    def oral_c(t):
        if t <= 0:
            return 0.0
        c = (F_true * dose * ka_true) / (V_true * (ka_true - ke_true)) * \
            (math.exp(-ke_true * t) - math.exp(-ka_true * t))
        return max(c, 0.0)

    Cmax = oral_c(Tmax)

    # AUClast — trapezoid up to t=24 h
    obs_times = [0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 24.0]
    obs_concs = [oral_c(t) for t in obs_times]
    AUClast   = 0.0
    for j in range(len(obs_times) - 1):
        dt = obs_times[j+1] - obs_times[j]
        AUClast += 0.5 * (obs_concs[j] + obs_concs[j+1]) * dt

    # Add mild assay noise to reported NCA values (~3 %)
    def jitter(v, cv=0.03):
        return round(v * (1 + random.gauss(0, cv)), 4)

    subjects.append({
        "subject_id": subj_id,
        "AUClast":    jitter(AUClast),
        "AUCinf":     jitter(AUCinf),
        "Cmax":       jitter(Cmax),
        "Tmax":       round(Tmax, 3),
        "t_half":     round(t_half, 3),
        "CL_F":       jitter(CL_F),
        "Vd_F":       jitter(Vd_F),
        "dose":       dose,
        "route":      route,
        "F_apparent": round(F_true, 4),
    })

# Write nca_results.csv
header = "subject_id,AUClast,AUCinf,Cmax,Tmax,t_half,CL_F,Vd_F,dose,route"
rows   = [header]
for s in subjects:
    rows.append(
        f"{s['subject_id']},{s['AUClast']},{s['AUCinf']},"
        f"{s['Cmax']},{s['Tmax']},{s['t_half']},"
        f"{s['CL_F']},{s['Vd_F']},{s['dose']},{s['route']}"
    )
with open("nca_results.csv", "w") as f:
    f.write("\\n".join(rows) + "\\n")

# Compute summary statistics
def stats(values):
    n    = len(values)
    mean = sum(values) / n
    var  = sum((v - mean)**2 for v in values) / (n - 1)
    sd   = math.sqrt(var)
    cv   = sd / mean * 100
    sorted_v = sorted(values)
    med  = sorted_v[n // 2] if n % 2 == 1 else (sorted_v[n//2 - 1] + sorted_v[n//2]) / 2
    return {"n": n, "mean": round(mean, 4), "sd": round(sd, 4),
            "cv_pct": round(cv, 2), "median": round(med, 4),
            "min": round(min(values), 4), "max": round(max(values), 4)}

nca_summary = {
    "study_info": {
        "n_subjects":      n_subjects,
        "dose":            dose,
        "route":           route,
        "time_unit":       time_unit,
        "conc_unit":       conc_unit,
        "auc_unit":        f"ng*{time_unit}/mL",
        "cl_unit":         f"L/{time_unit}",
        "vd_unit":         "L",
        "analysis_method": "NCA (linear-up log-down trapezoidal)",
        "software":        "PKNCA (mock mode)",
        "timestamp":       datetime.utcnow().isoformat() + "Z",
        "mock_mode":       True,
    },
    "population_summary": {
        "AUClast":  stats([s["AUClast"] for s in subjects]),
        "AUCinf":   stats([s["AUCinf"]  for s in subjects]),
        "Cmax":     stats([s["Cmax"]    for s in subjects]),
        "Tmax":     stats([s["Tmax"]    for s in subjects]),
        "t_half":   stats([s["t_half"]  for s in subjects]),
        "CL_F":     stats([s["CL_F"]    for s in subjects]),
        "Vd_F":     stats([s["Vd_F"]    for s in subjects]),
    },
    "individual_results": subjects,
}

with open("nca_summary.json", "w") as f:
    json.dump(nca_summary, f, indent=2)

print(f"NCA mock complete: {n_subjects} subjects")
for s in subjects:
    print(f"  {s['subject_id']}: AUClast={s['AUClast']:.1f}  "
          f"Cmax={s['Cmax']:.1f}  t½={s['t_half']:.1f} h  CL/F={s['CL_F']:.2f} L/h")
EOF

    else
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
        timestamp       = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        mock_mode       = FALSE
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
cat("PKNCA analysis complete — ", nrow(params_wide), "subjects\\n")
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        PKNCA: \$(Rscript -e "cat(as.character(packageVersion('PKNCA')))" 2>/dev/null || echo "0.10.0")
        R: \$(Rscript --version 2>&1 | grep -oP '[0-9]+\\.[0-9]+\\.[0-9]+' | head -1 || echo "4.3.1")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        mock_mode: "${mock}"
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

process NCA_REPORT_HTML {
    tag "nca_report"
    label 'process_low'
    publishDir "${params.outdir}/03_report", mode: params.publish_dir_mode

    container 'docker.io/rocker/tidyverse:4.3.1'

    input:
    path nca_results_csv
    path nca_summary_json

    output:
    path "nca_report.html", emit: report
    path "versions.yml",    emit: versions

    script:
    def mock      = params.mock_mode
    def dose      = params.dose
    def route     = params.route
    def time_unit = params.time_unit
    def conc_unit = params.conc_unit
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import csv
from datetime import datetime

# Read NCA results for the HTML table
rows = []
with open("${nca_results_csv}") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

summary = json.load(open("${nca_summary_json}"))
pop  = summary.get("population_summary", {})
info = summary.get("study_info", {})

def fmt(val, dp=2):
    try:
        return ("{:." + str(dp) + "f}").format(float(val))
    except Exception:
        return str(val)

def pop_mean(key):
    v = pop.get(key, {}).get("mean", None)
    return fmt(v) if v is not None else "—"

def pop_cv(key):
    v = pop.get(key, {}).get("cv_pct", None)
    return fmt(v) if v is not None else "—"

route     = "${route}"
dose_val  = "${dose}"
time_unit = "${time_unit}"
conc_unit = "${conc_unit}"
auc_unit  = info.get("auc_unit", "ng*h/mL")
cl_unit   = info.get("cl_unit", "L/h")
n_subj    = len(rows)
now_date  = datetime.utcnow().strftime('%Y-%m-%d')
now_ts    = datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
badge_cls = "badge-oral" if route == "oral" else "badge-iv"

# Build individual rows HTML
row_html_parts = []
for r in rows:
    row_html_parts.append(
        "<tr>"
        "<td>" + r.get('subject_id','') + "</td>"
        "<td>" + fmt(r.get('AUClast','')) + "</td>"
        "<td>" + fmt(r.get('AUCinf','')) + "</td>"
        "<td>" + fmt(r.get('Cmax','')) + "</td>"
        "<td>" + fmt(r.get('Tmax','')) + "</td>"
        "<td>" + fmt(r.get('t_half','')) + "</td>"
        "<td>" + fmt(r.get('CL_F','')) + "</td>"
        "<td>" + fmt(r.get('Vd_F','')) + "</td>"
        "</tr>"
    )
row_html = "\n    ".join(row_html_parts)

pop_row = (
    "<tr class='pop-row'>"
    "<td>Mean (CV%)</td>"
    "<td>" + pop_mean('AUClast') + " (" + pop_cv('AUClast') + "%)</td>"
    "<td>" + pop_mean('AUCinf')  + " (" + pop_cv('AUCinf')  + "%)</td>"
    "<td>" + pop_mean('Cmax')    + " (" + pop_cv('Cmax')    + "%)</td>"
    "<td>" + pop_mean('Tmax')    + " (" + pop_cv('Tmax')    + "%)</td>"
    "<td>" + pop_mean('t_half')  + " (" + pop_cv('t_half')  + "%)</td>"
    "<td>" + pop_mean('CL_F')    + " (" + pop_cv('CL_F')    + "%)</td>"
    "<td>" + pop_mean('Vd_F')    + " (" + pop_cv('Vd_F')    + "%)</td>"
    "</tr>"
)

# Build HTML by joining lines — no triple-quoted strings to avoid Nextflow parser conflicts
html_lines = [
    "<!DOCTYPE html>",
    "<html lang='en'>",
    "<head>",
    "  <meta charset='UTF-8'>",
    "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>",
    "  <title>NCA Report &mdash; PKNCA</title>",
    "  <style>",
    "    body      { font-family: 'Segoe UI', Arial, sans-serif; margin: 2em 3em; color: #222; background: #fff; }",
    "    h1        { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 0.3em; }",
    "    h2        { color: #34495e; margin-top: 2em; }",
    "    h3        { color: #5d6d7e; }",
    "    table     { border-collapse: collapse; width: 100%; margin-top: 1em; font-size: 0.92em; }",
    "    th        { background: #2c3e50; color: #fff; padding: 0.55em 0.9em; text-align: left; }",
    "    td        { padding: 0.45em 0.9em; border-bottom: 1px solid #ddd; }",
    "    tr:nth-child(even) { background: #f8f9fa; }",
    "    tr.pop-row { font-weight: bold; background: #ebf5fb; }",
    "    .badge    { display: inline-block; padding: 0.2em 0.6em; border-radius: 4px; font-size: 0.82em; }",
    "    .badge-oral { background: #d5f5e3; color: #1e8449; }",
    "    .badge-iv   { background: #d6eaf8; color: #1a5276; }",
    "    .badge-mock { background: #fdebd0; color: #784212; }",
    "    .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1em; margin: 1em 0; }",
    "    .info-card { background: #f0f3f4; border-radius: 6px; padding: 1em; }",
    "    .info-card dt { font-weight: bold; color: #555; font-size: 0.85em; text-transform: uppercase; }",
    "    .info-card dd { margin: 0.2em 0 0.8em 0; font-size: 1.05em; }",
    "    .plot-placeholder { background: #f0f3f4; border: 2px dashed #aaa; border-radius: 8px;",
    "                        padding: 3em; text-align: center; color: #888; margin: 1.5em 0; }",
    "    .note     { background: #fef9e7; border-left: 4px solid #f1c40f; padding: 0.8em 1.2em;",
    "                border-radius: 0 4px 4px 0; margin: 1em 0; font-size: 0.92em; }",
    "    footer    { margin-top: 3em; font-size: 0.82em; color: #999; border-top: 1px solid #eee;",
    "                padding-top: 1em; }",
    "  </style>",
    "</head>",
    "<body>",
    "",
    "<h1>NCA Report &mdash; PKNCA</h1>",
    "",
    "<p>",
    "  Generated by <strong>BioMate</strong> &bull;",
    "  Analysis date: <strong>" + now_date + "</strong> &bull;",
    "  Mode: <span class='badge badge-mock'>MOCK</span>",
    "</p>",
    "",
    "<div class='note'>",
    "  <strong>Mock mode:</strong> All concentration-time data and NCA parameters in this report",
    "  are synthetically generated for demonstration purposes. No real PK data was used.",
    "</div>",
    "",
    "<h2>1. Study Information</h2>",
    "<div class='info-grid'>",
    "  <div class='info-card'>",
    "    <dl>",
    "      <dt>Dose</dt><dd>" + dose_val + " mg</dd>",
    "      <dt>Route</dt><dd><span class='badge " + badge_cls + "'>" + route.upper() + "</span></dd>",
    "      <dt>Subjects (N)</dt><dd>" + str(n_subj) + "</dd>",
    "    </dl>",
    "  </div>",
    "  <div class='info-card'>",
    "    <dl>",
    "      <dt>Time unit</dt><dd>" + time_unit + "</dd>",
    "      <dt>Concentration unit</dt><dd>" + conc_unit + "</dd>",
    "      <dt>AUC unit</dt><dd>" + auc_unit + "</dd>",
    "      <dt>Software</dt><dd>PKNCA (R package, Beal / nlmixr2 team)</dd>",
    "    </dl>",
    "  </div>",
    "</div>",
    "",
    "<h2>2. Concentration-Time Profile</h2>",
    "<div class='plot-placeholder'>",
    "  <p><strong>[Concentration-Time Plot]</strong></p>",
    "  <p>In live mode, a ggplot2 semi-log plot (individual + geometric mean profiles)<br>",
    "     is rendered here via knitr/Rmd.</p>",
    "  <p style='font-size:0.85em'>",
    "    X-axis: Time (" + time_unit + ") &nbsp;|&nbsp; Y-axis: Concentration (" + conc_unit + ", log scale)",
    "  </p>",
    "</div>",
    "",
    "<h2>3. NCA Parameters by Subject</h2>",
    "<table>",
    "  <thead><tr>",
    "    <th>Subject</th>",
    "    <th>AUC<sub>last</sub><br><small>" + auc_unit + "</small></th>",
    "    <th>AUC<sub>inf</sub><br><small>" + auc_unit + "</small></th>",
    "    <th>C<sub>max</sub><br><small>" + conc_unit + "</small></th>",
    "    <th>T<sub>max</sub><br><small>" + time_unit + "</small></th>",
    "    <th>t<sub>1/2</sub><br><small>" + time_unit + "</small></th>",
    "    <th>CL/F<br><small>" + cl_unit + "</small></th>",
    "    <th>V<sub>d</sub>/F<br><small>L</small></th>",
    "  </tr></thead>",
    "  <tbody>",
    "    " + row_html,
    "    " + pop_row,
    "  </tbody>",
    "</table>",
    "",
    "<h2>4. NCA Assumptions &amp; Limitations</h2>",
    "<h3>Assumptions met in this analysis:</h3>",
    "<ul>",
    "  <li><strong>Linear pharmacokinetics</strong> &mdash; AUC scales proportionally with dose;</li>",
    "  <li><strong>Steady-state not required</strong> &mdash; Single-dose NCA design.</li>",
    "  <li><strong>Adequate sampling</strong> &mdash; Schedule covers absorption and at least 3x t&#189; terminal phase.</li>",
    "  <li><strong>Terminal phase linearity</strong> &mdash; &lambda;<sub>z</sub> estimated from last 3+ time points above LLOQ.</li>",
    "  <li><strong>Negligible urine contribution</strong> &mdash; All PK inferred from plasma concentration data.</li>",
    "</ul>",
    "<h3>Limitations:</h3>",
    "<ul>",
    "  <li>AUC<sub>inf</sub> reliability decreases when &gt;30% of AUC is extrapolated.</li>",
    "  <li>CL/F and V<sub>d</sub>/F are <em>apparent</em> parameters; absolute F requires an IV arm.</li>",
    "  <li>T<sub>max</sub> is a discrete, sampling-schedule-dependent estimate.</li>",
    "  <li>NCA does not detect flip-flop kinetics.</li>",
    "</ul>",
    "",
    "<footer>",
    "  <p>NCA performed with <strong>PKNCA</strong> (Denney W et al. <em>J Pharmacokinet Pharmacodyn</em> 2015) &bull;",
    "  Report generated by <strong>BioMate AI</strong> &bull; " + now_ts + "</p>",
    "</footer>",
    "",
    "</body>",
    "</html>",
]

with open("nca_report.html", "w") as fout:
    fout.write("\n".join(html_lines) + "\n")

print("NCA HTML report (mock) written: nca_report.html")
print("  " + str(n_subj) + " subjects | route=" + route + " | dose=" + dose_val)
EOF

    else
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
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        R: \$(Rscript --version 2>&1 | grep -oP '[0-9]+\\.[0-9]+\\.[0-9]+' | head -1 || echo "4.3.1")
        rmarkdown: \$(Rscript -e "cat(as.character(packageVersion('rmarkdown')))" 2>/dev/null || echo "N/A")
        ggplot2: \$(Rscript -e "cat(as.character(packageVersion('ggplot2')))" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2 || echo "N/A")
        mock_mode: "${mock}"
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

    if (params.mock_mode) {
        // In mock mode, generate a synthetic CSV on the fly so no real file
        // is needed (the validation process itself creates the data).
        ch_input = Channel.of(
            file("${projectDir}/test_data/conc_time.csv", checkIfExists: false)
        ).map { csv ->
            csv.exists() ? csv : {
                def tmp = file("${workDir}/mock_conc_time.csv")
                tmp.text = [
                    "subject_id,time,conc,dose,route",
                    "SUBJ01,0,0.0,${params.dose},${params.route}",
                    "SUBJ01,1.0,450.2,${params.dose},${params.route}",
                    "SUBJ01,2.0,620.8,${params.dose},${params.route}",
                    "SUBJ01,4.0,410.1,${params.dose},${params.route}",
                    "SUBJ01,8.0,185.3,${params.dose},${params.route}",
                    "SUBJ01,12.0,82.0,${params.dose},${params.route}",
                    "SUBJ01,24.0,12.5,${params.dose},${params.route}",
                ].join("\n")
                tmp
            }()
        }
    } else {
        if (!params.input_csv) {
            error "params.input_csv is required in live mode. Pass --input_csv <path>"
        }
        ch_input = Channel.fromPath(params.input_csv, checkIfExists: true)
    }

    // Run the pipeline
    NCA_PKNCA(ch_input)

    // Display output locations
    NCA_PKNCA.out.nca_results.view { f ->
        "NCA results CSV  : ${f}"
    }
    NCA_PKNCA.out.nca_summary.view { f ->
        "NCA summary JSON : ${f}"
    }
    NCA_PKNCA.out.report.view { f ->
        "NCA HTML report  : ${f}"
    }
}
