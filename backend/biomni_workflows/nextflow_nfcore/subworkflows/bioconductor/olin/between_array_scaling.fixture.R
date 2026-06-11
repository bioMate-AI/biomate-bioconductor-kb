# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("sw.olin")
.obj <- get("sw.olin")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "normalized_microarray_data.RData", row.names=TRUE)
