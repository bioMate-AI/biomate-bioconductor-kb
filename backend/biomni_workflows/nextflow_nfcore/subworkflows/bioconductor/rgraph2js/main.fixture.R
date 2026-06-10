# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RGraph2js")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RGraph2js)

v <- c(1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,
       1,1,0,1,1,1,0,0,0,0,0,0,0,0,0,
       1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
       0,1,0,1,1,0,0,0,0,0,1,0,0,0,0,
       0,1,0,1,1,0,0,0,1,0,0,0,0,0,0,
       0,1,0,0,0,0,1,1,0,0,0,0,0,0,0,
       0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,
       0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,
       0,0,0,0,1,0,0,0,1,1,0,0,0,0,0,
       0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,
       0,0,0,1,0,0,0,0,0,0,0,1,1,1,0,
       0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,
       0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,
       0,0,0,0,0,0,0,0,0,0,1,0,0,0,1,
       0,0,0,0,0,0,0,0,0,0,0,0,0,1,1
      )
a1515 <- matrix(v, 15, 15)
colnames(a1515) <- LETTERS[1:15]
rownames(a1515) <- LETTERS[1:15]

write.csv(a1515, "input.csv", row.names=TRUE)