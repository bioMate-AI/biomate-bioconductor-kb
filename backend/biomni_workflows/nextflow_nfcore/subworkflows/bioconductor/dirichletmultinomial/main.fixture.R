# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("fit")
.obj <- get("fit")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "Twins.csv", row.names=TRUE)
