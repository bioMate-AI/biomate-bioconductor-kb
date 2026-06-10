# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RITANdata", "RITAN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RITANdata)
library(RITAN)

# Create study_set from RITANdata's geneset_list
selection <- grepl('GSE9988_(LOW_)*LPS_VS_.+UP', names(geneset_list$MSigDB_C7), perl=TRUE)
study_set <- geneset_list$MSigDB_C7[selection]

# Save study_set.rds
saveRDS(study_set, "study_set.rds")

# Create annotation matrix
mat <- matrix(c("LPS", "LPS", "LPS", "LPS", "LOW_LPS", "LOW_LPS", "LOW_LPS",
                "LOW_LPS", "LPS_AND_ANTI_TREM1", "CTRL_TREATED", "VEHICLE_TREATED",
                "ANTI_TREM1_AND_LPS", "CTRL_TREATED", "VEHICLE_TREATED"),
              nrow = 2, byrow = TRUE)
rownames(mat) <- c('Condition1', 'Condition2')
colnames(mat) <- sprintf('Sample%s', 1:7)

# Save annotation_metadata.csv
write.csv(mat, "annotation_metadata.csv", row.names = TRUE)