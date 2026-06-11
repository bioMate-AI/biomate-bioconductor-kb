# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "mcool_file.mcool": fetch via the package's ExperimentHub accessor
for (.dp in c("HiContactsData")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- tryCatch(HiContactsData::HiContactsData('yeast_wt', format = 'mcool'), error = function(e) NA_character_)
stopifnot("could not fetch example mcool_file.mcool via accessor"=!is.na(.src) && file.exists(.src))
file.copy(.src, "mcool_file.mcool", overwrite=TRUE)
# co-input "A-compartments.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "A-compartments.bed")
# co-input "B-compartments.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "B-compartments.bed")
# co-input "borders.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "borders.bed")
