# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("BS.chr21")
.obj <- get("BS.chr21")
saveRDS(.obj, "bs_object.rds")
