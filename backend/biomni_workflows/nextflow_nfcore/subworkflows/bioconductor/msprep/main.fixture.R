# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("msquant")
.obj <- get("msquant")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "metabolomics_df.csv", row.names=TRUE)
