# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("copyNumbersSegmented")
.obj <- get("copyNumbersSegmented")
saveRDS(.obj, "copyNumbersSegmented.rds")
