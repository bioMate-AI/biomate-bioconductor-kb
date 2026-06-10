# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("famVCF")
.obj <- get("famVCF")
saveRDS(.obj, "pedigree_structures.rds")
