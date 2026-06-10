# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("gtf")
.obj <- get("gtf")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "experiment.txt", row.names=TRUE)
