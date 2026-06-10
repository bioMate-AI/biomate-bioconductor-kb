# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DEP")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DEP)

# Reproduce the VIGNETTE'S OWN data-preparation code
# Load the example dataset 'arabidopsis' which contains Ubiq_Proteins and Ubiq_ExpDesign
data("arabidopsis")

# Serialize Ubiq_Proteins to proteinGroups.txt
# The workflow reads proteinGroups.txt using read.delim(..., header = TRUE, sep = "\t", stringsAsFactors = FALSE).
# We write the data frame as a tab-separated file without row names and without quoting strings.
write.table(Ubiq_Proteins,
            file = "proteinGroups.txt",
            sep = "\t",
            row.names = FALSE,
            quote = FALSE)

# Serialize Ubiq_ExpDesign to experimental_design.txt
# The workflow reads experimental_design.txt using read.delim(..., header = TRUE, sep = "\t", stringsAsFactors = FALSE).
# We write the data frame as a tab-separated file without row names and without quoting strings.
write.table(Ubiq_ExpDesign,
            file = "experimental_design.txt",
            sep = "\t",
            row.names = FALSE,
            quote = FALSE)