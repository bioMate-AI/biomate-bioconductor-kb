# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("genesets_sel")
.obj <- get("genesets_sel")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "gsea_results.csv", row.names=TRUE)
