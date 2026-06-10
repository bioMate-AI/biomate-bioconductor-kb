# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("contig_list")
.obj <- get("contig_list")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "filtered_contig_annotations.csv", row.names=TRUE)
