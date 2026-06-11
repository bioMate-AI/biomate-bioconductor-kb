# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("crm.features")
.obj <- get("crm.features")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "crm.features", row.names=TRUE)
