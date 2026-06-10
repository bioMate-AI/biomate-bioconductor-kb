# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("targets")
.obj <- get("targets")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "targets.csv", row.names=TRUE)
