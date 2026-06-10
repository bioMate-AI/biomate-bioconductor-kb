# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RedeR", "igraph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RedeR)
library(igraph)

# Reproduce vignette data preparation
gtoy1 <- make_lattice(c(3, 3, 3))

g1 <- sample_pa(100, directed=FALSE)
V(g1)$name <- paste0("V", 1:vcount(g1))
g1$bgcolor <- "white"
V(g1)$nodeLineColor <- "skyblue"
V(g1)$nodeSize <- 50
E(g1)$edgeLineColor <- "skyblue"
E(g1)$edgeLineWidth <- 10

df <- data.frame(ID=sample(V(g1)$name))
df$newAttr1 <- rnorm(nrow(df))
df$newAttr2 <- rnorm(nrow(df))

# Write the requested input file
data(iris)
saveRDS(iris, "iris.csv")