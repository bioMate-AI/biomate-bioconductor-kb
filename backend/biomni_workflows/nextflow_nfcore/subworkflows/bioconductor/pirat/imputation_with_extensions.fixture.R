# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("subropers")
.obj <- get("subropers")
saveRDS(.obj, "subropers.rds")
