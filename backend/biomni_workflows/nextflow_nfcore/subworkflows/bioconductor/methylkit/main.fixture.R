# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("methylKit")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(methylKit)

# 1. Prepare the 'file.list' input file
# The vignette provides the exact R code to create the list of file paths.
file.list_R_object <- list(
  system.file("extdata", "test1.myCpG.txt", package = "methylKit"),
  system.file("extdata", "test2.myCpG.txt", package = "methylKit"),
  system.file("extdata", "control1.myCpG.txt", package = "methylKit"),
  system.file("extdata", "control2.myCpG.txt", package = "methylKit")
)

# The workflow reads "file.list" using readLines().
# Write each path from the R list to a new line in the "file.list" file.
writeLines(unlist(file.list_R_object), "file.list")

# 2. Prepare the 'gene.obj' input file
# The provided vignette excerpt does not explicitly show the creation of 'gene.obj'
# using readTranscriptFeatures. However, the methylKit package documentation for
# readTranscriptFeatures provides a canonical example using system.file.
# We will use this example to obtain the content for the 'gene.obj' file.
original_gene_file_path <- system.file("extdata", "refseq.hg18.bed.txt", package = "methylKit")

# The workflow reads "gene.obj" using readTranscriptFeatures("gene.obj").
# Copy the content of the example file to the "gene.obj" file in the working directory.
file.copy(original_gene_file_path, "gene.obj")

# 3. Prepare the 'cpg.obj' input file
# Similar to 'gene.obj', the vignette excerpt does not explicitly show the creation
# of 'cpg.obj' using readFeatureFlank. The methylKit package documentation for
# readFeatureFlank provides a canonical example using system.file.
# We will use this example to obtain the content for the 'cpg.obj' file.
original_cpg_file_path <- system.file("extdata", "cpgi.hg18.bed.txt", package = "methylKit")

# The workflow reads "cpg.obj" using readFeatureFlank("cpg.obj", ...).
# Copy the content of the example file