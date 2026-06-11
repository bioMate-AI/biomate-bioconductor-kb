# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CFAssay")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CFAssay)

# Reproduce the data preparation code from the vignette (chunk 10)
# This creates the 'datatab' object used in the ANOVA example.
datatab <- read.table(system.file("doc", "exp2_2waycfa.txt", package="CFAssay"),
                      header=TRUE, sep="\t")

# Serialize the 'datatab' object to 'anova_data.txt'
# The workflow reads this file using read.table(input_file, header=TRUE, sep="\t")
write.table(datatab, file="anova_data.txt", sep="\t", row.names=FALSE, quote=FALSE)