# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("arabidopsisThalianaRefseq")
.obj <- get("arabidopsisThalianaRefseq")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "tir_query.txt", row.names=TRUE)
