# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MASS", "ANF")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MASS)
library(ANF)

set.seed(1)
patient_ids <- paste0("patient_", 1:200)
true.class <- rep(c("TCGA-ACC", "TCGA-PCPG"), each = 100)
names(true.class) <- patient_ids

# Helper to generate synthetic affinity matrix
gen_aff <- function(mean1, mean2, n_feat) {
    mat1 <- mvrnorm(100, rep(mean1, n_feat), diag(runif(n_feat, 0.2, 2)))
    mat2 <- mvrnorm(100, rep(mean2, n_feat), diag(runif(n_feat, 0.2, 2)))
    feat <- rbind(mat1, mat2)
    rownames(feat) <- patient_ids
    d <- as.matrix(dist(feat))
    A <- affinity_matrix(d, 10)
    rownames(A) <- patient_ids
    colnames(A) <- patient_ids
    return(A)
}

A1 <- gen_aff(0, 0.5, 20)
A2 <- gen_aff(10, 9.5, 30)
A3 <- gen_aff(-5, -4, 15)

# Construct Wall matching the complex list structure expected by the workflow
Wall <- list(
  adrenal_gland = list(
    log.sel = list(
      fpkm = A1,
      mirnas = A2,
      methy450 = A3
    )
  ),
  uterus = list(
    raw.all = list(
      fpkm = A1,
      mirnas = A2,
      methy450 = A3
    )
  )
)

project_ids <- true.class

saveRDS(Wall, "Wall")
saveRDS(project_ids, "project_ids")