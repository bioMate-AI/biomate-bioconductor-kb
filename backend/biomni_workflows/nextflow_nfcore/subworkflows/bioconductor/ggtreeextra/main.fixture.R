# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ggtreeExtra")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ggtreeExtra)

files_to_copy <- c(
  "tree.nwk" = "tree.nwk",
  "tree_tippoint_bar.csv" = "tree_tippoint_bar.csv",
  "first_ring_discrete.csv" = "first_ring_discrete.csv",
  "second_ring_continuous.csv" = "second_ring_continuous.csv"
)

for (f in names(files_to_copy)) {
  src <- system.file("extdata", f, package="ggtreeExtra")
  if (src != "" && file.exists(src)) {
    file.copy(src, files_to_copy[f], overwrite = TRUE)
  } else {
    src_any <- list.files(system.file(package="ggtreeExtra"), pattern=f, recursive=TRUE, full.names=TRUE)
    if (length(src_any) > 0) {
      file.copy(src_any[1], files_to_copy[f], overwrite = TRUE)
    } else {
      stop(paste("Could not find file:", f, "in ggtreeExtra package."))
    }
  }
}