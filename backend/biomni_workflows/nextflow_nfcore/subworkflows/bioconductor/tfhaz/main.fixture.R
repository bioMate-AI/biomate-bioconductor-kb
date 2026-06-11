# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("Ishikawa")
.obj <- get("Ishikawa")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "tf_regions.GRanges", row.names=TRUE)
