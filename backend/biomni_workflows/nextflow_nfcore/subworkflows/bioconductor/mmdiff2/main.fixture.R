# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("Cfp1")
.obj <- get("Cfp1")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "peaks.GRanges", row.names=TRUE)
