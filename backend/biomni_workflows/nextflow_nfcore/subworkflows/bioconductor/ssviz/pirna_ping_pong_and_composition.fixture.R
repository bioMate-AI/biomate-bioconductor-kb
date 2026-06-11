# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("ssviz")
.obj <- get("ssviz")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "file1.bam", row.names=TRUE)
