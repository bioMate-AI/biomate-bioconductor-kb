# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("snijders")
.obj <- get("snijders")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "user_data.txt", row.names=TRUE)
