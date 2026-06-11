# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("sigoraDatabase")
.obj <- get("sigoraDatabase")
saveRDS(.obj, "enriched_pathways.rds")
