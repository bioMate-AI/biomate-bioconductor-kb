# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("sim_data")
.obj <- get("sim_data")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "orthologous_genes_data.csv", row.names=TRUE)
