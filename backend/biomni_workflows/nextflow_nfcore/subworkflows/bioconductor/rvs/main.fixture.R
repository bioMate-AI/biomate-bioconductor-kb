# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("samplePedigrees")
.obj <- get("samplePedigrees")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "pedigree_data.txt", row.names=TRUE)
