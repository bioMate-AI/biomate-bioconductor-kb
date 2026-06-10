# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("nucleosome_tiling")
.obj <- get("nucleosome_tiling")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "tiling_data.RData", row.names=TRUE)
