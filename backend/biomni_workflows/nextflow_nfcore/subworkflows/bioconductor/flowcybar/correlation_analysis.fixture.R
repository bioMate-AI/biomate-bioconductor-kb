# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("Corr_data_sample")
.obj <- get("Corr_data_sample")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "Corr_data_sample.txt", row.names=TRUE)
