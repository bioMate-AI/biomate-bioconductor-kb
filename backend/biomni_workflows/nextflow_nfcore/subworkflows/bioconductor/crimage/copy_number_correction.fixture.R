# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CRImage")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CRImage)

# Code chunk number 10 from CRImage.Rnw:201-211
# This chunk creates the 'z' data frame used by the workflow.
LRR <- c(rnorm(100, 0, 1), rnorm(10, -2, 1), rnorm(20, 3, 1),
       rnorm(100,0, 1))
BAF <- c(rnorm(100, 0.5, 0.1), rnorm(5, 0.2, 0.01), rnorm(5, 0.8, 0.01), rnorm(10, 0.25, 0.1), rnorm(10, 0.75, 0.1),
       rnorm(100,0.5, 0.1))

Pos <- sample(x=1:500, size=230, replace=TRUE)
Pos <- cumsum(Pos)
Chrom <- rep(1, length(LRR))
z <- data.frame(Name=1:length(LRR), Chrom=Chrom, Pos=Pos, LRR=LRR, BAF=BAF)

# Serialize the 'z' data frame to the expected input files.
# The workflow reads 'z' using read.table, 'z.csv' using read.csv, or 'z.txt' using read.table.

# Create 'z' (tab-separated, with header, no row names)
write.table(z, file="z.csv", sep="\t", row.names=FALSE, col.names=TRUE)

# Create 'z.csv' (comma-separated, with header, no row names)
write.csv(z, file="z.csv", row.names=FALSE)

# Create 'z.txt' (tab-separated, with header, no row names)
write.table(z, file="z.csv", sep="\t", row.names=FALSE, col.names=TRUE)