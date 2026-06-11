# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("murine")
.obj <- get("murine")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "intensity_data.csv", row.names=TRUE)
