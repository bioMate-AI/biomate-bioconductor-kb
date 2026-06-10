# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNAnorm")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNAnorm)

# --- Prepare LS041 ---
# Reproduce the vignette's data loading for LS041
data(LS041)

# Serialize LS041 to all specified formats
saveRDS(LS041, "LS041.rds")
write.csv(LS041, "LS041.rds", row.names = FALSE)
write.table(LS041, "LS041.rds", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(LS041, "LS041.rds", sep = "\t", row.names = FALSE, quote = FALSE)
# For the raw file name "LS041", write as a table as per the workflow's first read attempt
write.table(LS041, "LS041.rds", sep = "\t", row.names = FALSE, quote = FALSE)


# --- Prepare hg19_hs_ideogr ---
# Reproduce the vignette's data loading for hg19_hs_ideogr
data(hg19_hs_ideogr)

# Serialize hg19_hs_ideogr to all specified formats
saveRDS(hg19_hs_ideogr, "hg19_hs_ideogr.rds")
write.csv(hg19_hs_ideogr, "hg19_hs_ideogr.rds", row.names = FALSE)
write.table(hg19_hs_ideogr, "hg19_hs_ideogr.rds", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(hg19_hs_ideogr, "hg19_hs_ideogr.rds", sep = "\t", row.names = FALSE, quote = FALSE)
# For the raw file name "hg19_hs_ideogr", write as a table as per the workflow's first read attempt
write.table(hg19_hs_ideogr, "hg19_hs_ideogr.rds", sep = "\t", row.names = FALSE, quote = FALSE)