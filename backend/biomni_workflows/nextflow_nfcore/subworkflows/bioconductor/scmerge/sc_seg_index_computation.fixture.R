# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("example_sce")
.obj <- get("example_sce")
saveRDS(.obj, "example_sce.rds")
