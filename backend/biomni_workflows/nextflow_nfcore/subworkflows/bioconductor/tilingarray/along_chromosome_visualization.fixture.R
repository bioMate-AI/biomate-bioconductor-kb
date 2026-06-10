# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tilingArray")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("tilingArray")

# Load the datasets provided by the package
data("segnf", package="tilingArray")
data("gffSub", package="tilingArray")

# Prepare the RData file containing the segmentation objects
# We save both the individual objects ("1.+", "1.-") and an environment object 
# named 'segmentation_env' to ensure compatibility regardless of how the workflow loads it.
e <- new.env()
for(n in ls(segnf)) {
    assign(n, get(n, envir=segnf), envir=e)
}
e$segmentation_env <- segnf

save(list=ls(e), envir=e, file="segmentation_env.RData")

# Write the GFF annotation data frame to a file
write.table(gffSub, file="gff_annotation.gff", sep="\t", quote=FALSE, row.names=FALSE, col.names=TRUE)