# [biomate] structured fixture (rule: binary_example_data) — deterministic, no LLM
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
# binary input "condition-1.replicate-1.cool": fetch via the package's ExperimentHub accessor
for (.dp in c("HiContactsData")) if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
.src <- tryCatch(HiContactsData::HiContactsData('yeast_wt', format = 'cool'), error = function(e) NA_character_)
stopifnot("could not fetch example condition-1.replicate-1.cool via accessor"=!is.na(.src) && file.exists(.src))
file.copy(.src, "condition-1.replicate-1.cool", overwrite=TRUE)
# co-input "data.tsv": synthetic
write.table(data.frame(id=paste0("f",1:50),s1=rpois(50,20),s2=rpois(50,20)), "data.tsv", sep="\t", row.names=FALSE, quote=FALSE)
# co-input "condition-1.replicate-1.bed": synthetic
writeLines(c("chr1\t1000\t2000\tpeak1\t100\t+","chr1\t3000\t4000\tpeak2\t80\t-"), "condition-1.replicate-1.bed")
