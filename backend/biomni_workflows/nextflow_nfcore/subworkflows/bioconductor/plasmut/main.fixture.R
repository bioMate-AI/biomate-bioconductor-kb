# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("crcseq")
.obj <- get("crcseq")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "user_mutation_data.csv", row.names=TRUE)
