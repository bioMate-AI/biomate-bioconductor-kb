# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("BS.cancer.ex")
.obj <- get("BS.cancer.ex")
saveRDS(.obj, "diff_gr_methylsig.rds")
