# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("annotationTools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(annotationTools)

# Reproduce the vignette's data-preparation code
# Chunk 23: data(orthologs_example)
# This loads table_mouse, table_human, and ortho into the environment.
data(orthologs_example)

# The workflow's find_and_read function attempts to read files using read.csv first.
# Therefore, we should save the files in CSV format.
# Use write.csv with row.names = FALSE to match the expected input format.

# Serialize table_mouse to "table_mouse"
write.csv(table_mouse, "table_mouse", row.names = FALSE)

# Serialize table_human to "table_human"
write.csv(table_human, "table_human", row.names = FALSE)

# Serialize ortho to "ortho"
write.csv(ortho, "ortho", row.names = FALSE)