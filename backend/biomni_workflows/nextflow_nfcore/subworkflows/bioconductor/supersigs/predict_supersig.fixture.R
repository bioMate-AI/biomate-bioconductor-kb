# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("supersigs", "BSgenome.Hsapiens.UCSC.hg19", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(supersigs)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(dplyr)
})

# 1. Reproduce the vignette's data-preparation code
# example_dt is provided by the supersigs package
input_dt <- make_matrix(example_dt)

# Add IndVar column as done in the vignette
input_dt <- input_dt %>%
  mutate(IndVar = c(1, 1, 1, 0, 0)) %>%
  relocate(IndVar)

# supersig_ls is a pre-trained list of SuperSigs provided by the package
# It is lazy-loaded with the package

# 2. Serialize objects to the declared input files
# Since no specific read excerpt is provided, we save them as RDS files 
# which preserves the exact S4 objects and tibble classes.
saveRDS(input_dt, "input_dt.csv")
saveRDS(supersig_ls, "supersig_ls")