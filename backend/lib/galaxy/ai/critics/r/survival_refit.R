#!/usr/bin/env Rscript
# ============================================================================
# survival_refit.R — reusable survival re-fit stats, decoupled from cox.nf
#
# This is the SAME statistics that used to live inside
#   subworkflows/bioconductor/survival/cox_proportional_hazards_regression.nf
# extracted into a standalone, reusable script the SurvivalConfoundingCritic /
# SurvivalPHCritic orchestrate from Python. It reads a clinical CSV and a primary
# covariate (+ optional confounders), fits the naive and adjusted Cox models, runs
# the Schoenfeld PH test, and prints the survival_qc.json schema to stdout:
#
#   { primary_covariate, naive_primary_hr, adjusted_primary_hr,
#     schoenfeld_global_p, ph_violating_covariates[], omitted_confounders[] }
#
# Usage:
#   Rscript survival_refit.R <clinical.csv> <primary_covariate> [conf1,conf2,...]
#
# Keeping this OUT of the .nf is the whole point: a critic (or any other consumer)
# can run the stats without the workflow, and the stats are independently testable.
# ============================================================================

suppressWarnings(suppressMessages({
  if (!requireNamespace("survival", quietly = TRUE))
    stop("survival package required")
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("jsonlite package required")
  library(survival)
}))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: survival_refit.R <csv> <primary> [conf1,conf2,...]")
csv_path <- args[[1]]
primary  <- args[[2]]
confounders <- if (length(args) >= 3 && nzchar(args[[3]])) strsplit(args[[3]], ",")[[1]] else character(0)

d <- read.csv(csv_path)
covs <- setdiff(colnames(d), c("time", "status"))
if (!(primary %in% covs)) stop(sprintf("primary covariate %s not in data", primary))

hr_from <- function(fit, v) {
  ci <- summary(fit)$conf.int
  if (v %in% rownames(ci)) unname(ci[v, "exp(coef)"]) else NA
}
p_from <- function(fit, v) {
  co <- summary(fit)$coefficients
  if (v %in% rownames(co)) unname(co[v, ncol(co)]) else NA
}

# Naive: primary only.
naive_fit <- coxph(as.formula(paste0("Surv(time, status) ~ ", primary)), data = d)
naive_hr  <- hr_from(naive_fit, primary)

# Adjusted: primary + requested confounders (or all other covariates if none given).
adj_covs <- if (length(confounders)) confounders else setdiff(covs, primary)
adj_fit  <- coxph(as.formula(paste0("Surv(time, status) ~ ",
                                    paste(c(primary, adj_covs), collapse = " + "))), data = d)
adjusted_hr <- hr_from(adj_fit, primary)

# PH test on the adjusted model.
cz     <- cox.zph(adj_fit)
cz_tab <- as.data.frame(cz$table)
global_p <- if ("GLOBAL" %in% rownames(cz_tab)) unname(cz_tab["GLOBAL", "p"]) else NA
violators <- rownames(cz_tab)[!is.na(cz_tab$p) & cz_tab$p < 0.05 & rownames(cz_tab) != "GLOBAL"]

omitted <- lapply(adj_covs, function(v) {
  list(name = v, hr = round(hr_from(adj_fit, v), 4), p = p_from(adj_fit, v))
})

qc <- list(
  process = "SURVIVAL_REFIT",
  domain = "survival",
  primary_covariate = primary,
  naive_primary_hr = if (is.na(naive_hr)) NULL else round(naive_hr, 4),
  adjusted_primary_hr = if (is.na(adjusted_hr)) NULL else round(adjusted_hr, 4),
  schoenfeld_global_p = if (is.na(global_p)) NULL else global_p,
  ph_violating_covariates = as.list(violators),
  omitted_confounders = omitted
)
cat(jsonlite::toJSON(qc, auto_unbox = TRUE, null = "null"))
