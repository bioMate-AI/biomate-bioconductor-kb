# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("SEQC.Example")
.obj <- get("SEQC.Example")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "UHRR.HBRR.arrayDat", row.names=TRUE)
