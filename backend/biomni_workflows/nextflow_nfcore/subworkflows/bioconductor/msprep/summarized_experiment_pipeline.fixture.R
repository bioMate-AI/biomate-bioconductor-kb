# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("COPD_131")
.obj <- get("COPD_131")
saveRDS(.obj, "metabolomics_se.rds")
