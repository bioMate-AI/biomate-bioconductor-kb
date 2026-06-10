# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("mosbi")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(mosbi)

z_score <- function(x, margin = 2) {
  z_fun <- function(y) {
    (y - mean(y, na.rm = TRUE)) / sd(y, na.rm = TRUE)
  }
  if (margin == 2) {
    return(apply(x, margin, z_fun))
  } else if (margin == 1) {
    return(t(apply(x, margin, z_fun)))
  }
}

# get data
data(mouse_data, package = "mosbi")
mouse_data <- mouse_data[c(
  grep("metabolite_identification", colnames(mouse_data)),
  grep("^X", colnames(mouse_data))
)]

# Make data matrix
data_matrix <- z_score(log2(as.matrix(mouse_data[2:ncol(mouse_data)])), 1)
rownames(data_matrix) <- mouse_data$metabolite_identification

# Serialize to the expected input file
saveRDS(data_matrix, "data_matrix.rds")