# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("tcga_aml_meth_rna_chr18")
.obj <- get("tcga_aml_meth_rna_chr18")
saveRDS(.obj, "tcga_aml_meth_rna_chr18")
