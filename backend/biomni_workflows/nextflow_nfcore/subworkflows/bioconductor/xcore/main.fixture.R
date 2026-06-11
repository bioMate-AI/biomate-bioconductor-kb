# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("xcore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("xcore")

data("rinderpest_mini")

write.csv(rinderpest_mini, "counts.csv", row.names = TRUE)

design <- matrix(
  data = c(1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1),
  ncol = 3,
  nrow = 9,
  byrow = TRUE,
  dimnames = list(
    c(
      "00hr_rep1", "00hr_rep2", "00hr_rep3",
      "12hr_rep1", "12hr_rep2", "12hr_rep3",
      "24hr_rep1", "24hr_rep2", "24hr_rep3"
    ),
    c("00hr", "12hr", "24hr")
  )
)

write.csv(design, "design_matrix.csv", row.names = TRUE)