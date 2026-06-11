# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("yeastCC")
.obj <- get("yeastCC")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "expression_data.csv", row.names=TRUE)
