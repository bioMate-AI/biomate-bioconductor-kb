# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("OUTRIDER")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(OUTRIDER)

# Use the vignette's method to get the small testing data set
odsSmall <- makeExampleOutriderDataSet(dataset="Kremer")

# Extract counts and annotations
ctsTable_data <- counts(odsSmall)
annoTable_data <- as.data.frame(colData(odsSmall))

# Ensure RNA_ID exists as the vignette script maps it to sampleID
if (!"RNA_ID" %in% colnames(annoTable_data) && "sampleID" %in% colnames(annoTable_data)) {
    annoTable_data$RNA_ID <- annoTable_data$sampleID
}

# Serialize to the exact filenames expected by the workflow
write.table(ctsTable_data, file="ctsTable", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)
write.table(annoTable_data, file="annoTable", sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)