# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("scfeatures_result")
.obj <- get("scfeatures_result")
saveRDS(.obj, "scfeatures_result.rds")
