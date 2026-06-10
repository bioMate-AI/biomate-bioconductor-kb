# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("OUTRIDER")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(OUTRIDER)
})

# Generate example dataset using the package's built-in function
odsSmall <- makeExampleOutriderDataSet(dataset="Kremer")

# Extract counts and annotations
ctsTable <- counts(odsSmall)
annoTable <- as.data.frame(colData(odsSmall))

# Ensure RNA_ID exists as expected by the vignette's downstream code
if (!"RNA_ID" %in% colnames(annoTable)) {
    if ("sampleID" %in% colnames(annoTable)) {
        annoTable$RNA_ID <- annoTable$sampleID
    } else {
        annoTable$RNA_ID <- rownames(annoTable)
    }
}

# Write to files in the format expected by the workflow (tab-separated)
write.table(ctsTable, "ctsTable.csv", sep="\t", quote=FALSE, col.names=NA)
write.table(annoTable, "annoTable.csv", sep="\t", quote=FALSE, row.names=FALSE)