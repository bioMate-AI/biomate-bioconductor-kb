# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("rrvgo")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(rrvgo)

# Reproduce the vignette's data preparation to create the 'go_analysis' object
# The vignette itself reads an internal example file to create this object.
go_analysis <- read.delim(system.file("extdata/example.txt", package="rrvgo"),
                          header = TRUE,
                          sep = "\t",
                          stringsAsFactors = FALSE)

# Serialize the 'go_analysis' object to 'go_analysis.txt'
# The workflow reads this file using read.delim("go_analysis.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
# So, we need to write a tab-separated file with a header and no row names.
write.table(go_analysis,
            file = "go_analysis.txt",
            sep = "\t",
            row.names = FALSE,
            quote = FALSE)