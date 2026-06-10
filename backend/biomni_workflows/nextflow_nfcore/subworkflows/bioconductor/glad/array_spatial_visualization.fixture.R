# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("arrayCGH")
.obj <- get("arrayCGH")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "raw_array_data.txt", row.names=TRUE)
