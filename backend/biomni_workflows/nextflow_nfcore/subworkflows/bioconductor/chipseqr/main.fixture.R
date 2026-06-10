# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ChIPseqR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ChIPseqR)

set.seed(1)
dist <- sample(c(170:300, 400), 10100, prob=c(dnbinom(0:130, mu=30, size=5), 0.2), replace=TRUE)
pos <- cumsum(dist)
pos <- pos[pos < 2e6 - 200]

fwdRegion <- unlist(lapply(pos, function(x) (x-88):(x-68)))
revRegion <- unlist(lapply(pos, function(x) (x+68):(x+88)))

fwd <- sample(fwdRegion, 5e4, replace=TRUE)
rev <- sample(revRegion, 5e4, replace=TRUE)

fwd <- c(fwd, sample(25:(2e6-25), 2e5, replace=TRUE))
rev <- c(rev, sample(25:(2e6-25), 2e5, replace=TRUE))

reads <- data.frame(chromosome="chr1", position=c(fwd, rev), length=25, 
        strand=rep(c("+", "-"), each=250000))

write.csv(reads, "reads.csv", row.names = FALSE)