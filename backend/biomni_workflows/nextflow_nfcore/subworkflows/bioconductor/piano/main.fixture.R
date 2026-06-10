# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("piano")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(piano)

# 1. Reproduce the 'mySetup' object as shown in vignette chunk 3
oxygen <- c("aerobic","anaerobic")
limitation <- c("Clim","Nlim")
mySetup <- cbind(oxygen[c(1,1,1,2,2,2,1,1,1,2,2,2)],
               limitation[c(1,1,1,1,1,1,2,2,2,2,2,2)])
rownames(mySetup) <- c("CAE1","CAE2","CAE3","CAN1","CAN2","CAN3",
                     "NAE1","NAE2","NAE3","NAN1","NAN2","NAN3")
colnames(mySetup) <- c("oxygen","limitation")

# 2. Serialize 'mySetup' to 'setup.txt' in the format expected by read.delim
#    (tab-separated, with row names as the first column and a header row)
write.table(mySetup, file="setup.txt", sep="\t", quote=FALSE, row.names=TRUE, col.names=TRUE)

# 3. Materialize the 'myArrayData' object using the vignette's data-preparation code (chunk 4)
#    This involves loading the example 'norm_data.txt