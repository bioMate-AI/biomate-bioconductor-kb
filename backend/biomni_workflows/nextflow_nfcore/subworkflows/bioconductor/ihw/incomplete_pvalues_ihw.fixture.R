# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DESeq2", "dplyr", "airway")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("DESeq2")
library("dplyr")
library("airway") # This package contains the 'airway' dataset

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data("airway", package = "airway")
dds <- DESeqDataSet(se = airway, design = ~ cell + dex) %>% DESeq
deRes <- as.data.frame(results(dds))

# The vignette later uses na.omit(deRes) for diagnostic plots.
# Since 'simSub.csv' is listed as an input file but not explicitly generated
# or described in the vignette, we will create it as a common subset,
# such as the version of deRes with NA values removed, as seen in the vignette.
deRes_na_omit <- na.omit(deRes)

# 2. Serialize the objects to the declared input files
# Save the full deRes data frame to sim.csv
write.csv(deRes, "sim.csv", row.names = TRUE)

# Save the na.omit version of deRes to simSub.csv
write.csv(deRes_na_omit, "simSub.csv", row.names = TRUE)