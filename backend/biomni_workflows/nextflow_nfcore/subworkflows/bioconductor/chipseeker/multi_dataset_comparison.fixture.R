# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("tagMatrixList")
.obj <- get("tagMatrixList")
saveRDS(.obj, "txdb.rds")
