# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ggtreeExtra", "ape")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ggtreeExtra)

trfile <- system.file("extdata", "tree.nwk", package="ggtreeExtra")
if (file.exists(trfile)) {
    file.copy(trfile, "tree.nwk", overwrite = TRUE)
} else {
    library(ape)
    set.seed(1024)
    tr <- rtree(100)
    write.tree(tr, "tree.nwk")
}

tippoint1 <- system.file("extdata", "tree_tippoint_bar.csv", package="ggtreeExtra")
if (file.exists(tippoint1)) {
    file.copy(tippoint1, "associated_data.csv", overwrite = TRUE)
} else {
    library(ape)
    tr <- read.tree("tree.nwk")
    dt <- data.frame(
        ID = tr$tip.label,
        Location = sample(c("HK", "SG"), length(tr$tip.label), replace = TRUE),
        Length = abs(rnorm(length(tr$tip.label))),
        Group = sample(c("Yes", "No"), length(tr$tip.label), replace = TRUE),
        Abundance = abs(rnorm(length(tr$tip.label), 10, 2))
    )
    write.csv(dt, "associated_data.csv", row.names = FALSE)
}