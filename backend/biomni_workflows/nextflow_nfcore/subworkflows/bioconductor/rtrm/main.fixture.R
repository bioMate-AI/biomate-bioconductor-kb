# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("biogrid_mm")
.obj <- get("biogrid_mm")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "ESC-expressed.txt", row.names=TRUE)
