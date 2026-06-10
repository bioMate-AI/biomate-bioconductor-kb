# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("ethnicityCpGs")
.obj <- get("ethnicityCpGs")
saveRDS(.obj, "DNAm_betas.rds")
