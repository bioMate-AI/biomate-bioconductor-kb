# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("airway", "DESeq2", "emdbook")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(airway)
library(DESeq2)
library(emdbook)

data(airway)
keep <- head(which(rowSums(assay(airway)) >= 10), 3000)
airway <- airway[keep,]

dds <- DESeqDataSet(airway, ~ cell + dex)
dds$dex <- relevel(dds$dex, "untrt")
dds <- DESeq(dds)
res <- results(dds)

n <- 20
f <- factor(rep(1:2, each=n))
mu <- ifelse(res$baseMean > 50, res$baseMean, 50)
set.seed(1)
cts <- matrix(rnbinom(nrow(dds) * 2 * n, mu=mu, size=1/dispersions(dds)), ncol=2 * n)
theta <- runif(nrow(cts), 1, 1000)
prob <- rnorm(nrow(cts), .5, .05) 
ase.cts <- matrix(rbetabinom(prod(dim(cts)), prob=prob, size=cts, theta=rep(theta, ncol(cts))), nrow=nrow(cts))

idx <- 1:10
idx2 <- which(f == 2)
theta[idx] <- 1000
prob[idx] <- 0.75 
ase.cts[idx,idx2] <- matrix(rbetabinom(length(idx) * length(idx2), prob=prob[idx], size=cts[idx,idx2], theta=theta[idx]), nrow=length(idx))

saveRDS(ase.cts, "ase.cts")
saveRDS(cts, "cts")