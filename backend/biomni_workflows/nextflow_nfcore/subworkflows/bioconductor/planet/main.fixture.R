# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("plBetas")
.obj <- get("plBetas")
saveRDS(.obj, "DNAm_betas.rds")
