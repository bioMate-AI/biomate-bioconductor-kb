# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("cosmic_v2_sigs")
.obj <- get("cosmic_v2_sigs")
.df <- tryCatch(as.data.frame(.obj), error=function(e) as.data.frame(as.matrix(.obj)))
write.csv(.df, "public_LUAD_TCGA-97-7938.vcf", row.names=TRUE)
