# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GeneOverlap")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GeneOverlap)
data(GeneOverlap)

# Extract the specific gene lists and background size used in the vignette's first example
# These correspond to the inputs expected by the workflow.
list1_data <- hESC.ChIPSeq.list$H3K4me3
list2_data <- hESC.RNASeq.list$"Exp High"
background_size_data <- gs.RNASeq

# Write list1_data to "list1.txt"
# The workflow uses scan("list1.txt", what = character()), which expects one item per line.
writeLines(list1_data, "list1.txt")

# Write list2_data to "list2.txt"
# The workflow uses scan("list2.txt", what = character()), which expects one item per line.
writeLines(list2_data, "list2.txt")

# Write background_size_data to "background_size"
# The workflow uses scan("background_size", what = integer())[1], expecting a single integer.
write(as.character(background_size_data), "background_size")