# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "mcool_file.mcool": fetch via the package's ExperimentHub accessor
for (.dp in c("HiContactsData")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- tryCatch(HiContactsData::HiContactsData('yeast_wt', format = 'mcool'), error = function(e) NA_character_)
stopifnot("could not fetch example mcool_file.mcool via accessor"=!is.na(.src) && file.exists(.src))
file.copy(.src, "mcool_file.mcool", overwrite=TRUE)
