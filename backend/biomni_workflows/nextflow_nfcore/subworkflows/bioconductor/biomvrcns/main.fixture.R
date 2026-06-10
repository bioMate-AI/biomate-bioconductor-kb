# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("coriell")
.obj <- get("coriell")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "coriell.txt", row.names=TRUE)
