# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("inputCaseA")
.obj <- get("inputCaseA")
saveRDS(.obj, "inputCaseA")
