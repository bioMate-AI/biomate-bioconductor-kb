# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("Cfp1")
.obj <- get("Cfp1")
# Workflow loads this input with readRDS(); serialize the real object
# (a write.csv data-frame dump is not an RDS and fails readRDS at load).
saveRDS(.obj, "peaks.GRanges")
